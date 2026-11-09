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

    private static func calls(_ fake: FakeProcessRunner) -> [[String]] {
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
            ["checkout", "main"],
            ["checkout", "--track", "-b", "feat", "origin/feat"],
            ["checkout", "-B", "feat", "origin/feat"],
            ["checkout", "-B", "feat", "origin/feat"],
            ["checkout", "abc123"],
            ["checkout", "-b", "a"],
            ["checkout", "-B", "b", "main"],
            ["branch", "c", "main"],
            ["branch", "-f", "d"],
            ["branch", "-m", "old", "new"],
            ["branch", "-m", "old", "new"],
            ["branch", "--unset-upstream", "new"]
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
            ["rev-list", "--count", "main..feat"],
            ["log", "--format=%h|%s|%an|%ad", "--date=short", "main..feat"],
            ["log", "--format=%h  %s", "main..feat"],
            ["branch", "gone", "abc"],
            ["tag", "v1", "abc"],
            ["push", "origin", "--delete", "feat"],
            ["tag", "-d", "v1"],
            ["push", "origin", "refs/tags/v1"]
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
            ["-c", "core.editor=true", "pull", "--rebase", "origin", "feat/x"],
            ["-c", "core.editor=true", "pull", "--no-rebase", "origin", "feat"],
            ["branch", "--set-upstream-to=origin/feat", "feat"],
            ["branch", "--unset-upstream", "feat"],
            ["fetch", "origin"],
            ["merge", "--ff-only", "origin/main"],
            ["fetch", "origin", "feat/x:feat"],
            ["worktree", "add", "/tmp/wt", "feat"],
            ["worktree", "add", "/tmp/wt2"],
            ["worktree", "add", "/tmp/wt3"],
            ["worktree", "add", "/"]
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
            ["checkout", "feat"]
        ])

        let (missing, missingFake) = ScmFakeGit.client { invocation in
            ScmFakeGit.arguments(invocation).first == "rev-parse" ? ScmFakeGit.failure("", code: 1) : ScmFakeGit.ok()
        }
        try await missing.branchOpsCheckoutRemote("origin/feat")
        #expect(Self.calls(missingFake) == [
            ["rev-parse", "-q", "--verify", "refs/heads/feat"],
            ["checkout", "--track", "-b", "feat", "origin/feat"]
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
        #expect(Self.calls(okFake) == [["branch", "-d", "x"], ["branch", "-D", "x"]])
        #expect(Self.calls(fake) == [["branch", "-d", "x"], ["branch", "-D", "x"]])
    }

    @Test
    func mergeReportsConflictsFromOutputOrStateAndFailuresOtherwise() async throws {
        let (conflicting, _) = ScmFakeGit.client { invocation in
            ScmFakeGit.arguments(invocation).contains("merge")
                ? ScmFakeGit.failure("CONFLICT (content): Merge conflict in a.txt", code: 1)
                : ScmFakeGit.ok()
        }
        #expect(try await conflicting.branchOpsMerge("topic"))

        let (clean, cleanFake) = ScmFakeGit.client { _ in ScmFakeGit.ok() }
        #expect(try await clean.branchOpsMerge("topic") == false)
        #expect(Self.calls(cleanFake).first == ["-c", "core.editor=true", "merge", "--no-edit", "topic"])

        let (failing, _) = ScmFakeGit.client { _ in ScmFakeGit.failure("fatal: refusing", code: 128) }
        await #expect(throws: GitClient.GitClientError.outputError("refusing")) {
            _ = try await failing.branchOpsMerge("topic")
        }
    }

    @Test
    func rebaseReportsConflictsFromOutputAndFailuresOtherwise() async throws {
        let (conflicting, _) = ScmFakeGit.client { invocation in
            ScmFakeGit.arguments(invocation).first == "rebase"
                ? ScmFakeGit.failure("error: could not apply abc123... change", code: 1)
                : ScmFakeGit.ok()
        }
        #expect(try await conflicting.branchOpsRebase(onto: "main"))

        let (conflictText, _) = ScmFakeGit.client { invocation in
            ScmFakeGit.arguments(invocation).first == "rebase"
                ? FakeProcessRunner.output("CONFLICT (content)", exitCode: 1)
                : ScmFakeGit.ok()
        }
        #expect(try await conflictText.branchOpsRebase(onto: "main"))

        let (clean, _) = ScmFakeGit.client { _ in ScmFakeGit.ok() }
        #expect(try await clean.branchOpsRebase(onto: "main") == false)

        let (failing, _) = ScmFakeGit.client { _ in ScmFakeGit.failure("fatal: invalid upstream", code: 128) }
        await #expect(throws: GitClient.GitClientError.outputError("invalid upstream")) {
            _ = try await failing.branchOpsRebase(onto: "main")
        }
    }

    @Test
    func checkoutAndRebaseSwitchesBeforeReplaying() async throws {
        let (client, fake) = ScmFakeGit.client { _ in ScmFakeGit.ok() }
        #expect(try await client.branchOpsCheckoutAndRebase("feat", onto: "main") == false)
        #expect(Self.calls(fake).prefix(2) == [["checkout", "feat"], ["rebase", "main"]])
    }

    @Test
    func tagsAreParsedFromRefListing() async throws {
        let (client, fake) = ScmFakeGit.client { _ in ScmFakeGit.ok("v2|bbb\nv1|aaa\n\n") }
        let tags = try await client.branchOpsListTags()
        #expect(tags == [GitTag(name: "v1", objectName: "aaa"), GitTag(name: "v2", objectName: "bbb")])
        #expect(Self.calls(fake) == [["for-each-ref", "--format=%(refname:short)|%(objectname:short)", "refs/tags"]])
    }

    @Test
    func revisionsAreTrimmed() async throws {
        let (client, _) = ScmFakeGit.client { _ in ScmFakeGit.ok("abc123\n") }
        #expect(try await client.branchOpsRevision("HEAD") == "abc123")
    }

    @Test
    func recentBranchesFilterTheReflogByExistingLocalBranches() async throws {
        let (client, _) = ScmFakeGit.client { invocation in
            switch ScmFakeGit.arguments(invocation).first {
            case "reflog":
                ScmFakeGit.ok("checkout: moving from main to feature\ncheckout: moving from feature to gone\n")
            default:
                ScmFakeGit.ok("refs/heads/main\nrefs/heads/feature\n")
            }
        }
        let recent = try await client.branchOpsRecentBranchNames(limit: 5)
        #expect(recent == ["feature"])
    }
}
