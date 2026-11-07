import Foundation

nonisolated enum ProcessStream: Sendable, Hashable {
    case standardOutput
    case standardError
}

nonisolated enum ProcessEvent: Sendable, Equatable {
    case line(ProcessStream, String)
    case exit(code: Int32, terminatedBySignal: Bool)
}

nonisolated enum ProcessRunnerError: Error, Sendable, Equatable {
    case launchFailed(executable: String, reason: String)
    case timedOut(Duration)
}

nonisolated protocol ProcessRunning: Sendable {
    func run(_ invocation: ProcessInvocation) async throws -> ProcessOutput
    func stream(_ invocation: ProcessInvocation) -> AsyncThrowingStream<ProcessEvent, any Error>
}

nonisolated extension ProcessRunning {
    func stream(_ invocation: ProcessInvocation) -> AsyncThrowingStream<ProcessEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let output = try await self.run(invocation)
                    for (stream, data) in [
                        (ProcessStream.standardOutput, output.standardOutput),
                        (ProcessStream.standardError, output.standardError)
                    ] {
                        var splitter = ProcessLineSplitter()
                        for line in splitter.append(data) {
                            continuation.yield(.line(stream, line))
                        }
                        if let last = splitter.finish() {
                            continuation.yield(.line(stream, last))
                        }
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
