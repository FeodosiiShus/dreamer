import Foundation
import Testing
@testable import Dreamder

struct ShellCoverageTests {
    @Test
    func shellsKnowTheirExecutables() {
        #expect(Shell.bash.defaultPath == "/bin/bash")
        #expect(Shell.zsh.defaultPath == "/bin/zsh")
    }

    @Test
    func execArgumentsFollowTheRequestedBehavior() {
        for shell in Shell.allCases {
            #expect(shell.execArguments(interactive: false, login: false) == nil)
            #expect(shell.execArguments(interactive: true, login: false) == "-i")
            #expect(shell.execArguments(interactive: false, login: true) == "-l")
            #expect(shell.execArguments(interactive: true, login: true) == "-il")
        }
    }

    @Test
    func defaultShellFallsBackToZshWithoutACurrentUser() {
        #expect(Shell.autoDetectDefaultShell(currentUser: nil) == "/bin/zsh")
    }

    @Test
    func defaultShellIsTheCurrentUsersShell() {
        let expected = CurrentUser.getCurrentUser()?.shell ?? "/bin/zsh"
        #expect(Shell.autoDetectDefaultShell() == expected)
    }

    @Test
    func missingBashInjectionScriptFailsWithADescribedError() throws {
        try withTempDir { directory in
            let bundle = try makeEmptyShellIntegrationBundle(in: directory)
            var environment: [String] = []

            #expect(throws: ShellIntegration.Error.bashShellFileNotFound) {
                try ShellIntegration.setUpIntegration(
                    for: .bash,
                    environment: &environment,
                    useLogin: false,
                    interactive: true,
                    bundle: bundle
                )
            }
        }
    }

    @Test
    func missingZshInjectionScriptsFailWithADescribedError() throws {
        try withTempDir { directory in
            let bundle = try makeEmptyShellIntegrationBundle(in: directory)
            var environment: [String] = []

            #expect(throws: ShellIntegration.Error.zshShellFileNotFound) {
                try ShellIntegration.setUpIntegration(
                    for: .zsh,
                    environment: &environment,
                    useLogin: true,
                    interactive: true,
                    bundle: bundle
                )
            }
        }
    }

    @Test
    func integrationErrorsDescribeTheMissingFile() {
        let bash: any Error = ShellIntegration.Error.bashShellFileNotFound
        let zsh: any Error = ShellIntegration.Error.zshShellFileNotFound

        #expect(bash.localizedDescription == "Failed to find bash injection file.")
        #expect(zsh.localizedDescription == "Failed to find zsh injection file.")
    }

    @Test
    func zshRemembersTheUsersZDotDirFromTheEnvironment() throws {
        try withTempDir { directory in
            var environment = ["ZDOTDIR=/custom/zdot"]

            _ = try ShellIntegration.setUpIntegration(
                for: .zsh,
                environment: &environment,
                useLogin: false,
                interactive: true,
                temporaryDirectory: directory
            )

            #expect(environment.contains("\(ShellIntegration.Variables.userZDotDir)=/custom/zdot"))
        }
    }

    @Test
    func zshFallsBackToTheHomeDirectoryWhenZDotDirIsEmpty() throws {
        try withTempDir { directory in
            var environment = ["ZDOTDIR="]
            let home = CurrentUser.getCurrentUser()?.homeDir ?? "~"

            _ = try ShellIntegration.setUpIntegration(
                for: .zsh,
                environment: &environment,
                useLogin: false,
                interactive: true,
                temporaryDirectory: directory
            )

            #expect(environment.contains("\(ShellIntegration.Variables.userZDotDir)=\(home)"))
        }
    }

    @Test
    func zshWithoutACurrentUserUsesTildeAndAnUnknownUserDirectory() throws {
        try withTempDir { directory in
            var environment: [String] = []
            let expectedDirectory = directory.appending(path: "unknown-dreamder-zsh")

            _ = try ShellIntegration.setUpIntegration(
                for: .zsh,
                environment: &environment,
                useLogin: false,
                interactive: true,
                currentUser: nil,
                temporaryDirectory: directory
            )

            #expect(environment.contains("\(ShellIntegration.Variables.userZDotDir)=~"))
            #expect(environment.contains("\(ShellIntegration.Variables.zDotDir)=\(expectedDirectory.path())"))
            for name in [".zshrc", ".zprofile", ".zlogin", ".zshenv"] {
                #expect(FileManager.default.fileExists(atPath: expectedDirectory.appending(path: name).path()))
            }
        }
    }

    @Test
    func settingUpZshTwiceReplacesTheCopiedScripts() throws {
        try withTempDir { directory in
            var first: [String] = []
            var second: [String] = []
            let rcScript = directory.appending(path: "\(CurrentUser.getCurrentUser()?.name ?? "unknown")-dreamder-zsh")
                .appending(path: ".zshrc")

            for index in 0..<2 {
                var environment: [String] = []
                _ = try ShellIntegration.setUpIntegration(
                    for: .zsh,
                    environment: &environment,
                    useLogin: false,
                    interactive: true,
                    temporaryDirectory: directory
                )
                if index == 0 { first = environment } else { second = environment }
                #expect(FileManager.default.fileExists(atPath: rcScript.path()))
            }

            #expect(first == second)
        }
    }
}
