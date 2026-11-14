//
//  ShellIntegration.swift
//  Dreamder
//
//  Created by Khan Winter on 6/2/24.
//

import Foundation
import os

/// Provides a single function for setting up shell integrations.
/// See ``ShellIntegration/setUpIntegration(for:environment:)``
nonisolated enum ShellIntegration {
    private static let logger = Logger(subsystem: "dev.dreamder.Dreamder", category: "ShellIntegration")

    /// Variable constants used by setup scripts.
    nonisolated enum Variables {
        static let shellLogin = "CE_SHELL_LOGIN"
        static let ceZDotDir = "CE_ZDOTDIR"
        static let userZDotDir = "USER_ZDOTDIR"
        static let zDotDir = "ZDOTDIR"
        static let ceInjection = "CE_INJECTION"
        static let disableHistory = "CE_DISABLE_HISTORY"
    }

    /// Errors for shell integration setup.
    nonisolated enum Error: Swift.Error, LocalizedError {
        case bashShellFileNotFound
        case zshShellFileNotFound

        var errorDescription: String? {
            switch self {
            case .bashShellFileNotFound:
                return "Failed to find bash injection file."
            case .zshShellFileNotFound:
                return "Failed to find zsh injection file."
            }
        }
    }

    /// Setup shell integration.
    ///
    /// Injects necessary init files for whatever shell is being used for Dreamder to receive notifications about
    /// running processes for display in the UI.
    /// Any other setup/configuration should also be done here.
    ///
    /// - Parameters:
    ///   - shell: The shell being set up.
    ///   - environment: The existing environment variables. Passed as an `inout` parameter because this function will
    ///                  modify this array.
    ///   - useLogin: Whether or not to use a login shell.
    /// - Returns: An array of args to pass to the shell executable.
    /// - Throws: Errors involving filesystem operations. This function requires copying various files, which can
    ///           throw. Can also throw ``ShellIntegration/Error`` errors if required files are not found in the bundle.
    static func setUpIntegration(
        for shell: Shell,
        environment: inout [String],
        useLogin: Bool,
        interactive: Bool,
        bundle: Bundle = .main,
        currentUser: CurrentUser? = .getCurrentUser(),
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) throws -> [String] {
        do {
            var args: [String] = []

            // Enable injection in our scripts.
            environment.append("\(Variables.ceInjection)=1")

            switch shell {
            case .bash:
                try bash(&args, bundle: bundle)
            case .zsh:
                try zsh(&environment, bundle: bundle, currentUser: currentUser, temporaryDirectory: temporaryDirectory)
            }

            if useLogin {
                environment.append("\(Variables.shellLogin)=1")
            }

            if let execArgs = shell.execArguments(interactive: interactive, login: useLogin) {
                args.append(execArgs)
            }

            return args
        } catch {
            // catch so we can log this here
            logger.error("Failed to setup shell integration: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Shell Specific Setup

    /// Sets up the `bash` shell integration.
    ///
    /// Sets the bash `--init-file` option to point to CE's shell integration script. This script will source the
    /// user's "real" init file and then install our required functions.
    /// Also sets the `-i` option to initialize an interactive session if `interactive` is true.
    ///
    /// - Parameters:
    ///   - args: The args to use for shell exec, will be modified by this function.
    ///   - interactive: Set to true to use an interactive shell.
    private static func bash(_ args: inout [String], bundle: Bundle) throws {
        // Inject our own bash script that will execute the user's init files, then install our pre/post exec functions.
        guard let scriptURL = bundle.url(
            forResource: "dreamder_shell_integration",
            withExtension: "bash"
        ) else {
            throw Error.bashShellFileNotFound
        }
        args.append(contentsOf: ["--init-file", scriptURL.path()])
    }

    /// Sets up the `zsh` shell integration.
    ///
    /// Sets the zsh init directory to a temporary directory containing CE setup scripts. Each script corresponds to an
    /// available zsh init script, and will source the user's real init script. To inject our `preexec/precmd` functions
    /// we first source the user's zsh init files, then install our functions. Transparently installing our functions
    /// and still using the user's init files w/o modifying anyone's rc files.
    /// Also sets up an interactive session using the `-i` parameter.
    ///
    /// - Parameters:
    ///   - shellExecArgs: The args to use for shell exec, will be modified by this function.
    ///   - environment: Environment variables in an array. Formatted as `EnvVar=Value`. Will be modified by this
    ///                  function.
    ///   - useLogin: Whether to use a login shell.
    ///   - interactive: Whether to use an interactive shell.
    private static func zsh(
        _ environment: inout [String],
        bundle: Bundle,
        currentUser: CurrentUser?,
        temporaryDirectory: URL
    ) throws {
        // All injection script URLs
        guard let profileScriptURL = bundle.url(
            forResource: "dreamder_shell_integration_profile",
            withExtension: "zsh"
        ), let envScriptURL = bundle.url(
            forResource: "dreamder_shell_integration_env",
            withExtension: "zsh"
        ), let loginScriptURL = bundle.url(
            forResource: "dreamder_shell_integration_login",
            withExtension: "zsh"
        ), let rcScriptURL = bundle.url(
            forResource: "dreamder_shell_integration_rc",
            withExtension: "zsh"
        ) else {
            throw Error.zshShellFileNotFound
        }

        let tempDir = try makeTempDir(forShell: .zsh, user: currentUser, in: temporaryDirectory)

        // Save any existing home dir. First getting a value from the environment.
        // Falling back to the user's home dir, then ~
        let envZDotDir = environment.first(where: { $0.starts(with: "ZDOTDIR=") })?.trimmingPrefix("ZDOTDIR=")
        let userZDotDir = envZDotDir.flatMap { $0.isEmpty ? nil : String($0) } ?? currentUser?.homeDir ?? "~"

        environment.append("\(Variables.zDotDir)=\(tempDir.path())")
        environment.append("\(Variables.userZDotDir)=\(userZDotDir)")

        // Move all shell files to new temp dir
        try installScript(profileScriptURL, at: tempDir.appending(path: ".zprofile"))
        try installScript(envScriptURL, at: tempDir.appending(path: ".zshenv"))
        try installScript(loginScriptURL, at: tempDir.appending(path: ".zlogin"))
        try installScript(rcScriptURL, at: tempDir.appending(path: ".zshrc"))
    }

    static func installScript(_ origin: URL, at destination: URL) throws {
        let script = try Data(contentsOf: origin)
        if (try? Data(contentsOf: destination)) == script { return }
        try script.write(to: destination, options: .atomic)
    }

    /// Creates a temporary directory for a user/shell combination.
    /// - Parameters:
    ///   - shell: The shell to create the directory for.
    ///   - user: The current user, will attempt to get the current user if none are supplied.
    /// - Returns: The URL of the temporary directory.
    /// - Throws: Errors from `FileManager` operations.
    private static func makeTempDir(
        forShell shell: Shell,
        user: CurrentUser?,
        in temporaryDirectory: URL
    ) throws -> URL {
        let username = user?.name ?? "unknown" // doesn't really matter but this is used later so might as well

        // Create a temp directory to store our init files in.
        // The name of the directory is user-specific and shell-specific to avoid overlap.
        let tempDir = temporaryDirectory.appending(
            path: "\(username)-dreamder-\(shell.rawValue)"
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }
}
