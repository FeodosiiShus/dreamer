import Foundation
import Synchronization

nonisolated final class ProcessExecution: Sendable {
    typealias Sink = @Sendable (ProcessStream, Data) -> Void

    static let readChunkSize = 65_536
    static let killGracePeriod: DispatchTimeInterval = .seconds(3)
    static let drainGracePeriod: DispatchTimeInterval = .seconds(2)

    private enum StopReason: Sendable {
        case cancelled
        case timedOut
    }

    private enum ReadResult {
        case data(Data)
        case wouldBlock
        case endOfStream
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
    private let timeout: Duration?

    private init(sink: Sink?, timeout: Duration?) {
        self.sink = sink
        self.timeout = timeout
    }

    static func run(_ invocation: ProcessInvocation, sink: Sink? = nil) async throws -> ProcessOutput {
        let execution = ProcessExecution(sink: sink, timeout: invocation.timeout)
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
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            launch(invocation)
        }
    }

    private func launch(_ invocation: ProcessInvocation) {
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
            Self.terminate(process)
        }
    }

    private func drain(_ handle: FileHandle, stream: ProcessStream) {
        switch Self.readAvailable(from: handle.fileDescriptor) {
        case .data(let chunk):
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
        case .wouldBlock:
            break
        case .endOfStream:
            handle.readabilityHandler = nil
            state.withLock { _ = $0.openStreams.remove(stream) }
            completeIfDrained()
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
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.drainGracePeriod) { [self] in
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
            Self.terminate(process)
        }
    }

    private func scheduleTimeout(_ timeout: Duration) {
        let task = Task { [self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            stop(.timedOut)
        }
        let discard = state.withLock { state -> Bool in
            guard !state.finished else { return true }
            state.timeoutTask = task
            return false
        }
        if discard {
            task.cancel()
        }
    }

    private func finish(launchError: (any Error)? = nil) {
        let outcome = state.withLock { state -> Outcome? in
            guard !state.finished else { return nil }
            state.finished = true
            let result: Result<ProcessOutput, any Error>
            switch state.stopReason {
            case .cancelled:
                result = .failure(CancellationError())
            case .timedOut:
                result = .failure(ProcessRunnerError.timedOut(timeout ?? .zero))
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

    private static func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let target = UnsafeSendable(value: process)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + killGracePeriod) {
            if target.value.isRunning {
                kill(target.value.processIdentifier, SIGKILL)
            }
        }
    }

    private static func feed(_ data: Data, into pipe: Pipe) {
        let writer = UnsafeSendable(value: pipe.fileHandleForWriting)
        DispatchQueue.global(qos: .utility).async {
            try? writer.value.write(contentsOf: data)
            try? writer.value.close()
        }
    }

    private static func readAvailable(from descriptor: Int32) -> ReadResult {
        withUnsafeTemporaryAllocation(of: UInt8.self, capacity: readChunkSize) { buffer -> ReadResult in
            guard let base = buffer.baseAddress else { return .endOfStream }
            var count: Int
            repeat {
                count = Darwin.read(descriptor, base, buffer.count)
            } while count < 0 && errno == EINTR
            if count > 0 {
                return .data(Data(bytes: base, count: count))
            }
            if count < 0 && errno == EAGAIN {
                return .wouldBlock
            }
            return .endOfStream
        }
    }
}
