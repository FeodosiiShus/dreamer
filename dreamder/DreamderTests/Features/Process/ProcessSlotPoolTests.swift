import Foundation
import Synchronization
import Testing
@testable import Dreamder

@Suite
struct ProcessSlotPoolTests {
    private final class Gauge: Sendable {
        private let state = Mutex((current: 0, peak: 0))

        func enter() {
            state.withLock { state in
                state.current += 1
                state.peak = max(state.peak, state.current)
            }
        }

        func leave() {
            state.withLock { $0.current -= 1 }
        }

        var peak: Int {
            state.withLock { $0.peak }
        }
    }

    @Test
    func zeroLimitClampsToOne() {
        #expect(ProcessSlotPool(limit: 0).limit == 1)
        #expect(ProcessSlotPool(limit: 0).availableSlots == 1)
    }

    @Test
    func concurrentBodiesNeverExceedTheLimit() async throws {
        let pool = ProcessSlotPool(limit: 3)
        let gauge = Gauge()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<12 {
                group.addTask {
                    try await pool.withSlot {
                        gauge.enter()
                        try await Task.sleep(for: .milliseconds(10))
                        gauge.leave()
                    }
                }
            }
            try await group.waitForAll()
        }
        #expect(gauge.peak == 3)
        #expect(pool.availableSlots == 3)
    }

    @Test
    func slotIsReleasedWhenTheBodyThrows() async {
        struct Failure: Error {}
        let pool = ProcessSlotPool(limit: 1)
        await #expect(throws: Failure.self) {
            try await pool.withSlot { throw Failure() }
        }
        #expect(pool.availableSlots == 1)
    }

    @Test
    func waitersAreServedInOrder() async throws {
        let pool = ProcessSlotPool(limit: 1)
        let order = Mutex<[Int]>([])
        try await pool.acquire()
        var waiters: [Task<Void, any Error>] = []
        for index in 1...3 {
            waiters.append(Task {
                try await pool.withSlot {
                    order.withLock { $0.append(index) }
                }
            })
            try await Task.sleep(for: .milliseconds(20))
        }
        try await Task.sleep(for: .milliseconds(50))
        pool.release()
        for waiter in waiters {
            try await waiter.value
        }
        #expect(order.withLock { $0 } == [1, 2, 3])
        #expect(pool.availableSlots == 1)
    }

    @Test
    func cancellingAWaiterThrowsAndKeepsTheSlotAccounting() async throws {
        let pool = ProcessSlotPool(limit: 1)
        try await pool.acquire()
        let waiter = Task {
            try await pool.withSlot { 42 }
        }
        try await Task.sleep(for: .milliseconds(50))
        waiter.cancel()
        await #expect(throws: CancellationError.self) {
            try await waiter.value
        }
        pool.release()
        #expect(pool.availableSlots == 1)
        let value = try await pool.withSlot { 7 }
        #expect(value == 7)
    }

    @Test
    func acquiringFromACancelledTaskThrowsImmediately() async {
        let pool = ProcessSlotPool(limit: 1)
        let task = Task {
            while !Task.isCancelled {
                await Task.yield()
            }
            try await pool.acquire()
        }
        task.cancel()
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(pool.availableSlots == 1)
    }
}
