import Darwin
import Foundation
import Synchronization
import Testing
@testable import Dreamder

nonisolated private final class FakeProcessSystem: Sendable {
    enum Delivery: Equatable, Sendable {
        case process(pid_t, Int32)
        case group(pid_t, Int32)
    }

    enum Spawning: Sendable {
        case none
        case once(parent: pid_t, child: pid_t)
        case everyDelivery(parent: pid_t, firstChild: pid_t)
    }

    private struct State: Sendable {
        var tree: [pid_t: [pid_t]]
        var spawning: Spawning
        var deliveries: [Delivery] = []
        var spawnedCount: pid_t = 0
    }

    private let state: Mutex<State>
    private let groups: [pid_t: pid_t]

    init(tree: [pid_t: [pid_t]], groups: [pid_t: pid_t], spawning: Spawning = .none) {
        state = Mutex(State(tree: tree, spawning: spawning))
        self.groups = groups
    }

    var deliveries: [Delivery] {
        state.withLock { $0.deliveries }
    }

    var system: ProcessTree.System {
        ProcessTree.System(
            children: { [self] pid in state.withLock { $0.tree[pid] ?? [] } },
            processGroup: { [self] pid in groups[pid] ?? -1 },
            deliver: { [self] pid, signal in
                record(.process(pid, signal))
                return 0
            },
            deliverToGroup: { [self] pid, signal in
                record(.group(pid, signal))
                return 0
            }
        )
    }

    private func record(_ delivery: Delivery) {
        state.withLock { state in
            state.deliveries.append(delivery)
            switch state.spawning {
            case .none:
                break
            case let .once(parent, child):
                state.tree[parent, default: []].append(child)
                state.spawning = .none
            case let .everyDelivery(parent, firstChild):
                state.tree[parent, default: []].append(firstChild + state.spawnedCount)
                state.spawnedCount += 1
            }
        }
    }
}

struct ProcessTreeSignalDeliveryTests {
    @Test
    func aRootLeadingItsGroupIsSignalledOnceThroughTheGroup() {
        let fake = FakeProcessSystem(
            tree: [100: [101], 101: [102]],
            groups: [100: 100, 101: 100, 102: 200]
        )

        ProcessTree.send(SIGTERM, to: 100, using: fake.system)

        #expect(fake.deliveries == [.group(100, SIGTERM), .process(102, SIGTERM)])
    }

    @Test
    func aRootInsideAnotherGroupIsSignalledDirectlyAndNeverThroughTheGroup() {
        let fake = FakeProcessSystem(
            tree: [100: [101]],
            groups: [100: 1, 101: 1]
        )

        ProcessTree.send(SIGINT, to: 100, using: fake.system)

        #expect(fake.deliveries == [.process(100, SIGINT), .process(101, SIGINT)])
    }

    @Test
    func continueReachesTheLeavesBeforeTheRoot() {
        let fake = FakeProcessSystem(
            tree: [100: [101], 101: [102]],
            groups: [100: 100, 101: 300, 102: 400]
        )

        ProcessTree.send(SIGCONT, to: 100, using: fake.system)

        #expect(fake.deliveries == [.process(102, SIGCONT), .process(101, SIGCONT), .group(100, SIGCONT)])
    }

    @Test(arguments: [pid_t(500), 100])
    func aChildForkedWhileTheTreeIsSignalledIsSignalledInAFollowUpRound(_ lateChildGroup: pid_t) {
        let fake = FakeProcessSystem(
            tree: [100: [101]],
            groups: [100: 100, 101: 100, 200: lateChildGroup],
            spawning: .once(parent: 101, child: 200)
        )

        ProcessTree.send(SIGTERM, to: 100, using: fake.system)

        #expect(fake.deliveries == [.group(100, SIGTERM), .process(200, SIGTERM)])
    }

    @Test
    func aTreeThatKeepsForkingIsSignalledOncePerProcessAndStopsAtTheRoundLimit() {
        let fake = FakeProcessSystem(
            tree: [:],
            groups: [:],
            spawning: .everyDelivery(parent: 100, firstChild: 1000)
        )

        ProcessTree.send(SIGKILL, to: 100, using: fake.system)

        let expected = [pid_t(100)] + (0..<(ProcessTree.maxRounds - 1)).map { pid_t(1000) + pid_t($0) }
        #expect(fake.deliveries == expected.map { FakeProcessSystem.Delivery.process($0, SIGKILL) })
    }

    @Test
    func invalidRootsAreNeverSignalled() {
        let fake = FakeProcessSystem(tree: [0: [1]], groups: [:])

        ProcessTree.send(SIGTERM, to: 0, using: fake.system)
        ProcessTree.send(SIGTERM, to: -1, using: fake.system)

        #expect(fake.deliveries.isEmpty)
    }

    @Test
    func descendantsAreWalkedThroughTheInjectedEnumerator() {
        let tree: [pid_t: [pid_t]] = [1: [2, 3], 2: [4], 4: [1]]

        let found = ProcessTree.descendants(of: 1, children: { tree[$0] ?? [] })

        #expect(found == [2, 3, 4])
    }
}
