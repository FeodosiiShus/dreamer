//
//  ShellClient.swift
//  Dreamder
//
//  Created by Matthijs Eikelenboom on 25/11/2022.
//

import Foundation

/// Errors that can occur during shell operations
nonisolated enum ShellClientError: Error, Equatable {
    case taskTerminated(code: Int)
}

/// Shell Client
/// Run commands in shell
nonisolated final class ShellClient: ShellRunning, Sendable {
    static let shellExecutable = URL(fileURLWithPath: "/bin/zsh")

    private let runner: any ProcessRunning
    private let shellEnvironment: ShellEnvironment

    init(runner: any ProcessRunning = ProcessRunner(), shellEnvironment: ShellEnvironment = .shared) {
        self.runner = runner
        self.shellEnvironment = shellEnvironment
    }

    func run(_ command: String) async throws -> ShellResult {
        let invocation = await makeInvocation(arguments: ["-c", command])
        let output = try await runner.run(invocation)
        return ShellResult(
            exitCode: output.exitCode,
            terminatedBySignal: output.terminatedBySignal,
            standardOutput: output.standardOutputText,
            standardError: output.standardErrorText
        )
    }

    func runAsync(_ command: String) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [self] in
                do {
                    let invocation = await makeInvocation(arguments: ["-c", "exec 2>&1\n" + command])
                    for try await event in runner.stream(invocation) {
                        switch event {
                        case .line(_, let line):
                            continuation.yield(line)
                        case .exit(let code, let terminatedBySignal):
                            if code != 0 || terminatedBySignal {
                                throw ShellClientError.taskTerminated(code: Int(code))
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func live() -> ShellClient {
        ShellClient()
    }

    private func makeInvocation(arguments: [String]) async -> ProcessInvocation {
        let environment = await shellEnvironment.load()
        return ProcessInvocation(
            executable: Self.shellExecutable,
            arguments: arguments,
            environment: environment
        )
    }
}
