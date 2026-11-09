import Foundation
import Synchronization

nonisolated final class ProcessExecution: Sendable {
    typealias Sink = @Sendable (ProcessStream, Data) -> Void

    static let readChunkSize = 65_536

    nonisolated struct Tuning: Sendable {
        var killGracePeriod: Duration = .seconds(3)
        var drainGracePeriod: Duration = .seconds(2)
        var afterSpawn: (@Sendable () -> Void)?
    }

    private enum StopReason: Sendable {
        case cancelled
        case timedOut(Duration)
    }

    private struct UnsafeSendable<Value>: @unchecked Sendable {
        let value: Value
    }

    private struct State {
        var process: UnsafeSendable<Process>?
        var launched = false
        var standardOutput = Data()
        var standardError = Data()
        var openStreams: Set<ProcessStream> = [.standardOutput, .standardError]
        var terminated = false
        var exitCode: Int32 = 0
        var terminatedBySignal = false
        var stopReason: StopReason?
        var continuation: CheckedContinuation<ProcessOutput, any Error>?
        var timeoutTask: Task<Void, Never>?
        var finished = false
    }

    private struct Outcome: Sendable {
        let continuation: CheckedContinuation<ProcessOutput, any Error>?
        let process: UnsafeSendable<Process>?
        let timeoutTask: Task<Void, Never>?
        let result: Result<ProcessOutput, any Error>
    }

    private let state = Mutex(State())
    private let sink: Sink?
    private let tuning: Tuning

    private init(sink: Sink?, tuning: Tuning) {
        self.sink = sink
        self.tuning = tuning
    }

    static func run(
        _ invocation: ProcessInvocation,
        sink: Sink? = nil,
        tuning: Tuning = Tuning()
    ) async throws -> ProcessOutput {
        let execution = ProcessExecution(sink: sink, tuning: tuning)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                execution.begin(invocation, continuation)
            }
        } onCancel: {
            execution.stop(.cancelled)
        }
    }

    private func begin(_ invocation: ProcessInvocation, _ continuation: CheckedContinuation<ProcessOutput, any Error>) {
        state.withLock { $0.continuation = continuation }
        Task(priority: .userInitiated) { [self] in
            await launch(invocation)
        }
    }

    @concurrent
    private func launch(_ invocation: ProcessInvocation) async {
        let alreadyStopped = state.withLock { $0.stopReason != nil }
        if alreadyStopped {
            finish()
            return
        }

        let process = Process()
        process.executableURL = invocation.executable
        process.arguments = invocation.arguments
        process.currentDirectoryURL = invocation.workingDirectory
        process.environment = ProcessEnvironment.sanitized(invocation.environment)

        let output = Pipe.closingOnExec()
        let error = Pipe.closingOnExec()
        process.standardOutput = output
        process.standardError = error

        var inputPipe: Pipe?
        if invocation.standardInput != nil {
            let pipe = Pipe.closingOnExec()
            _ = fcntl(pipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
            process.standardInput = pipe
            inputPipe = pipe
        } else {
            process.standardInput = FileHandle.nullDevice
        }

        process.terminationHandler = { [self] terminated in
            didTerminate(terminated)
        }
        state.withLock { $0.process = UnsafeSendable(value: process) }

        do {
            try process.run()
        } catch {
            finish(launchError: ProcessRunnerError.launchFailed(
                executable: invocation.executable.path(percentEncoded: false),
                reason: error.localizedDescription
            ))
            return
        }

        tuning.afterSpawn?()
        let stopReason = state.withLock { state -> StopReason? in
            state.launched = true
            return state.stopReason
        }

        output.fileHandleForReading.readabilityHandler = { [self] handle in
            drain(handle, stream: .standardOutput)
        }
        error.fileHandleForReading.readabilityHandler = { [self] handle in
            drain(handle, stream: .standardError)
        }

        if let data = invocation.standardInput, let inputPipe {
            Self.feed(data, into: inputPipe)
        }
        if let timeout = invocation.timeout {
            scheduleTimeout(timeout)
        }
        if stopReason != nil {
            terminate(process)
        }
    }

    private func drain(_ handle: FileHandle, stream: ProcessStream) {
        guard let chunk = Self.readAvailable(from: handle.fileDescriptor) else {
            handle.readabilityHandler = nil
            state.withLock { _ = $0.openStreams.remove(stream) }
            completeIfDrained()
            return
        }
        if !chunk.isEmpty {
            deliver(chunk, from: stream)
        }
    }

    private func deliver(_ chunk: Data, from stream: ProcessStream) {
        if let sink {
            sink(stream, chunk)
        } else {
            state.withLock { state in
                switch stream {
                case .standardOutput: state.standardOutput.append(chunk)
                case .standardError: state.standardError.append(chunk)
                }
            }
        }
    }

    private func didTerminate(_ process: Process) {
        let status = process.terminationStatus
        let bySignal = process.terminationReason == .uncaughtSignal
        state.withLock { state in
            state.terminated = true
            state.exitCode = status
            state.terminatedBySignal = bySignal
        }
        guard !completeIfDrained() else { return }
        Task(priority: .utility) { [self] in
            try? await Task.sleep(for: tuning.drainGracePeriod)
            finish()
        }
    }

    @discardableResult
    private func completeIfDrained() -> Bool {
        let ready = state.withLock { $0.terminated && $0.openStreams.isEmpty && !$0.finished }
        guard ready else { return false }
        finish()
        return true
    }

    private func stop(_ reason: StopReason) {
        let target = state.withLock { state -> UnsafeSendable<Process>? in
            guard !state.finished, state.stopReason == nil else { return nil }
            state.stopReason = reason
            return state.launched && !state.terminated ? state.process : nil
        }
        if let process = target?.value {
            terminate(process)
        }
    }

    private func scheduleTimeout(_ timeout: Duration) {
        state.withLock { state in
            guard !state.finished else { return }
            state.timeoutTask = Task { [self] in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                stop(.timedOut(timeout))
            }
        }
    }
}

nonisolated extension ProcessExecution {
    private func finish(launchError: (any Error)? = nil) {
        let outcome = state.withLock { state -> Outcome? in
            guard !state.finished else { return nil }
            state.finished = true
            let result: Result<ProcessOutput, any Error>
            switch state.stopReason {
            case .cancelled:
                result = .failure(CancellationError())
            case .timedOut(let limit):
                result = .failure(ProcessRunnerError.timedOut(limit))
            case nil:
                if let launchError {
                    result = .failure(launchError)
                } else {
                    result = .success(ProcessOutput(
                        exitCode: state.exitCode,
                        terminatedBySignal: state.terminatedBySignal,
                        standardOutput: state.standardOutput,
                        standardError: state.standardError
                    ))
                }
            }
            let outcome = Outcome(
                continuation: state.continuation,
                process: state.process,
                timeoutTask: state.timeoutTask,
                result: result
            )
            state.continuation = nil
            state.process = nil
            state.timeoutTask = nil
            return outcome
        }
        guard let outcome else { return }
        outcome.timeoutTask?.cancel()
        if let process = outcome.process?.value {
            process.terminationHandler = nil
            (process.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
            (process.standardError as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        }
        outcome.continuation?.resume(with: outcome.result)
    }

    private func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let target = UnsafeSendable(value: process)
        let gracePeriod = tuning.killGracePeriod
        Task(priority: .utility) {
            try? await Task.sleep(for: gracePeriod)
            if target.value.isRunning {
                kill(target.value.processIdentifier, SIGKILL)
            }
        }
    }

    private static func feed(_ data: Data, into pipe: Pipe) {
        let writer = UnsafeSendable(value: pipe.fileHandleForWriting)
        Task(priority: .utility) {
            await write(data, to: writer)
        }
    }

    @concurrent
    private static func write(_ data: Data, to writer: UnsafeSendable<FileHandle>) async {
        try? writer.value.write(contentsOf: data)
        try? writer.value.close()
    }

    static func readAvailable(from descriptor: Int32) -> Data? {
        withUnsafeTemporaryAllocation(of: UInt8.self, capacity: readChunkSize) { buffer -> Data? in
            var count: Int
            repeat {
                count = Darwin.read(descriptor, buffer.baseAddress, buffer.count)
            } while count < 0 && errno == EINTR
            if count > 0 {
                return Data(buffer: UnsafeBufferPointer(rebasing: buffer[..<count]))
            }
            return count < 0 && errno == EAGAIN ? Data() : nil
        }
    }
}
