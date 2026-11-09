import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct BranchesPopupOngoingActionsCoverage {
    private let pooledDefaults: PooledDefaults
    private var defaults: UserDefaults { pooledDefaults.defaults }

    init() throws {
        pooledDefaults = try PooledDefaults()
    }

    @MainActor
    private final class Harness {
        let fixture: GitMergeFixture
        let manager: SourceControlManager
        let workspace: WorkspaceDocument
        let model: BranchesPopupViewModel

        init(_ fixture: GitMergeFixture, defaults: UserDefaults) {
            self.fixture = fixture
            manager = SourceControlManager(workspaceURL: fixture.root, editorManager: EditorManager())
            workspace = WorkspaceDocument()
            workspace.sourceControlManager = manager
            model = BranchesPopupViewModel(
                sourceControlManager: manager,
                workspace: workspace,
                defaults: defaults,
                dismiss: {}
            )
            model.notify = { _ in }
            model.openConflicts = {}
            model.comparePresenter = { _, _, _ in }
        }

        func settle() async throws {
            try await eventually { model.runningOperations == 0 }
        }

        func head() async throws -> String {
            try await fixture.run("log", "-1", "--format=%s").trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func conflictingRepository(in dir: URL) async throws -> GitMergeFixture {
        let fixture = try await GitMergeFixture(root: dir)
        try fixture.write("a.txt", "base\n")
        try await fixture.commit("base")
        try await fixture.run("checkout", "-q", "-b", "feature")
        try fixture.write("a.txt", "feature side\n")
        try await fixture.commit("feature edits a")
        try await fixture.run("checkout", "-q", "main")
        try fixture.write("a.txt", "main side\n")
        try await fixture.commit("main edits a")
        return fixture
    }

    private func makeHarness(for fixture: GitMergeFixture) async -> Harness {
        let harness = Harness(fixture, defaults: defaults)
        await harness.model.reload()
        return harness
    }

    @Test
    func cherryPickContinueReportsUnresolvedConflictsThenFinishesOnceResolved() async throws {
        try await withTempDir { dir in
            let fixture = try await conflictingRepository(in: dir)
            _ = try await fixture.runIgnoringFailure("cherry-pick", "feature")
            let harness = await makeHarness(for: fixture)
            #expect(harness.model.operationState.isCherryPicking)
            #expect(harness.model.rows.compactMap(\.ongoingAction) == [.cherryPickAbort, .cherryPickContinue])

            harness.model.performOngoing(.cherryPickContinue)
            try await eventually { harness.manager.lastAlert?.title == "Cherry-Pick Continue failed" }
            try await harness.settle()
            #expect(harness.model.operationState.isCherryPicking)

            try fixture.write("a.txt", "resolved\n")
            try await fixture.run("add", "a.txt")
            harness.model.performOngoing(.cherryPickContinue)

            try await eventually { harness.model.operationState == .none }
            try await harness.settle()
            #expect(try await harness.head() == "feature edits a")
            #expect(harness.model.rows.compactMap(\.ongoingAction).isEmpty)
        }
    }

    @Test
    func cherryPickAbortRestoresTheBranchTip() async throws {
        try await withTempDir { dir in
            let fixture = try await conflictingRepository(in: dir)
            _ = try await fixture.runIgnoringFailure("cherry-pick", "feature")
            let harness = await makeHarness(for: fixture)
            #expect(harness.model.operationState.isCherryPicking)

            harness.model.performOngoing(.cherryPickAbort)

            try await eventually { harness.model.operationState == .none }
            try await harness.settle()
            #expect(try await harness.head() == "main edits a")
            #expect(try fixture.read("a.txt") == "main side\n")
            #expect(harness.manager.lastAlert == nil)
        }
    }

    @Test
    func revertAbortLeavesTheRevertAndRestoresTheFile() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture(root: dir)
            try fixture.write("a.txt", "one\n")
            try await fixture.commit("one")
            try fixture.write("a.txt", "two\n")
            try await fixture.commit("two")
            try fixture.write("a.txt", "three\n")
            try await fixture.commit("three")
            _ = try await fixture.runIgnoringFailure("revert", "--no-edit", "HEAD~1")
            let harness = await makeHarness(for: fixture)
            #expect(harness.model.operationState.isReverting)
            #expect(harness.model.rows.compactMap(\.ongoingAction) == [.revertAbort])

            harness.model.performOngoing(.revertAbort)

            try await eventually { harness.model.operationState == .none }
            try await harness.settle()
            #expect(try await harness.head() == "three")
            #expect(try fixture.read("a.txt") == "three\n")
            #expect(harness.manager.lastAlert == nil)
        }
    }

    @Test
    func rebaseContinueReportsUnresolvedConflictsThenFinishesOnceResolved() async throws {
        try await withTempDir { dir in
            let fixture = try await conflictingRepository(in: dir)
            try await fixture.run("checkout", "-q", "feature")
            _ = try await fixture.runIgnoringFailure("rebase", "main")
            let harness = await makeHarness(for: fixture)
            #expect(harness.model.operationState.isRebasing)
            #expect(harness.model.rows.compactMap(\.ongoingAction) == [.rebaseAbort, .rebaseContinue, .rebaseSkip])

            harness.model.performOngoing(.rebaseContinue)
            try await eventually { harness.manager.lastAlert?.title == "Rebase Continue failed" }
            try await harness.settle()
            #expect(harness.model.operationState.isRebasing)

            try fixture.write("a.txt", "resolved\n")
            try await fixture.run("add", "a.txt")
            harness.model.performOngoing(.rebaseContinue)

            try await eventually { harness.model.operationState == .none }
            try await harness.settle()
            #expect(try await harness.head() == "feature edits a")
            #expect(try fixture.read("a.txt") == "resolved\n")
        }
    }

    @Test
    func rebaseSkipDropsTheConflictingCommit() async throws {
        try await withTempDir { dir in
            let fixture = try await conflictingRepository(in: dir)
            try await fixture.run("checkout", "-q", "feature")
            _ = try await fixture.runIgnoringFailure("rebase", "main")
            let harness = await makeHarness(for: fixture)
            #expect(harness.model.operationState.isRebasing)

            harness.model.performOngoing(.rebaseSkip)

            try await eventually { harness.model.operationState == .none }
            try await harness.settle()
            #expect(try await harness.head() == "main edits a")
            #expect(try fixture.read("a.txt") == "main side\n")
            #expect(harness.manager.lastAlert == nil)
        }
    }

    @Test
    func releasingTheModelStopsItsTreeObservation() async throws {
        try await withTempDir { dir in
            weak var released: BranchesPopupViewModel?
            do {
                let harness = Harness(GitMergeFixture(existing: dir), defaults: defaults)
                released = harness.model
                #expect(released != nil)
            }

            try await eventually { released == nil }
        }
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct BranchesPopupDefaultConflictsOpenerCoverage {
    private let pooledDefaults: PooledDefaults
    private var defaults: UserDefaults { pooledDefaults.defaults }

    init() throws {
        pooledDefaults = try PooledDefaults()
    }

    @Test
    func theDefaultConflictsOpenerShowsTheConflictsWindowOfItsWorkspace() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture(root: dir)
            try fixture.write("a.txt", "a\n")
            try await fixture.commit("initial")
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let manager = try #require(workspace.sourceControlManager)
            let model = BranchesPopupViewModel(
                sourceControlManager: manager,
                workspace: workspace,
                defaults: defaults,
                dismiss: {}
            )
            let opener = try #require(model.openConflicts)
            #expect(MergeToolPresenter.conflictsModel(for: workspace) == nil)

            opener()

            try await eventually { MergeToolPresenter.conflictsModel(for: workspace) != nil }
            let shown = try #require(MergeToolPresenter.conflictsModel(for: workspace))
            #expect(shown.workspace === workspace)
            if MergeToolPresenter.conflictsModel === shown {
                MergeToolPresenter.conflictsWindow?.close()
            }
        }
    }
}

@MainActor
@Suite(.uiGate)
struct BranchesPopupReleasedModelNotificationCoverage {
    private let pooledDefaults: PooledDefaults
    private var defaults: UserDefaults { pooledDefaults.defaults }

    init() throws {
        pooledDefaults = try PooledDefaults()
    }

    @MainActor
    private final class Sink {
        var requests: [BranchesPopupNotificationRequest] = []
        var conflictsOpened = 0
    }

    private func repository(in dir: URL, conflicting: Bool = false) async throws -> GitMergeFixture {
        let fixture = try await GitMergeFixture(root: dir)
        try fixture.write("a.txt", "base\n")
        try await fixture.commit("base")
        try await fixture.run("tag", "v1.0")
        try await fixture.run("branch", "obsolete")
        try await fixture.run("checkout", "-q", "-b", "feature")
        try fixture.write("a.txt", "feature side\n")
        try await fixture.commit("feature edits a")
        try await fixture.run("checkout", "-q", "main")
        if conflicting {
            try fixture.write("a.txt", "main side\n")
            try await fixture.commit("main edits a")
        }
        return fixture
    }

    private func localRef(_ name: String) -> BranchesPopupRef {
        BranchesPopupRef(kind: .local, name: name, shortName: name, upstream: nil, isCurrent: false)
    }

    private func requestAfterRelease(
        _ fixture: GitMergeFixture,
        sink: Sink,
        trigger: (BranchesPopupViewModel) -> Void
    ) async throws -> BranchesPopupNotificationRequest {
        weak var released: BranchesPopupViewModel?
        do {
            let manager = SourceControlManager(workspaceURL: fixture.root, editorManager: EditorManager())
            let workspace = WorkspaceDocument()
            workspace.sourceControlManager = manager
            let model = BranchesPopupViewModel(
                sourceControlManager: manager,
                workspace: workspace,
                defaults: defaults,
                dismiss: {}
            )
            model.notify = { sink.requests.append($0) }
            model.openConflicts = { sink.conflictsOpened += 1 }
            released = model
            trigger(model)
            try await eventually { sink.requests.count == 1 && model.runningOperations == 0 }
        }
        try await eventually { released == nil }
        return try #require(sink.requests.first)
    }

    private func branchNames(_ fixture: GitMergeFixture) async throws -> [String] {
        try await fixture.run("branch", "--format=%(refname:short)")
            .split(separator: "\n")
            .map(String.init)
            .sorted()
    }

    @Test
    func restoringABranchWorksAfterThePopupModelIsGone() async throws {
        try await withTempDir { dir in
            let fixture = try await repository(in: dir)
            let sink = Sink()
            let request = try await requestAfterRelease(fixture, sink: sink) { $0.delete(localRef("obsolete")) }
            #expect(request.title == "Deleted Branch: obsolete")
            #expect(try await branchNames(fixture).contains("obsolete") == false)

            request.action()

            try await eventually { (try? await branchNames(fixture))?.contains("obsolete") == true }
        }
    }

    @Test
    func restoringATagWorksAfterThePopupModelIsGone() async throws {
        try await withTempDir { dir in
            let fixture = try await repository(in: dir)
            let sink = Sink()
            let tag = BranchesPopupRef(kind: .tag, name: "v1.0", shortName: "v1.0", upstream: nil, isCurrent: false)
            let request = try await requestAfterRelease(fixture, sink: sink) { $0.delete(tag) }
            #expect(request.title == "Deleted Tag: v1.0")
            #expect(try await fixture.run("tag").contains("v1.0") == false)

            request.action()

            try await eventually { ((try? await fixture.run("tag")) ?? "").contains("v1.0") }
        }
    }

    @Test
    func resolvingMergeConflictsWorksAfterThePopupModelIsGone() async throws {
        try await withTempDir { dir in
            let fixture = try await repository(in: dir, conflicting: true)
            let sink = Sink()
            let request = try await requestAfterRelease(fixture, sink: sink) { $0.merge(localRef("feature")) }
            #expect(request.title == "Branch 'feature' merged with conflicts")
            #expect(sink.conflictsOpened == 0)

            request.action()

            #expect(sink.conflictsOpened == 1)
        }
    }

    @Test
    func resolvingRebaseConflictsWorksAfterThePopupModelIsGone() async throws {
        try await withTempDir { dir in
            let fixture = try await repository(in: dir, conflicting: true)
            let sink = Sink()
            let request = try await requestAfterRelease(fixture, sink: sink) { $0.rebaseCurrent(onto: localRef("feature")) }
            #expect(request.title == "Rebase stopped with conflicts")
            #expect(sink.conflictsOpened == 0)

            request.action()

            #expect(sink.conflictsOpened == 1)
        }
    }
}
