import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
final class SpawnRecorder {
    private(set) var requests: [ProcessSpawn] = []

    func record(_ request: ProcessSpawn) {
        requests.append(request)
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct TerminalShellResolutionTests {
    @Test
    func explicitShellTypesWinOverTheSettings() {
        let view = terminalCoverageView()

        let bash = view.resolveShell(.bash, userSetting: .zsh)
        let zsh = view.resolveShell(.zsh, userSetting: .bash)

        #expect(bash == .ready(shell: .bash, path: "/bin/bash", replacedPath: nil))
        #expect(zsh == .ready(shell: .zsh, path: "/bin/zsh", replacedPath: nil))
    }

    @Test
    func shellSettingsPickTheMatchingShell() {
        let view = terminalCoverageView()

        let bash = view.resolveShell(nil, userSetting: .bash)
        let zsh = view.resolveShell(nil, userSetting: .zsh)

        #expect(bash == .ready(shell: .bash, path: "/bin/bash", replacedPath: nil))
        #expect(zsh == .ready(shell: .zsh, path: "/bin/zsh", replacedPath: nil))
    }

    @Test
    func systemShellSettingUsesTheDetectedShellWhenSupported() {
        let view = terminalCoverageView()
        view.isExecutable = { _ in true }

        view.systemShell = { "/opt/homebrew/bin/bash" }
        let bash = view.resolveShell(nil, userSetting: .system)
        view.systemShell = { "/bin/zsh" }
        let zsh = view.resolveShell(nil, userSetting: .system)

        #expect(bash == .ready(shell: .bash, path: "/opt/homebrew/bin/bash", replacedPath: nil))
        #expect(zsh == .ready(shell: .zsh, path: "/bin/zsh", replacedPath: nil))
    }

    @Test
    func anUnsupportedSystemShellIsReplacedByZsh() {
        let view = terminalCoverageView()
        view.isExecutable = { _ in true }
        view.systemShell = { "/opt/homebrew/bin/fish" }

        let resolution = view.resolveShell(nil, userSetting: .system)

        #expect(resolution == .ready(shell: .zsh, path: "/bin/zsh", replacedPath: "/opt/homebrew/bin/fish"))
    }

    @Test
    func aSystemShellThatIsNotExecutableIsReplacedByZsh() {
        let view = terminalCoverageView()
        view.isExecutable = { $0 == "/bin/zsh" }
        view.systemShell = { "/opt/homebrew/bin/bash" }

        let resolution = view.resolveShell(nil, userSetting: .system)

        #expect(resolution == .ready(shell: .zsh, path: "/bin/zsh", replacedPath: "/opt/homebrew/bin/bash"))
    }

    @Test
    func anExplicitShellThatIsNotExecutableIsReplacedByZsh() {
        let view = terminalCoverageView()
        view.isExecutable = { $0 == "/bin/zsh" }

        let resolution = view.resolveShell(.bash, userSetting: .zsh)

        #expect(resolution == .ready(shell: .zsh, path: "/bin/zsh", replacedPath: "/bin/bash"))
    }

    @Test
    func withoutAnExecutableFallbackNoShellIsAvailable() {
        let view = terminalCoverageView()
        view.isExecutable = { _ in false }
        view.systemShell = { "/opt/homebrew/bin/fish" }

        let resolution = view.resolveShell(nil, userSetting: .system)

        #expect(
            resolution == .unavailable(
                reason: "Cannot start a shell: /opt/homebrew/bin/fish and /bin/zsh are not executable files."
            )
        )
    }

    @Test
    func systemShellDefaultsToTheUsersLoginShell() {
        let view = terminalCoverageView()

        #expect(view.systemShell() == Shell.autoDetectDefaultShell())
    }

    @Test
    func isExecutableDefaultsToTheFileSystemCheck() {
        let view = terminalCoverageView()

        #expect(view.isExecutable("/bin/zsh"))
        #expect(!view.isExecutable("/bin"))
    }

    @Test
    func anUnsupportedSystemShellIsReplacedByZshAndTheReplacementIsAnnounced() async throws {
        try await withTempDir { directory in
            try await withTerminalCoverageSettings(
                { $0.shell = .system; $0.useShellIntegration = false },
                perform: {
                    let view = terminalCoverageView()
                    let delegate = TerminalCoverageDelegate()
                    view.processDelegate = delegate
                    view.systemShell = { "/opt/homebrew/bin/fish" }
                    let spawns = SpawnRecorder()
                    view.spawnProcess = { _, request in spawns.record(request) }

                    view.startProcess(workspaceURL: directory)

                    #expect(delegate.titles == ["zsh"])
                    let request = try #require(spawns.requests.first)
                    #expect(request.executable == "/bin/zsh")
                    #expect(request.executableName == "zsh")
                    #expect(
                        terminalCoverageText(view)
                            .contains("Shell /opt/homebrew/bin/fish cannot be used, using /bin/zsh.")
                    )
                }
            )
        }
    }

    @Test
    func startingWithoutAnyExecutableShellReportsTheReasonAndSpawnsNothing() async throws {
        await withTerminalCoverageSettings(
            { $0.shell = .system },
            perform: {
                let view = terminalCoverageView()
                let delegate = TerminalCoverageDelegate()
                view.processDelegate = delegate
                view.systemShell = { "/opt/homebrew/bin/fish" }
                view.isExecutable = { _ in false }
                let spawns = SpawnRecorder()
                view.spawnProcess = { _, request in spawns.record(request) }

                let started = view.startProcess(workspaceURL: nil)

                #expect(!started)
                #expect(spawns.requests.isEmpty)
                #expect(!view.process.running)
                #expect(delegate.titles.isEmpty)
                #expect(terminalCoverageText(view).contains("Cannot start a shell"))
            }
        )
    }

    @Test
    func aSpawnThatLeavesNoRunningProcessIsReportedAsAFailure() async throws {
        try await withTempDir { directory in
            try await withTerminalCoverageSettings(
                { $0.shell = .zsh; $0.useShellIntegration = false },
                perform: {
                    let view = terminalCoverageView()
                    let spawns = SpawnRecorder()
                    view.spawnProcess = { _, request in spawns.record(request) }

                    let started = view.startProcess(workspaceURL: directory)

                    #expect(!started)
                    let request = try #require(spawns.requests.first)
                    #expect(request.executable == "/bin/zsh")
                    #expect(request.executableName == "zsh")
                    #expect(request.currentDirectory == directory.absolutePath)
                    #expect(terminalCoverageText(view).contains("Failed to start /bin/zsh."))
                }
            )
        }
    }
}
