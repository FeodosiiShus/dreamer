import Foundation
import Synchronization
import Testing

nonisolated final class UISuiteGate: Sendable {
    static let shared = UISuiteGate(slots: 3)

    @TaskLocal static var isHoldingSlot = false

    private struct State {
        var available: Int
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    private let state: Mutex<State>

    init(slots: Int) {
        state = Mutex(State(available: max(1, slots)))
    }

    var availableSlots: Int {
        state.withLock { $0.available }
    }

    func acquire() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let granted = state.withLock { state in
                guard state.available > 0 else {
                    state.waiters.append(continuation)
                    return false
                }
                state.available -= 1
                return true
            }
            if granted {
                continuation.resume()
            }
        }
    }

    func release() {
        let next = state.withLock { state -> CheckedContinuation<Void, Never>? in
            guard !state.waiters.isEmpty else {
                state.available += 1
                return nil
            }
            return state.waiters.removeFirst()
        }
        next?.resume()
    }

    func withSlot(_ body: @Sendable () async throws -> Void) async throws {
        guard !Self.isHoldingSlot else {
            try await body()
            return
        }
        await acquire()
        defer { release() }
        try await Self.$isHoldingSlot.withValue(true) {
            try await body()
        }
    }
}

nonisolated struct UISuiteGateTrait: SuiteTrait, TestScoping {
    var isRecursive: Bool { false }

    @concurrent func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @concurrent @Sendable () async throws -> Void
    ) async throws {
        guard testCase == nil, test.isSuite else {
            try await function()
            return
        }
        defer { StaleTestDefaults.purge() }
        try await UISuiteGate.shared.withSlot {
            try await function()
        }
    }
}

extension Trait where Self == UISuiteGateTrait {
    static var uiGate: Self { UISuiteGateTrait() }
}
