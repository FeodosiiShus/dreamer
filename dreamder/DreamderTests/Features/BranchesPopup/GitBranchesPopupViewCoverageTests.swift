import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
private final class GitBranchesPopupCoverageRecorder {
    var dismissals = 0
    var sizes: [CGSize] = []
    var presented: [BranchesPopupItemID] = []
    var focusRequests = 0
}

@MainActor
private final class GitBranchesPopupCoverageHarness {
    let fixture: GitMergeFixture
    let workspace: WorkspaceDocument
    let model: BranchesPopupViewModel
    let recorder: GitBranchesPopupCoverageRecorder
    let hosted: HostedView
    let defaults: UserDefaults
    let suiteName: String

    init(
        fixture: GitMergeFixture,
        workspace: WorkspaceDocument,
        model: BranchesPopupViewModel,
        recorder: GitBranchesPopupCoverageRecorder,
        hosted: HostedView,
        defaults: UserDefaults,
        suiteName: String
    ) {
        self.fixture = fixture
        self.workspace = workspace
        self.model = model
        self.recorder = recorder
        self.hosted = hosted
        self.defaults = defaults
        self.suiteName = suiteName
    }

    func close() {
        hosted.close()
        workspace.close()
        removeIsolatedDefaults(defaults, suiteName: suiteName)
    }

    func row(where predicate: (BranchesPopupRow) -> Bool) -> BranchesPopupRow? {
        model.rows.first(where: predicate)
    }

    func refRow(_ shortName: String) -> BranchesPopupRow? {
        row { $0.ref?.shortName == shortName }
    }

    func makeView(searchText: String = "") -> GitBranchesPopupView {
        let recorder = recorder
        return GitBranchesPopupView(
            viewModel: model,
            dismiss: { recorder.dismissals += 1 },
            onSizeChange: { recorder.sizes.append($0) },
            initialSearchText: searchText,
            presentMenu: { row, _, _ in recorder.presented.append(row.id) }
        )
    }
}

@MainActor
@Suite(.uiGate)
struct GitBranchesPopupViewCoverageTests {
    private func makeHarness(
        in dir: URL,
        searchText: String = "",
        waitForLoad: Bool = true
    ) async throws -> GitBranchesPopupCoverageHarness {
        let fixture = try await GitMergeFixture(root: dir)
        try fixture.write("a.txt", "a\n")
        try await fixture.commit("initial")
        try await fixture.run("tag", "v1.0")
        for name in ["feature/one", "feature/two", "obsolete"] {
            try await fixture.run("branch", name)
        }
        let workspace = try HostedViewFixture.makeWorkspace(in: dir)
        let manager = try #require(workspace.sourceControlManager)
        let (defaults, suiteName) = try makeIsolatedDefaults()
        let recorder = GitBranchesPopupCoverageRecorder()
        let model = BranchesPopupViewModel(
            sourceControlManager: manager,
            workspace: workspace,
            defaults: defaults,
            dismiss: { recorder.dismissals += 1 }
        )
        let view = GitBranchesPopupView(
            viewModel: model,
            dismiss: { recorder.dismissals += 1 },
            onSizeChange: { recorder.sizes.append($0) },
            initialSearchText: searchText,
            presentMenu: { row, _, _ in recorder.presented.append(row.id) }
        )
        let hosted = try HostedViewFixture.hostInWorkspace(workspace, size: NSSize(width: 500, height: 700)) { view }
        let harness = GitBranchesPopupCoverageHarness(
            fixture: fixture,
            workspace: workspace,
            model: model,
            recorder: recorder,
            hosted: hosted,
            defaults: defaults,
            suiteName: suiteName
        )
        hosted.layout()
        if waitForLoad {
            try await eventually { model.isLoading == false && model.rows.contains { $0.ref != nil } }
            try await hosted.settle()
        }
        return harness
    }

    private func withPopup(
        searchText: String = "",
        waitForLoad: Bool = true,
        _ body: (GitBranchesPopupCoverageHarness) async throws -> Void
    ) async throws {
        try await withTempDir { dir in
            let harness = try await makeHarness(in: dir, searchText: searchText, waitForLoad: waitForLoad)
            defer { harness.close() }
            try await body(harness)
        }
    }

    private func keyDown(_ keyCode: UInt16, in window: NSWindow) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: keyCode
            )
        )
    }

    @Test
    func popupRendersLoadingThenSectionsGroupsAndActions() async throws {
        try await withTempDir { dir in
            let harness = try await makeHarness(in: dir, waitForLoad: false)
            defer { harness.close() }
            let model = harness.model

            harness.hosted.layout()
            try await eventually { model.isLoading == false && model.rows.contains { $0.ref != nil } }
            try await harness.hosted.settle()

            #expect(harness.hosted.renders())
            #expect(model.rows.contains { $0.kind == .section })
            #expect(model.rows.contains { $0.kind == .group })
            #expect(model.rows.contains { $0.kind == .separator })
            #expect(model.rows.contains { $0.kind == .action })
            #expect(harness.refRow("feature/one") != nil)
            #expect(harness.recorder.sizes.contains { $0.width == 380 })
        }
    }

    @Test
    func theDefaultMenuPresenterTogglesGroupRowsWithoutOpeningAMenu() async throws {
        try await withPopup { harness in
            let model = harness.model
            let group = try #require(harness.row { $0.kind == .group })
            let view = GitBranchesPopupView(viewModel: model, dismiss: {})
            let wasExpanded = model.isExpanded(group.id)

            view.presentMenu(group, BranchesPopupRowAnchors(), model)

            #expect(model.isExpanded(group.id) == !wasExpanded)
        }
    }

    @Test
    func popupRendersEmptyMessageAndRestoresRowsWhenQueryClears() async throws {
        try await withPopup { harness in
            let model = harness.model
            let populated = harness.hosted.snapshot()

            model.query = "zzzz-no-branch"
            try await harness.hosted.settle()
            #expect(model.emptyMessage == "Nothing found")
            let empty = harness.hosted.snapshot()

            model.query = ""
            try await harness.hosted.settle()

            #expect(model.emptyMessage == nil)
            #expect(HostedView.pixelsDiffer(populated, empty))
        }
    }

    @Test
    func popupRendersFetchSpinnerWhileFetching() async throws {
        try await withPopup { harness in
            harness.model.isFetching = true
            try await harness.hosted.settle()
            let fetchingRenders = harness.hosted.renders()
            harness.model.isFetching = false
            try await harness.hosted.settle()

            #expect(fetchingRenders)
            #expect(harness.hosted.renders())
        }
    }

    @Test
    func popupRendersCollapsedSectionsGroupsAndSelection() async throws {
        try await withPopup { harness in
            let model = harness.model
            let group = try #require(harness.row { $0.kind == .group })
            let local = BranchesPopupItemID.section(.local)

            model.toggleExpansion(group.id)
            model.toggleExpansion(local)
            try await harness.hosted.settle()
            #expect(model.isExpanded(local) == false)

            model.toggleExpansion(local)
            model.toggleExpansion(group.id)
            let ref = try #require(harness.refRow("feature/two"))
            model.selectedID = ref.id
            try await harness.hosted.settle()
            model.selectedID = nil
            try await harness.hosted.settle()
            model.selectedID = harness.row { $0.kind == .section }?.id
            try await harness.hosted.settle()

            #expect(model.isExpanded(local))
            #expect(harness.hosted.renders())
        }
    }

    @Test
    func optionToggleStateIsReflectedInRows() async throws {
        try await withPopup { harness in
            let model = harness.model

            model.showsTags = false
            model.groupsByDirectory = false
            model.showsRecentBranches = false
            model.showsActionsInSearch = false
            try await harness.hosted.settle()

            #expect(harness.hosted.renders())
            #expect(harness.row { $0.kind == .group } == nil)
        }
    }

    @Test
    func initialSearchTextIsAppliedToTheModelAfterTheDebounce() async throws {
        try await withPopup(searchText: "feat") { harness in
            try await eventually { harness.model.query == "feat" }
            try await harness.hosted.settle()

            #expect(harness.model.query == "feat")
            #expect(harness.hosted.renders())
        }
    }

    @Test
    func onAppearInstallsTheRefMenuPresenter() async throws {
        try await withPopup { harness in
            let section = try #require(harness.row { $0.kind == .section })
            let ref = try #require(harness.refRow("feature/one"))

            harness.model.presentRefActions?(section)
            harness.model.presentRefActions?(ref)

            #expect(harness.recorder.presented == [section.id, ref.id])
        }
    }

    @Test
    func searchTextChangedClearsTheQueryOnSlashOnly() async throws {
        try await withPopup { harness in
            let view = harness.makeView()
            harness.model.query = "feat"

            view.searchTextChanged("feat", "feature")
            #expect(harness.model.query == "feat")

            view.searchTextChanged("feature", "/")
            #expect(harness.model.query == "")
        }
    }

    @Test
    func applySearchTextDebouncesAndHonoursCancellationAndNoChange() async throws {
        try await withPopup { harness in
            let unchanged = harness.makeView()
            await unchanged.applySearchText()
            #expect(harness.model.query == "")

            let typed = harness.makeView(searchText: "feat")
            await typed.applySearchText()
            #expect(harness.model.query == "feat")

            let cancelled = harness.makeView(searchText: "obs")
            let task = Task { @MainActor in await cancelled.applySearchText() }
            task.cancel()
            await task.value
            #expect(harness.model.query == "feat")
        }
    }

    @Test
    func appearedAndRemoveKeyMonitorCanRunOnAStandaloneView() async throws {
        try await withPopup { harness in
            let view = harness.makeView()
            let section = try #require(harness.row { $0.kind == .section })

            view.removeKeyMonitor()
            view.appeared()
            harness.model.presentRefActions?(section)

            #expect(harness.recorder.presented.last == section.id)
        }
    }

    @Test
    func rowActionsDriveTheModelAndRequestSearchFocus() async throws {
        try await withPopup { harness in
            let model = harness.model
            let recorder = harness.recorder
            let anchors = BranchesPopupRowAnchors()
            let section = try #require(harness.row { $0.id == .section(.local) })
            let ref = try #require(harness.refRow("feature/one"))

            func actions(for row: BranchesPopupRow) -> BranchesPopupRowActions {
                BranchesPopupRowActions(
                    row: row,
                    viewModel: model,
                    anchors: anchors,
                    presentMenu: { row, _, _ in recorder.presented.append(row.id) },
                    focusSearch: { recorder.focusRequests += 1 }
                )
            }

            let wasExpanded = model.isExpanded(section.id)
            actions(for: section).activate()
            #expect(model.isExpanded(section.id) == !wasExpanded)
            actions(for: section).toggle()
            #expect(model.isExpanded(section.id) == wasExpanded)

            let presentedBefore = recorder.presented.count
            actions(for: ref).activate()
            #expect(recorder.presented.count == presentedBefore + 1)
            actions(for: ref).openMenu()
            #expect(recorder.presented.last == ref.id)

            let favoriteID = try #require(ref.ref?.id)
            let favoriteBefore = model.favorites.contains(favoriteID)
            actions(for: ref).toggleFavorite()
            #expect(model.favorites.contains(favoriteID) == !favoriteBefore)
            actions(for: ref).toggleFavorite()
            #expect(model.favorites.contains(favoriteID) == favoriteBefore)

            let favoritesBeforeSection = model.favorites
            actions(for: section).toggleFavorite()
            #expect(model.favorites == favoritesBeforeSection)

            #expect(recorder.focusRequests == 7)
        }
    }

    @Test
    func arrowKeyMovesTheSelectionThroughTheInstalledKeyMonitor() async throws {
        try await withPopup { harness in
            let model = harness.model
            let before = model.selectedID
            let event = try keyDown(125, in: harness.hosted.window)

            var attempts = 0
            while model.selectedID == before, attempts < 100 {
                NSApp.sendEvent(event)
                attempts += 1
                try await Task.sleep(for: .milliseconds(20))
            }

            #expect(model.selectedID != before)
        }
    }

    @Test
    func escapeKeyDismissesThroughTheInstalledKeyMonitor() async throws {
        try await withPopup { harness in
            let event = try keyDown(53, in: harness.hosted.window)

            var attempts = 0
            while harness.recorder.dismissals == 0, attempts < 100 {
                NSApp.sendEvent(event)
                attempts += 1
                try await Task.sleep(for: .milliseconds(20))
            }

            #expect(harness.recorder.dismissals >= 1)
        }
    }

    @Test
    func publicInitBuildsAViewModelFromTheWorkspace() async throws {
        try await withPopup { harness in
            let manager = try #require(harness.workspace.sourceControlManager)
            let recorder = harness.recorder

            let view = GitBranchesPopupView(
                sourceControlManager: manager,
                workspace: harness.workspace,
                dismiss: { recorder.dismissals += 1 }
            )
            let host = try HostedViewFixture.hostInWorkspace(harness.workspace) { view }
            defer { host.close() }
            try await host.settle()

            #expect(host.renders())
            #expect(recorder.dismissals == 0)
        }
    }
}
