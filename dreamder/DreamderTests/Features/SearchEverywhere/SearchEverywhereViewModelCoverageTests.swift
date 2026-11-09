import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
final class ActionCounter {
    var performed = 0
    var dismissals = 0
}

@MainActor
@Suite(.serialized, .isolatedDefaults, .uiGate)
struct SearchEverywhereViewModelCoverageTests {
    private static let previewKey = "dreamder.searchEverywhere.showPreview"

    func makeModel(
        workspace: WorkspaceDocument?,
        mode: SearchEverywhereMode = .everywhere,
        actions: [SearchEverywhereAction] = []
    ) throws -> SearchEverywhereViewModel {
        let defaults = try IsolatedDefaults.require()
        return SearchEverywhereViewModel(
            workspace: workspace,
            mode: mode,
            defaults: defaults,
            recentFiles: SearchEverywhereRecentFilesStore(defaults: defaults),
            actions: { actions }
        )
    }

    @Test
    func selectingAnItemMovesTheSelectionAndRefreshesThePreview() async throws {
        try await withTempDir { dir in
            let workspace = try SearchEverywhereFixtures.makeWorkspace(dir)
            defer { workspace.tearDownFileScope() }
            let model = try makeModel(workspace: workspace)
            model.start(on: .files)
            model.query = "s"
            try await eventually { model.flatItems.count >= 2 }
            let second = try #require(model.flatItems.dropFirst().first)

            model.select(second)

            #expect(model.selection == 1)
            #expect(model.selectedItem?.id == second.id)
            try await eventually { model.preview?.url == second.url }

            model.select(second)
            #expect(model.selection == 1)

            model.select(SearchEverywhereFixtures.item(id: "file:not-in-results"))
            #expect(model.selection == 1)
        }
    }

    @Test
    func reselectingTheCurrentTabKeepsTheSelectionAndOtherTabsResetIt() async throws {
        try await withTempDir { dir in
            let workspace = try SearchEverywhereFixtures.makeWorkspace(dir)
            defer { workspace.tearDownFileScope() }
            let model = try makeModel(workspace: workspace)
            model.start(on: .files)
            model.query = "s"
            try await eventually { model.flatItems.count >= 2 }
            model.moveSelection(by: 1)

            model.selectTab(.files)

            #expect(model.tab == .files)
            #expect(model.selection == 1)

            model.selectTab(.classes)

            #expect(model.tab == .classes)
            #expect(model.selection == 0)
        }
    }

    @Test
    func pageKeysAndTheOptionShortcutDriveSelectionAndPreview() async throws {
        try await withTempDir { dir in
            let workspace = try SearchEverywhereFixtures.makeWorkspace(dir)
            defer { workspace.tearDownFileScope() }
            let model = try makeModel(workspace: workspace)
            model.start(on: .files)
            model.query = "s"
            try await eventually { model.flatItems.count >= 2 }
            let count = model.flatItems.count
            let defaults = try IsolatedDefaults.require()

            #expect(model.handle(event: try SearchEverywhereFixtures.keyEvent(119)))
            #expect(model.selection == count - 1)
            #expect(model.handle(event: try SearchEverywhereFixtures.keyEvent(116)))
            #expect(model.selection == max(count - 1 - 10, 0))

            #expect(model.handle(event: try SearchEverywhereFixtures.keyEvent(35)) == false)
            #expect(model.showsPreview)

            #expect(model.handle(event: try SearchEverywhereFixtures.keyEvent(35, flags: .option)))
            #expect(!model.showsPreview)
            #expect(model.preview == nil)
            #expect(defaults.object(forKey: Self.previewKey) as? Bool == false)

            #expect(model.handle(event: try SearchEverywhereFixtures.keyEvent(35, flags: .option)))
            #expect(model.showsPreview)
            try await eventually { model.preview != nil }
            #expect(defaults.object(forKey: Self.previewKey) as? Bool == true)
        }
    }

    @Test
    func thePreviewPreferenceIsReadBackFromTheInjectedDefaults() throws {
        let defaults = try IsolatedDefaults.require()
        let first = try makeModel(workspace: nil)
        #expect(first.showsPreview)

        first.togglePreview()

        let second = try makeModel(workspace: nil)
        #expect(!second.showsPreview)
        #expect(defaults.object(forKey: Self.previewKey) as? Bool == false)
        let recents = try makeModel(workspace: nil, mode: .recentFiles)
        #expect(!recents.showsPreview)
    }

    @Test
    func actionsAreListedFilteredAndPerformedOnOpen() async throws {
        let counter = ActionCounter()
        let toggle = SearchEverywhereFixtures.action("Navigate | Toggle Everything") { counter.performed += 1 }
        let close = SearchEverywhereFixtures.action("Window | Close Window")
        let model = try makeModel(workspace: nil, actions: [toggle, close])
        model.dismiss = { counter.dismissals += 1 }

        model.start(on: .actions)

        #expect(Set(model.flatItems.map(\.title)) == ["Toggle Everything", "Close Window"])
        #expect(model.flatItems.allSatisfy { $0.kind == .action })

        model.query = "toggle"
        try await eventually { model.flatItems.map(\.title) == ["Toggle Everything"] }
        let item = try #require(model.selectedItem)
        #expect(item.detail == "Navigate")
        #expect(item.action === toggle)

        model.openSelected()

        #expect(counter.performed == 1)
        #expect(counter.dismissals == 1)
    }

    @Test
    func openingWithoutResultsDoesNothing() throws {
        let counter = ActionCounter()
        let model = try makeModel(workspace: nil)
        model.dismiss = { counter.dismissals += 1 }

        model.openSelected()

        #expect(counter.dismissals == 0)
    }

    @Test
    func recentFilesLeadTheAllTabAndGiveWayToFileResultsOnAQuery() async throws {
        try await withTempDir { dir in
            let workspace = try SearchEverywhereFixtures.makeWorkspace(dir)
            defer { workspace.tearDownFileScope() }
            try SearchEverywhereFixtures.openTab("README.md", in: workspace, dir: dir)
            try SearchEverywhereFixtures.openTab("Sources/AppDelegate.swift", in: workspace, dir: dir)
            let model = try makeModel(workspace: workspace)

            model.start(on: .all)

            #expect(model.sections.first?.kind == .recent)
            let recent = model.flatItems.filter { $0.section == .recent }
            #expect(Set(recent.map(\.title)) == ["README.md", "AppDelegate.swift"])
            #expect(Set(recent.map(\.detail)) == ["", "Sources"])
            #expect(recent.allSatisfy { $0.kind == .file && $0.url != nil })

            model.query = "appdel"
            try await eventually {
                model.flatItems.contains { $0.section == .files && $0.title == "AppDelegate.swift" }
            }
            #expect(!model.flatItems.contains { $0.section == .recent })
        }
    }

    @Test
    func recentFilesModeListsOnlyMatchingRecentFiles() async throws {
        try await withTempDir { dir in
            let workspace = try SearchEverywhereFixtures.makeWorkspace(dir)
            defer { workspace.tearDownFileScope() }
            try SearchEverywhereFixtures.openTab("README.md", in: workspace, dir: dir)
            try SearchEverywhereFixtures.openTab("Sources/Helpers/StringUtils.swift", in: workspace, dir: dir)
            let model = try makeModel(workspace: workspace, mode: .recentFiles)

            model.start(on: .all)

            #expect(model.tab == .files)
            #expect(Set(model.flatItems.map(\.title)) == ["README.md", "StringUtils.swift"])
            #expect(model.flatItems.allSatisfy { $0.section == .recent })

            model.query = "strutil"
            try await eventually { model.flatItems.map(\.title) == ["StringUtils.swift"] }

            model.query = "zzzzqqq"
            try await eventually { model.flatItems.isEmpty }
        }
    }
}
