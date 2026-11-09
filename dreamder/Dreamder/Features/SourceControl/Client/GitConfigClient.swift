//
//  GitConfigClient.swift
//  Dreamder
//
//  Created by Austin Condiff on 10/31/24.
//

import Foundation
import OSLog

/// A client for managing Git configuration settings.
/// Provides methods to read and write Git configuration values at both
/// project and global levels.
nonisolated final class GitConfigClient: Sendable {
    private static let unsetKeyMissingExitCode: Int32 = 5
    private static let keyMissingExitCode: Int32 = 1

    private let projectURL: URL?
    private let commandRunner: GitCommandRunner
    private let logger = Logger(subsystem: "dev.dreamder.Dreamder", category: "GitConfigClient")

    init(projectURL: URL? = nil, commandRunner: GitCommandRunner) {
        self.projectURL = projectURL
        self.commandRunner = commandRunner
    }

    /// Initializes a new GitConfigClient.
    /// - Parameters:
    ///   - projectURL: The project directory URL (if any).
    ///   - shellClient: The client responsible for executing shell commands.
    convenience init(
        projectURL: URL? = nil,
        shellClient: ShellClient,
        processRunner: any ProcessRunning = ProcessRunner()
    ) {
        self.init(projectURL: projectURL, commandRunner: GitCommandRunner(runner: processRunner))
    }

    private func runConfigCommand(_ arguments: [String], global: Bool) async throws -> GitCommandResult {
        var fullArguments = ["config"]
        if global {
            fullArguments.append("--global")
        }
        fullArguments.append(contentsOf: arguments)
        return try await commandRunner.run(arguments: fullArguments, workingDirectory: global ? nil : projectURL)
    }

    /// Retrieves a Git configuration value.
    /// - Parameters:
    ///   - key: The configuration key to retrieve.
    ///   - global: Whether to retrieve the value globally or locally.
    /// - Returns: The value as a type conforming to `GitConfigRepresentable`, or `nil` if not found.
    func get<T: GitConfigRepresentable>(key: String, global: Bool = false) async throws -> T? {
        let result = try await runConfigCommand([key], global: global)
        if result.exitCode == Self.keyMissingExitCode, result.startFailure == nil {
            return nil
        }
        guard result.success else {
            throw GitClient.error(for: result)
        }
        let trimmedOutput = result.outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        return T(configValue: trimmedOutput)
    }

    /// Sets a Git configuration value.
    /// - Parameters:
    ///   - key: The configuration key to set.
    ///   - value: The value to set, conforming to `GitConfigRepresentable`.
    ///   - global: Whether to set the value globally or locally.
    func set<T: GitConfigRepresentable>(key: String, value: T, global: Bool = false) async {
        let shouldUnset: Bool
        if let boolValue = value as? Bool {
            shouldUnset = !boolValue
        } else if let stringValue = value as? String {
            shouldUnset = stringValue.isEmpty
        } else {
            shouldUnset = false
        }

        let arguments = shouldUnset ? ["--unset", key] : [key, value.asConfigValue]

        do {
            let result = try await runConfigCommand(arguments, global: global)
            let ignoredExitCodes: Set<Int32> = shouldUnset ? [Self.unsetKeyMissingExitCode] : []
            if !result.success(ignoring: ignoredExitCodes) {
                logger.error("Failed to set \(key, privacy: .public): \(result.errorMessage, privacy: .public)")
            }
        } catch {
            logger.error("Failed to set \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
