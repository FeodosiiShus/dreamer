import Foundation
import Testing
@testable import Dreamder

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
}
