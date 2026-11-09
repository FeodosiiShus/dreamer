//
//  ShellIntegration.swift
//  Dreamder
//
//  Created by Khan Winter on 6/1/24.
//

import Foundation

/// Shells supported by Dreamder
nonisolated enum Shell: String, CaseIterable, Sendable {
    case bash
    case zsh

    var defaultPath: String {
        switch self {
        case .bash:
            "/bin/bash"
        case .zsh:
            "/bin/zsh"
        }
    }

    /// Create the exec arguments for a new shell with the given behavior.
    /// - Parameters:
    ///   - interactive: The shell is interactive, accepts user input.
    ///   - login: A login shell.
    /// - Returns: The argument string.
    func execArguments(interactive: Bool, login: Bool) -> String? {
        var args = ""

        switch self {
        case .bash, .zsh:
            if interactive {
                args.append("i")
            }

            if login {
                args.append("l")
            }
        }

        return args.isEmpty ? nil : "-" + args
    }

    /// Gets the default shell from the current user and returns the string of the shell path.
    ///
    /// If getting the user's shell does not work, defaults to `zsh`,
    static func autoDetectDefaultShell(currentUser: CurrentUser? = CurrentUser.getCurrentUser()) -> String {
        guard let currentUser else {
            return Self.zsh.defaultPath
        }
        return currentUser.shell
    }
}
