import Foundation
import Testing
@testable import Dreamder

extension GitClientFakeRunnerCoverage {
    @Test
    func configReadsDistinguishMissingKeysFromFailures() async throws {
        let (client, fake) = ScmFakeGit.client { invocation in
            switch ScmFakeGit.arguments(invocation).last {
            case "missing": ScmFakeGit.failure("", code: 1)
            case "broken": ScmFakeGit.failure("fatal: bad config", code: 128)
            case "flag": ScmFakeGit.ok("  TRUE \n")
            case "junk": ScmFakeGit.ok("maybe\n")
            default: ScmFakeGit.ok("value\n")
            }
        }
        let missing: String? = try await client.getConfig(key: "missing")
        #expect(missing == nil)
        let flag: Bool? = try await client.getConfig(key: "flag")
        #expect(flag == true)
        let junk: Bool? = try await client.getConfig(key: "junk")
        #expect(junk == nil)
        let text: String? = try await client.getConfig(key: "user.name")
        #expect(text == "value")
        await #expect(throws: GitClient.GitClientError.outputError("bad config")) {
            let _: String? = try await client.getConfig(key: "broken")
        }
        #expect(ScmFakeGit.arguments(try #require(fake.invocations.first)) == ["config", "missing"])
    }

    @Test
    func configReadWithAStartFailureThrows() async {
        let (client, _) = ScmFakeGit.client { _ in
            throw ProcessRunnerError.launchFailed(executable: "git", reason: "gone")
        }
        await #expect(throws: GitClient.GitClientError.outputError("Failed to start git: gone")) {
            let _: String? = try await client.getConfig(key: "user.name")
        }
    }

    @Test
    func configWritesPickSetOrUnsetFromTheValue() async throws {
        let (client, fake) = ScmFakeGit.client { _ in ScmFakeGit.ok() }
        await client.setConfig(key: "a.flag", value: true)
        await client.setConfig(key: "a.flag", value: false)
        await client.setConfig(key: "a.text", value: "hello")
        await client.setConfig(key: "a.text", value: "")
        await client.setConfig(key: "a.count", value: ScmCountConfig(count: 0))

        let written = fake.invocations.map(ScmFakeGit.arguments)
        #expect(written == [
            ["config", "a.flag", "true"],
            ["config", "--unset", "a.flag"],
            ["config", "a.text", "hello"],
            ["config", "--unset", "a.text"],
            ["config", "a.count", "0"]
        ])
    }

    @Test
    func configWriteFailuresAreLoggedNotThrown() async throws {
        let (failing, failingFake) = ScmFakeGit.client { _ in ScmFakeGit.failure("error: could not lock", code: 255) }
        await failing.setConfig(key: "a.text", value: "x")
        #expect(failingFake.invocations.count == 1)

        let (missing, missingFake) = ScmFakeGit.client { _ in ScmFakeGit.failure("", code: 5) }
        await missing.setConfig(key: "a.text", value: "")
        #expect(missingFake.invocations.count == 1)

        let (throwing, throwingFake) = ScmFakeGit.client { _ in throw ProcessRunnerError.timedOut(.seconds(1)) }
        await throwing.setConfig(key: "a.text", value: "x")
        #expect(throwingFake.invocations.count == 1)
    }

    @Test
    func globalConfigRunsWithoutAWorkingDirectoryAndProjectConfigInsideTheProject() async throws {
        let fake = FakeProcessRunner { _ in ScmFakeGit.ok("v\n") }
        let project = URL(fileURLWithPath: "/tmp/dreamder-config-project", isDirectory: true)
        let config = GitConfigClient(projectURL: project, commandRunner: ScmFakeGit.commandRunner(fake))

        let global: String? = try await config.get(key: "core.editor", global: true)
        let local: String? = try await config.get(key: "core.editor")
        await config.set(key: "core.editor", value: "vim", global: true)

        #expect(global == "v")
        #expect(local == "v")
        let invocations = fake.invocations
        #expect(invocations.map(ScmFakeGit.arguments) == [
            ["config", "--global", "core.editor"],
            ["config", "core.editor"],
            ["config", "--global", "core.editor", "vim"]
        ])
        #expect(invocations[0].workingDirectory == nil)
        #expect(invocations[1].workingDirectory == project)
    }

    @Test
    func remoteURLIsNilWithoutARemoteAndOtherFailuresPropagate() async throws {
        let (noRemote, _) = ScmFakeGit.client { _ in
            ScmFakeGit.failure("fatal: No remote configured to list refs from.")
        }
        #expect(try await noRemote.getRemoteURL() == nil)

        let (broken, _) = ScmFakeGit.client { _ in ScmFakeGit.failure("fatal: something else") }
        await #expect(throws: GitClient.GitClientError.outputError("something else")) {
            _ = try await broken.getRemoteURL()
        }

        let (configured, _) = ScmFakeGit.client { _ in ScmFakeGit.ok("https://github.com/acme/widgets.git\n") }
        #expect(try await configured.getRemoteURL() == URL(string: "https://github.com/acme/widgets.git"))
    }

    @Test
    func unsyncedCommitsParseTheBranchAbLine() async throws {
        let (client, _) = ScmFakeGit.client { _ in
            ScmFakeGit.ok("# branch.oid abc\n# branch.head main\n# branch.ab +3 -4\n")
        }
        let counts = try await client.numberOfUnsyncedCommits()
        #expect(counts.ahead == 3)
        #expect(counts.behind == 4)

        let (garbage, _) = ScmFakeGit.client { _ in ScmFakeGit.ok("# branch.ab garbage\n") }
        let zero = try await garbage.numberOfUnsyncedCommits()
        #expect(zero.ahead == 0)
        #expect(zero.behind == 0)

        let (none, _) = ScmFakeGit.client { _ in ScmFakeGit.ok("# branch.head main\n") }
        let missing = try await none.numberOfUnsyncedCommits()
        #expect(missing.ahead == 0)
        #expect(missing.behind == 0)
    }

    @Test
    func commitChangedFilesKeepOnlyTwoColumnEntries() async throws {
        let directory = URL(fileURLWithPath: "/tmp/dreamder-fake-changed", isDirectory: true)
        let (client, fake) = ScmFakeGit.client(directory: directory) { _ in
            ScmFakeGit.ok("\nM\ta.txt\nA\tb c.txt\nX\tweird\nR100\told\tnew\ngarbage\n")
        }
        let files = try await client.getCommitChangedFiles(commitSHA: "abc")

        #expect(files.map(\.status) == [GitStatus.modified, GitStatus.added, GitStatus.none])
        #expect(files.map(\.fileURL.lastPathComponent) == ["a.txt", "b c.txt", "weird"])
        #expect(files.allSatisfy { $0.stagedStatus == GitStatus.none && $0.originalFilename == nil })
        #expect(ScmFakeGit.arguments(try #require(fake.invocations.first)) == [
            "diff-tree", "--no-commit-id", "--name-status", "-r", "abc"
        ])
    }
}
