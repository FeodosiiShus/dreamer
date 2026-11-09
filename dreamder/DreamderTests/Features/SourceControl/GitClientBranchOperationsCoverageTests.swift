import Foundation
import Testing
@testable import Dreamder

@Suite
struct GitClientBranchOperationsCoverage {
    private static func recordingClient() -> (client: GitClient, fake: FakeProcessRunner) {
        ScmFakeGit.client { invocation in
            ScmFakeGit.arguments(invocation).first == "rev-list" ? ScmFakeGit.ok("3\n") : ScmFakeGit.ok()
        }
    }

    static func calls(_ fake: FakeProcessRunner) -> [[String]] {
        fake.invocations.map(ScmFakeGit.arguments)
    }

    @Test
    func operationStateDefaultsToNoOngoingOperation() {
        let state = GitBranchOperationState()
        #expect(state == GitBranchOperationState.none)
        #expect(state.hasOngoingOperation == false)
        #expect(GitBranchOperationState(isMerging: true).hasOngoingOperation)
        #expect(GitBranchOperationState(isRebasing: true).hasOngoingOperation)
        #expect(GitBranchOperationState(isCherryPicking: true).hasOngoingOperation)
        #expect(GitBranchOperationState(isReverting: true).hasOngoingOperation)
    }

    @Test(arguments: [
        ("MERGE_HEAD", GitBranchOperationState(isMerging: true)),
        ("rebase-merge", GitBranchOperationState(isRebasing: true)),
        ("rebase-apply", GitBranchOperationState(isRebasing: true)),
        ("CHERRY_PICK_HEAD", GitBranchOperationState(isCherryPicking: true)),
        ("REVERT_HEAD", GitBranchOperationState(isReverting: true))
    ])
    func operationStateReadsMarkersFromAnAbsoluteGitDirectory(marker: String, expected: GitBranchOperationState) async throws {
        try await withTempDir { directory in
            let gitDirectory = directory.appending(path: "gitdir", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: gitDirectory, withIntermediateDirectories: true)
            let (client, _) = ScmFakeGit.client(directory: directory) { _ in
                ScmFakeGit.ok(gitDirectory.path(percentEncoded: false) + "\n")
            }
            #expect(await client.branchOpsOperationState() == GitBranchOperationState.none)

            try Data().write(to: gitDirectory.appending(path: marker))
            #expect(await client.branchOpsOperationState() == expected)
        }
    }

    @Test
    func operationStateResolvesARelativeGitDirectoryAgainstTheRepository() async throws {
        try await withTempDir { directory in
            let gitDirectory = directory.appending(path: ".git", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: gitDirectory, withIntermediateDirectories: true)
            try Data().write(to: gitDirectory.appending(path: "MERGE_HEAD"))
            let (client, fake) = ScmFakeGit.client(directory: directory) { _ in ScmFakeGit.ok(".git\n") }

            #expect(await client.branchOpsOperationState() == GitBranchOperationState(isMerging: true))
            #expect(Self.calls(fake) == [["rev-parse", "--git-dir"]])
        }
    }

    @Test
    func operationStateIsNoneWhenGitCannotLocateTheDirectory() async {
        let failing = ScmFakeGit.client { _ in ScmFakeGit.failure("fatal: not a git repository") }.client
        #expect(await failing.branchOpsOperationState() == GitBranchOperationState.none)

        let empty = ScmFakeGit.client { _ in ScmFakeGit.ok("  \n") }.client
        #expect(await empty.branchOpsOperationState() == GitBranchOperationState.none)
    }

    @Test
    func checkoutAndCreationCommandsUseTheExpectedFlags() async throws {
        let (client, fake) = Self.recordingClient()
        try await client.branchOpsCheckoutLocal("main")
        try await client.branchOpsCheckoutRemoteTrackingBranch(localName: "feat", remote: "origin/feat")
        try await client.branchOpsCheckoutRemoteTrackingBranch(localName: "feat", remote: "origin/feat", overwrite: true)
        try await client.branchOpsResetLocalBranchToRemote(localName: "feat", remote: "origin/feat")
        try await client.branchOpsCheckoutRevision("abc123")
        try await client.branchOpsCreateBranch(name: "a", from: nil)
        try await client.branchOpsCreateBranch(name: "b", from: "main", checkout: true, overwrite: true)
        try await client.branchOpsCreateBranch(name: "c", from: "main", checkout: false)
        try await client.branchOpsCreateBranch(name: "d", from: nil, checkout: false, overwrite: true)
        try await client.branchOpsRenameBranch(oldName: "old", newName: "new")
        try await client.branchOpsRenameBranch(oldName: "old", newName: "new", unsetUpstream: true)

        #expect(Self.calls(fake) == [
            ["checkout", "--end-of-options", "main"],
            ["checkout", "--track", "-b", "feat", "--end-of-options", "origin/feat"],
            ["checkout", "-B", "feat", "--end-of-options", "origin/feat"],
            ["checkout", "-B", "feat", "--end-of-options", "origin/feat"],
            ["checkout", "--end-of-options", "abc123"],
            ["checkout", "-b", "a"],
            ["checkout", "-B", "b", "--end-of-options", "main"],
            ["branch", "--end-of-options", "c", "main"],
            ["branch", "-f", "--end-of-options", "d"],
            ["branch", "-m", "--end-of-options", "old", "new"],
            ["branch", "-m", "--end-of-options", "old", "new"],
            ["branch", "--unset-upstream", "--end-of-options", "new"]
        ])
    }

    @Test
    func historyAndRestoreCommandsUseTheExpectedArguments() async throws {
        let (client, fake) = Self.recordingClient()
        #expect(try await client.branchOpsCommitCount(branch: "feat", notIn: "main") == 3)
        _ = try await client.branchOpsCommits(branch: "feat", notIn: "main")
        _ = try await client.branchOpsUnmergedCommits(branch: "feat", base: "main")
        try await client.branchOpsRestoreBranch(name: "gone", at: "abc")
        try await client.branchOpsRestoreTag(name: "v1", at: "abc")
        try await client.branchOpsDeleteRemoteBranch(remote: "origin", branch: "feat")
        try await client.branchOpsDeleteTag("v1")
        try await client.branchOpsPushTag(name: "v1", remote: "origin")

        #expect(Self.calls(fake) == [
            ["rev-list", "--count", "--end-of-options", "main..feat"],
            ["log", "--format=%h|%s|%an|%ad", "--date=short", "--end-of-options", "main..feat"],
            ["log", "--format=%h  %s", "--end-of-options", "main..feat"],
            ["branch", "--end-of-options", "gone", "abc"],
            ["tag", "--end-of-options", "v1", "abc"],
            ["push", "--delete", "--end-of-options", "origin", "feat"],
            ["tag", "-d", "--end-of-options", "v1"],
            ["push", "--end-of-options", "origin", "refs/tags/v1"]
        ])
    }

    @Test
    func nonNumericCommitCountsFallBackToZero() async throws {
        let (client, _) = ScmFakeGit.client { _ in ScmFakeGit.ok("many\n") }
        #expect(try await client.branchOpsCommitCount(branch: "a", notIn: "b") == 0)
    }

    @Test
    func unmergedCommitsAreTrimmedAndBlankLinesDropped() async throws {
        let (client, _) = ScmFakeGit.client { _ in ScmFakeGit.ok("abc1234  one\n\n  def5678  two  \n") }
        #expect(try await client.branchOpsUnmergedCommits(branch: "a", base: "b") == ["abc1234  one", "def5678  two"])
    }

    @Test
    func rebaseAndCherryPickControlCommandsUseTheExpectedArguments() async throws {
        let (client, fake) = Self.recordingClient()
        try await client.branchOpsRebaseAbort()
        try await client.branchOpsRebaseContinue()
        try await client.branchOpsRebaseSkip()
        try await client.branchOpsMergeAbort()
        try await client.branchOpsCherryPickAbort()
        try await client.branchOpsCherryPickContinue()

        #expect(Self.calls(fake) == [
            ["rebase", "--abort"],
            ["-c", "core.editor=true", "rebase", "--continue"],
            ["-c", "core.editor=true", "rebase", "--skip"],
            ["merge", "--abort"],
            ["cherry-pick", "--abort"],
            ["-c", "core.editor=true", "cherry-pick", "--continue"]
        ])
    }

    @Test
    func synchronisationCommandsUseTheExpectedArguments() async throws {
        let (client, fake) = Self.recordingClient()
        try await client.branchOpsFetchAll()
        try await client.branchOpsPullCurrent()
        try await client.branchOpsPull(ref: "origin/feat/x", rebase: true)
        try await client.branchOpsPull(ref: "origin/feat", rebase: false)
        try await client.branchOpsSetUpstream(branch: "feat", upstream: "origin/feat")
        try await client.branchOpsSetUpstream(branch: "feat", upstream: nil)
        try await client.branchOpsUpdateBranch(name: "main", upstream: "origin/main", isCurrent: true)
        try await client.branchOpsUpdateBranch(name: "feat", upstream: "origin/feat/x", isCurrent: false)
        try await client.branchOpsAddWorktree(path: "/tmp/wt", ref: "feat")
        try await client.branchOpsAddWorktree(path: "/tmp/wt2", ref: nil)
        try await client.branchOpsAddWorktree(path: "/tmp/wt3//", ref: nil)
        try await client.branchOpsAddWorktree(path: "/", ref: nil)

        #expect(Self.calls(fake) == [
            ["fetch", "--all", "--prune"],
            ["pull", "--no-rebase"],
            ["-c", "core.editor=true", "pull", "--rebase", "--end-of-options", "origin", "feat/x"],
            ["-c", "core.editor=true", "pull", "--no-rebase", "--end-of-options", "origin", "feat"],
            ["branch", "--set-upstream-to=origin/feat", "--end-of-options", "feat"],
            ["branch", "--unset-upstream", "--end-of-options", "feat"],
            ["fetch", "--end-of-options", "origin"],
            ["merge", "--ff-only", "--end-of-options", "origin/main"],
            ["fetch", "--end-of-options", "origin", "feat/x:feat"],
            ["worktree", "add", "--end-of-options", "/tmp/wt", "feat"],
            ["worktree", "add", "--end-of-options", "/tmp/wt2"],
            ["worktree", "add", "--end-of-options", "/tmp/wt3"],
            ["worktree", "add", "--end-of-options", "/"]
        ])
    }

    @Test(arguments: ["origin", "origin/", ""])
    func malformedRemoteReferencesAreRejectedWithoutRunningGit(reference: String) async {
        let (client, fake) = Self.recordingClient()
        await #expect(throws: GitClient.GitClientError.outputError("Invalid remote branch '\(reference)'")) {
            try await client.branchOpsPull(ref: reference, rebase: false)
        }
        await #expect(throws: GitClient.GitClientError.outputError("Invalid remote branch '\(reference)'")) {
            try await client.branchOpsCheckoutRemote(reference)
        }
        #expect(fake.invocations.isEmpty)
    }

    @Test
    func updatingFromAnUpstreamWithoutARemoteIsRejected() async {
        let (client, fake) = Self.recordingClient()
        await #expect(throws: GitClient.GitClientError.outputError("Invalid upstream branch 'main'")) {
            try await client.branchOpsUpdateBranch(name: "main", upstream: "main", isCurrent: true)
        }
        #expect(fake.invocations.isEmpty)
    }

    @Test
    func checkingOutARemoteBranchReusesAnExistingLocalBranch() async throws {
        let (existing, existingFake) = ScmFakeGit.client { invocation in
            ScmFakeGit.arguments(invocation).first == "rev-parse" ? ScmFakeGit.ok("abc\n") : ScmFakeGit.ok()
        }
        try await existing.branchOpsCheckoutRemote("origin/feat")
        #expect(Self.calls(existingFake) == [
            ["rev-parse", "-q", "--verify", "refs/heads/feat"],
            ["checkout", "--end-of-options", "feat"]
        ])

        let (missing, missingFake) = ScmFakeGit.client { invocation in
            ScmFakeGit.arguments(invocation).first == "rev-parse" ? ScmFakeGit.failure("", code: 1) : ScmFakeGit.ok()
        }
        try await missing.branchOpsCheckoutRemote("origin/feat")
        #expect(Self.calls(missingFake) == [
            ["rev-parse", "-q", "--verify", "refs/heads/feat"],
            ["checkout", "--track", "-b", "feat", "--end-of-options", "origin/feat"]
        ])
    }

    @Test
    func branchExistenceReportsMissingBranchesAndPropagatesRealFailures() async throws {
        let (found, _) = ScmFakeGit.client { _ in ScmFakeGit.ok("abc\n") }
        #expect(try await found.branchOpsBranchExists("main"))

        let (missing, _) = ScmFakeGit.client { _ in ScmFakeGit.failure("", code: 1) }
        #expect(try await missing.branchOpsBranchExists("nope") == false)

        let (broken, _) = ScmFakeGit.client { _ in ScmFakeGit.failure("fatal: not a git repository") }
        await #expect(throws: GitClient.GitClientError.notGitRepository) {
            _ = try await broken.branchOpsBranchExists("main")
        }
    }

    @Test
    func deletingABranchMapsUnmergedRefusalsOnlyWhenNotForced() async throws {
        let (client, fake) = ScmFakeGit.client { _ in
            ScmFakeGit.failure("error: the branch 'x' is not fully merged.", code: 1)
        }
        await #expect(throws: GitClient.GitClientError.branchNotFullyMerged) {
            try await client.branchOpsDeleteLocalBranch("x")
        }
        await #expect(throws: GitClient.GitClientError.outputError("the branch 'x' is not fully merged.")) {
            try await client.branchOpsDeleteLocalBranch("x", force: true)
        }

        let (other, _) = ScmFakeGit.client { _ in ScmFakeGit.failure("error: branch 'x' not found.", code: 1) }
        await #expect(throws: GitClient.GitClientError.outputError("branch 'x' not found.")) {
            try await other.branchOpsDeleteLocalBranch("x")
        }

        let (variant, _) = ScmFakeGit.client { _ in ScmFakeGit.failure("error: not merged yet", code: 1) }
        await #expect(throws: GitClient.GitClientError.branchNotFullyMerged) {
            try await variant.branchOpsDeleteLocalBranch("x")
        }

        let (ok, okFake) = ScmFakeGit.client { _ in ScmFakeGit.ok() }
        try await ok.branchOpsDeleteLocalBranch("x")
        try await ok.branchOpsDeleteLocalBranch("x", force: true)
        #expect(Self.calls(okFake) == [
            ["branch", "-d", "--end-of-options", "x"],
            ["branch", "-D", "--end-of-options", "x"]
        ])
        #expect(Self.calls(fake) == [
            ["branch", "-d", "--end-of-options", "x"],
            ["branch", "-D", "--end-of-options", "x"]
        ])
    }
}
