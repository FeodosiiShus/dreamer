import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct FindNavigatorKeyboardTests {
    private func expectCursor(_ tab: Editor.Tab?, matches usage: FindUsage) throws {
        let position = try #require(tab?.cursorPositions.first)
        #expect(position.start.line == usage.start.line)
        #expect(position.start.column == usage.start.column)
        #expect(position.end?.line == usage.end.line)
        #expect(position.end?.column == usage.end.column)
    }

    private func closeSelectedTab(in editor: Editor) throws {
        editor.closeTab(file: try #require(editor.selectedTab).file)
        #expect(editor.tabs.isEmpty)
    }

    private func read(_ name: String, in dir: URL) throws -> String {
        try String(contentsOf: dir.appending(path: name), encoding: .utf8)
    }

    @Test
    func returnKeyCodesCoverReturnAndEnter() {
        #expect(FindOutlineView.returnKeyCodes == [36, 76])
    }

    @Test
    func outlineForwardsOnlyReturnKeysWithTheirDeviceIndependentModifiers() throws {
        let window = NSWindow()
        window.isReleasedWhenClosed = false
        let outline = FindOutlineView()
        var received: [NSEvent.ModifierFlags] = []
        outline.onReturn = { received.append($0) }

        outline.keyDown(with: try FindNavigatorKeyEvents.returnKey(in: window))
        outline.keyDown(with: try FindNavigatorKeyEvents.returnKey(
            keyCode: FindNavigatorKeyEvents.enterKeyCode,
            modifiers: [.option, .shift],
            in: window
        ))
        outline.keyDown(with: try FindNavigatorKeyEvents.make(.keyDown, keyCode: 0, characters: "a", in: window))

        #expect(received == [[], [.option, .shift]])
    }

    @Test
    func defaultReturnHandlerIgnoresTheKey() throws {
        let window = NSWindow()
        window.isReleasedWhenClosed = false
        let outline = FindOutlineView()

        outline.keyDown(with: try FindNavigatorKeyEvents.returnKey(in: window))

        #expect(outline.numberOfRows == 0)
    }

    @Test
    func moveDownAndUpWalkThroughTheRows() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searched(in: dir)
            let harness = try FindNavigatorListHarness(workspace: workspace)
            defer { harness.close() }
            harness.load()

            harness.select(harness.fileA)
            #expect(harness.outline.selectedRow == 0)

            harness.outline.moveDown(nil)
            #expect(harness.outline.selectedRow == 1)
            let firstMatch = try harness.fileA.lineMatches.required(at: 0)
            #expect((harness.outline.item(atRow: 1) as? SearchResultMatchModel) === firstMatch)
            guard case .match(let selected)? = workspace.searchState?.resultSelection else {
                Issue.record("expected a match selection")
                return
            }
            #expect(selected === firstMatch)

            harness.outline.moveDown(nil)
            harness.outline.moveDown(nil)
            #expect(harness.outline.selectedRow == 3)
            #expect((harness.outline.item(atRow: 3) as? SearchResultModel) === harness.fileB)

            harness.outline.moveUp(nil)
            #expect(harness.outline.selectedRow == 2)
        }
    }

    @Test
    func arrowCommandsClampAtTheEndsAndStartFromTheEdgesWithoutSelection() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searched(in: dir)
            let harness = try FindNavigatorListHarness(workspace: workspace)
            defer { harness.close() }
            harness.load()
            #expect(harness.outline.selectedRow == -1)

            harness.outline.moveUp(nil)
            #expect(harness.outline.selectedRow == 4)
            harness.outline.moveDown(nil)
            #expect(harness.outline.selectedRow == 4)

            harness.outline.deselectAll(nil)
            harness.outline.moveDown(nil)
            #expect(harness.outline.selectedRow == 0)
            harness.outline.moveUp(nil)
            #expect(harness.outline.selectedRow == 0)
        }
    }

    @Test
    func arrowCommandsDoNothingWithoutRows() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searched(in: dir)
            let harness = try FindNavigatorListHarness(workspace: workspace)
            defer { harness.close() }
            harness.controller.updateNewSearchResults([])

            harness.outline.moveDown(nil)
            harness.outline.moveUp(nil)

            #expect(harness.outline.selectedRow == -1)
        }
    }

    @Test
    func returnOpensTheSelectedMatchAtItsUsage() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searched(in: dir)
            let harness = try FindNavigatorListHarness(workspace: workspace)
            defer { harness.close() }
            harness.load()
            let editor = try #require(harness.editor)
            let match = try harness.fileA.lineMatches.required(at: 1)
            let usage = try #require(match.usage)
            #expect(usage.start == FindTextPosition(line: 2, column: 13))
            #expect(usage.end == FindTextPosition(line: 2, column: 19))

            harness.select(match)
            try closeSelectedTab(in: editor)
            harness.outline.keyDown(with: try FindNavigatorKeyEvents.returnKey(in: harness.window))

            #expect(editor.selectedTab?.file.url == match.file.url)
            try expectCursor(editor.selectedTab, matches: usage)

            try closeSelectedTab(in: editor)
            harness.outline.keyDown(with: try FindNavigatorKeyEvents.returnKey(
                keyCode: FindNavigatorKeyEvents.enterKeyCode,
                in: harness.window
            ))

            #expect(editor.selectedTab?.file.url == match.file.url)
            try expectCursor(editor.selectedTab, matches: usage)
        }
    }

    @Test
    func returnOnAFileRowOpensTheFileAndWithoutSelectionDoesNothing() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searched(in: dir)
            let harness = try FindNavigatorListHarness(workspace: workspace)
            defer { harness.close() }
            harness.load()
            let editor = try #require(harness.editor)

            harness.select(harness.fileB)
            try closeSelectedTab(in: editor)
            harness.outline.keyDown(with: try FindNavigatorKeyEvents.returnKey(in: harness.window))
            #expect(editor.selectedTab?.file.url == harness.fileB.file.url)

            try closeSelectedTab(in: editor)
            harness.outline.deselectAll(nil)
            harness.outline.keyDown(with: try FindNavigatorKeyEvents.returnKey(in: harness.window))
            #expect(editor.tabs.isEmpty)
        }
    }

    @Test
    func commandReturnOutsideReplaceModeOpensTheSelectionInsteadOfReplacing() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searched(in: dir)
            let harness = try FindNavigatorListHarness(workspace: workspace)
            defer { harness.close() }
            harness.load()
            let editor = try #require(harness.editor)
            let state = try #require(workspace.searchState)
            #expect(!state.selectedMode.isReplaceMode)

            try harness.select(harness.fileB.lineMatches.required(at: 0))
            try closeSelectedTab(in: editor)
            harness.outline.keyDown(with: try FindNavigatorKeyEvents.returnKey(modifiers: .command, in: harness.window))

            #expect(editor.selectedTab?.file.url == harness.fileB.file.url)
            #expect(try read("b.txt", in: dir) == "needle here\n")
            #expect(state.findNavigatorStatus == .found)
        }
    }

    @Test
    func commandReturnInReplaceModeReplacesOnlyTheSelectedMatch() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searchedForReplace(in: dir)
            let harness = try FindNavigatorListHarness(workspace: workspace)
            defer { harness.close() }
            harness.load()
            let editor = try #require(harness.editor)
            let state = try #require(workspace.searchState)

            try harness.select(harness.fileB.lineMatches.required(at: 0))
            try closeSelectedTab(in: editor)
            harness.outline.keyDown(with: try FindNavigatorKeyEvents.returnKey(modifiers: .command, in: harness.window))

            try await eventually { state.searchResult.count == 1 }
            #expect(try read("b.txt", in: dir) == "pin here\n")
            #expect(try read("a.swift", in: dir) == "let needle = 1\nlet other = needle + 2\n")
            #expect(state.findNavigatorStatus == .found)
            #expect(editor.tabs.isEmpty)
        }
    }

    @Test
    func commandReturnInReplaceModeWithoutSelectionReplacesNothing() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searchedForReplace(in: dir)
            let harness = try FindNavigatorListHarness(workspace: workspace)
            defer { harness.close() }
            harness.load()
            let state = try #require(workspace.searchState)
            #expect(state.resultSelection == nil)

            harness.controller.handleReturn(.command)
            try await Task.sleep(for: .milliseconds(100))

            #expect(try read("b.txt", in: dir) == "needle here\n")
            #expect(state.findNavigatorStatus == .found)
            #expect(state.searchResult.count == 2)
        }
    }

    @Test
    func optionShiftReturnReplacesEveryMatch() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searchedForReplace(in: dir)
            let harness = try FindNavigatorListHarness(workspace: workspace)
            defer { harness.close() }
            harness.load()
            let state = try #require(workspace.searchState)

            harness.outline.keyDown(with: try FindNavigatorKeyEvents.returnKey(
                modifiers: [.option, .shift],
                in: harness.window
            ))

            try await eventually { state.findNavigatorStatus == .replaced(updatedFiles: 2) }
            #expect(try read("a.swift", in: dir) == "let pin = 1\nlet other = pin + 2\n")
            #expect(try read("b.txt", in: dir) == "pin here\n")
        }
    }

    @Test
    func openingWithoutASelectionOrAFocusRequestIsHarmless() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searched(in: dir)
            let harness = try FindNavigatorListHarness(workspace: workspace)
            defer { harness.close() }
            harness.load()
            let editor = try #require(harness.editor)

            harness.controller.openSelection(focusEditor: false)
            #expect(editor.tabs.isEmpty)

            harness.select(harness.fileA)
            try closeSelectedTab(in: editor)
            harness.controller.openSelection(focusEditor: false)
            #expect(editor.selectedTab?.file.url == harness.fileA.file.url)
        }
    }

    @Test
    func focusResultsSelectsTheFirstRowOnlyWhenNothingIsSelected() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searched(in: dir)
            let harness = try FindNavigatorListHarness(workspace: workspace)
            defer { harness.close() }
            harness.load()
            let state = try #require(workspace.searchState)
            #expect(harness.outline.selectedRow == -1)

            harness.controller.focusResults()
            #expect(harness.window.firstResponder === harness.outline)
            #expect(harness.outline.selectedRow == 0)
            #expect(state.resultSelection == .file(harness.fileA))

            try harness.select(harness.fileB.lineMatches.required(at: 0))
            let row = harness.outline.selectedRow
            harness.window.makeFirstResponder(nil)
            harness.controller.focusResults()
            #expect(harness.window.firstResponder === harness.outline)
            #expect(harness.outline.selectedRow == row)
        }
    }

    @Test
    func focusResultsWithZeroRowsLeavesTheFirstResponderAlone() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searched(in: dir)
            let harness = try FindNavigatorListHarness(workspace: workspace)
            defer { harness.close() }
            harness.controller.updateNewSearchResults([])
            harness.window.makeFirstResponder(nil)

            harness.controller.focusResults()

            #expect(harness.outline.numberOfRows == 0)
            #expect(harness.window.firstResponder !== harness.outline)
            #expect(workspace.searchState?.resultSelection == nil)
        }
    }

    @Test
    func deleteKeyInReplaceModeTogglesSkipAndBumpsTheRevision() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searchedForReplace(in: dir)
            let harness = try FindNavigatorListHarness(workspace: workspace)
            defer { harness.close() }
            harness.load()
            let state = try #require(workspace.searchState)
            let match = try harness.fileA.lineMatches.required(at: 0)
            let revision = state.skipRevision

            harness.select(match)
            harness.controller.keyUp(with: try FindNavigatorKeyEvents.deleteKeyUp(in: harness.window))
            #expect(match.isSkipped)
            #expect(state.skipRevision == revision + 1)
            #expect(harness.outline.numberOfRows == 5)
            #expect(harness.fileA.lineMatches.count == 2)

            harness.controller.keyUp(with: try FindNavigatorKeyEvents.deleteKeyUp(in: harness.window))
            #expect(!match.isSkipped)
            #expect(state.skipRevision == revision + 2)

            harness.select(harness.fileA)
            harness.controller.keyUp(with: try FindNavigatorKeyEvents.deleteKeyUp(in: harness.window))
            #expect(harness.fileA.lineMatches.allSatisfy { $0.isSkipped })
            harness.controller.keyUp(with: try FindNavigatorKeyEvents.deleteKeyUp(in: harness.window))
            #expect(harness.fileA.lineMatches.allSatisfy { !$0.isSkipped })
            #expect(state.skipRevision == revision + 4)
        }
    }

    @Test
    func deleteKeyInFindModeRemovesTheRowWithoutTouchingSkips() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searched(in: dir)
            let harness = try FindNavigatorListHarness(workspace: workspace)
            defer { harness.close() }
            harness.load()
            let state = try #require(workspace.searchState)
            let revision = state.skipRevision

            harness.select(harness.fileB)
            harness.controller.keyUp(with: try FindNavigatorKeyEvents.deleteKeyUp(in: harness.window))

            #expect(harness.outline.numberOfRows == 3)
            #expect(state.skipRevision == revision)
        }
    }

    @Test
    func formDownArrowFocusesTheResultsOnlyWhenThereAreAny() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searched(in: dir)
            defer { workspace.close() }
            let state = try #require(workspace.searchState)
            let form = FindNavigatorForm(state: state)
            let results = state.searchResult

            state.searchResult = []
            #expect(form.focusResults() == .ignored)
            #expect(!state.shouldFocusResults)

            state.searchResult = results
            #expect(form.focusResults() == .handled)
            #expect(state.shouldFocusResults)
        }
    }

    @Test
    func hostedToolWindowMovesFocusIntoTheResultsAndNavigatesWithTheKeyboard() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searched(in: dir)
            defer { workspace.close() }
            let state = try #require(workspace.searchState)
            workspace.toolWindowManager.show(.find)

            let hosted = try HostedViewFixture.hostInWorkspace(workspace) { FindToolWindow() }
            defer { hosted.close() }
            try await eventually { hosted.views(of: FindOutlineView.self).first?.numberOfRows == 5 }
            try await hosted.settle()
            let outline = try #require(hosted.views(of: FindOutlineView.self).first)
            let editor = try #require(workspace.editorManager?.activeEditor)

            state.shouldFocusResults = true
            try await eventually { !state.shouldFocusResults }
            try await eventually { hosted.window.firstResponder === outline }
            #expect(outline.selectedRow == 0)
            let firstFile = try #require(outline.item(atRow: 0) as? SearchResultModel)
            #expect(state.resultSelection == .file(firstFile))

            outline.moveDown(nil)
            let firstMatch = try #require(outline.item(atRow: 1) as? SearchResultMatchModel)
            #expect(outline.selectedRow == 1)
            #expect(state.resultSelection == .match(firstMatch))
            #expect(editor.selectedTab?.file.url == firstMatch.file.url)

            try closeSelectedTab(in: editor)
            outline.keyDown(with: try FindNavigatorKeyEvents.returnKey(in: hosted.window))
            #expect(editor.selectedTab?.file.url == firstMatch.file.url)
            try expectCursor(editor.selectedTab, matches: try #require(firstMatch.usage))
        }
    }
}
