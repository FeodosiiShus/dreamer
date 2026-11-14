import Foundation
import Synchronization
import SwiftTerm
import Testing
@testable import Dreamder

nonisolated private final class ReapScript: Sendable {
    private let state: Mutex<(answers: [ChildReap], asked: [pid_t])>

    init(_ answers: [ChildReap]) {
        state = Mutex((answers, []))
    }

    func next(_ processIdentifier: pid_t) -> ChildReap {
        state.withLock { state in
            state.asked.append(processIdentifier)
            return state.answers.count > 1 ? state.answers.removeFirst() : state.answers.first ?? .unavailable
        }
    }

    var asked: [pid_t] {
        state.withLock { $0.asked }
    }
}

nonisolated private final class WakeCount: Sendable {
    private let count = Mutex(0)

    func wake() -> Bool {
        count.withLock { $0 += 1 }
        return true
    }

    var value: Int {
        count.withLock { $0 }
    }
}

nonisolated private func makePump(script: ReapScript, wakes: WakeCount, attempts: Int) -> LocalProcessPump {
    LocalProcessPump(
        reapAttempts: attempts,
        reapInterval: .milliseconds(1),
        reap: { script.next($0) },
        windowSize: { winsize() },
        wake: { wakes.wake() }
    )
}

struct LocalProcessPumpTerminationTests {
    private let child: pid_t = 4242

    @Test
    func aChildTheTerminalFailedToReapReportsItsRealWaitStatus() {
        let script = ReapScript([.exited(waitStatus: 9)])
        let pump = makePump(script: script, wakes: WakeCount(), attempts: 3)

        pump.resolveTermination(of: child, reported: 0, attemptsLeft: 3)

        #expect(pump.takeEvents() == [.terminated(9)])
        #expect(script.asked == [child])
    }

    @Test
    func aChildThatWasAlreadyReapedKeepsTheReportedStatus() {
        let script = ReapScript([.unavailable])
        let pump = makePump(script: script, wakes: WakeCount(), attempts: 3)

        pump.resolveTermination(of: child, reported: 3 << 8, attemptsLeft: 3)

        #expect(pump.takeEvents() == [.terminated(3 << 8)])
    }

    @Test
    func aChildWithoutAProcessIdentifierIsNeverWaitedFor() {
        let script = ReapScript([.exited(waitStatus: 9)])
        let pump = makePump(script: script, wakes: WakeCount(), attempts: 3)

        pump.resolveTermination(of: 0, reported: 5, attemptsLeft: 3)
        pump.resolveTermination(of: -1, reported: nil, attemptsLeft: 3)

        #expect(pump.takeEvents() == [.terminated(5), .terminated(nil)])
        #expect(script.asked.isEmpty)
    }

    @Test
    func aChildThatIsStillExitingIsAskedAgainUntilItsStatusArrives() async throws {
        let script = ReapScript([.pending, .pending, .exited(waitStatus: 2 << 8)])
        let wakes = WakeCount()
        let pump = makePump(script: script, wakes: wakes, attempts: 10)

        pump.resolveTermination(of: child, reported: 0, attemptsLeft: 10)
        #expect(pump.takeEvents().isEmpty)

        try await eventually(timeout: .seconds(30)) { wakes.value == 1 }
        #expect(pump.takeEvents() == [.terminated(2 << 8)])
        #expect(script.asked == [child, child, child])
    }

    @Test
    func aChildThatNeverBecomesReapableFallsBackToTheReportedStatus() async throws {
        let script = ReapScript([.pending])
        let wakes = WakeCount()
        let pump = makePump(script: script, wakes: wakes, attempts: 2)

        pump.resolveTermination(of: child, reported: 7 << 8, attemptsLeft: 2)

        try await eventually(timeout: .seconds(30)) { wakes.value == 1 }
        #expect(pump.takeEvents() == [.terminated(7 << 8)])
        #expect(script.asked == [child, child, child])
    }

    @Test
    func aPumpReleasedWhileWaitingForTheStatusDeliversNothing() async throws {
        let script = ReapScript([.pending])
        let wakes = WakeCount()
        var pump: LocalProcessPump? = makePump(script: script, wakes: wakes, attempts: 1_000)
        let queue = try #require(pump?.queue)

        pump?.resolveTermination(of: child, reported: 0, attemptsLeft: 1_000)
        pump = nil
        await withCheckedContinuation { continuation in
            queue.asyncAfter(deadline: .now() + .milliseconds(20)) { continuation.resume() }
        }

        #expect(wakes.value == 0)
        #expect(script.asked == [child])
    }

    @Test
    func theTerminalDelegateCallResolvesTheStatusOfTheProcessItNames() {
        let script = ReapScript([.exited(waitStatus: 9)])
        let pump = makePump(script: script, wakes: WakeCount(), attempts: 3)
        let unstarted = LocalProcess(delegate: pump)

        pump.processTerminated(unstarted, exitCode: 3 << 8)

        #expect(pump.takeEvents() == [.terminated(3 << 8)])
        #expect(script.asked.isEmpty)
    }
}
