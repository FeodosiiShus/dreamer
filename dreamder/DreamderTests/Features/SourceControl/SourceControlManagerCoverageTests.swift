import AppKit
import Foundation
import Testing
@testable import Dreamder

private struct ScmManagerLocalizedError: LocalizedError {
    var description: String?
    var reason: String?
    var suggestion: String?

    var errorDescription: String? { description }
    var failureReason: String? { reason }
    var recoverySuggestion: String? { suggestion }
}

private struct ScmManagerPlainError: Error {}

@MainActor
private struct ScmManagerWorld {
    let world: ScmRemoteWorld
    let manager: SourceControlManager

    static func make(in directory: URL, origin: Bool = true, push: Bool = true) async throws -> ScmManagerWorld {
        let world = try await ScmRemoteWorld.make(in: directory, origin: origin)
        if origin && push {
            try await world.client.pushToRemote(remote: "origin", branch: "main", setUpstream: true)
        }
        let manager = SourceControlManager(workspaceURL: world.work.root, editorManager: EditorManager())
        return ScmManagerWorld(world: world, manager: manager)
    }

    var work: GitMergeFixture { world.work }

    func rev(_ revision: String) async throws -> String {
        try await world.head(of: world.work, revision)
    }

    func remoteBranches(of fixture: GitMergeFixture) async throws -> [String] {
        try await fixture.run("branch", "--format=%(refname:short)")
            .split(separator: "\n")
            .map(String.init)
            .sorted()
    }
}

@MainActor
@Suite(.uiGate)
struct SourceControlManagerCoverage {
    @Test
    func repositoryLocationFindsTheNearestGitEntryAndItsPrefix() async throws {
        try await withTempDir { directory in
            let plain = directory.appending(path: "plain", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
            #expect(SourceControlManager.repositoryLocation(of: plain) == nil)

            let repo = directory.appending(path: "repo", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
            _ = try await GitMergeFixture(root: repo)
            #expect(SourceControlManager.repositoryLocation(of: repo) == SourceControlManager.RepositoryLocation(prefix: nil))

            let nested = repo.appending(path: "sub/deeper", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            #expect(SourceControlManager.repositoryLocation(of: nested) == SourceControlManager.RepositoryLocation(prefix: "sub/deeper"))

            let hooks = repo.appending(path: ".git/hooks", directoryHint: .isDirectory)
            #expect(SourceControlManager.repositoryLocation(of: hooks) == nil)
        }
    }

    @Test
    func managersKnowWhetherTheirWorkspaceIsARepository() async throws {
        try await withTempDir { directory in
            let plain = directory.appending(path: "plain", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
            let notRepository = SourceControlManager(workspaceURL: plain, editorManager: EditorManager())
            #expect(notRepository.isGitRepository == false)
            #expect(notRepository.gitClient.scopePath == nil)
            #expect(notRepository.repositoryURL == plain)

            let repo = directory.appending(path: "repo", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
            _ = try await GitMergeFixture(root: repo)
            let manager = SourceControlManager(workspaceURL: repo, editorManager: EditorManager())
            #expect(manager.isGitRepository)
            #expect(manager.gitClient.scopePath == nil)
            #expect(manager.repositoryURL == repo)
            #expect(manager.workspaceURL == repo)
            #expect(manager.changedFiles.isEmpty)
        }
    }

    private func bareManager(_ directory: URL) -> SourceControlManager {
        SourceControlManager(workspaceURL: directory, editorManager: EditorManager())
    }

    @Test
    func localBranchesAreOrderedCurrentFirstThenAlphabetically() throws {
        try withTempDir { directory in
            let manager = bareManager(directory)
            func branch(_ name: String, _ long: String) -> GitBranch {
                GitBranch(name: name, longName: long, upstream: nil, ahead: 0, behind: 0)
            }
            let main = branch("main", "refs/heads/main")
            manager.branches = [
                branch("feature/b", "refs/heads/feature/b"),
                branch("Alpha", "refs/heads/Alpha"),
                main,
                branch("origin/x", "refs/remotes/origin/x")
            ]

            #expect(manager.orderedLocalBranches.map(\.name) == ["Alpha", "feature/b", "main"])

            manager.currentBranch = main
            #expect(manager.orderedLocalBranches.map(\.name) == ["main", "Alpha", "feature/b"])

            manager.branches = []
            #expect(manager.orderedLocalBranches.map(\.name) == ["main"])
        }
    }

    @Test
    func presentingThePushOrPullSheetResetsTheOperationSelection() throws {
        try withTempDir { directory in
            let manager = bareManager(directory)
            let branch = GitBranch(name: "main", longName: "refs/heads/main", upstream: nil, ahead: 0, behind: 0)
            @MainActor func dirty() {
                manager.operationBranch = branch
                manager.operationRebase = true
                manager.operationForce = true
                manager.operationIncludeTags = true
            }
            @MainActor func isClean() -> Bool {
                manager.operationBranch == nil && !manager.operationRebase
                    && !manager.operationForce && !manager.operationIncludeTags
            }

            dirty()
            manager.pushSheetIsPresented = true
            #expect(manager.pushSheetIsPresented)
            #expect(isClean())

            dirty()
            manager.pullSheetIsPresented = true
            #expect(manager.pullSheetIsPresented)
            #expect(isClean())
        }
    }

    @Test
    func gitClientErrorsAreShownWithTheirOwnDescription() async throws {
        try await withTempDir { directory in
            let manager = bareManager(directory)
            await manager.showAlertForError(title: "Push failed", error: GitClient.GitClientError.noRemoteConfigured)
            #expect(manager.lastAlert == SourceControlAlert(title: "Push failed", message: "No remote configured"))
        }
    }

    @Test
    func localizedErrorsCombineDescriptionReasonAndSuggestion() async throws {
        try await withTempDir { directory in
            let manager = bareManager(directory)
            let cases: [(ScmManagerLocalizedError, String)] = [
                (ScmManagerLocalizedError(description: "D", reason: "R", suggestion: "S"), "D\n\nR\n\nS"),
                (ScmManagerLocalizedError(description: nil, reason: "R", suggestion: nil), "R"),
                (ScmManagerLocalizedError(description: nil, reason: nil, suggestion: "S"), "S"),
                (ScmManagerLocalizedError(description: "D", reason: nil, suggestion: "S"), "D\n\nS"),
                (ScmManagerLocalizedError(description: "D", reason: "R", suggestion: nil), "D\n\nR"),
                (ScmManagerLocalizedError(description: nil, reason: "R", suggestion: "S"), "R\n\nS")
            ]
            for (error, message) in cases {
                await manager.showAlertForError(title: "T", error: error)
                #expect(manager.lastAlert == SourceControlAlert(title: "T", message: message))
            }
        }
    }

    @Test
    func otherErrorsFallBackToTheirLocalizedDescription() async throws {
        try await withTempDir { directory in
            let manager = bareManager(directory)
            await manager.showAlertForError(title: "T", error: ScmManagerPlainError())
            #expect(manager.lastAlert == SourceControlAlert(title: "T", message: ScmManagerPlainError().localizedDescription))
        }
    }

    @Test
    func errorAlertsRunThroughTheSuppressedHeadlessModal() async throws {
        guard DreamderHeadless.isEnabled else { return }
        try await withTempDir { directory in
            let manager = bareManager(directory)
            let title = "Source control alert \(UUID().uuidString)"
            let before = DreamderHeadless.suppressedModals.count

            await manager.showAlertForError(title: title, error: ScmManagerPlainError())

            #expect(manager.lastAlert?.title == title)
            #expect(DreamderHeadless.suppressedModals.dropFirst(before).contains(title))
        }
    }

    @Test
    func discardingEverythingOutsideARepositoryShowsTheFailureAlert() async throws {
        try await withTempDir { directory in
            let manager = bareManager(directory)

            manager.discardAllChanges()

            try await eventually { manager.lastAlert?.title == "Failed to discard changes" }
        }
    }

    @Test
    func stashedChangesAreAppliedThroughTheManager() async throws {
        try await withTempDir { directory in
            let fixture = try await ScmManagerWorld.make(in: directory, origin: false)
            let manager = fixture.manager
            try fixture.work.write("a.txt", "wip\n")

            try await manager.stashChanges(message: "saved")
            #expect(try fixture.work.read("a.txt") == "one\n")
            let entry = try #require(manager.stashEntries.first)
            #expect(entry.message == "saved")

            try await manager.applyStashEntry(stashEntry: entry)

            #expect(try fixture.work.read("a.txt") == "wip\n")
            #expect(manager.changedFiles.map(\.fileURL.lastPathComponent) == ["a.txt"])
        }
    }

    @Test
    func refreshLoadsRemotesBranchesCurrentBranchAndCounters() async throws {
        try await withTempDir { directory in
            let fixture = try await ScmManagerWorld.make(in: directory)
            await fixture.manager.branchOpsRefresh()

            #expect(fixture.manager.remotes.map(\.name) == ["origin"])
            #expect(fixture.manager.branches.map(\.name).contains("main"))
            #expect(fixture.manager.currentBranch?.name == "main")
            #expect(fixture.manager.currentBranch?.upstream == "origin/main")
            #expect(fixture.manager.numberOfUnsyncedCommits.ahead == 0)
            #expect(fixture.manager.changedFiles.isEmpty)
            #expect(await fixture.manager.branchOpsOperationState() == GitBranchOperationState.none)
        }
    }

    @Test
    func localBranchLifecycleGoesThroughTheManager() async throws {
        try await withTempDir { directory in
            let fixture = try await ScmManagerWorld.make(in: directory)
            let manager = fixture.manager

            try await manager.branchOpsCreateBranch(name: "feature", from: nil)
            #expect(manager.currentBranch?.name == "feature")
            try fixture.work.write("f.txt", "f\n")
            try await fixture.work.commit("feature work")
            let featureTip = try await fixture.rev("feature")

            try await manager.branchOpsCheckoutLocal("main")
            #expect(manager.currentBranch?.name == "main")
            #expect(await manager.branchOpsBranchExists("feature"))
            #expect(await manager.branchOpsBranchExists("nope") == false)
            #expect(try await manager.branchOpsRevision("feature") == featureTip)
            #expect(try await manager.branchOpsCommitCount(branch: "feature", notIn: "main") == 1)
            let commits = try await manager.branchOpsCommits(branch: "feature", notIn: "main")
            #expect(commits.map(\.subject) == ["feature work"])
            let unmerged = try await manager.branchOpsUnmergedCommits(branch: "feature", base: "main")
            #expect(unmerged.count == 1)
            #expect(unmerged[0].hasSuffix("feature work"))
            #expect(await manager.branchOpsRecentBranchNames(limit: 5).contains("feature"))

            #expect(try await manager.branchOpsMerge("feature") == false)
            #expect(fixture.work.exists("f.txt"))

            try await manager.branchOpsCreateBranch(name: "spare", from: "main", checkout: false)
            try await manager.branchOpsCreateBranch(name: "spare", from: "feature", checkout: false, overwrite: true)
            #expect(try await fixture.rev("spare") == featureTip)
            try await manager.branchOpsRenameBranch(oldName: "spare", newName: "spare2")
            try await manager.branchOpsDeleteLocalBranch("spare2")
            try await manager.branchOpsRestoreBranch(name: "restored", at: featureTip)
            #expect(try await fixture.remoteBranches(of: fixture.work).contains("restored"))

            try await manager.branchOpsCheckoutRevision(featureTip)
            #expect(try await fixture.work.run("rev-parse", "--abbrev-ref", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines) == "HEAD")
            try await manager.branchOpsCheckoutLocal("main")

            try await fixture.work.run("checkout", "-q", "-b", "wip")
            try fixture.work.write("wip.txt", "w\n")
            try await fixture.work.commit("wip work")
            try await manager.branchOpsCheckoutLocal("main")
            await #expect(throws: GitClient.GitClientError.branchNotFullyMerged) {
                try await manager.branchOpsDeleteLocalBranch("wip")
            }
            try await manager.branchOpsDeleteLocalBranch("wip", force: true)
            #expect(try await fixture.remoteBranches(of: fixture.work).contains("wip") == false)
        }
    }

    @Test
    func tagsAreRestoredListedPushedAndDeletedThroughTheManager() async throws {
        try await withTempDir { directory in
            let fixture = try await ScmManagerWorld.make(in: directory)
            let manager = fixture.manager
            #expect(await manager.branchOpsTags().isEmpty)
            let head = try await fixture.rev("HEAD")

            try await manager.branchOpsRestoreTag(name: "v1", at: head)
            #expect(await manager.branchOpsTags().map(\.name) == ["v1"])

            try await manager.branchOpsPushTag(name: "v1", remote: "origin")
            let remoteTags = try await fixture.world.bare.run("tag", "--list")
            #expect(remoteTags.trimmingCharacters(in: .whitespacesAndNewlines) == "v1")

            try await manager.branchOpsDeleteTag("v1")
            #expect(await manager.branchOpsTags().isEmpty)
        }
    }

    @Test
    func remoteBranchOperationsGoThroughTheManager() async throws {
        try await withTempDir { directory in
            let fixture = try await ScmManagerWorld.make(in: directory)
            let manager = fixture.manager
            let other = try await fixture.world.clone(named: "other", in: directory)
            try await other.fixture.run("checkout", "-q", "-b", "feature")
            try other.fixture.write("feature.txt", "f\n")
            try await other.fixture.commit("feature work")
            try await other.fixture.run("push", "-q", "-u", "origin", "feature")

            try await manager.branchOpsFetchAll()
            try await manager.branchOpsCheckoutRemote("origin/feature")
            #expect(manager.currentBranch?.name == "feature")
            #expect(manager.currentBranch?.upstream == "origin/feature")

            try await manager.branchOpsCheckoutLocal("main")
            try await manager.branchOpsCheckoutRemoteTrackingBranch(localName: "tracking", remote: "origin/feature")
            #expect(manager.currentBranch?.name == "tracking")
            try await manager.branchOpsCheckoutLocal("main")
            try await manager.branchOpsCheckoutRemoteTrackingBranch(localName: "tracking", remote: "origin/feature", overwrite: true)
            #expect(manager.currentBranch?.name == "tracking")
            try await manager.branchOpsCheckoutLocal("main")
            try await manager.branchOpsResetLocalBranchToRemote(localName: "feature", remote: "origin/feature")
            #expect(manager.currentBranch?.name == "feature")
            try await manager.branchOpsCheckoutLocal("main")

            try await manager.branchOpsSetUpstream(branch: "tracking", upstream: "origin/main")
            #expect(try await fixture.world.head(of: fixture.work, "tracking@{upstream}") == fixture.rev("origin/main"))
            try await manager.branchOpsSetUpstream(branch: "tracking", upstream: nil)
            await #expect(throws: (any Error).self) {
                _ = try await fixture.work.run("rev-parse", "tracking@{upstream}")
            }

            try await manager.branchOpsDeleteRemoteBranch(remote: "origin", branch: "feature")
            #expect(try await fixture.remoteBranches(of: fixture.world.bare) == ["main"])
        }
    }

    @Test
    func pullingAndUpdatingBranchesGoThroughTheManager() async throws {
        try await withTempDir { directory in
            let fixture = try await ScmManagerWorld.make(in: directory)
            let manager = fixture.manager
            let other = try await fixture.world.clone(named: "other", in: directory)

            func publish(_ name: String) async throws {
                try other.fixture.write(name, "x\n")
                try await other.fixture.commit("remote \(name)")
                try await other.fixture.run("push", "-q", "origin", "main")
            }

            try await publish("one.txt")
            try await manager.branchOpsUpdateProject()
            #expect(fixture.work.exists("one.txt"))

            try await publish("two.txt")
            try await manager.branchOpsPull(ref: "origin/main", rebase: false)
            #expect(fixture.work.exists("two.txt"))

            try fixture.work.write("local.txt", "l\n")
            try await fixture.work.commit("local")
            try await publish("three.txt")
            try await manager.branchOpsPull(ref: "origin/main", rebase: true)
            #expect(fixture.work.exists("three.txt"))
            #expect(fixture.work.exists("local.txt"))
            try await fixture.work.run("push", "-q", "origin", "main")
            try await other.fixture.run("pull", "-q", "--ff-only")

            try await publish("four.txt")
            try await manager.branchOpsUpdateBranch(name: "main", upstream: "origin/main", isCurrent: true)
            #expect(fixture.work.exists("four.txt"))

            try await fixture.work.run("branch", "side", "main~1")
            try await manager.branchOpsUpdateBranch(name: "side", upstream: "origin/main", isCurrent: false)
            #expect(try await fixture.rev("side") == fixture.rev("origin/main"))

            await #expect(throws: GitClient.GitClientError.self) {
                try await manager.branchOpsPull(ref: "origin", rebase: false)
            }
            await #expect(throws: GitClient.GitClientError.self) {
                try await manager.branchOpsUpdateBranch(name: "main", upstream: "main", isCurrent: true)
            }
        }
    }

    @Test
    func worktreesAreAddedThroughTheManager() async throws {
        try await withTempDir { directory in
            let fixture = try await ScmManagerWorld.make(in: directory)
            try await fixture.work.run("branch", "wt")
            let withRef = directory.appending(path: "wt-ref", directoryHint: .isDirectory)
            let withoutRef = directory.appending(path: "wt-new", directoryHint: .isDirectory)

            try await fixture.manager.branchOpsAddWorktree(path: withRef.path(percentEncoded: false), ref: "wt")
            try await fixture.manager.branchOpsAddWorktree(path: withoutRef.path(percentEncoded: false), ref: nil)

            #expect(FileManager.default.fileExists(atPath: withRef.appending(path: "a.txt").path(percentEncoded: false)))
            #expect(FileManager.default.fileExists(atPath: withoutRef.appending(path: "a.txt").path(percentEncoded: false)))
        }
    }

    private func makeConflictWorld(_ directory: URL) async throws -> (ScmManagerWorld, topicTip: String) {
        let fixture = try await ScmManagerWorld.make(in: directory, origin: false)
        try fixture.work.write("c.txt", "base\n")
        try await fixture.work.commit("base")
        try await fixture.work.run("checkout", "-q", "-b", "topic")
        try fixture.work.write("c.txt", "topic\n")
        try await fixture.work.commit("topic change")
        let topicTip = try await fixture.rev("HEAD")
        try await fixture.work.run("checkout", "-q", "main")
        try fixture.work.write("c.txt", "main\n")
        try await fixture.work.commit("main change")
        await fixture.manager.branchOpsRefresh()
        return (fixture, topicTip)
    }

    @Test
    func mergeConflictsAreReportedAndCanBeAborted() async throws {
        try await withTempDir { directory in
            let (fixture, _) = try await makeConflictWorld(directory)
            let manager = fixture.manager

            #expect(try await manager.branchOpsMerge("topic"))
            #expect(await manager.branchOpsOperationState().isMerging)
            try await manager.branchOpsMergeAbort()
            #expect(await manager.branchOpsOperationState() == GitBranchOperationState.none)
            #expect(try fixture.work.read("c.txt") == "main\n")
        }
    }

    @Test
    func rebaseConflictsCanBeAbortedContinuedAndSkipped() async throws {
        try await withTempDir { directory in
            let (fixture, _) = try await makeConflictWorld(directory)
            let manager = fixture.manager
            let baseTip = try await fixture.rev("main~1")

            try await manager.branchOpsCheckoutLocal("topic")
            #expect(try await manager.branchOpsRebase(onto: "main"))
            #expect(await manager.branchOpsOperationState().isRebasing)
            try await manager.branchOpsRebaseAbort()
            #expect(await manager.branchOpsOperationState() == GitBranchOperationState.none)

            #expect(try await manager.branchOpsRebase(onto: "main"))
            try fixture.work.write("c.txt", "resolved\n")
            try await fixture.work.run("add", "c.txt")
            try await manager.branchOpsRebaseContinue()
            #expect(await manager.branchOpsOperationState() == GitBranchOperationState.none)
            #expect(try fixture.work.read("c.txt") == "resolved\n")

            try await fixture.work.run("checkout", "-q", "-b", "other", baseTip)
            try fixture.work.write("c.txt", "other\n")
            try await fixture.work.commit("other change")
            try await manager.branchOpsCheckoutLocal("main")
            #expect(try await manager.branchOpsCheckoutAndRebase("other", onto: "main"))
            try await manager.branchOpsRebaseSkip()
            #expect(await manager.branchOpsOperationState() == GitBranchOperationState.none)
            #expect(manager.currentBranch?.name == "other")

            try await manager.branchOpsCheckoutLocal("main")
            try await fixture.work.run("checkout", "-q", "-b", "clean")
            try fixture.work.write("clean.txt", "c\n")
            try await fixture.work.commit("clean change")
            try await manager.branchOpsCheckoutLocal("main")
            #expect(try await manager.branchOpsCheckoutAndRebase("clean", onto: "main") == false)
        }
    }

    @Test
    func cherryPickConflictsCanBeAbortedAndContinued() async throws {
        try await withTempDir { directory in
            let (fixture, topicTip) = try await makeConflictWorld(directory)
            let manager = fixture.manager

            _ = try await fixture.work.runIgnoringFailure("cherry-pick", topicTip)
            #expect(await manager.branchOpsOperationState().isCherryPicking)
            try await manager.branchOpsCherryPickAbort()
            #expect(await manager.branchOpsOperationState() == GitBranchOperationState.none)

            _ = try await fixture.work.runIgnoringFailure("cherry-pick", topicTip)
            try fixture.work.write("c.txt", "picked\n")
            try await fixture.work.run("add", "c.txt")
            try await manager.branchOpsCherryPickContinue()
            #expect(await manager.branchOpsOperationState() == GitBranchOperationState.none)
            #expect(try fixture.work.read("c.txt") == "picked\n")
        }
    }
}
