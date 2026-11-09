import Foundation
import OrderedCollections
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct EditorHistoryTabSwitchModelsCoverageTests {
    private func file(_ name: String) -> CEWorkspaceFile {
        CEWorkspaceFile(url: URL(filePath: "/fake/\(name)"))
    }

    private func makeEditor(opening names: [String]) -> (editor: Editor, files: [CEWorkspaceFile]) {
        let editor = Editor()
        let files = names.map { file($0) }
        for file in files {
            editor.openTab(file: file, asTemporary: false)
        }
        return (editor, files)
    }

    private func tabNames(_ editor: Editor) -> [String] {
        editor.tabs.map { $0.file.url.lastPathComponent }
    }

    private func historyNames(_ editor: Editor) -> [String] {
        editor.history.map { $0.url.lastPathComponent }
    }

    private func selectedName(_ editor: Editor) -> String? {
        editor.selectedTab?.file.url.lastPathComponent
    }

    @Test
    func openingTabsRecordsHistoryNewestFirst() {
        let (editor, _) = makeEditor(opening: ["a", "b", "c"])

        #expect(historyNames(editor) == ["c", "b", "a"])
        #expect(tabNames(editor) == ["a", "b", "c"])
        #expect(editor.historyOffset == 0)
    }

    @Test
    func addToHistorySkipsTheCurrentHead() throws {
        let (editor, _) = makeEditor(opening: ["a", "b"])
        let head = try #require(editor.tabs.last)

        editor.addToHistory(head)

        #expect(historyNames(editor) == ["b", "a"])
    }

    @Test
    func goingBackAndForwardWalksTheHistoryAndSelectsTheTab() {
        let (editor, _) = makeEditor(opening: ["a", "b", "c"])
        #expect(editor.canGoBackInHistory)
        #expect(!editor.canGoForwardInHistory)

        editor.goBackInHistory()
        #expect(editor.historyOffset == 1)
        #expect(selectedName(editor) == "b")
        #expect(editor.canGoBackInHistory)
        #expect(editor.canGoForwardInHistory)

        editor.goBackInHistory()
        #expect(editor.historyOffset == 2)
        #expect(selectedName(editor) == "a")
        #expect(!editor.canGoBackInHistory)

        editor.goBackInHistory()
        #expect(editor.historyOffset == 2)
        #expect(selectedName(editor) == "a")

        editor.goForwardInHistory()
        #expect(editor.historyOffset == 1)
        #expect(selectedName(editor) == "b")

        editor.goForwardInHistory()
        #expect(editor.historyOffset == 0)
        #expect(selectedName(editor) == "c")
        #expect(!editor.canGoForwardInHistory)

        editor.goForwardInHistory()
        #expect(editor.historyOffset == 0)
        #expect(selectedName(editor) == "c")
    }

    @Test
    func emptyAndSingleEntryHistoriesCannotNavigate() {
        let empty = Editor()
        #expect(!empty.canGoBackInHistory)
        #expect(!empty.canGoForwardInHistory)
        empty.goBackInHistory()
        empty.goForwardInHistory()
        #expect(empty.historyOffset == 0)

        let (single, _) = makeEditor(opening: ["a"])
        #expect(!single.canGoBackInHistory)
        single.goBackInHistory()
        #expect(single.historyOffset == 0)
        #expect(selectedName(single) == "a")
    }

    @Test
    func goingBackToAClosedTabReopensItAsTheTemporaryTab() {
        let (editor, files) = makeEditor(opening: ["a", "b", "c"])
        editor.closeTab(file: files[2])
        #expect(tabNames(editor) == ["a", "b"])
        #expect(historyNames(editor) == ["b", "c", "b", "a"])

        editor.goBackInHistory()

        #expect(editor.historyOffset == 1)
        #expect(tabNames(editor) == ["a", "b", "c"])
        #expect(selectedName(editor) == "c")
        #expect(editor.temporaryTab?.file == files[2])
        #expect(historyNames(editor) == ["b", "c", "b", "a"])
    }

    @Test
    func goingBackToAClosedTabReplacesTheExistingTemporaryTab() {
        let (editor, files) = makeEditor(opening: ["a", "b"])
        editor.temporaryTab = editor.tabs.last
        editor.history = [files[0], files[1], file("c")]

        editor.historyOffset = 2

        #expect(tabNames(editor) == ["a", "c"])
        #expect(selectedName(editor) == "c")
        #expect(editor.temporaryTab?.file.url.lastPathComponent == "c")
        #expect(historyNames(editor) == ["a", "b", "c"])
    }

    @Test
    func openingATabAfterGoingBackDropsTheFutureAndKeepsTheNewTabSelected() {
        let (editor, _) = makeEditor(opening: ["a", "b", "c"])
        editor.goBackInHistory()
        editor.goBackInHistory()
        #expect(editor.historyOffset == 2)
        #expect(selectedName(editor) == "a")

        editor.openTab(file: file("d"), asTemporary: false)

        #expect(editor.historyOffset == 0)
        #expect(historyNames(editor) == ["d", "a"])
        #expect(tabNames(editor) == ["a", "d", "b", "c"])
        #expect(selectedName(editor) == "d")
        #expect(!editor.canGoForwardInHistory)
    }

    @Test
    func clearFutureWithoutAFutureKeepsTheHistory() {
        let (editor, _) = makeEditor(opening: ["a", "b"])

        editor.clearFuture()

        #expect(historyNames(editor) == ["b", "a"])
        #expect(editor.historyOffset == 0)
        #expect(selectedName(editor) == "b")
    }

    @Test
    func clearFutureAfterGoingBackKeepsTheCurrentTab() {
        let (editor, _) = makeEditor(opening: ["a", "b", "c"])
        editor.goBackInHistory()

        editor.clearFuture()

        #expect(historyNames(editor) == ["b", "a"])
        #expect(editor.historyOffset == 0)
        #expect(selectedName(editor) == "b")
    }

    @Test
    func selectNextTabAdvancesAndWrapsAround() {
        let (editor, _) = makeEditor(opening: ["a", "b", "c"])
        #expect(selectedName(editor) == "c")

        editor.selectNextTab()
        #expect(selectedName(editor) == "a")

        editor.selectNextTab()
        #expect(selectedName(editor) == "b")
    }

    @Test
    func selectPreviousTabRewindsAndWrapsAround() {
        let (editor, _) = makeEditor(opening: ["a", "b", "c"])

        editor.selectPreviousTab()
        #expect(selectedName(editor) == "b")

        editor.selectPreviousTab()
        #expect(selectedName(editor) == "a")

        editor.selectPreviousTab()
        #expect(selectedName(editor) == "c")
    }

    @Test
    func tabSwitchingWithoutASelectedTabDoesNothing() {
        let editor = Editor()

        editor.selectNextTab()
        editor.selectPreviousTab()

        #expect(editor.selectedTab == nil)
        #expect(editor.tabs.isEmpty)
    }

    @Test
    func tabSwitchingWithASelectionOutsideTheTabsDoesNothing() {
        let files: OrderedSet<CEWorkspaceFile> = [file("a"), file("b")]
        let editor = Editor(files: files, selectedTab: EditorInstance(workspace: nil, file: file("z")))

        editor.selectNextTab()
        #expect(selectedName(editor) == "z")

        editor.selectPreviousTab()
        #expect(selectedName(editor) == "z")
    }
}
