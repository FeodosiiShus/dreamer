import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct EditorManagerCoverageTests {
    private func makeManager(editors: [Editor]) -> EditorManager {
        let manager = EditorManager()
        let layouts = editors.map { EditorLayout.one($0) }
        manager.editorLayout = .horizontal(SplitViewData(.horizontal, editorLayouts: layouts))
        if let first = editors.first {
            manager.activeEditor = first
        }
        manager.activeEditorHistory.removeAll()
        return manager
    }

    @Test
    func flatteningASingleEditorLayoutLeavesItUntouched() {
        let manager = EditorManager()
        let editor = Editor()
        manager.editorLayout = .one(editor)

        manager.flatten()

        #expect(manager.editorLayout == .one(editor))
        #expect(manager.getFlattened().isEmpty)
    }

    @Test
    func closingTheActiveEditorWithoutHistoryActivatesASiblingEditor() {
        let closing = Editor()
        let sibling = Editor()
        let manager = makeManager(editors: [closing, sibling])

        manager.setNewActiveEditor(excluding: closing)

        #expect(manager.activeEditor === sibling)
    }

    @Test
    func closingTheActiveEditorWithHistoryActivatesTheMostRecentLiveEditor() {
        let closing = Editor()
        let sibling = Editor()
        let manager = makeManager(editors: [closing, sibling])
        manager.activeEditorHistory.prepend { [weak sibling] in sibling }

        manager.setNewActiveEditor(excluding: closing)

        #expect(manager.activeEditor === sibling)
    }

    @Test
    func closingTheOnlyEditorResetsTheManagerToACleanState() {
        let only = Editor()
        let manager = makeManager(editors: [only])

        manager.setNewActiveEditor(excluding: only)

        #expect(manager.activeEditor !== only)
        #expect(manager.getFlattened().count == 1)
        #expect(manager.getFlattened().first === manager.activeEditor)
        #expect(!manager.isFocusingActiveEditor)
    }

    @Test
    func aCleanStateKeepsServingTheActiveEditorHistory() {
        let only = Editor()
        let manager = makeManager(editors: [only])
        manager.setNewActiveEditor(excluding: only)
        let clean = manager.activeEditor

        manager.setNewActiveEditor(excluding: only)

        #expect(manager.activeEditor === clean)
    }

    @Test
    func findingSomeEditorExcludingTheOnlyEditorBuildsACleanEditor() {
        let only = Editor()
        let manager = makeManager(editors: [only])

        let found = manager.findSomeEditor(excluding: only)

        #expect(found !== only)
        #expect(found === manager.activeEditor)
    }

    @Test
    func findingSomeEditorReturnsAnotherEditorOfTheLayout() {
        let first = Editor()
        let second = Editor()
        let manager = makeManager(editors: [first, second])

        #expect(manager.findSomeEditor(excluding: first) === second)
        #expect(manager.activeEditor === first)
    }

    @Test
    func togglingFocusActivatesTheGivenEditorOnlyWhenEnteringFocusMode() {
        let first = Editor()
        let second = Editor()
        let manager = makeManager(editors: [first, second])
        #expect(!manager.isFocusingActiveEditor)

        manager.toggleFocusingEditor(from: second)
        #expect(manager.isFocusingActiveEditor)
        #expect(manager.activeEditor === second)

        manager.toggleFocusingEditor(from: first)
        #expect(!manager.isFocusingActiveEditor)
        #expect(manager.activeEditor === second)
    }

    @Test
    func unsplittingAnEditorWithoutASelectionSelectsTheFirstMergedTab() {
        let empty = Editor()
        let other = Editor()
        other.openTab(file: CEWorkspaceFile(url: URL(filePath: "/fake/x.txt")), asTemporary: false)
        let manager = makeManager(editors: [empty, other])

        #expect(manager.unsplit(empty))

        #expect(empty.tabs.map(\.file.url.lastPathComponent) == ["x.txt"])
        #expect(empty.selectedTab?.file.url.lastPathComponent == "x.txt")
        #expect(manager.activeEditor === empty)
    }
}
