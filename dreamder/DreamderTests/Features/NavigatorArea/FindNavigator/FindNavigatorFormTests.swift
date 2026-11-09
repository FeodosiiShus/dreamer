import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct FindNavigatorFormTests {
    func withState(
        files: [String: String] = [:],
        _ body: (WorkspaceDocument, WorkspaceDocument.SearchState, URL) async throws -> Void
    ) async throws {
        try await withTempDir { dir in
            for (name, content) in files {
                try content.write(to: dir.appending(path: name), atomically: true, encoding: .utf8)
            }
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let state = try #require(workspace.searchState)
            try await eventually { state.indexStatus == .done }
            try await body(workspace, state, dir)
        }
    }

    @Test
    func rendersFindModeAndQueryEditsFlowIntoTheModel() async throws {
        try await withState { workspace, state, _ in
            let hosted = try HostedViewFixture.hostInWorkspace(workspace) { FindNavigatorForm(state: state) }
            defer { hosted.close() }
            try await hosted.settle()
            #expect(hosted.renders())
            #expect(hosted.views(of: NSPopUpButton.self).count == 3)
            let empty = hosted.snapshot()

            state.searchQuery = "needle"
            try await hosted.settle()
            #expect(state.findModel.isMultiline == false)
            #expect(HostedView.pixelsDiffer(empty, hosted.snapshot()))

            state.searchQuery = "needle\nhay"
            try await eventually { state.findModel.isMultiline }
            try await hosted.settle()
            #expect(hosted.renders())
        }
    }

    @Test
    func focusRequestIsConsumedOnAppearanceAndOnLaterChanges() async throws {
        try await withState { workspace, state, _ in
            state.shouldFocusSearchField = true
            let hosted = try HostedViewFixture.hostInWorkspace(workspace) { FindNavigatorForm(state: state) }
            defer { hosted.close() }
            try await eventually { !state.shouldFocusSearchField }

            state.shouldFocusSearchField = true
            try await eventually { !state.shouldFocusSearchField }
            #expect(hosted.renders())
        }
    }

    @Test
    func replaceModeShowsReplaceRowAndRegexTogglesTheModeList() async throws {
        try await withState { workspace, state, _ in
            state.selectedMode = [.Replace, .Text, .Containing]
            state.searchQuery = "foo"
            state.replaceText = "bar"
            let hosted = try HostedViewFixture.hostInWorkspace(workspace) { FindNavigatorForm(state: state) }
            defer { hosted.close() }
            try await hosted.settle()
            #expect(hosted.renders())
            let replace = hosted.snapshot()
            #expect(hosted.views(of: NSPopUpButton.self).count == 3)

            state.isRegularExpression = true
            try await hosted.settle()
            #expect(state.selectedMode == [.Replace, .RegularExpression])
            #expect(hosted.views(of: NSPopUpButton.self).count == 2)
            #expect(HostedView.pixelsDiffer(replace, hosted.snapshot()))

            state.selectedMode = [.Find, .Text, .Containing]
            try await hosted.settle()
            #expect(HostedView.pixelsDiffer(replace, hosted.snapshot()))
        }
    }

    @Test
    func scopeSectionRendersEveryScopeVariant() async throws {
        try await withState { workspace, state, _ in
            let collapsed = try HostedViewFixture.hostInWorkspace(workspace) { FindNavigatorForm(state: state) }
            defer { collapsed.close() }
            try await collapsed.settle()
            let collapsedShot = collapsed.snapshot()

            let project = try HostedViewFixture.hostInWorkspace(workspace) {
                FindNavigatorForm(state: state, showsScopeOptions: true)
            }
            defer { project.close() }
            try await project.settle()
            #expect(HostedView.pixelsDiffer(collapsedShot, project.snapshot()))
            let projectShot = project.snapshot()

            state.findModel.isProjectScope = false
            state.directoryScopePath = "Sources"
            try await project.settle()
            #expect(HostedView.pixelsDiffer(projectShot, project.snapshot()))
            #expect(state.scopeDescription == "Sources")

            state.fileMask = "*.swift"
            try await collapsed.settle()
            #expect(state.findModel.fileFilter == "*.swift")
            #expect(collapsed.renders())
        }
    }

    @Test
    func scopeButtonAndMaskStateChangeTheScopedLabelVariants() async throws {
        try await withState { workspace, state, _ in
            let form = FindNavigatorForm(state: state)
            form.toggleScopeOptions()
            let hosted = try HostedViewFixture.hostInWorkspace(workspace) { form }
            defer { hosted.close() }
            try await hosted.settle()
            let plain = hosted.snapshot()

            state.fileMask = "*.txt"
            try await hosted.settle()
            #expect(HostedView.pixelsDiffer(plain, hosted.snapshot()))

            state.fileMask = ""
            state.findModel.isProjectScope = false
            try await hosted.settle()
            #expect(hosted.renders())
        }
    }

    @Test
    func menuSelectionsDriveTheSelectedModeThroughTheRealPopupMenus() async throws {
        try await withState { workspace, state, _ in
            let hosted = try HostedViewFixture.hostInWorkspace(workspace) { FindNavigatorForm(state: state) }
            defer { hosted.close() }
            try await hosted.settle()
            let before = hosted.snapshot()

            let kindMenu = try #require(hosted.views(of: NSPopUpButton.self).first?.menu)
            kindMenu.performActionForItem(at: 1)
            try await eventually { state.selectedMode.first == .Replace }
            try await hosted.settle()
            #expect(state.selectedMode == [.Replace, .Text, .Containing])
            #expect(HostedView.pixelsDiffer(before, hosted.snapshot()))

            let popups = hosted.views(of: NSPopUpButton.self)
            #expect(popups.count == 3)
            let thirdPopup = try #require(popups.dropFirst(2).first)
            thirdPopup.menu?.performActionForItem(at: 2)
            try await eventually { state.selectedMode.third == .StartingWith }
            #expect(state.selectedMode == [.Replace, .Text, .StartingWith])
            #expect(state.makeFindModel(query: "x").textAnchor == .wordStart)
        }
    }

    @Test
    func onSelectMenuItemRebuildsTheModeListForEveryLevel() async throws {
        try await withState { _, state, _ in
            let form = FindNavigatorForm(state: state)

            form.onSelectMenuItem(0, searchMode: .Replace)
            #expect(state.selectedMode == [.Replace, .Text, .Containing])

            state.selectedMode = [.Find, .References, .RegularExpression]
            form.onSelectMenuItem(0, searchMode: .Replace)
            #expect(state.selectedMode == [.Replace, .Text, .Containing])

            state.selectedMode = [.Find, .References, .EndingWith]
            form.onSelectMenuItem(0, searchMode: .Replace)
            #expect(state.selectedMode == [.Replace, .Text, .EndingWith])

            state.selectedMode = [.Find, .CallHierarchy]
            form.onSelectMenuItem(0, searchMode: .Replace)
            #expect(state.selectedMode == [.Replace, .Text])

            state.selectedMode = [.Find, .Text, .Containing]
            form.onSelectMenuItem(0, searchMode: .Containing)
            #expect(state.selectedMode == [.Containing])

            state.selectedMode = [.Find, .Text, .Containing]
            form.onSelectMenuItem(1, searchMode: .References)
            #expect(state.selectedMode == [.Find, .References, .Containing])

            form.onSelectMenuItem(1, searchMode: .RegularExpression)
            #expect(state.selectedMode == [.Find, .RegularExpression])

            state.selectedMode = [.Find, .Text, .EndingWith]
            form.onSelectMenuItem(1, searchMode: .Definitions)
            #expect(state.selectedMode == [.Find, .Definitions, .EndingWith])

            state.selectedMode = [.Find, .Text, .RegularExpression]
            form.onSelectMenuItem(1, searchMode: .Definitions)
            #expect(state.selectedMode == [.Find, .Definitions, .Containing])

            form.onSelectMenuItem(2, searchMode: .MatchingWord)
            #expect(state.selectedMode == [.Find, .Definitions, .MatchingWord])

            form.onSelectMenuItem(3, searchMode: .Containing)
            #expect(state.selectedMode == [.Find, .Definitions, .MatchingWord])

            state.selectedMode = []
            form.onSelectMenuItem(1, searchMode: .Text)
            #expect(state.selectedMode.isEmpty)
            form.onSelectMenuItem(2, searchMode: .Containing)
            #expect(state.selectedMode.isEmpty)
        }
    }

    @Test
    func menuListsFollowTheSelectedPath() async throws {
        try await withState { _, state, _ in
            let form = FindNavigatorForm(state: state)
            #expect(form.getMenuList(0) == SearchModeModel.SearchModes)
            #expect(form.getMenuList(1) == SearchModeModel.Find.children)
            #expect(form.getMenuList(2) == SearchModeModel.Text.children)
            state.selectedMode = [.Replace]
            #expect(form.getMenuList(2).isEmpty)
            state.selectedMode = []
            #expect(form.getMenuList(1).isEmpty)
        }
    }

    @Test
    func modeSelectionBindingReadsAndWritesTheSelectedMode() async throws {
        try await withState { _, state, _ in
            let form = FindNavigatorForm(state: state)
            let binding = form.modeSelectionBinding(0)
            #expect(binding.wrappedValue == .Find)
            binding.wrappedValue = .Replace
            #expect(state.selectedMode.first == .Replace)
            #expect(form.modeSelectionBinding(1).wrappedValue == .Text)
            state.selectedMode = [.Replace]
            #expect(form.modeSelectionBinding(2).wrappedValue == .Find)
        }
    }
}
