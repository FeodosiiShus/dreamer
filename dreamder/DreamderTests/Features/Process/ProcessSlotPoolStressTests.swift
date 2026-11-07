import Foundation
import Testing
@testable import Dreamder

@Suite
struct ProcessSlotPoolStressTests {
    @Test(.timeLimit(.minutes(2)))
    func slotsAreReturnedAfterCancellationsTimeoutsAndFailures() async throws {
        let pool = ProcessSlotPool(limit: 3)
        let runner = ProcessRunner(slots: pool)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<40 {
                group.addTask {
                    switch index % 4 {
                    case 0:
                        _ = try await runner.run(ProcessTestSupport.shell("printf ok"))
                    case 1:
                        let task = Task {
                            try await runner.run(ProcessTestSupport.shell("sleep 5"))
                        }
                        try await Task.sleep(for: .milliseconds(20 + index))
                        task.cancel()
                        _ = try? await task.value
                    case 2:
                        _ = try? await runner.run(ProcessTestSupport.shell("sleep 5", timeout: .milliseconds(150)))
                    default:
                        _ = try await runner.run(ProcessTestSupport.shell("exit 7"))
                    }
                }
            }
            try await group.waitForAll()
        }

        #expect(pool.availableSlots == 3)
        let output = try await runner.run(ProcessTestSupport.shell("printf done"))
        #expect(output.standardOutputText == "done")
    }

    @Test(.timeLimit(.minutes(2)))
    func cancellingWhileWaitingForASlotDoesNotLoseIt() async throws {
        let pool = ProcessSlotPool(limit: 1)
        let runner = ProcessRunner(slots: pool)
        let holder = Task {
            try await runner.run(ProcessTestSupport.shell("sleep 1"))
        }
        try await Task.sleep(for: .milliseconds(100))
        let waiters = (0..<5).map { _ in
            Task {
                try await runner.run(ProcessTestSupport.shell("printf waited"))
            }
        }
        try await Task.sleep(for: .milliseconds(100))
        for waiter in waiters.prefix(3) {
            waiter.cancel()
        }
        _ = try await holder.value
        for waiter in waiters {
            _ = try? await waiter.value
        }

        #expect(pool.availableSlots == 1)
    }
}
