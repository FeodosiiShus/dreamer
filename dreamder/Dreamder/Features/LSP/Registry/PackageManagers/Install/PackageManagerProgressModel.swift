//
//  PackageManagerProgressModel.swift
//  Dreamder
//
//  Created by Khan Winter on 8/8/25.
//

import Foundation
import Observation

/// This model is injected into each ``PackageManagerInstallStep`` when executing a ``PackageManagerInstallOperation``.
/// A single model is used for each step. Output is collected by the ``PackageManagerInstallOperation``.
///
/// Yields output into an async stream, and provides common helper methods for exec-ing commands, creating
/// directories, etc.
@MainActor
@Observable
final class PackageManagerProgressModel {
    enum OutputItem {
        case status(String)
        case output(String)
    }

    let outputStream: AsyncStream<OutputItem>

    nonisolated static let envExecutable = URL(filePath: "/usr/bin/env")

    private let runner: any ProcessRunning
    private let shellEnvironment: ShellEnvironment
    private let outputContinuation: AsyncStream<OutputItem>.Continuation

    init(runner: any ProcessRunning = ProcessRunner(), shellEnvironment: ShellEnvironment = .shared) {
        self.runner = runner
        self.shellEnvironment = shellEnvironment
        (outputStream, outputContinuation) = AsyncStream<OutputItem>.makeStream()
    }

    func status(_ string: String) {
        outputContinuation.yield(.status(string))
    }

    /// Creates the directory for the language server to be installed in
    func createDirectoryStructure(for packagePath: URL) throws {
        let decodedPath = packagePath.path(percentEncoded: false)
        if FileManager.default.fileExists(atPath: decodedPath) {
            status("Removing existing installation.")
            try FileManager.default.removeItem(at: packagePath)
        }

        status("Creating directory: \(decodedPath)")
        try FileManager.default.createDirectory(
            at: packagePath,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    @discardableResult
    func run(
        _ argv: [String],
        in directory: URL? = nil,
        environment overrides: [String: String] = [:]
    ) async throws -> [String] {
        guard let executable = argv.first, RegistryInputValidation.isAllowedExecutable(executable) else {
            throw PackageManagerError.unsafeValue(argv.first ?? "")
        }
        status(argv.joined(separator: " "))
        var environment = await shellEnvironment.load()
        environment.merge(overrides) { _, override in override }
        let invocation = ProcessInvocation(
            executable: Self.envExecutable,
            arguments: argv,
            workingDirectory: directory,
            environment: environment
        )
        var output: [String] = []
        for try await event in runner.stream(invocation) {
            switch event {
            case .line(_, let line):
                output.append(line)
                outputContinuation.yield(.output(line))
            case let .exit(code, terminatedBySignal):
                if code != 0 || terminatedBySignal {
                    throw ShellClientError.taskTerminated(code: Int(code))
                }
            }
        }
        return output
    }

    func finish() {
        outputContinuation.finish()
    }
}
