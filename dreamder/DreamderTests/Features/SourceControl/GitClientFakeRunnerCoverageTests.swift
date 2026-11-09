import Foundation
import Testing
@testable import Dreamder

nonisolated enum ScmFakeGit {
    static let executable = URL(fileURLWithPath: "/usr/bin/git")

    static func commandRunner(_ fake: FakeProcessRunner) -> GitCommandRunner {
        GitCommandRunner(runner: fake, gitExecutable: executable, baseEnvironment: { [:] })
    }

    static func client(
        directory: URL = URL(fileURLWithPath: "/tmp/dreamder-fake-\(UUID().uuidString)", isDirectory: true),
        scopePath: String? = nil,
        handler: @escaping FakeProcessRunner.Handler
    ) -> (client: GitClient, fake: FakeProcessRunner) {
        let fake = FakeProcessRunner(handler: handler)
        return (GitClient(directoryURL: directory, scopePath: scopePath, commandRunner: commandRunner(fake)), fake)
    }

    static func arguments(_ invocation: ProcessInvocation) -> [String] {
        Array(invocation.arguments.dropFirst(GitCommandRunner.configuration.count))
    }

    static func ok(_ stdout: String = "") -> ProcessOutput {
        FakeProcessRunner.output(stdout)
    }

    static func failure(_ stderr: String, code: Int32 = 128) -> ProcessOutput {
        FakeProcessRunner.output("", stderr: stderr, exitCode: code)
    }
}

nonisolated struct ScmCountConfig: GitConfigRepresentable {
    let count: Int

    init(count: Int) {
        self.count = count
    }

    init?(configValue: String) {
        guard let count = Int(configValue) else { return nil }
        self.count = count
    }

    var asConfigValue: String {
        String(count)
    }
}

@Suite
struct GitClientFakeRunnerCoverage {
    @Test
    func errorDescriptionsNameEveryFailure() {
        let cases: [(GitClient.GitClientError, String)] = [
            (.outputError("boom"), "boom"),
            (.notGitRepository, "Not a git repository"),
            (.failedToDecodeURL, "Failed to decode URL"),
            (.noRemoteConfigured, "No remote configured"),
            (.branchNotFullyMerged, "Branch is not fully merged"),
            (.statusParseEarlyEnd, "Invalid status, found end of string too early"),
            (.invalidStatus("x"), "Invalid status received: x"),
            (.statusInvalidChangeType("y"), "Status invalid change type: y")
        ]
        for (error, text) in cases {
            #expect(error.description == text)
        }
    }

    @Test
    func errorMappingRecognizesRepositoryAndRemoteFailures() {
        let notRepository = GitCommandResult(
            exitCode: 128,
            standardError: Data("fatal: not a git repository (or any of the parent directories): .git".utf8)
        )
        #expect(GitClient.error(for: notRepository) == .notGitRepository)

        let noRemote = GitCommandResult(
            exitCode: 128,
            standardError: Data("fatal: No remote configured to list refs from.".utf8)
        )
        #expect(GitClient.error(for: noRemote) == .noRemoteConfigured)

        let startFailure = GitCommandResult.startFailed("Failed to start git: nope")
        #expect(GitClient.error(for: startFailure) == .outputError("Failed to start git: nope"))

        let plain = GitCommandResult(exitCode: 1, standardError: Data("error: pathspec 'x' did not match\n".utf8))
        #expect(GitClient.error(for: plain) == .outputError("pathspec 'x' did not match"))
    }

    @Test
    func fieldLookupIsBoundsChecked() {
        let fields = ["a", "b"]
        #expect(GitClient.field(at: 1, in: fields) == "b")
        #expect(GitClient.field(at: 2, in: fields) == nil)
        #expect(GitClient.field(at: -1, in: fields) == nil)
    }

    @Test
    func scopePathspecQuotesTheScopeAndIsEmptyWithoutOne() {
        let unscoped = ScmFakeGit.client { _ in ScmFakeGit.ok() }.client
        #expect(unscoped.scopePathspec.isEmpty)
        #expect(unscoped.scopePathspecArguments.isEmpty)

        let scoped = ScmFakeGit.client(scopePath: "it's app") { _ in ScmFakeGit.ok() }.client
        #expect(scoped.scopePathspec == " -- 'it'\\''s app'")
        #expect(scoped.scopePathspecArguments == ["--", "it's app"])
    }

    @Test
    func malformedCommandStringsAreRejectedBeforeAnyProcessStarts() async throws {
        let (client, fake) = ScmFakeGit.client { _ in ScmFakeGit.ok() }
        do {
            _ = try await client.run("log 'oops")
            Issue.record("expected a tokenizer error")
        } catch GitClient.GitClientError.outputError(let message) {
            #expect(message.hasPrefix("Malformed git command"))
        }
        do {
            for try await _ in client.runLive("log 'oops") {}
            Issue.record("expected a tokenizer error")
        } catch GitClient.GitClientError.outputError(let message) {
            #expect(message.hasPrefix("Malformed git command"))
        }
        #expect(fake.invocations.isEmpty)
    }

    @Test
    func runDataThrowsGitsMessageOnFailureAndReturnsBytesOnSuccess() async throws {
        let (client, _) = ScmFakeGit.client { invocation in
            ScmFakeGit.arguments(invocation).first == "cat-file"
                ? ScmFakeGit.ok("blob")
                : ScmFakeGit.failure("fatal: bad object x")
        }
        #expect(try await client.runData("cat-file blob x") == Data("blob".utf8))
        await #expect(throws: GitClient.GitClientError.outputError("bad object x")) {
            _ = try await client.runData("show x")
        }
    }

    @Test
    func runLiveStreamsEveryLineFromBothPipes() async throws {
        let (client, fake) = ScmFakeGit.client { _ in
            FakeProcessRunner.output("a\nb\n", stderr: "warn\n")
        }
        var lines: [String] = []
        for try await line in client.runLive("fetch --all") {
            lines.append(line)
        }
        #expect(lines == ["a", "b", "warn"])
        #expect(ScmFakeGit.arguments(try #require(fake.invocations.first)) == ["fetch", "--all"])
    }

    @Test
    func runLiveFailureCarriesOnlyNonProgressStderr() async throws {
        let (client, _) = ScmFakeGit.client { _ in
            FakeProcessRunner.output(
                "out\n",
                stderr: "Receiving objects:  50% (1/2)\nfatal: boom\n",
                exitCode: 128
            )
        }
        do {
            for try await _ in client.runLive(arguments: ["clone", "x"]) {}
            Issue.record("expected the stream to fail")
        } catch GitClient.GitClientError.outputError(let message) {
            #expect(message == "boom")
        }
    }

    @Test
    func runLiveReportsProcessesKilledBySignals() async throws {
        let (client, _) = ScmFakeGit.client { _ in
            ProcessOutput(exitCode: 9, terminatedBySignal: true)
        }
        do {
            for try await _ in client.runLive(arguments: ["gc"]) {}
            Issue.record("expected the stream to fail")
        } catch GitClient.GitClientError.outputError(let message) {
            #expect(message == "git was terminated by signal 9")
        }
    }

    @Test
    func runLiveMapsLaunchFailuresAndForwardsOtherErrors() async throws {
        let (launchFailing, _) = ScmFakeGit.client { _ in
            throw ProcessRunnerError.launchFailed(executable: "git", reason: "nope")
        }
        do {
            for try await _ in launchFailing.runLive(arguments: ["status"]) {}
            Issue.record("expected the stream to fail")
        } catch GitClient.GitClientError.outputError(let message) {
            #expect(message == "Failed to start git: nope")
        }

        let (timingOut, _) = ScmFakeGit.client { _ in
            throw ProcessRunnerError.timedOut(.seconds(1))
        }
        do {
            for try await _ in timingOut.runLive(arguments: ["status"]) {}
            Issue.record("expected the stream to fail")
        } catch let error as ProcessRunnerError {
            #expect(error == .timedOut(.seconds(1)))
        }
    }

    @Test
    func stoppingToConsumeAStreamCancelsIt() async throws {
        let (client, _) = ScmFakeGit.client { _ in
            FakeProcessRunner.output("one\ntwo\nthree\n")
        }
        for try await line in client.runLive(arguments: ["log"]) {
            #expect(line == "one")
            break
        }
    }

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

    @Test
    func commitHistoryParsesRefsTagsAndMissingFields() async throws {
        let full = "abc1234¦abc1234full¦Subject one¦Ann¦ann@x.io¦Ann C¦ann@c.io¦1700000000¦Body text¦"
        let output = [
            full + "HEAD -> main, origin/main, origin/HEAD¦",
            full + "tag: v1.0¦",
            full + "¦",
            "h¦H",
            "solo"
        ].joined(separator: "\0") + "\0"
        let (client, fake) = ScmFakeGit.client { invocation in
            switch ScmFakeGit.arguments(invocation).first {
            case "log": ScmFakeGit.ok(output)
            default: ScmFakeGit.ok("https://github.com/acme/widgets.git\n")
            }
        }
        let commits = try await client.getCommitHistory()

        #expect(commits.count == 5)
        let first = commits[0]
        #expect(first.hash == "abc1234")
        #expect(first.commitHash == "abc1234full")
        #expect(first.message == "Subject one")
        #expect(first.author == "Ann")
        #expect(first.authorEmail == "ann@x.io")
        #expect(first.committer == "Ann C")
        #expect(first.committerEmail == "ann@c.io")
        #expect(first.body == "Body text")
        #expect(first.refs == ["main", "origin/main"])
        #expect(first.tag.isEmpty)
        #expect(first.remoteURL == URL(string: "https://github.com/acme/widgets.git"))
        #expect(first.date == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(commits[1].tag == "v1.0")
        #expect(commits[1].refs.isEmpty)
        #expect(commits[2].refs.isEmpty)
        let sparse = commits[3]
        #expect(sparse.hash == "h")
        #expect(sparse.commitHash == "H")
        #expect(sparse.message.isEmpty)
        #expect(sparse.author.isEmpty)
        #expect(sparse.body.isEmpty)
        #expect(abs(sparse.date.timeIntervalSinceNow) < 60)
        let bare = commits[4]
        #expect(bare.hash == "solo")
        #expect(bare.commitHash.isEmpty)
        #expect(bare.refs.isEmpty)

        let logArguments = ScmFakeGit.arguments(try #require(fake.invocations.first))
        #expect(logArguments.starts(with: ["log", "--no-merges", "-z"]))
        #expect(logArguments.last == "--")
    }

    @Test
    func commitHistoryHonoursBranchLimitPathAndMergeFlag() async throws {
        let (client, fake) = ScmFakeGit.client { invocation in
            ScmFakeGit.arguments(invocation).first == "log"
                ? ScmFakeGit.ok("")
                : ScmFakeGit.failure("fatal: No remote configured to list refs from.")
        }
        let commits = try await client.getCommitHistory(
            branchName: "release",
            maxCount: 5,
            fileLocalPath: "src/a.txt",
            showMergeCommits: true
        )

        #expect(commits.isEmpty)
        let logArguments = ScmFakeGit.arguments(try #require(fake.invocations.first))
        #expect(!logArguments.contains("--no-merges"))
        #expect(Array(logArguments.suffix(5)) == ["-n", "5", "release", "--", "src/a.txt"])
    }

    @Test
    func commitHistoryRecordsMissingRemoteAsNil() async throws {
        let record = "abc¦ABC¦S¦A¦a@x¦C¦c@x¦1700000000¦¦¦"
        let (client, _) = ScmFakeGit.client { invocation in
            ScmFakeGit.arguments(invocation).first == "log"
                ? ScmFakeGit.ok(record + "\0")
                : ScmFakeGit.failure("fatal: No remote configured to list refs from.")
        }
        let commits = try await client.getCommitHistory()
        #expect(commits.count == 1)
        #expect(commits[0].remoteURL == nil)
    }

    @Test
    func logGraphChangedFilesDiffAgainstTheFirstParentOrTheRootTree() async throws {
        let directory = URL(fileURLWithPath: "/tmp/dreamder-fake-log", isDirectory: true)
        let (client, fake) = ScmFakeGit.client(directory: directory) { _ in
            ScmFakeGit.ok("M\ta.txt\nR100\told.txt\tnew.txt\n")
        }
        let withParent = GitLogCommit(
            hash: "h1",
            parents: ["p1", "p2"],
            authorName: "A",
            authorEmail: "a@x",
            date: Date(timeIntervalSince1970: 0),
            refs: [],
            subject: "s"
        )
        let root = GitLogCommit(
            hash: "h0",
            parents: [],
            authorName: "A",
            authorEmail: "a@x",
            date: Date(timeIntervalSince1970: 0),
            refs: [],
            subject: "s"
        )

        let merged = try await client.logGraphChangedFiles(commit: withParent)
        let initial = try await client.logGraphChangedFiles(commit: root)

        #expect(merged.count == 2)
        #expect(initial.count == 2)
        let invocations = fake.invocations.map(ScmFakeGit.arguments)
        #expect(invocations[0] == ["diff", "--name-status", "p1", "h1"])
        #expect(invocations[1] == ["diff-tree", "--root", "--no-commit-id", "--name-status", "-r", "h0"])
    }

    @Test
    func logGraphMessageIsTrimmed() async throws {
        let (client, fake) = ScmFakeGit.client { _ in ScmFakeGit.ok("\nSubject\n\nBody\n\n") }
        #expect(try await client.logGraphMessage(hash: "abc") == "Subject\n\nBody")
        #expect(ScmFakeGit.arguments(try #require(fake.invocations.first)) == ["log", "-1", "--format=%B", "abc"])
    }

    @Test
    func logGraphBranchNamesComeFromBothRefNamespaces() async throws {
        let (client, _) = ScmFakeGit.client { _ in
            ScmFakeGit.ok("refs/heads/main\nrefs/remotes/origin/main\nrefs/remotes/origin/HEAD\n")
        }
        #expect(try await client.logGraphBranchNames() == ["main", "origin/main"])
    }

    @Test
    func logGraphBranchNameParsingSkipsOtherNamespacesAndHeads() {
        let output = [
            "  refs/heads/main  ",
            "refs/heads/feature/x",
            "refs/heads/",
            "refs/remotes/origin/HEAD",
            "refs/remotes/origin/dev",
            "refs/remotes/",
            "refs/tags/v1",
            "refs/heads/HEAD",
            ""
        ].joined(separator: "\n")
        #expect(GitClient.logGraphBranchNames(fromRefNames: output) == ["main", "feature/x", "origin/dev"])
    }

    @Test
    func logGraphCurrentUserNeedsAtLeastOneOfNameOrEmail() async throws {
        let both = ScmFakeGit.client { invocation in
            ScmFakeGit.arguments(invocation).last == "user.name" ? ScmFakeGit.ok("Ann\n") : ScmFakeGit.ok("ann@x.io\n")
        }.client
        #expect(await both.logGraphCurrentUser() == GitLogUser(name: "Ann", email: "ann@x.io"))

        let nameOnly = ScmFakeGit.client { invocation in
            ScmFakeGit.arguments(invocation).last == "user.name" ? ScmFakeGit.ok("Ann\n") : ScmFakeGit.failure("", code: 1)
        }.client
        #expect(await nameOnly.logGraphCurrentUser() == GitLogUser(name: "Ann", email: ""))

        let emailOnly = ScmFakeGit.client { invocation in
            ScmFakeGit.arguments(invocation).last == "user.email" ? ScmFakeGit.ok("ann@x.io\n") : ScmFakeGit.failure("", code: 1)
        }.client
        #expect(await emailOnly.logGraphCurrentUser() == GitLogUser(name: "", email: "ann@x.io"))

        let neither = ScmFakeGit.client { _ in ScmFakeGit.failure("", code: 1) }.client
        #expect(await neither.logGraphCurrentUser() == nil)
    }

    @Test
    func logGraphChangedFileParsingHandlesRenamesAndRejectsBrokenLines() {
        let root = URL(fileURLWithPath: "/repo", isDirectory: true)
        let output = "M\ta.txt\nR100\told.txt\tnew.txt\nZ\tx\nM\n\nD\tgone.txt"
        let files = GitClient.logGraphParseChangedFiles(output, root: root)

        #expect(files.map(\.status) == [.modified, .renamed, .deleted])
        #expect(files.map(\.fileURL.lastPathComponent) == ["a.txt", "new.txt", "gone.txt"])
        #expect(files.map(\.originalFilename) == [nil, "old.txt", nil])
    }

    @Test
    func logGraphRecordParsingRequiresNineFieldsAHashAndADate() {
        let unit = "\u{1f}"
        func record(_ fields: [String]) -> String { fields.joined(separator: unit) }

        let valid = record(["h1", "p1 p2", "Ann", "a@x", "100", "200", "HEAD -> main", "Subject", "Subject\n\nBody\n"])
        let parsed = GitClient.logGraphParse(record: valid)
        #expect(parsed?.hash == "h1")
        #expect(parsed?.parents == ["p1", "p2"])
        #expect(parsed?.date == Date(timeIntervalSince1970: 100))
        #expect(parsed?.commitDate == Date(timeIntervalSince1970: 200))
        #expect(parsed?.message == "Subject\n\nBody")
        #expect(parsed?.refs == [GitLogRef(name: "main", kind: .head)])

        let fallbackCommitDate = GitClient.logGraphParse(
            record: record(["h2", "", "Ann", "a@x", "100", "later", "", "Subject", "  \n"])
        )
        #expect(fallbackCommitDate?.commitDate == Date(timeIntervalSince1970: 100))
        #expect(fallbackCommitDate?.message == "Subject")
        #expect(fallbackCommitDate?.parents.isEmpty == true)

        #expect(GitClient.logGraphParse(record: record(["h", "p"])) == nil)
        #expect(GitClient.logGraphParse(record: record(["h", "", "A", "a", "abc", "1", "", "s", "m"])) == nil)
        #expect(GitClient.logGraphParse(record: record(["", "", "A", "a", "1", "1", "", "s", "m"])) == nil)

        let joined = valid + "\0" + "broken" + "\0" + record(["h3", "", "B", "b@x", "5", "5", "", "S3", "S3"])
        #expect(GitClient.logGraphParse(joined).map(\.hash) == ["h1", "h3"])
    }

    @Test
    func logGraphDecorationParsingClassifiesAndDeduplicatesRefs() {
        #expect(GitClient.logGraphRefs(from: "  ").isEmpty)

        let refs = GitClient.logGraphRefs(
            from: "HEAD -> main, tag: v1, origin/main, origin/HEAD, grafted, feature, feature, tag: v1, "
                + "other -> x, HEAD ->"
        )
        #expect(refs == [
            GitLogRef(name: "main", kind: .head),
            GitLogRef(name: "v1", kind: .tag),
            GitLogRef(name: "origin/main", kind: .remote),
            GitLogRef(name: "feature", kind: .branch)
        ])
    }

    @Test
    func logGraphQuotingEscapesSingleQuotes() {
        #expect(GitClient.logGraphQuote("a b") == "'a b'")
        #expect(GitClient.logGraphQuote("it's") == "'it'\\''s'")
    }

    @Test
    func cloneProgressMapsEveryPhaseOntoOneBar() async throws {
        let (client, fake) = ScmFakeGit.client { _ in
            FakeProcessRunner.output(
                "",
                stderr: [
                    "Cloning into 'x'...",
                    "remote: Counting objects:  50% (1/2)",
                    "Counting objects: 100% (2/2), done.",
                    "Compressing objects:  50% (1/2)",
                    "Receiving objects:  50% (1/2)",
                    "Resolving deltas:  50% (1/2)"
                ].joined(separator: "\n") + "\n"
            )
        }
        var steps: [GitClient.CloneProgress] = []
        for try await step in client.cloneRepository(
            remoteUrl: URL(fileURLWithPath: "/tmp/origin repo"),
            localPath: URL(fileURLWithPath: "/tmp/target")
        ) {
            steps.append(step)
        }

        let expected: [Double] = [0, 5, 10, 15, 40, 80]
        #expect(steps.count == expected.count)
        for (step, value) in zip(steps, expected) {
            #expect(abs(step.progress - value) < 1e-9)
        }
        #expect(steps.map(\.state.label) == ["Cloning", "Counting", "Counting", "Compressing", "Receiving", "Resolving"])
        #expect(
            ScmFakeGit.arguments(try #require(fake.invocations.first))
                == ["clone", "--progress", "--", "file:///tmp/origin%20repo", "/tmp/target"]
        )
    }

    @Test
    func cloneProgressLabelsNameEveryState() {
        let states: [(GitClient.GitCloneProgressState, String)] = [
            (.initialState, "Cloning"),
            (.counting, "Counting"),
            (.compressing, "Compressing"),
            (.receiving, "Receiving"),
            (.resolving, "Resolving")
        ]
        for (state, label) in states {
            #expect(state.label == label)
        }
    }

    @Test
    func remoteListingPairsFetchAndPushLocationsOnly() {
        let output = [
            "origin\thttps://example.com/a.git (fetch)",
            "origin\thttps://example.com/a.git (push)",
            "pushfirst\tgit@example.com:b.git (push)",
            "pushfirst\tgit@example.com:b.git (fetch)",
            "fetchfirst\thttps://example.com/c.git (fetch)",
            "fetchfirst\thttps://example.com/c.git (push)",
            "fetchonly\thttps://example.com/d.git (fetch)",
            "pushonly\thttps://example.com/e.git (push)",
            "no tab here",
            "odd\thttps://example.com/f.git (weird)"
        ].joined(separator: "\n")

        let remotes = Set(parseGitRemotes(from: output))
        #expect(remotes == [
            GitRemote(name: "origin", pushLocation: "https://example.com/a.git", fetchLocation: "https://example.com/a.git"),
            GitRemote(name: "pushfirst", pushLocation: "git@example.com:b.git", fetchLocation: "git@example.com:b.git"),
            GitRemote(name: "fetchfirst", pushLocation: "https://example.com/c.git", fetchLocation: "https://example.com/c.git")
        ])
    }

    @Test
    func stashParsingSkipsMalformedEntries() {
        let input = [
            "stash@{0}\u{1f}1700000000\u{1f}On main: first",
            "stash@{1}\u{1f}notatime\u{1f}On main: skipped",
            "stash@{2}\u{1f}1700000000",
            "stash@{3}\u{1f}1700000000\u{1f}no separator",
            "stash@{4}\u{1f}1699999999\u{1f}WIP on main: abc subject"
        ].joined(separator: "\n")
        let entries = parseGitStashEntries(input)

        #expect(entries.map(\.index) == [0, 4])
        #expect(entries.map(\.message) == ["first", "abc subject"])
        #expect(entries[0].date == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(parseGitStashEntries("").isEmpty)
    }

    @Test
    func branchListingParsesTrackInformationAndFiltersByRemote() async throws {
        let output = [
            "main|refs/heads/main|origin/main [ahead 1, behind 2]",
            "feature|refs/heads/feature| ",
            "origin/HEAD|refs/remotes/origin/HEAD| ",
            "origin/main|refs/remotes/origin/main| ",
            "upstream/dev|refs/remotes/upstream/dev| ",
            ""
        ].joined(separator: "\n")
        let (client, fake) = ScmFakeGit.client { _ in ScmFakeGit.ok(output) }

        let all = try await client.getBranches()
        #expect(all.map(\.name) == ["main", "feature", "origin/main", "upstream/dev"])
        #expect(all[0] == GitBranch(name: "main", longName: "refs/heads/main", upstream: "origin/main", ahead: 1, behind: 2))
        #expect(all[1].upstream == nil)

        let remote = try await client.getBranches(remote: "origin")
        #expect(remote.map(\.name) == ["main"])

        let remoteOnly = ScmFakeGit.client { _ in
            ScmFakeGit.ok("origin/HEAD|refs/remotes/origin/HEAD| \norigin/dev|refs/remotes/origin/dev| \nupstream/x|refs/remotes/upstream/x| \n")
        }.client
        let listed = try await remoteOnly.getBranches(remote: "origin")
        #expect(listed.map(\.name) == ["dev"])
        #expect(listed.first?.longName == "refs/remotes/origin/dev")
        #expect(fake.invocations.map(ScmFakeGit.arguments).map(\.last) == ["-a", "-r"])
    }

    @Test
    func currentBranchCombinesNameUpstreamAndTracking() async throws {
        let (client, _) = ScmFakeGit.client { invocation in
            ScmFakeGit.arguments(invocation).first == "branch"
                ? ScmFakeGit.ok("main\n")
                : ScmFakeGit.ok("refs/heads/main|origin/main [behind 3]\n")
        }
        let branch = try #require(try await client.getCurrentBranch())
        #expect(branch == GitBranch(name: "main", longName: "refs/heads/main", upstream: "origin/main", ahead: 0, behind: 3))

        let (untracked, _) = ScmFakeGit.client { invocation in
            ScmFakeGit.arguments(invocation).first == "branch"
                ? ScmFakeGit.ok("topic\n")
                : ScmFakeGit.ok("refs/heads/topic| \n")
        }
        let local = try #require(try await untracked.getCurrentBranch())
        #expect(local.upstream == nil)
        #expect(local.ahead == 0)
    }

    @Test
    func checkoutOfARemoteBranchFallsBackToTheExistingLocalOne() async throws {
        let (client, fake) = ScmFakeGit.client { invocation in
            let arguments = ScmFakeGit.arguments(invocation)
            if arguments.contains("-b") {
                return ScmFakeGit.failure("fatal: a branch named 'feature' already exists")
            }
            return ScmFakeGit.ok()
        }
        let remote = GitBranch(name: "feature", longName: "refs/remotes/origin/feature", upstream: nil, ahead: 0, behind: 0)
        try await client.checkoutBranch(remote)

        #expect(fake.invocations.map(ScmFakeGit.arguments) == [
            ["checkout", "-b", "feature", "--track", "origin/feature"],
            ["checkout", "feature"]
        ])
    }

    @Test(arguments: [
        ("origin/feature", "refs/remotes/origin/feature", "feature"),
        ("origin/feature/deep", "refs/remotes/origin/feature/deep", "feature/deep"),
        ("feature", "refs/remotes/origin/feature", "feature")
    ])
    func remoteBranchesGetALocalNameWithoutTheRemotePrefix(name: String, longName: String, local: String) async throws {
        let (client, fake) = ScmFakeGit.client { _ in ScmFakeGit.ok() }
        let remote = GitBranch(name: name, longName: longName, upstream: nil, ahead: 0, behind: 0)
        try await client.checkoutBranch(remote)

        #expect(fake.invocations.map(ScmFakeGit.arguments) == [
            ["checkout", "-b", local, "--track", longName.replacingOccurrences(of: "refs/remotes/", with: "")]
        ])
    }

    @Test
    func aRemoteReferenceWithoutARemoteSegmentKeepsItsWholeName() async throws {
        let (client, fake) = ScmFakeGit.client { _ in ScmFakeGit.ok() }
        let odd = GitBranch(name: "x", longName: "refs/remotes/lonely", upstream: nil, ahead: 0, behind: 0)
        try await client.checkoutBranch(odd)
        #expect(fake.invocations.map(ScmFakeGit.arguments) == [["checkout", "-b", "lonely", "--track", "lonely"]])
    }

    @Test
    func checkoutFailuresOtherThanAnExistingBranchPropagate() async throws {
        let (client, fake) = ScmFakeGit.client { _ in ScmFakeGit.failure("error: pathspec 'x' did not match") }
        let remote = GitBranch(name: "x", longName: "refs/remotes/origin/x", upstream: nil, ahead: 0, behind: 0)
        await #expect(throws: GitClient.GitClientError.outputError("pathspec 'x' did not match")) {
            try await client.checkoutBranch(remote)
        }
        let local = GitBranch(name: "x", longName: "refs/heads/x", upstream: nil, ahead: 0, behind: 0)
        await #expect(throws: GitClient.GitClientError.outputError("pathspec 'x' did not match")) {
            try await client.checkoutBranch(local)
        }
        #expect(fake.invocations.count == 2)
    }

    @Test
    func checkoutOfALocalBranchWithANewNameCreatesIt() async throws {
        let (client, fake) = ScmFakeGit.client { _ in ScmFakeGit.ok() }
        let local = GitBranch(name: "main", longName: "refs/heads/main", upstream: nil, ahead: 0, behind: 0)
        try await client.checkoutBranch(local, newName: "copy")
        #expect(fake.invocations.map(ScmFakeGit.arguments) == [["checkout", "-b", "copy", "main"]])
    }

    @Test
    func checkoutOfARemoteBranchUnderANewNameTracksTheRemote() async throws {
        let (client, fake) = ScmFakeGit.client { _ in ScmFakeGit.ok() }
        let remote = GitBranch(name: "origin/feature", longName: "refs/remotes/origin/feature", upstream: nil, ahead: 0, behind: 0)
        try await client.checkoutBranch(remote, newName: "mine")
        #expect(fake.invocations.map(ScmFakeGit.arguments) == [["checkout", "-b", "mine", "--track", "origin/feature"]])
    }

    @Test(arguments: [
        ("HEAD -> main, tag: v1, origin/main", ["main", "origin/main"], "v1"),
        ("tag: v2, tag: v1", [String](), "v2, v1"),
        ("HEAD -> main, tag: v1.0, tag: rc-1, origin/main, origin/HEAD, feature", ["main", "origin/main", "feature"], "v1.0, rc-1"),
        ("HEAD -> main, origin/main, origin/HEAD", ["main", "origin/main"], ""),
        ("tag:v3", [String](), "v3"),
        ("HEAD", ["HEAD"], ""),
        (" , ", [String](), ""),
        ("", [String](), "")
    ])
    func decorationsSplitIntoRefsAndTags(decoration: String, refs: [String], tag: String) {
        let parsed = GitClient.commitHistoryDecoration(decoration)
        #expect(parsed.refs == refs)
        #expect(parsed.tag == tag)
    }
}
