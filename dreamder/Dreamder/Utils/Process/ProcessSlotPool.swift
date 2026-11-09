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

    private enum Admission {
        case granted
        case cancelled
        case queued
    }

    let limit: Int
    private let state: Mutex<State>
    private let beforeAdmission: @Sendable () -> Void

    init(limit: Int, beforeAdmission: @escaping @Sendable () -> Void = ProcessSlotPool.admitImmediately) {
        self.limit = max(1, limit)
        state = Mutex(State(available: self.limit))
        self.beforeAdmission = beforeAdmission
    }

    static func admitImmediately() {}

    var availableSlots: Int {
        state.withLock { $0.available }
    }

    func withSlot<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        try await acquire()
        defer { release() }
        return try await body()
    }

    func acquire() async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                beforeAdmission()
                let admission = state.withLock { state -> Admission in
                    if Task.isCancelled { return .cancelled }
                    if state.available > 0 {
                        state.available -= 1
                        return .granted
                    }
                    state.waiters.append(Waiter(id: id, continuation: continuation))
                    return .queued
                }
                switch admission {
                case .granted:
                    continuation.resume()
                case .cancelled:
                    continuation.resume(throwing: CancellationError())
                case .queued:
                    break
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
