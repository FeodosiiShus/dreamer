import Foundation
import Synchronization
import Testing
@testable import Dreamder

nonisolated private final class OverlapProbe: ProcessRunning, Sendable {
    private struct State {
        var active = 0
        var maximum = 0
        var completed = 0
    }

    private let state = Mutex(State())
    private let delay: Duration

    init(delay: Duration) {
        self.delay = delay
    }

    var maximumConcurrency: Int {
        state.withLock { $0.maximum }
    }

    var completedRuns: Int {
        state.withLock { $0.completed }
    }

    func run(_ invocation: ProcessInvocation) async throws -> ProcessOutput {
        state.withLock { state in
            state.active += 1
            state.maximum = max(state.maximum, state.active)
        }
        try await Task.sleep(for: delay)
        state.withLock { state in
            state.active -= 1
            state.completed += 1
        }
        return FakeProcessRunner.output("")
    }
}

@Suite
struct GitCommandRunnerTests {
    private static let git = URL(fileURLWithPath: "/usr/bin/git")

    private func runner(
        _ fake: any ProcessRunning,
        base: [String: String] = ["PATH": "/usr/bin", "HOME": "/Users/test"]
    ) -> GitCommandRunner {
        GitCommandRunner(runner: fake, gitExecutable: Self.git, baseEnvironment: { base })
    }

    @Test
    func prependsTheFixedConfigurationBeforeTheArguments() async throws {
        let fake = FakeProcessRunner { _ in FakeProcessRunner.output("ok") }
        let result = try await runner(fake).run(arguments: ["log", "-1"], workingDirectory: nil)

        let invocation = try #require(fake.invocations.first)
        #expect(invocation.executable == Self.git)
        #expect(invocation.arguments == [
            "-c", "core.quotepath=false", "-c", "log.showSignature=false", "log", "-1"
        ])
        #expect(result.success)
        #expect(result.outputText == "ok")
    }

    @Test
    func runsInTheRequestedDirectoryWithTheGivenInputAndTimeout() async throws {
        let fake = FakeProcessRunner { _ in FakeProcessRunner.output("") }
        let directory = URL(fileURLWithPath: "/tmp/some repo")
        _ = try await runner(fake).run(
            arguments: ["hash-object", "--stdin"],
            workingDirectory: directory,
            standardInput: Data("payload".utf8),
            timeout: .seconds(7)
        )
        let invocation = try #require(fake.invocations.first)
        #expect(invocation.workingDirectory == directory)
        #expect(invocation.standardInput == Data("payload".utf8))
        #expect(invocation.timeout == .seconds(7))
    }

    @Test
    func disablesPromptsAndPinsMessagesToEnglish() async throws {
        let fake = FakeProcessRunner { _ in FakeProcessRunner.output("") }
        let base = [
            "PATH": "/usr/bin",
            "LC_ALL": "de_DE.UTF-8",
            "LANGUAGE": "de",
            "LANG": "de_DE.UTF-8",
            "GIT_TERMINAL_PROMPT": "1"
        ]
        _ = try await runner(fake, base: base).run(arguments: ["commit"], workingDirectory: nil)

        let environment = try #require(fake.invocations.first).environment
        #expect(environment["GIT_TERMINAL_PROMPT"] == "0")
        #expect(environment["LC_MESSAGES"] == "C")
        #expect(environment["LC_ALL"] == nil)
        #expect(environment["LANGUAGE"] == nil)
        #expect(environment["LANG"] == "de_DE.UTF-8")
        #expect(environment["PATH"] == "/usr/bin")
    }

    @Test
    func neverPassesDyldVariablesToGit() async throws {
        let fake = FakeProcessRunner { _ in FakeProcessRunner.output("") }
        let base = [
            "PATH": "/usr/bin",
            "DYLD_FRAMEWORK_PATH": "/Applications/Xcode.app/Contents/SharedFrameworks",
            "DYLD_LIBRARY_PATH": "/x",
            "__XPC_DYLD_LIBRARY_PATH": "/y"
        ]
        _ = try await runner(fake, base: base).run(arguments: ["status"], workingDirectory: nil)
        _ = try await runner(fake, base: base).run(arguments: ["commit"], workingDirectory: nil)

        for invocation in fake.invocations {
            #expect(invocation.environment.keys.allSatisfy { !$0.hasPrefix("DYLD_") && !$0.hasPrefix("__XPC_DYLD_") })
            #expect(invocation.environment["PATH"] == "/usr/bin")
        }
    }

    @Test(arguments: [
        ["status", "--porcelain"],
        ["diff", "--name-status"],
        ["log", "-1"],
        ["show", "HEAD:file"],
        ["rev-parse", "HEAD"],
        ["for-each-ref"],
        ["branch", "--list"],
        ["ls-files", "--others"],
        ["-c", "core.editor=true", "blame", "file"],
        ["stash", "list"],
        ["stash", "show", "-p"]
    ])
    func readOnlyCommandsSkipOptionalLocks(arguments: [String]) async throws {
        let fake = FakeProcessRunner { _ in FakeProcessRunner.output("") }
        _ = try await runner(fake).run(arguments: arguments, workingDirectory: nil)
        #expect(try #require(fake.invocations.first).environment["GIT_OPTIONAL_LOCKS"] == "0")
    }

    @Test(arguments: [
        ["commit", "--message=x"],
        ["add", "--", "file"],
        ["checkout", "main"],
        ["merge", "--no-edit", "x"],
        ["rebase", "main"],
        ["reset", "--hard"],
        ["restore", "."],
        ["stash"],
        ["stash", "push"],
        ["stash", "pop"],
        ["cherry-pick", "abc"],
        ["init"]
    ])
    func writingCommandsKeepGitsOptionalLocks(arguments: [String]) async throws {
        let fake = FakeProcessRunner { _ in FakeProcessRunner.output("") }
        _ = try await runner(fake).run(arguments: arguments, workingDirectory: nil)
        #expect(try #require(fake.invocations.first).environment["GIT_OPTIONAL_LOCKS"] == nil)
    }

    @Test
    func subcommandDetectionSkipsGlobalOptions() {
        #expect(GitCommandPolicy.subcommand(in: ["-c", "a=b", "-C", "dir", "--no-pager", "log", "-1"])?.name == "log")
        #expect(GitCommandPolicy.subcommand(in: ["--git-dir=x", "status"])?.name == "status")
        #expect(GitCommandPolicy.subcommand(in: ["-c", "a=b"]) == nil)
        #expect(GitCommandPolicy.subcommand(in: [])?.name == nil)
        #expect(GitCommandPolicy.subcommand(in: ["stash", "list"])?.arguments.first == "list")
    }

    @Test
    func startFailuresBecomeResultsInsteadOfErrors() async throws {
        let fake = FakeProcessRunner { invocation in
            throw ProcessRunnerError.launchFailed(
                executable: invocation.executable.path(percentEncoded: false),
                reason: "no such file"
            )
        }
        let result = try await runner(fake).run(arguments: ["status"], workingDirectory: nil)
        #expect(!result.success)
        #expect(result.startFailure == "Failed to start /usr/bin/git: no such file")
        #expect(result.exitCode == -1)
    }

    @Test
    func timeoutsAndOtherRunnerErrorsPropagate() async {
        let fake = FakeProcessRunner { _ in throw ProcessRunnerError.timedOut(.seconds(1)) }
        await #expect(throws: ProcessRunnerError.timedOut(.seconds(1))) {
            try await runner(fake).run(arguments: ["status"], workingDirectory: nil, timeout: .seconds(1))
        }
    }

    @Test
    func failingExitCodesAreReportedNotThrown() async throws {
        let fake = FakeProcessRunner { _ in
            FakeProcessRunner.output("", stderr: "fatal: bad object\n", exitCode: 128)
        }
        let result = try await runner(fake).run(arguments: ["cat-file", "x"], workingDirectory: nil)
        #expect(result.exitCode == 128)
        #expect(!result.success)
        #expect(result.errorMessage == "bad object")
    }

    @Test
    func writeCommandsInOneRepositoryNeverOverlap() async throws {
        try await withTempDir { directory in
            let probe = OverlapProbe(delay: .milliseconds(60))
            let commandRunner = runner(probe)
            try await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0..<6 {
                    group.addTask {
                        _ = try await commandRunner.run(arguments: ["commit", "--message=x"], workingDirectory: directory)
                    }
                }
                try await group.waitForAll()
            }
            #expect(probe.completedRuns == 6)
            #expect(probe.maximumConcurrency == 1)
        }
    }

    @Test
    func readCommandsRunConcurrently() async throws {
        try await withTempDir { directory in
            let probe = OverlapProbe(delay: .milliseconds(300))
            let commandRunner = runner(probe)
            try await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0..<4 {
                    group.addTask {
                        _ = try await commandRunner.run(arguments: ["status"], workingDirectory: directory)
                    }
                }
                try await group.waitForAll()
            }
            #expect(probe.maximumConcurrency > 1)
        }
    }

    @Test
    func writeCommandsInDifferentRepositoriesRunConcurrently() async throws {
        try await withTempDir { directory in
            let first = directory.appending(path: "first")
            let second = directory.appending(path: "second")
            try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
            let probe = OverlapProbe(delay: .milliseconds(400))
            let commandRunner = runner(probe)
            try await withThrowingTaskGroup(of: Void.self) { group in
                for repository in [first, second] {
                    group.addTask {
                        _ = try await commandRunner.run(arguments: ["add", "--", "a"], workingDirectory: repository)
                    }
                }
                try await group.waitForAll()
            }
            #expect(probe.maximumConcurrency == 2)
        }
    }

    @Test
    func aCancelledWaiterNeverRunsItsCommand() async throws {
        try await withTempDir { directory in
            let probe = OverlapProbe(delay: .milliseconds(400))
            let commandRunner = runner(probe)
            let first = Task {
                try await commandRunner.run(arguments: ["commit", "--message=a"], workingDirectory: directory)
            }
            try await Task.sleep(for: .milliseconds(100))
            let second = Task {
                try await commandRunner.run(arguments: ["commit", "--message=b"], workingDirectory: directory)
            }
            try await Task.sleep(for: .milliseconds(50))
            second.cancel()

            _ = try await first.value
            await #expect(throws: CancellationError.self) { try await second.value }
            #expect(probe.completedRuns == 1)
        }
    }

    @Test
    func theExecutableIsResolvedOnceThroughXcrunAndCached() async throws {
        try await withTempDir { directory in
            let tool = directory.appending(path: "git")
            try Data("#!/bin/sh\n".utf8).write(to: tool)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path(percentEncoded: false))
            let fake = FakeProcessRunner { _ in
                FakeProcessRunner.output(tool.path(percentEncoded: false) + "\n")
            }
            let locator = GitExecutableLocator(runner: fake)

            let first = await locator.executableURL()
            let second = await locator.executableURL()

            #expect(first.path(percentEncoded: false) == tool.path(percentEncoded: false))
            #expect(second == first)
            #expect(fake.invocations.count == 1)
            let invocation = try #require(fake.invocations.first)
            #expect(invocation.executable.path(percentEncoded: false) == "/usr/bin/xcrun")
            #expect(invocation.arguments == ["--find", "git"])
            #expect(invocation.timeout != nil)
        }
    }

    @Test
    func theExecutableFallsBackWhenXcrunFailsOrReturnsGarbage() async {
        let fallback = URL(fileURLWithPath: "/usr/bin/git")
        let failing = FakeProcessRunner { _ in FakeProcessRunner.output("", stderr: "xcrun: error", exitCode: 1) }
        #expect(await GitExecutableLocator(runner: failing, fallback: fallback).executableURL() == fallback)

        let garbage = FakeProcessRunner { _ in FakeProcessRunner.output("/nonexistent/dreamder/git\n") }
        #expect(await GitExecutableLocator(runner: garbage, fallback: fallback).executableURL() == fallback)

        let throwing = FakeProcessRunner { _ in throw ProcessRunnerError.timedOut(.seconds(10)) }
        #expect(await GitExecutableLocator(runner: throwing, fallback: fallback).executableURL() == fallback)
    }
}
