//
//  GitClient.swift
//  Dreamder
//
//  Created by Matthijs Eikelenboom on 26/11/2022.
//

import Foundation
import OSLog

nonisolated final class GitClient: Sendable {
    nonisolated enum GitClientError: Error, Equatable {
        case outputError(String)
        case notGitRepository
        case failedToDecodeURL
        case noRemoteConfigured
        case branchNotFullyMerged
        // Status parsing
        case statusParseEarlyEnd
        case invalidStatus(_ char: Character)
        case statusInvalidChangeType(_ type: Character)

        var description: String {
            switch self {
            case .outputError(let string): string
            case .notGitRepository: "Not a git repository"
            case .failedToDecodeURL: "Failed to decode URL"
            case .noRemoteConfigured: "No remote configured"
            case .branchNotFullyMerged: "Branch is not fully merged"
            case .statusParseEarlyEnd: "Invalid status, found end of string too early"
            case let .invalidStatus(char): "Invalid status received: \(char)"
            case let .statusInvalidChangeType(char): "Status invalid change type: \(char)"
            }
        }
    }

    let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "GitClient")

    internal let directoryURL: URL
    internal let scopePath: String?

    private let configClient: GitConfigClient
    private let commandRunner: GitCommandRunner

    init(
        directoryURL: URL,
        scopePath: String? = nil,
        commandRunner: GitCommandRunner
    ) {
        self.directoryURL = directoryURL
        self.scopePath = scopePath
        self.commandRunner = commandRunner
        self.configClient = GitConfigClient(projectURL: directoryURL, commandRunner: commandRunner)
    }

    convenience init(
        directoryURL: URL,
        shellClient: ShellClient,
        scopePath: String? = nil,
        processRunner: any ProcessRunning = ProcessRunner(),
        gitExecutable: URL? = nil
    ) {
        self.init(
            directoryURL: directoryURL,
            scopePath: scopePath,
            commandRunner: GitCommandRunner(runner: processRunner, gitExecutable: gitExecutable)
        )
    }

    var scopePathspec: String {
        scopePath.map { " -- " + Self.logGraphQuote($0) } ?? ""
    }

    var scopePathspecArguments: [String] {
        scopePath.map { ["--", $0] } ?? []
    }

    func getConfig<T: GitConfigRepresentable>(key: String) async throws -> T? {
        return try await configClient.get(key: key, global: false)
    }

    func setConfig<T: GitConfigRepresentable>(key: String, value: T) async {
        await configClient.set(key: key, value: value, global: false)
    }

    @concurrent
    internal func run(_ command: String, accepting acceptedExitCodes: Set<Int32> = [0]) async throws -> String {
        let arguments = try Self.arguments(from: command)
        return try await run(arguments: arguments, accepting: acceptedExitCodes)
    }

    @concurrent
    internal func run(arguments: [String], accepting acceptedExitCodes: Set<Int32> = [0]) async throws -> String {
        let result = try await runResult(arguments: arguments)
        guard result.success(ignoring: acceptedExitCodes) else {
            throw Self.error(for: result)
        }
        return result.outputText
    }

    @concurrent
    internal func runData(_ command: String) async throws -> Data {
        let result = try await runResult(command)
        guard result.success else {
            throw Self.error(for: result)
        }
        return result.standardOutput
    }

    @concurrent
    internal func runResult(_ command: String) async throws -> GitCommandResult {
        try await execute(arguments: try Self.arguments(from: command), display: command)
    }

    @concurrent
    internal func runResult(arguments: [String]) async throws -> GitCommandResult {
        try await execute(arguments: arguments, display: GitCommandLine.display(arguments))
    }

    internal typealias LiveCommandStream = AsyncThrowingStream<String, any Error>

    /// Runs a git command in same way as `run`, but returns a async stream of the output
    internal func runLive(_ command: String) -> LiveCommandStream {
        do {
            return runLive(arguments: try Self.arguments(from: command))
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
    }

    internal func runLive(arguments: [String]) -> LiveCommandStream {
        AsyncThrowingStream { continuation in
            let task = Task { [self] in
                var errorLines: [String] = []
                do {
                    for try await event in commandRunner.stream(arguments: arguments, workingDirectory: directoryURL) {
                        switch event {
                        case .line(let stream, let line):
                            if stream == .standardError, !GitCommandResult.looksLikeProgress(line) {
                                errorLines.append(line)
                            }
                            continuation.yield(line)
                        case .exit(let code, let terminatedBySignal):
                            if code != 0 || terminatedBySignal {
                                throw Self.error(for: GitCommandResult(
                                    exitCode: code,
                                    terminatedBySignal: terminatedBySignal,
                                    standardError: Data(errorLines.joined(separator: "\n").utf8)
                                ))
                            }
                        }
                    }
                    continuation.finish()
                } catch ProcessRunnerError.launchFailed(let executable, let reason) {
                    continuation.finish(throwing: GitClientError.outputError("Failed to start \(executable): \(reason)"))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func arguments(from command: String) throws -> [String] {
        do {
            return try GitCommandLine.tokenize(command)
        } catch let error as GitCommandLineError {
            throw GitClientError.outputError(error.description)
        }
    }

    static func field(at index: Int, in fields: [String]) -> String? {
        fields.indices.contains(index) ? fields[index] : nil
    }

    static func error(for result: GitCommandResult) -> GitClientError {
        let errorText = result.startFailure ?? result.standardErrorText
        if errorText.contains("not a git repository") {
            return .notGitRepository
        }
        if errorText.contains("No remote configured") {
            return .noRemoteConfigured
        }
        return .outputError(result.errorMessage)
    }

    private func execute(arguments: [String], display: String) async throws -> GitCommandResult {
        let result = try await commandRunner.run(arguments: arguments, workingDirectory: directoryURL)
        await recordInConsole(arguments: arguments, display: display, result: result)
        return result
    }

    private func recordInConsole(arguments: [String], display: String, result: GitCommandResult) async {
        guard !GitCommandPolicy.isQuery(arguments) else { return }
        let directory = directoryURL
        let output = result.combinedText
        await MainActor.run {
            guard GitConsoleLog.changesRepository(display) else { return }
            GitConsoleLog.log(for: directory).record(command: display, directory: directory, output: output)
        }
    }
}
