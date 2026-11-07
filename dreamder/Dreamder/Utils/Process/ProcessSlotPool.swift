import Foundation
import Synchronization

nonisolated final class ProcessSlotPool: Sendable {
    static let shared = ProcessSlotPool(limit: max(4, ProcessInfo.processInfo.activeProcessorCount * 2))

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var available: Int
        var waiters: [Waiter] = []
    }

    let limit: Int
    private let state: Mutex<State>

    init(limit: Int) {
        self.limit = max(1, limit)
        state = Mutex(State(available: self.limit))
    }

    var availableSlots: Int {
        state.withLock { $0.available }
    }

    func withSlot<T: Sendable>(_ body: () async throws -> T) async throws -> T {
        try await acquire()
        defer { release() }
        return try await body()
    }

    func acquire() async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let granted = state.withLock { state -> Bool in
                    if state.available > 0 {
                        state.available -= 1
                        return true
                    }
                    state.waiters.append(Waiter(id: id, continuation: continuation))
                    return false
                }
                if granted {
                    continuation.resume()
                }
            }
        } onCancel: {
            let cancelled = state.withLock { state -> Waiter? in
                guard let index = state.waiters.firstIndex(where: { $0.id == id }) else { return nil }
                return state.waiters.remove(at: index)
            }
            cancelled?.continuation.resume(throwing: CancellationError())
        }
    }

    func release() {
        let next = state.withLock { state -> Waiter? in
            if state.waiters.isEmpty {
                state.available += 1
                return nil
            }
            return state.waiters.removeFirst()
        }
        next?.continuation.resume()
    }
}
