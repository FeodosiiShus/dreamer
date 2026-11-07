import Foundation
import Testing
@testable import Dreamder

@Suite
struct GitBranchOperationsTests {
    private struct Repo {
        let fixture: GitMergeFixture
        let client: GitClient

        var currentBranch: String {
            get throws {
                try fixture.run("rev-parse", "--abbrev-ref", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        func branches() throws -> [String] {
            try fixture.run("branch", "--format=%(refname:short)")
                .split(separator: "\n")
                .map(String.init)
                .sorted()
        }

        func upstream(of branch: String) -> String? {
            let output = try? fixture.run("rev-parse", "--abbrev-ref", "\(branch)@{upstream}")
            return output?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func makeRepo(_ dir: URL, name: String = "repo") throws -> Repo {
        let root = dir.appending(path: name)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fixture = try GitMergeFixture(root: root)
        try fixture.write("a.txt", "one\n")
        try fixture.commit("initial")
        return Repo(fixture: fixture, client: GitClient(directoryURL: root, shellClient: .live()))
    }

    private func makeClone(of origin: Repo, in dir: URL) throws -> Repo {
        let root = dir.appending(path: "clone")
        try origin.fixture.run("clone", "-q", origin.fixture.root.path(percentEncoded: false), root.path(percentEncoded: false))
        let fixture = GitMergeFixture(existing: root)
        try fixture.run("config", "user.email", "clone@dreamder.test")
        try fixture.run("config", "user.name", "Clone")
        try fixture.run("config", "commit.gpgsign", "false")
        return Repo(fixture: fixture, client: GitClient(directoryURL: root, shellClient: .live()))
    }

    @Test
    func createBranchFromHeadAndFromRef() async throws {
        try await withTempDir { dir in
            let repo = try makeRepo(dir)
            try repo.fixture.run("tag", "v1")
            try repo.fixture.write("a.txt", "two\n")
            try repo.fixture.commit("second")

            try await repo.client.branchOpsCreateBranch(name: "from-head", from: nil)
            #expect(try repo.currentBranch == "from-head")
            #expect(try repo.fixture.read("a.txt") == "two\n")

            try await repo.client.branchOpsCreateBranch(name: "from-tag", from: "v1")
            #expect(try repo.currentBranch == "from-tag")
            #expect(try repo.fixture.read("a.txt") == "one\n")
        }
    }

    @Test
    func creatingAnExistingBranchFails() async throws {
        try await withTempDir { dir in
            let repo = try makeRepo(dir)
            await #expect(throws: GitClient.GitClientError.self) {
                try await repo.client.branchOpsCreateBranch(name: "main", from: nil)
            }
            #expect(try repo.currentBranch == "main")
        }
    }

    @Test
    func renameAndDeleteLocalBranch() async throws {
        try await withTempDir { dir in
            let repo = try makeRepo(dir)
            try repo.fixture.run("branch", "old")
            try await repo.client.branchOpsRenameBranch(oldName: "old", newName: "renamed")
            #expect(try repo.branches() == ["main", "renamed"])

            try await repo.client.branchOpsDeleteLocalBranch("renamed")
            #expect(try repo.branches() == ["main"])
        }
    }

    @Test
    func deletingTheCurrentBranchFails() async throws {
        try await withTempDir { dir in
            let repo = try makeRepo(dir)
            await #expect(throws: GitClient.GitClientError.self) {
                try await repo.client.branchOpsDeleteLocalBranch("main")
            }
            #expect(try repo.branches() == ["main"])
        }
    }

    @Test
    func checkoutLocalBranchAndRevision() async throws {
        try await withTempDir { dir in
            let repo = try makeRepo(dir)
            let first = try repo.fixture.run("rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
            try repo.fixture.run("branch", "other")
            try repo.fixture.write("a.txt", "two\n")
            try repo.fixture.commit("second")

            try await repo.client.branchOpsCheckoutLocal("other")
            #expect(try repo.currentBranch == "other")

            try await repo.client.branchOpsCheckoutRevision(first)
            #expect(try repo.currentBranch == "HEAD")
            #expect(try repo.fixture.read("a.txt") == "one\n")
        }
    }

    @Test
    func checkoutOfUnknownBranchFailsAndKeepsHead() async throws {
        try await withTempDir { dir in
            let repo = try makeRepo(dir)
            await #expect(throws: GitClient.GitClientError.self) {
                try await repo.client.branchOpsCheckoutLocal("missing")
            }
            #expect(try repo.currentBranch == "main")
        }
    }

    @Test
    func checkoutRemoteCreatesTrackingBranchThenReusesIt() async throws {
        try await withTempDir { dir in
            let origin = try makeRepo(dir, name: "origin")
            try origin.fixture.run("branch", "feature")
            let clone = try makeClone(of: origin, in: dir)

            try await clone.client.branchOpsCheckoutRemote("origin/feature")
            #expect(try clone.currentBranch == "feature")
            #expect(clone.upstream(of: "feature") == "origin/feature")

            try await clone.client.branchOpsCheckoutLocal("main")
            try await clone.client.branchOpsCheckoutRemote("origin/feature")
            #expect(try clone.currentBranch == "feature")
            #expect(try clone.branches() == ["feature", "main"])
        }
    }

    @Test(arguments: ["origin", "origin/", "feature"])
    func checkoutRemoteRejectsNamesWithoutRemoteAndBranch(name: String) async throws {
        try await withTempDir { dir in
            let repo = try makeRepo(dir)
            await #expect(throws: GitClient.GitClientError.self) {
                try await repo.client.branchOpsCheckoutRemote(name)
            }
        }
    }

    @Test
    func mergeFastForwardsAndReportsConflicts() async throws {
        try await withTempDir { dir in
            let repo = try makeRepo(dir)
            try repo.fixture.run("checkout", "-q", "-b", "feature")
            try repo.fixture.write("b.txt", "feature\n")
            try repo.fixture.commit("feature adds b")
            try repo.fixture.run("checkout", "-q", "main")

            _ = try await repo.client.branchOpsMerge("feature")
            #expect(try repo.fixture.read("b.txt") == "feature\n")

            try repo.fixture.run("checkout", "-q", "feature")
            try repo.fixture.write("a.txt", "feature side\n")
            try repo.fixture.commit("feature edits a")
            try repo.fixture.run("checkout", "-q", "main")
            try repo.fixture.write("a.txt", "main side\n")
            try repo.fixture.commit("main edits a")

            let conflicted = try await repo.client.branchOpsMerge("feature")
            #expect(conflicted)
            #expect(try repo.fixture.unmergedPaths() == ["a.txt"])
            #expect(await repo.client.branchOpsOperationState().isMerging)

            try await repo.client.branchOpsMergeAbort()
            #expect(await repo.client.branchOpsOperationState() == .none)
        }
    }

    @Test
    func checkoutAndRebaseReplaysBranchOntoTarget() async throws {
        try await withTempDir { dir in
            let repo = try makeRepo(dir)
            try repo.fixture.run("checkout", "-q", "-b", "feature")
            try repo.fixture.write("feature.txt", "f\n")
            try repo.fixture.commit("feature work")
            try repo.fixture.run("checkout", "-q", "main")
            try repo.fixture.write("main.txt", "m\n")
            try repo.fixture.commit("main work")

            _ = try await repo.client.branchOpsCheckoutAndRebase("feature", onto: "main")

            #expect(try repo.currentBranch == "feature")
            let log = try repo.fixture.run("log", "--format=%s").split(separator: "\n").map(String.init)
            #expect(log == ["feature work", "main work", "initial"])
        }
    }

    @Test
    func tagsAreListedSortedAndCanBeDeleted() async throws {
        try await withTempDir { dir in
            let repo = try makeRepo(dir)
            try repo.fixture.run("tag", "v2")
            try repo.fixture.run("tag", "v10")
            try repo.fixture.run("tag", "a-tag")

            let tags = try await repo.client.branchOpsListTags()
            #expect(tags.map(\.name) == ["a-tag", "v10", "v2"])
            #expect(tags.allSatisfy { !$0.objectName.isEmpty })

            try await repo.client.branchOpsDeleteTag("v10")
            #expect(try await repo.client.branchOpsListTags().map(\.name) == ["a-tag", "v2"])
        }
    }

    @Test
    func recentBranchesComeFromReflogMostRecentFirst() async throws {
        try await withTempDir { dir in
            let repo = try makeRepo(dir)
            try repo.fixture.run("branch", "first")
            try repo.fixture.run("branch", "second")
            try repo.fixture.run("checkout", "-q", "first")
            try repo.fixture.run("checkout", "-q", "second")
            try repo.fixture.run("checkout", "-q", "main")

            let names = try await repo.client.branchOpsRecentBranchNames(limit: 2)
            #expect(names == ["main", "second"])
        }
    }

    @Test
    func setAndUnsetUpstream() async throws {
        try await withTempDir { dir in
            let origin = try makeRepo(dir, name: "origin")
            try origin.fixture.run("branch", "feature")
            let clone = try makeClone(of: origin, in: dir)
            try clone.fixture.run("branch", "--no-track", "local", "origin/main")

            try await clone.client.branchOpsSetUpstream(branch: "local", upstream: "origin/feature")
            #expect(clone.upstream(of: "local") == "origin/feature")

            try await clone.client.branchOpsSetUpstream(branch: "local", upstream: nil)
            #expect(clone.upstream(of: "local") == nil)
        }
    }

    @Test
    func pullWithoutTrackingBranchFails() async throws {
        try await withTempDir { dir in
            let origin = try makeRepo(dir, name: "origin")
            let clone = try makeClone(of: origin, in: dir)
            try clone.fixture.run("checkout", "-q", "-b", "untracked")
            await #expect(throws: GitClient.GitClientError.self) {
                try await clone.client.branchOpsPullCurrent()
            }
        }
    }

    @Test
    func fetchAndPullBringRemoteCommits() async throws {
        try await withTempDir { dir in
            let origin = try makeRepo(dir, name: "origin")
            let clone = try makeClone(of: origin, in: dir)
            try origin.fixture.write("a.txt", "remote\n")
            try origin.fixture.commit("remote change")

            try await clone.client.branchOpsFetchAll()
            #expect(try clone.fixture.read("a.txt") == "one\n")
            let behind = try clone.fixture.run("rev-list", "--count", "main..origin/main")
            #expect(behind.trimmingCharacters(in: .whitespacesAndNewlines) == "1")

            try await clone.client.branchOpsPullCurrent()
            #expect(try clone.fixture.read("a.txt") == "remote\n")
        }
    }

    @Test
    func updateBranchFastForwardsCurrentAndNonCurrentBranches() async throws {
        try await withTempDir { dir in
            let origin = try makeRepo(dir, name: "origin")
            try origin.fixture.run("branch", "feature")
            let clone = try makeClone(of: origin, in: dir)
            try clone.fixture.run("branch", "feature", "origin/feature")
            try origin.fixture.write("a.txt", "main moved\n")
            try origin.fixture.commit("main moved")
            try origin.fixture.run("checkout", "-q", "feature")
            try origin.fixture.write("f.txt", "feature moved\n")
            try origin.fixture.commit("feature moved")

            try await clone.client.branchOpsUpdateBranch(name: "main", upstream: "origin/main", isCurrent: true)
            #expect(try clone.fixture.read("a.txt") == "main moved\n")

            try await clone.client.branchOpsUpdateBranch(name: "feature", upstream: "origin/feature", isCurrent: false)
            let subject = try clone.fixture.run("log", "-1", "--format=%s", "feature")
            #expect(subject.trimmingCharacters(in: .whitespacesAndNewlines) == "feature moved")
            #expect(try clone.currentBranch == "main")
        }
    }

    @Test
    func updateBranchRejectsUpstreamWithoutRemote() async throws {
        try await withTempDir { dir in
            let repo = try makeRepo(dir)
            await #expect(throws: GitClient.GitClientError.self) {
                try await repo.client.branchOpsUpdateBranch(name: "main", upstream: "main", isCurrent: true)
            }
        }
    }

    @Test
    func deleteRemoteBranchPushesDeletion() async throws {
        try await withTempDir { dir in
            let origin = try makeRepo(dir, name: "origin")
            try origin.fixture.run("branch", "doomed")
            let clone = try makeClone(of: origin, in: dir)

            try await clone.client.branchOpsDeleteRemoteBranch(remote: "origin", branch: "doomed")
            #expect(try origin.branches() == ["main"])
        }
    }

    @Test
    func deleteLocalBranchRefusesUnmergedUntilForced() async throws {
        try await withTempDir { dir in
            let repo = try makeRepo(dir)
            try repo.fixture.run("checkout", "-q", "-b", "unmerged")
            try repo.fixture.write("b.txt", "b\n")
            try repo.fixture.commit("unmerged work")
            try repo.fixture.run("checkout", "-q", "main")

            await #expect(throws: GitClient.GitClientError.branchNotFullyMerged) {
                try await repo.client.branchOpsDeleteLocalBranch("unmerged")
            }
            #expect(try repo.branches().contains("unmerged"))

            let commits = try await repo.client.branchOpsUnmergedCommits(branch: "unmerged", base: "main")
            #expect(commits == ["unmerged work"] || commits.first?.hasSuffix("unmerged work") == true)

            try await repo.client.branchOpsDeleteLocalBranch("unmerged", force: true)
            #expect(try repo.branches() == ["main"])
        }
    }

    @Test
    func restoreBranchAtItsOldTip() async throws {
        try await withTempDir { dir in
            let repo = try makeRepo(dir)
            try repo.fixture.run("branch", "keep")
            let tip = try await repo.client.branchOpsRevision("keep")

            try await repo.client.branchOpsDeleteLocalBranch("keep")
            #expect(try repo.branches() == ["main"])

            try await repo.client.branchOpsRestoreBranch(name: "keep", at: tip)
            #expect(try repo.branches() == ["keep", "main"])
            #expect(try await repo.client.branchOpsRevision("keep") == tip)
        }
    }

    @Test
    func createBranchWithoutCheckoutAndWithOverwrite() async throws {
        try await withTempDir { dir in
            let repo = try makeRepo(dir)
            try await repo.client.branchOpsCreateBranch(name: "later", from: nil, checkout: false)
            #expect(try repo.currentBranch == "main")
            #expect(try repo.branches() == ["later", "main"])

            await #expect(throws: GitClient.GitClientError.self) {
                try await repo.client.branchOpsCreateBranch(name: "later", from: nil, checkout: false)
            }

            try await repo.client.branchOpsCreateBranch(
                name: "later",
                from: "main",
                checkout: false,
                overwrite: true
            )
            #expect(try repo.currentBranch == "main")

            try await repo.client.branchOpsCreateBranch(name: "checked-out", from: nil)
            #expect(try repo.currentBranch == "checked-out")
        }
    }

    @Test
    func renameBranchCanUnsetUpstream() async throws {
        try await withTempDir { dir in
            let origin = try makeRepo(dir, name: "origin")
            let clone = try makeClone(of: origin, in: dir)
            try clone.fixture.run("branch", "--track", "tracker", "origin/main")

            try await clone.client.branchOpsRenameBranch(
                oldName: "tracker",
                newName: "renamed",
                unsetUpstream: true
            )
            #expect(try clone.branches().contains("renamed"))
            #expect(clone.upstream(of: "renamed") == nil)
        }
    }

    @Test
    func addWorktreeCreatesDirectoryOnDisk() async throws {
        try await withTempDir { dir in
            let repo = try makeRepo(dir)
            try repo.fixture.run("branch", "wt")
            let worktree = dir.appending(path: "worktree")
            try await repo.client.branchOpsAddWorktree(path: worktree.path(percentEncoded: false), ref: "wt")
            #expect(FileManager.default.fileExists(atPath: worktree.appending(path: "a.txt").path(percentEncoded: false)))
            let list = try repo.fixture.run("worktree", "list", "--porcelain")
            #expect(list.contains("worktree"))
        }
    }

    @Test
    func pushTagToRemote() async throws {
        try await withTempDir { dir in
            let origin = try makeRepo(dir, name: "origin")
            let clone = try makeClone(of: origin, in: dir)
            try clone.fixture.run("tag", "v9")

            try await clone.client.branchOpsPushTag(name: "v9", remote: "origin")
            #expect(try origin.fixture.run("tag").contains("v9"))
        }
    }

    @Test
    func pullUsingRebaseAndMerge() async throws {
        try await withTempDir { dir in
            let origin = try makeRepo(dir, name: "origin")
            let clone = try makeClone(of: origin, in: dir)
            try clone.fixture.write("local.txt", "local\n")
            try clone.fixture.commit("local work")
            try origin.fixture.write("a.txt", "remote\n")
            try origin.fixture.commit("remote change")

            try await clone.client.branchOpsPull(ref: "origin/main", rebase: true)
            #expect(try clone.fixture.read("a.txt") == "remote\n")
            let merges = try clone.fixture.run("log", "--merges", "--format=%s")
            #expect(merges.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            try clone.fixture.write("local2.txt", "local2\n")
            try clone.fixture.commit("local work 2")
            try origin.fixture.write("a.txt", "remote2\n")
            try origin.fixture.commit("remote change 2")

            try await clone.client.branchOpsPull(ref: "origin/main", rebase: false)
            #expect(try clone.fixture.read("a.txt") == "remote2\n")
            let mergeCount = try clone.fixture.run("rev-list", "--count", "--merges", "HEAD")
            #expect(mergeCount.trimmingCharacters(in: .whitespacesAndNewlines) == "1")
        }
    }

    @Test
    func compareCommitsListsBothDirections() async throws {
        try await withTempDir { dir in
            let repo = try makeRepo(dir)
            try repo.fixture.run("checkout", "-q", "-b", "feature")
            try repo.fixture.write("f.txt", "f\n")
            try repo.fixture.commit("feature work")
            try repo.fixture.run("checkout", "-q", "main")
            try repo.fixture.write("m.txt", "m\n")
            try repo.fixture.commit("main work")

            let featureOnly = try await repo.client.branchOpsCommits(branch: "feature", notIn: "main")
            #expect(featureOnly.map(\.subject) == ["feature work"])
            let mainOnly = try await repo.client.branchOpsCommits(branch: "main", notIn: "feature")
            #expect(mainOnly.map(\.subject) == ["main work"])
        }
    }

    @Test
    func rebaseConflictCanBeAbortedContinuedOrSkipped() async throws {
        try await withTempDir { dir in
            let repo = try makeRepo(dir)
            try repo.fixture.run("checkout", "-q", "-b", "feature")
            try repo.fixture.write("a.txt", "feature side\n")
            try repo.fixture.commit("feature edits a")
            try repo.fixture.run("checkout", "-q", "main")
            try repo.fixture.write("a.txt", "main side\n")
            try repo.fixture.commit("main edits a")
            try repo.fixture.run("checkout", "-q", "feature")

            #expect(try await repo.client.branchOpsRebase(onto: "main"))
            #expect(await repo.client.branchOpsOperationState().isRebasing)
            try await repo.client.branchOpsRebaseAbort()
            #expect(await repo.client.branchOpsOperationState() == .none)

            #expect(try await repo.client.branchOpsRebase(onto: "main"))
            try repo.fixture.write("a.txt", "resolved\n")
            try repo.fixture.run("add", "a.txt")
            try await repo.client.branchOpsRebaseContinue()
            #expect(await repo.client.branchOpsOperationState() == .none)
            #expect(try repo.fixture.read("a.txt") == "resolved\n")

            try repo.fixture.run("checkout", "-q", "-B", "feature", "main")
            try repo.fixture.write("a.txt", "feature again\n")
            try repo.fixture.commit("feature edits a again")
            try repo.fixture.run("checkout", "-q", "main")
            try repo.fixture.write("a.txt", "main third\n")
            try repo.fixture.commit("main edits a third")
            try repo.fixture.run("checkout", "-q", "feature")
            #expect(try await repo.client.branchOpsRebase(onto: "main"))
            try await repo.client.branchOpsRebaseSkip()
            #expect(await repo.client.branchOpsOperationState() == .none)
        }
    }

    @Test
    func branchExistenceTreatsAMissingBranchAsFalseNotAnError() async throws {
        try await withTempDir { dir in
            let repo = try makeRepo(dir)
            #expect(try await repo.client.branchOpsBranchExists("main"))
            #expect(try await repo.client.branchOpsBranchExists("missing") == false)
            #expect(try await repo.client.branchOpsBranchExists("feature/with space") == false)
        }
    }

    @Test
    func mergingAnUnknownRefIsAnErrorRatherThanACleanMerge() async throws {
        try await withTempDir { dir in
            let repo = try makeRepo(dir)
            await #expect(throws: GitClient.GitClientError.self) {
                try await repo.client.branchOpsMerge("does-not-exist")
            }
            #expect(await repo.client.branchOpsOperationState() == .none)
        }
    }

    @Test
    func mergeRefusedBecauseOfLocalChangesIsAnErrorNotAConflict() async throws {
        try await withTempDir { dir in
            let repo = try makeRepo(dir)
            try repo.fixture.run("checkout", "-q", "-b", "feature")
            try repo.fixture.write("a.txt", "feature side\n")
            try repo.fixture.commit("feature edits a")
            try repo.fixture.run("checkout", "-q", "main")
            try repo.fixture.write("a.txt", "uncommitted\n")

            await #expect(throws: GitClient.GitClientError.self) {
                try await repo.client.branchOpsMerge("feature")
            }
            #expect(await repo.client.branchOpsOperationState() == .none)
            #expect(try repo.fixture.read("a.txt") == "uncommitted\n")
        }
    }

    @Test
    func rebasingOntoAnUnknownRefIsAnError() async throws {
        try await withTempDir { dir in
            let repo = try makeRepo(dir)
            await #expect(throws: GitClient.GitClientError.self) {
                try await repo.client.branchOpsRebase(onto: "does-not-exist")
            }
        }
    }

    @Test
    func revisionLookupOfAnUnknownRevisionThrows() async throws {
        try await withTempDir { dir in
            let repo = try makeRepo(dir)
            await #expect(throws: GitClient.GitClientError.self) {
                try await repo.client.branchOpsRevision("does-not-exist")
            }
            #expect(try await repo.client.branchOpsRevision("main").count == 40)
        }
    }

    @Test
    func abortingWithoutAnOperationInProgressFails() async throws {
        try await withTempDir { dir in
            let repo = try makeRepo(dir)
            await #expect(throws: GitClient.GitClientError.self) { try await repo.client.branchOpsMergeAbort() }
            await #expect(throws: GitClient.GitClientError.self) { try await repo.client.branchOpsRebaseAbort() }
        }
    }

    @Test
    func hostileBranchNamesAreNeverInterpretedByAShell() async throws {
        try await withTempDir { dir in
            let repo = try makeRepo(dir)
            let name = "feature$(>pwned-name)`x`;y\"z'w"

            try await repo.client.branchOpsCreateBranch(name: name, from: nil, checkout: false)
            #expect(try repo.branches().contains(name))
            #expect(try await repo.client.branchOpsBranchExists(name))

            try await repo.client.branchOpsCheckoutLocal(name)
            #expect(try repo.currentBranch == name)

            try await repo.client.branchOpsCheckoutLocal("main")
            try await repo.client.branchOpsDeleteLocalBranch(name)
            #expect(try repo.branches() == ["main"])
            #expect(!repo.fixture.exists("pwned-name"))
        }
    }

    @Test
    func deletingABranchOnAnUnknownRemoteIsAnError() async throws {
        try await withTempDir { dir in
            let repo = try makeRepo(dir)
            await #expect(throws: GitClient.GitClientError.self) {
                try await repo.client.branchOpsDeleteRemoteBranch(remote: "nowhere", branch: "x")
            }
        }
    }
}
