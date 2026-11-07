import Testing
import Foundation
@testable import Dreamder

private actor Recorder {
    private(set) var timeoutCalls = 0
    private(set) var operationSawCancellation = false

    func recordTimeoutCall() {
        timeoutCalls += 1
    }

    func recordCancellation(_ cancelled: Bool) {
        operationSawCancellation = cancelled
    }
}

private struct OperationFailure: Error, Equatable {
    let code: Int
}

private struct CleanupFailure: Error, Equatable {}

@Suite
struct WithTimeoutTests {
    @Test
    func returnsTheValueOfAnOperationThatFinishesBeforeTheLimit() async throws {
        let value = try await withTimeout(duration: .seconds(5), operation: { 42 })
        #expect(value == 42)
    }

    @Test
    func returnsTheValueOfAnOperationThatSuspendsBrieflyWithinTheLimit() async throws {
        let value = try await withTimeout(
            duration: .seconds(5),
            operation: {
                try await Task.sleep(for: .milliseconds(20))
                return "ready"
            }
        )
        #expect(value == "ready")
    }

    @Test
    func throwsTimedOutErrorWhenTheOperationIsSlowerThanTheLimit() async {
        await #expect(throws: TimedOutError()) {
            _ = try await withTimeout(
                duration: .milliseconds(20),
                operation: {
                    try await Task.sleep(for: .seconds(5))
                    return 1
                }
            )
        }
    }

    @Test
    func zeroDurationTimesOutAnOperationThatSuspends() async {
        await #expect(throws: TimedOutError()) {
            _ = try await withTimeout(
                duration: .zero,
                operation: {
                    try await Task.sleep(for: .seconds(5))
                    return 1
                }
            )
        }
    }

    @Test
    func errorThrownByTheOperationPropagatesUnchanged() async {
        await #expect(throws: OperationFailure(code: 7)) {
            _ = try await withTimeout(
                duration: .seconds(5),
                operation: { () async throws -> Int in throw OperationFailure(code: 7) }
            )
        }
    }

    @Test
    func timeoutCancelsTheStillRunningOperation() async throws {
        let recorder = Recorder()
        await #expect(throws: TimedOutError()) {
            _ = try await withTimeout(
                duration: .milliseconds(20),
                operation: {
                    do {
                        try await Task.sleep(for: .seconds(5))
                    } catch {
                        await recorder.recordCancellation(Task.isCancelled)
                        throw error
                    }
                    return 1
                }
            )
        }
        #expect(await recorder.operationSawCancellation)
    }

    @Test
    func onTimeoutRunsExactlyOnceWhenTheLimitExpires() async {
        let recorder = Recorder()
        await #expect(throws: TimedOutError()) {
            _ = try await withTimeout(
                duration: .milliseconds(20),
                onTimeout: { await recorder.recordTimeoutCall() },
                operation: {
                    try await Task.sleep(for: .seconds(5))
                    return 1
                }
            )
        }
        #expect(await recorder.timeoutCalls == 1)
    }

    @Test
    func onTimeoutDoesNotRunWhenTheOperationFinishesInTime() async throws {
        let recorder = Recorder()
        let value = try await withTimeout(
            duration: .seconds(5),
            onTimeout: { await recorder.recordTimeoutCall() },
            operation: { "done" }
        )
        #expect(value == "done")
        #expect(await recorder.timeoutCalls == 0)
    }

    @Test
    func errorThrownByOnTimeoutReplacesTimedOutError() async {
        await #expect(throws: CleanupFailure()) {
            _ = try await withTimeout(
                duration: .milliseconds(20),
                onTimeout: { throw CleanupFailure() },
                operation: {
                    try await Task.sleep(for: .seconds(5))
                    return 1
                }
            )
        }
    }

    @Test
    func cancellingTheOuterTaskCancelsTheOperation() async {
        let recorder = Recorder()
        let (started, startedSignal) = AsyncStream<Void>.makeStream()

        let task = Task {
            try await withTimeout(
                duration: .seconds(5),
                operation: {
                    startedSignal.yield()
                    do {
                        try await Task.sleep(for: .seconds(5))
                    } catch {
                        await recorder.recordCancellation(Task.isCancelled)
                        throw error
                    }
                    return 1
                }
            )
        }

        for await _ in started { break }
        task.cancel()
        _ = await task.result

        #expect(await recorder.operationSawCancellation)
    }
}
