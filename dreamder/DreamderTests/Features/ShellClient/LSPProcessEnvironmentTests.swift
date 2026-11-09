import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@Suite
struct LSPProcessEnvironmentTests {
    private static func loginShell(path: String?, extra: [String] = []) -> ShellEnvironment {
        let fake: FakeProcessRunner
        if let path {
            let output = (["PATH=\(path)", "HOME=/Users/tester"] + extra).map { $0 + "\0" }.joined()
            fake = FakeProcessRunner { _ in FakeProcessRunner.output(output) }
        } else {
            fake = FakeProcessRunner { _ in throw ProcessRunnerError.timedOut(.seconds(10)) }
        }
        return ShellEnvironment(runner: fake, baseEnvironment: { ["PATH": "/usr/bin"] })
    }

    private static func isNpmPrefix(_ invocation: ProcessInvocation) -> Bool {
        invocation.executable.path(percentEncoded: false) == "/usr/bin/env" && invocation.arguments == ["npm", "prefix", "-g"]
    }

    @Test
    func resolveReusesTheSharedLoginPathAndNeverStartsAnInteractiveShell() async throws {
        try await withTempDir { directory in
            let prefix = directory.appending(path: "npm")
            try FileManager.default.createDirectory(at: prefix.appending(path: "bin"), withIntermediateDirectories: true)
            let runner = FakeProcessRunner { invocation in
                Self.isNpmPrefix(invocation)
                    ? FakeProcessRunner.output(prefix.path(percentEncoded: false) + "\n")
                    : FakeProcessRunner.output("", exitCode: 1)
            }
            let environment = LSPProcessEnvironment(
                shellEnvironment: Self.loginShell(path: "/login/bin:/usr/bin"),
                runner: runner,
                homeDirectory: "/Users/tester"
            )

            let resolved = await environment.resolve()

            #expect(resolved.loginPath == "/login/bin:/usr/bin")
            #expect(resolved.npmGlobalBin == prefix.appending(path: "bin").path(percentEncoded: false))
            #expect(Array(resolved.searchPaths.prefix(4)) == [
                "/Users/tester/.local/share/mise/shims",
                "/Users/tester/.asdf/shims",
                "/login/bin",
                "/usr/bin"
            ])
            #expect(resolved.searchPaths.contains(prefix.appending(path: "bin").path(percentEncoded: false)))
            #expect(resolved.searchPaths.contains("/Users/tester/.cargo/bin"))
            #expect(resolved.environment["PATH"] == resolved.searchPaths.joined(separator: ":"))
            #expect(resolved.environment["HOME"] == "/Users/tester")

            let invocations = runner.invocations
            #expect(invocations.count == 1)
            let npm = try #require(invocations.first)
            #expect(npm.environment["PATH"] == "/login/bin:/usr/bin")
            #expect(npm.timeout != nil)
            #expect(!invocations.contains { $0.arguments.contains("-i") || $0.arguments.contains("-lic") })
        }
    }

    @Test
    func aFailedLoginEnvironmentIsReplacedByANonInteractivePathProbe() async {
        let runner = FakeProcessRunner { invocation in
            if invocation.executable.path(percentEncoded: false) == "/bin/zsh" {
                return FakeProcessRunner.output("banner__DREAMDER_PATH__/probed/bin:/usr/bin__DREAMDER_END__")
            }
            return FakeProcessRunner.output("", exitCode: 1)
        }
        let environment = LSPProcessEnvironment(
            shellEnvironment: Self.loginShell(path: nil),
            runner: runner,
            homeDirectory: "/Users/tester"
        )

        let resolved = await environment.resolve()

        #expect(resolved.loginPath == "/probed/bin:/usr/bin")
        #expect(Array(resolved.searchPaths.prefix(3)) == [
            "/Users/tester/.local/share/mise/shims",
            "/Users/tester/.asdf/shims",
            "/probed/bin"
        ])
        let probe = runner.invocations.first { $0.executable.path(percentEncoded: false) == "/bin/zsh" }
        #expect(probe.map { Array($0.arguments.prefix(2)) } == ["-l", "-c"])
        #expect(probe?.arguments.contains("-i") == false)
        #expect(probe?.timeout != nil)
    }

    @Test
    func aFailedPathProbeKeepsTheFallbackLoginPath() async {
        let runner = FakeProcessRunner { _ in FakeProcessRunner.output("", exitCode: 1) }
        let environment = LSPProcessEnvironment(
            shellEnvironment: Self.loginShell(path: nil),
            runner: runner,
            homeDirectory: "/Users/tester"
        )

        let resolved = await environment.resolve()

        #expect(resolved.loginPath?.hasPrefix("/usr/bin:/opt/homebrew/bin:") == true)
        #expect(runner.invocations.contains { $0.executable.path(percentEncoded: false) == "/bin/zsh" })
    }

    @Test
    func npmFailuresAndMissingBinDirectoriesAreIgnored() async throws {
        try await withTempDir { directory in
            let failing = FakeProcessRunner { _ in FakeProcessRunner.output("", exitCode: 1) }
            let first = LSPProcessEnvironment(
                shellEnvironment: Self.loginShell(path: "/login/bin"),
                runner: failing,
                homeDirectory: "/Users/tester"
            )
            #expect(await first.resolve().npmGlobalBin == nil)

            let missingBin = FakeProcessRunner { _ in
                FakeProcessRunner.output(directory.appending(path: "no-such-prefix").path(percentEncoded: false))
            }
            let second = LSPProcessEnvironment(
                shellEnvironment: Self.loginShell(path: "/login/bin"),
                runner: missingBin,
                homeDirectory: "/Users/tester"
            )
            #expect(await second.resolve().npmGlobalBin == nil)
        }
    }

    @Test
    func theSnapshotIsCachedAndSharedByConcurrentCallers() async {
        let runner = FakeProcessRunner { _ in FakeProcessRunner.output("", exitCode: 1) }
        let environment = LSPProcessEnvironment(
            shellEnvironment: Self.loginShell(path: "/login/bin"),
            runner: runner,
            homeDirectory: "/Users/tester"
        )
        let snapshots = await withTaskGroup(of: LSPProcessEnvironment.Resolved.self) { group in
            for _ in 0..<10 {
                group.addTask { await environment.resolve() }
            }
            var collected: [LSPProcessEnvironment.Resolved] = []
            for await snapshot in group {
                collected.append(snapshot)
            }
            return collected
        }
        _ = await environment.resolve()

        #expect(Set(snapshots.map(\.searchPaths)).count == 1)
        #expect(runner.invocations.count == 1)
    }

    @Test
    func synchronousAccessorsNeverRunProcessesAndSwitchToTheResolvedSnapshot() async {
        let runner = FakeProcessRunner { _ in FakeProcessRunner.output("", exitCode: 1) }
        let environment = LSPProcessEnvironment(
            shellEnvironment: Self.loginShell(path: "/login/bin"),
            runner: runner,
            homeDirectory: "/Users/tester"
        )

        let provisional = environment.searchPaths
        #expect(provisional.contains("/opt/homebrew/bin"))
        #expect(provisional.contains("/Users/tester/.bun/bin"))
        #expect(environment.environment["PATH"]?.isEmpty == false)
        #expect(runner.invocations.isEmpty)

        let resolved = await environment.resolve()
        #expect(environment.searchPaths == resolved.searchPaths)
        #expect(environment.loginPath == "/login/bin")
        #expect(environment.environment == resolved.environment)
    }

    @Test
    func findExecutableSearchesTheResolvedPathsInOrder() async throws {
        try await withTempDir { directory in
            let first = directory.appending(path: "first")
            let second = directory.appending(path: "second")
            for folder in [first, second] {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let tool = folder.appending(path: "dreamder-test-server")
                try Data("#!/bin/sh\n".utf8).write(to: tool)
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o755],
                    ofItemAtPath: tool.path(percentEncoded: false)
                )
            }
            let environment = LSPProcessEnvironment(
                shellEnvironment: Self.loginShell(
                    path: first.path(percentEncoded: false) + ":" + second.path(percentEncoded: false)
                ),
                runner: FakeProcessRunner { _ in FakeProcessRunner.output("", exitCode: 1) },
                homeDirectory: "/Users/tester"
            )
            _ = await environment.resolve()

            #expect(
                environment.findExecutable(named: "dreamder-test-server")
                    == first.appending(path: "dreamder-test-server").path(percentEncoded: false)
            )
            #expect(environment.findExecutable(named: "dreamder-does-not-exist") == nil)
        }
    }

    @Test
    func xcrunLookupsAreCachedPerTool() async throws {
        try await withTempDir { directory in
            let tool = directory.appending(path: "sourcekit-lsp")
            try Data("#!/bin/sh\n".utf8).write(to: tool)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path(percentEncoded: false))
            let runner = FakeProcessRunner { _ in FakeProcessRunner.output(tool.path(percentEncoded: false) + "\n") }
            let environment = LSPProcessEnvironment(
                shellEnvironment: Self.loginShell(path: "/login/bin"),
                runner: runner,
                homeDirectory: "/Users/tester"
            )

            let first = await environment.xcrunFind("sourcekit-lsp")
            let second = await environment.xcrunFind("sourcekit-lsp")

            #expect(first == tool.path(percentEncoded: false))
            #expect(second == first)
            #expect(runner.invocations.count == 1)
            let invocation = try #require(runner.invocations.first)
            #expect(invocation.executable.path(percentEncoded: false) == "/usr/bin/xcrun")
            #expect(invocation.arguments == ["--find", "sourcekit-lsp"])
        }
    }

    @Test
    func xcrunLookupOfAnUnknownToolIsNil() async {
        let runner = FakeProcessRunner { _ in FakeProcessRunner.output("", stderr: "not found", exitCode: 1) }
        let environment = LSPProcessEnvironment(
            shellEnvironment: Self.loginShell(path: "/login/bin"),
            runner: runner,
            homeDirectory: "/Users/tester"
        )
        #expect(await environment.xcrunFind("dreamder-no-such-tool") == nil)
        #expect(await environment.xcrunFind("dreamder-no-such-tool") == nil)
        #expect(runner.invocations.count == 1)
    }

    @Test
    func whenXcrunFindsNothingTheToolchainDirectoryProvidesTheTool() async throws {
        try await withTempDir { directory in
            let tool = directory.appending(path: "sourcekit-lsp")
            try Data("#!/bin/sh\n".utf8).write(to: tool)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path(percentEncoded: false))
            let runner = FakeProcessRunner { _ in FakeProcessRunner.output("\n") }
            let environment = LSPProcessEnvironment(
                shellEnvironment: Self.loginShell(path: "/login/bin"),
                runner: runner,
                homeDirectory: "/Users/tester",
                toolchainDirectory: directory.path(percentEncoded: false)
            )

            let found = await environment.xcrunFind("sourcekit-lsp")
            let missing = await environment.xcrunFind("dreamder-no-such-tool")

            #expect(found == directory.path(percentEncoded: false) + "/sourcekit-lsp")
            #expect(missing == nil)
        }
    }
}

@Suite
struct LanguageServerLauncherResolutionTests {
    private func makeMiseLayout(in directory: URL) throws -> (launcher: URL, mise: URL, target: URL) {
        let miseDirectory = directory.appending(path: "mise-bin")
        let shims = directory.appending(path: "shims")
        let package = directory.appending(path: "pkg/node_modules/typescript")
        for folder in [miseDirectory, shims, package.appending(path: "bin"), package.appending(path: "lib")] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let mise = miseDirectory.appending(path: "mise")
        try Data("#!/bin/sh\n".utf8).write(to: mise)
        let target = package.appending(path: "bin/tsserver")
        try Data("#!/bin/sh\n".utf8).write(to: target)
        try Data("// server".utf8).write(to: package.appending(path: "lib/tsserver.js"))
        let launcher = shims.appending(path: "tsserver")
        try FileManager.default.createSymbolicLink(at: launcher, withDestinationURL: mise)
        return (launcher, mise, target)
    }

    @Test
    func ordinaryLaunchersAreOnlyResolvedThroughSymlinks() async throws {
        try await withTempDir { directory in
            let real = directory.appending(path: "real-server")
            try Data("#!/bin/sh\n".utf8).write(to: real)
            let link = directory.appending(path: "link-server")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
            let runner = FakeProcessRunner { _ in FakeProcessRunner.output("unexpected") }

            let resolved = await LanguageServerDiscovery.resolveLauncher(
                link.path(percentEncoded: false),
                workspacePath: nil,
                runner: runner,
                environment: [:]
            )

            #expect(resolved == real.path(percentEncoded: false))
            #expect(runner.invocations.isEmpty)
        }
    }

    @Test
    func miseShimsAreResolvedWithMiseWhichInTheWorkspace() async throws {
        try await withTempDir { directory in
            let layout = try makeMiseLayout(in: directory)
            let runner = FakeProcessRunner { _ in
                FakeProcessRunner.output(layout.target.path(percentEncoded: false) + "\n")
            }

            let resolved = await LanguageServerDiscovery.resolveLauncher(
                layout.launcher.path(percentEncoded: false),
                workspacePath: directory.path(percentEncoded: false),
                runner: runner,
                environment: ["PATH": "/mise/path"]
            )

            #expect(resolved == layout.target.path(percentEncoded: false))
            let invocation = try #require(runner.invocations.first)
            #expect(invocation.executable.path(percentEncoded: false) == layout.mise.path(percentEncoded: false))
            #expect(invocation.arguments == ["which", "tsserver"])
            #expect(invocation.workingDirectory?.path(percentEncoded: false) == directory.path(percentEncoded: false))
            #expect(invocation.environment["PATH"] == "/mise/path")
            #expect(invocation.timeout != nil)
        }
    }

    @Test
    func failedMiseLookupsKeepTheShimTarget() async throws {
        try await withTempDir { directory in
            let layout = try makeMiseLayout(in: directory)
            for output in [
                FakeProcessRunner.output("", stderr: "mise: not found", exitCode: 1),
                FakeProcessRunner.output("   \n")
            ] {
                let runner = FakeProcessRunner { _ in output }
                let resolved = await LanguageServerDiscovery.resolveLauncher(
                    layout.launcher.path(percentEncoded: false),
                    workspacePath: nil,
                    runner: runner,
                    environment: [:]
                )
                #expect(resolved == layout.mise.path(percentEncoded: false))
            }
            let throwing = FakeProcessRunner { _ in throw ProcessRunnerError.timedOut(.seconds(10)) }
            let resolved = await LanguageServerDiscovery.resolveLauncher(
                layout.launcher.path(percentEncoded: false),
                workspacePath: nil,
                runner: throwing,
                environment: [:]
            )
            #expect(resolved == layout.mise.path(percentEncoded: false))
        }
    }

    @Test
    func typeScriptOptionsUseTheServerBehindAMiseShim() async throws {
        try await withTempDir { directory in
            let layout = try makeMiseLayout(in: directory)
            let runner = FakeProcessRunner { _ in
                FakeProcessRunner.output(layout.target.path(percentEncoded: false) + "\n")
            }
            let workspace = directory.appending(path: "workspace")
            try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

            let options = await LanguageServerDiscovery.resolvedInitializationOptions(
                for: .typescript,
                workspacePath: workspace.path(percentEncoded: false),
                searchPaths: [layout.launcher.deletingLastPathComponent().path(percentEncoded: false)],
                inlayHints: InlayHintSettings(),
                runner: runner,
                environment: [:]
            )

            let server = directory.appending(path: "pkg/node_modules/typescript/lib/tsserver.js")
            #expect(options == .hash([
                "preferences": InlayHintServerPreferences.preferences(for: InlayHintSettings()),
                "tsserver": .hash(["path": .string(server.path(percentEncoded: false))])
            ]))
            #expect(runner.invocations.count == 1)
        }
    }

    @Test
    func nonTypeScriptLanguagesNeverSpawnProcesses() async {
        let runner = FakeProcessRunner { _ in FakeProcessRunner.output("") }
        let options = await LanguageServerDiscovery.resolvedInitializationOptions(
            for: .swift,
            workspacePath: "/project",
            searchPaths: ["/usr/bin"],
            inlayHints: InlayHintSettings(),
            runner: runner,
            environment: [:]
        )
        #expect(options == nil)
        #expect(runner.invocations.isEmpty)
    }
}
