import Foundation
import Synchronization

nonisolated final class TestClock: Clock, Sendable {
    struct Instant: InstantProtocol {
        var offset: Swift.Duration

        func advanced(by duration: Swift.Duration) -> Instant {
            Instant(offset: offset + duration)
        }

        func duration(to other: Instant) -> Swift.Duration {
            other.offset - offset
        }

        static func < (lhs: Instant, rhs: Instant) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    enum WaitError: Error, Equatable {
        case sleepersDidNotArrive(expected: Int, actual: Int)
    }

    private struct Sleeper {
        let deadline: Instant
        let continuation: CheckedContinuation<Void, Error>
    }

    private struct State {
        var now: Instant
        var nextSleeperID = 0
        var sleepers: [Int: Sleeper] = [:]
        var cancelledBeforeRegistration: Set<Int> = []
    }

    private let state: Mutex<State>

    init(now: Instant = Instant(offset: .zero)) {
        state = Mutex(State(now: now))
    }

    var now: Instant {
        state.withLock { $0.now }
    }

    var minimumResolution: Swift.Duration {
        .zero
    }

    var pendingSleeperCount: Int {
        state.withLock { $0.sleepers.count }
    }

    var pendingDeadlines: [Instant] {
        state.withLock { $0.sleepers.values.map(\.deadline).sorted() }
    }

    func sleep(until deadline: Instant, tolerance: Swift.Duration? = nil) async throws {
        let id = state.withLock { state -> Int in
            state.nextSleeperID += 1
            return state.nextSleeperID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let outcome = self.state.withLock { state -> RegistrationOutcome in
                    if state.cancelledBeforeRegistration.remove(id) != nil {
                        return .cancelled
                    }
                    if deadline <= state.now {
                        return .elapsed
                    }
                    state.sleepers[id] = Sleeper(deadline: deadline, continuation: continuation)
                    return .registered
                }
                switch outcome {
                case .registered:
                    break
                case .elapsed:
                    continuation.resume()
                case .cancelled:
                    continuation.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            let sleeper = self.state.withLock { state -> Sleeper? in
                guard let sleeper = state.sleepers.removeValue(forKey: id) else {
                    state.cancelledBeforeRegistration.insert(id)
                    return nil
                }
                return sleeper
            }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    func advance(by duration: Swift.Duration) {
        let due = state.withLock { state -> [Sleeper] in
            state.now = state.now.advanced(by: duration)
            let dueIDs = state.sleepers.filter { $0.value.deadline <= state.now }.keys
            let due = dueIDs.compactMap { state.sleepers.removeValue(forKey: $0) }
            return due.sorted { $0.deadline < $1.deadline }
        }
        for sleeper in due {
            sleeper.continuation.resume()
        }
    }

    func waitForSleepers(
        _ expected: Int = 1,
        timeout: Swift.Duration = .seconds(5)
    ) async throws {
        let wallClock = ContinuousClock()
        let limit = wallClock.now.advanced(by: timeout)
        while pendingSleeperCount < expected {
            if wallClock.now >= limit {
                throw WaitError.sleepersDidNotArrive(expected: expected, actual: pendingSleeperCount)
            }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    private enum RegistrationOutcome {
        case registered
        case elapsed
        case cancelled
    }
}
