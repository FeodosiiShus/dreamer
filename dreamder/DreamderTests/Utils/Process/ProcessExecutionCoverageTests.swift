import Foundation
import Synchronization
import Testing
@testable import Dreamder

private final class RunningTaskHolder: Sendable {
    private let stored = Mutex<Task<ProcessOutput, any Error>?>(nil)

    func store(_ task: Task<ProcessOutput, any Error>) {
        stored.withLock { $0 = task }
    }

    func cancelWhenStored() {
        while stored.withLock({ $0 }) == nil {
            sched_yield()
        }
        stored.withLock { $0?.cancel() }
    }
}

private final class OutputCollector: Sendable {
    private let text = Mutex("")

    func append(_ data: Data) {
        text.withLock { $0 += String(decoding: data, as: UTF8.self) }
    }

    var value: String {
        text.withLock { $0 }
    }
}

private struct CannedRunner: ProcessRunning {
    let output: ProcessOutput

    func run(_ invocation: ProcessInvocation) async throws -> ProcessOutput {
        output
    }
}

@Suite
struct ProcessExecutionCoverageTests {
    @Test
    func aTaskCancelledBeforeTheLaunchNeverSpawnsTheChild() async throws {
        let marker = ProcessTestSupport.shell("echo spawned")
        let task = Task { () throws -> ProcessOutput in
            while !Task.isCancelled {
                await Task.yield()
            }
            return try await ProcessExecution.run(marker)
        }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }

    @Test
    func cancellingRightAfterTheSpawnTerminatesTheChild() async throws {
        let holder = RunningTaskHolder()
        let tuning = ProcessExecution.Tuning(afterSpawn: { holder.cancelWhenStored() })
        let task = Task { () throws -> ProcessOutput in
            try await ProcessExecution.run(ProcessTestSupport.shell("sleep 30"), tuning: tuning)
        }
        holder.store(task)

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }

    @Test
    func aChildIgnoringTerminateIsKilledAfterTheGracePeriod() async throws {
        let collector = OutputCollector()
        let tuning = ProcessExecution.Tuning(killGracePeriod: .milliseconds(200))
        let invocation = ProcessTestSupport.shell("trap '' TERM; echo ready; exec sleep 30")
        let task = Task { () throws -> ProcessOutput in
            try await ProcessExecution.run(invocation, sink: { _, data in collector.append(data) }, tuning: tuning)
        }

        let started = try await ProcessTestSupport.waitUntil { collector.value.contains("ready") }
        #expect(started)
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }

    @Test
    func aDescendantHoldingThePipesOpenEndsTheRunAfterTheDrainGracePeriod() async throws {
        let tuning = ProcessExecution.Tuning(drainGracePeriod: .milliseconds(200))
        let invocation = ProcessTestSupport.shell("sleep 3 & echo done")

        let output = try await ProcessExecution.run(invocation, tuning: tuning)

        #expect(output.succeeded)
        #expect(output.standardOutputText == "done\n")
    }

    @Test
    func readingAPipeDistinguishesDataNothingYetAndEndOfStream() throws {
        let pipe = Pipe()
        let descriptor = pipe.fileHandleForReading.fileDescriptor
        _ = fcntl(descriptor, F_SETFL, O_NONBLOCK)

        #expect(ProcessExecution.readAvailable(from: descriptor) == Data())

        try pipe.fileHandleForWriting.write(contentsOf: Data("abc".utf8))
        #expect(ProcessExecution.readAvailable(from: descriptor) == Data("abc".utf8))

        try pipe.fileHandleForWriting.close()
        #expect(ProcessExecution.readAvailable(from: descriptor) == nil)
    }

    @Test
    func theDefaultStreamSplitsBothStreamsIncludingAnUnterminatedLastLine() async throws {
        let runner = CannedRunner(output: ProcessOutput(
            exitCode: 3,
            standardOutput: Data("first\nsecond".utf8),
            standardError: Data("oops".utf8)
        ))
        var events: [ProcessEvent] = []

        for try await event in runner.stream(ProcessTestSupport.shell("ignored")) {
            events.append(event)
        }

        #expect(events == [
            .line(.standardOutput, "first"),
            .line(.standardOutput, "second"),
            .line(.standardError, "oops"),
            .exit(code: 3, terminatedBySignal: false)
        ])
    }

    @Test
    func aWindowsLineBreakAfterABackslashInsideDoubleQuotesJoinsTheLines() throws {
        #expect(try GitCommandLine.tokenize("\"a\\\r\nb\"") == ["ab"])
    }
}
