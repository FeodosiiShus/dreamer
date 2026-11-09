import Foundation
import Synchronization
import Testing
@testable import Dreamder

@Suite
struct ProcessSlotPoolCancellationTests {
    private final class CancelCurrentTaskOnce: Sendable {
        private let armed = Mutex(false)

        func arm() {
            armed.withLock { $0 = true }
        }

        func fire() {
            let shouldCancel = armed.withLock { armed -> Bool in
                let wasArmed = armed
                armed = false
                return wasArmed
            }
            if shouldCancel {
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
    }

    private final class Flag: Sendable {
        private let value = Mutex(false)

        func raise() {
            value.withLock { $0 = true }
        }

        var isRaised: Bool {
            value.withLock { $0 }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellationLandingBeforeTheWaiterIsQueuedIsNotLost() async throws {
        let trigger = CancelCurrentTaskOnce()
        let pool = ProcessSlotPool(limit: 1, beforeAdmission: { trigger.fire() })
        try await pool.acquire()
        trigger.arm()

        let waiter = Task { try await pool.acquire() }

        await #expect(throws: CancellationError.self) {
            try await waiter.value
        }
        #expect(pool.availableSlots == 0)
        pool.release()
        #expect(pool.availableSlots == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func lostRaceNeverStrandsTheNextWaiter() async throws {
        let trigger = CancelCurrentTaskOnce()
        let pool = ProcessSlotPool(limit: 1, beforeAdmission: { trigger.fire() })
        try await pool.acquire()
        trigger.arm()

        let cancelled = Task { try await pool.acquire() }
        _ = try? await cancelled.value
        let next = Task { try await pool.acquire() }
        pool.release()

        try await next.value
        #expect(pool.availableSlots == 0)
        pool.release()
        #expect(pool.availableSlots == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellationWithAFreeSlotThrowsWithoutTakingTheSlot() async throws {
        let trigger = CancelCurrentTaskOnce()
        let pool = ProcessSlotPool(limit: 1, beforeAdmission: { trigger.fire() })
        trigger.arm()

        let task = Task { try await pool.acquire() }

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(pool.availableSlots == 1)
        let value = try await pool.withSlot { 5 }
        #expect(value == 5)
        #expect(pool.availableSlots == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func withSlotNeverRunsTheBodyWhenCancelledBeforeAdmission() async {
        let trigger = CancelCurrentTaskOnce()
        let pool = ProcessSlotPool(limit: 2, beforeAdmission: { trigger.fire() })
        let ran = Flag()
        trigger.arm()

        let task = Task {
            try await pool.withSlot { ran.raise() }
        }

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(ran.isRaised == false)
        #expect(pool.availableSlots == 2)
    }
}
