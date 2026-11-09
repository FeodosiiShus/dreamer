import Foundation
import Testing
@testable import Dreamder

@Suite
struct GitCommandRunnerTests {
    static let git = URL(fileURLWithPath: "/usr/bin/git")

    func runner(
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

    @Test
    func stripsEveryRepositoryRedirectingGitVariableAndKeepsTheRest() async throws {
        let fake = FakeProcessRunner { _ in FakeProcessRunner.output("") }
        let redirecting = [
            "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY", "GIT_COMMON_DIR",
            "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_NAMESPACE", "GIT_CEILING_DIRECTORIES",
            "GIT_DISCOVERY_ACROSS_FILESYSTEM", "GIT_CONFIG_PARAMETERS", "GIT_CONFIG_COUNT",
            "GIT_CONFIG_KEY_0", "GIT_CONFIG_KEY_12", "GIT_CONFIG_VALUE_0", "GIT_CONFIG_VALUE_12",
            "GIT_REPLACE_REF_BASE", "GIT_LITERAL_PATHSPECS", "GIT_GLOB_PATHSPECS", "GIT_NOGLOB_PATHSPECS",
            "GIT_ICASE_PATHSPECS"
        ]
        let userOwned = [
            "GIT_AUTHOR_NAME": "Ada", "GIT_AUTHOR_EMAIL": "ada@example.com", "GIT_AUTHOR_DATE": "1700000000 +0000",
            "GIT_COMMITTER_NAME": "Bob", "GIT_COMMITTER_EMAIL": "bob@example.com",
            "GIT_COMMITTER_DATE": "1700000001 +0000", "GIT_CONFIG_GLOBAL": "/Users/test/.gitconfig-work",
            "GIT_CONFIG_SYSTEM": "/etc/gitconfig-work", "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_SSH_COMMAND": "ssh -i key", "GIT_ASKPASS": "/usr/bin/askpass"
        ]
        var base = ["PATH": "/usr/bin"].merging(userOwned) { first, _ in first }
        for name in redirecting {
            base[name] = "/elsewhere"
        }
        _ = try await runner(fake, base: base).run(arguments: ["status"], workingDirectory: nil)
        _ = try await runner(fake, base: base).run(arguments: ["commit"], workingDirectory: nil)

        for invocation in fake.invocations {
            for name in redirecting {
                #expect(invocation.environment[name] == nil, "\(name)")
            }
            for (name, value) in userOwned {
                #expect(invocation.environment[name] == value, "\(name)")
            }
            #expect(invocation.environment["GIT_TERMINAL_PROMPT"] == "0")
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
}
