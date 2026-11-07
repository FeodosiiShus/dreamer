import Foundation
import Testing
@testable import Dreamder

@Suite
struct GitCommandResultTests {
    private func result(
        _ stdout: String = "",
        stderr: String = "",
        exitCode: Int32 = 0,
        signal: Bool = false
    ) -> GitCommandResult {
        GitCommandResult(
            exitCode: exitCode,
            terminatedBySignal: signal,
            standardOutput: Data(stdout.utf8),
            standardError: Data(stderr.utf8)
        )
    }

    @Test
    func zeroExitIsSuccess() {
        #expect(result().success)
        #expect(result("out").success(ignoring: []))
    }

    @Test
    func nonZeroExitIsFailureUnlessIgnored() {
        let failed = result(exitCode: 1)
        #expect(!failed.success)
        #expect(failed.success(ignoring: [1]))
        #expect(!failed.success(ignoring: [2, 128]))
        #expect(result(exitCode: 0).success(ignoring: [1]))
    }

    @Test
    func startFailureIsNeverSuccessEvenWhenIgnored() {
        let failed = GitCommandResult.startFailed("no git")
        #expect(failed.exitCode == -1)
        #expect(!failed.success)
        #expect(!failed.success(ignoring: [-1, 0]))
        #expect(failed.errorOutput == ["no git"])
        #expect(failed.errorMessage == "no git")
    }

    @Test
    func signalTerminationIsNeverSuccess() {
        let killed = result(exitCode: 9, signal: true)
        #expect(!killed.success)
        #expect(!killed.success(ignoring: [9]))
        #expect(killed.errorMessage == "git was terminated by signal 9")
    }

    @Test
    func initFromProcessOutputCopiesEveryField() {
        let output = ProcessOutput(
            exitCode: 128,
            terminatedBySignal: false,
            standardOutput: Data("o".utf8),
            standardError: Data("fatal: bad\n".utf8)
        )
        let converted = GitCommandResult(output)
        #expect(converted.exitCode == 128)
        #expect(converted.outputText == "o")
        #expect(converted.standardErrorText == "fatal: bad\n")
        #expect(converted.startFailure == nil)
    }

    @Test
    func errorMessageComesFromStandardErrorWithPrefixesRemoved() {
        let failed = result(stderr: "fatal: not a git repository\nhint: do something\n", exitCode: 128)
        #expect(failed.errorMessage == "not a git repository\nhint: do something")
        #expect(result(stderr: "error: first\nerror: second\n", exitCode: 1).errorMessage == "first\nsecond")
    }

    @Test
    func errorMessageFallsBackToOutputThenToTheExitCode() {
        #expect(result("On branch main\nnothing to commit\n", exitCode: 1).errorMessage == "On branch main\nnothing to commit")
        #expect(result(exitCode: 3).errorMessage == "git exited with code 3")
    }

    @Test
    func successHasNoErrorMessage() {
        #expect(result("fine").errorMessage.isEmpty)
        #expect(result(stderr: "", exitCode: 0).errorMessage.isEmpty)
    }

    @Test
    func errorMessageDropsBannerHeaderLinesAndProgress() {
        let stderr = """
        @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
        @    WARNING: UNPROTECTED KEY FILE! @
        @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
        Receiving objects: 10% (1/10)
        fatal: could not read from remote
        """
        #expect(result(stderr: stderr, exitCode: 128).errorMessage == "could not read from remote")
    }

    @Test
    func outputLinesTrimTerminatorsAndKeepInnerEmptyLines() {
        #expect(result("a\nb\n").output == ["a", "b"])
        #expect(result("a\r\n\r\nb").output == ["a", "", "b"])
        #expect(result("").output.isEmpty)
        #expect(result("\n").output == [""])
    }

    @Test
    func errorOutputExcludesProgressLines() {
        let stderr = "Cloning into 'x'...\nremote: Counting objects: 5, done.\nReceiving objects: 100% (5/5), done.\nfatal: boom\n"
        #expect(result(stderr: stderr, exitCode: 128).errorOutput == ["Cloning into 'x'...", "fatal: boom"])
    }

    @Test
    func combinedTextJoinsOutputAndErrorWithoutLosingNewlines() {
        #expect(result("out\n", stderr: "err\n").combinedText == "out\nerr\n")
        #expect(result("out", stderr: "err").combinedText == "out\nerr")
        #expect(result("out").combinedText == "out")
        #expect(result(stderr: "err").combinedText == "err")
        #expect(GitCommandResult.startFailed("nope").combinedText == "nope")
    }

    @Test
    func rawOutputBytesAreKeptExactly() {
        let bytes = Data([0x00, 0xFF, 0x0A, 0x61])
        let raw = GitCommandResult(exitCode: 0, standardOutput: bytes)
        #expect(raw.standardOutput == bytes)
    }

    @Test(arguments: [
        "remote: Finding sources:   1% (575/57489)   ",
        "Receiving objects: 100% (57489/57489), 50.03 MiB | 2.83 MiB/s, done.",
        "Resolving deltas: 12% (3/25)",
        "Updating files:  50% (5/10)",
        "remote: Counting objects: 198285, done",
        "Expanding reachable commits in commit graph: 95907",
        "Delta compression using up to 8 threads",
        "remote: Compressing objects: 100% (3/3), done.",
        "Checking out files: 7"
    ])
    func recognizesProgressLines(line: String) {
        #expect(GitCommandResult.looksLikeProgress(line))
    }

    @Test(arguments: [
        "fatal: not a git repository",
        "error: failed to push some refs",
        "Switched to branch 'main'",
        "remote: Resolve conflicts first",
        "100% (3/3)",
        "note: 1000% (3/3)",
        "Already up to date.",
        ""
    ])
    func rejectsOrdinaryMessages(line: String) {
        #expect(!GitCommandResult.looksLikeProgress(line))
    }

    @Test
    func cleanupErrorPrefixesStripsLeadingMarkers() {
        #expect(GitCommandResult.cleanupErrorPrefixes("fatal: error: x") == "x")
        #expect(GitCommandResult.cleanupErrorPrefixes("error: fatal: x") == "fatal: x")
        #expect(GitCommandResult.cleanupErrorPrefixes("  fatal: x ") == "x")
        #expect(GitCommandResult.cleanupErrorPrefixes("warning: x") == "warning: x")
    }

    @Test
    func clientMapsFailuresToItsErrors() {
        #expect(GitClient.error(for: result(stderr: "fatal: not a git repository (or any parent)\n", exitCode: 128)) == .notGitRepository)
        #expect(GitClient.error(for: result(stderr: "fatal: No remote configured to list refs from.\n", exitCode: 128)) == .noRemoteConfigured)
        #expect(GitClient.error(for: result(stderr: "fatal: bad revision 'x'\n", exitCode: 128)) == .outputError("bad revision 'x'"))
        #expect(GitClient.error(for: .startFailed("no git")) == .outputError("no git"))
    }
}
