import Foundation
import Synchronization

nonisolated struct ProcessRunner: ProcessRunning {
    init() {}

    func run(_ invocation: ProcessInvocation) async throws -> ProcessOutput {
        try await ProcessExecution.run(invocation)
    }

    func stream(_ invocation: ProcessInvocation) -> AsyncThrowingStream<ProcessEvent, any Error> {
        AsyncThrowingStream { continuation in
            let buffers = LineBuffers()
            let task = Task {
                do {
                    let output = try await ProcessExecution.run(invocation) { stream, data in
                        for line in buffers.append(data, to: stream) {
                            continuation.yield(.line(stream, line))
                        }
                    }
                    for (stream, line) in buffers.finish() {
                        continuation.yield(.line(stream, line))
                    }
                    continuation.yield(.exit(code: output.exitCode, terminatedBySignal: output.terminatedBySignal))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

nonisolated private final class LineBuffers: Sendable {
    private let splitters = Mutex<[ProcessStream: ProcessLineSplitter]>([:])

    func append(_ data: Data, to stream: ProcessStream) -> [String] {
        splitters.withLock { splitters in
            var splitter = splitters[stream] ?? ProcessLineSplitter()
            let lines = splitter.append(data)
            splitters[stream] = splitter
            return lines
        }
    }

    func finish() -> [(ProcessStream, String)] {
        splitters.withLock { splitters in
            var remaining: [(ProcessStream, String)] = []
            for stream in [ProcessStream.standardOutput, .standardError] {
                if var splitter = splitters[stream], let line = splitter.finish() {
                    remaining.append((stream, line))
                }
            }
            splitters.removeAll()
            return remaining
        }
    }
}
