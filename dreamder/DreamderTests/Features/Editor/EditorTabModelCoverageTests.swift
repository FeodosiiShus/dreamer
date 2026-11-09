import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct EditorTabModelCoverageTests {
    private func file(_ name: String) -> CEWorkspaceFile {
        CEWorkspaceFile(url: URL(filePath: "/fake/\(name)"))
    }

    private func names(_ editor: Editor) -> [String] {
        editor.tabs.map { $0.file.url.lastPathComponent }
    }

    @Test
    func selectingAFileWithoutATabKeepsTheSelection() {
        let editor = Editor()
        editor.openTab(file: file("a"), asTemporary: false)

        editor.setSelectedTab(file("ghost"))

        #expect(editor.selectedTab?.file.url.lastPathComponent == "a")
    }

    @Test
    func selectingNothingClearsTheSelection() {
        let editor = Editor()
        editor.openTab(file: file("a"), asTemporary: false)

        editor.setSelectedTab(nil)

        #expect(editor.selectedTab == nil)
    }

    @Test
    func closingTheSelectedTabOfAnEmptyEditorDoesNothing() {
        let editor = Editor()

        editor.closeSelectedTab()

        #expect(editor.tabs.isEmpty)
        #expect(editor.selectedTab == nil)
    }

    @Test
    func closingTheSelectedTabRemovesIt() {
        let editor = Editor()
        editor.openTab(file: file("a"), asTemporary: false)
        editor.openTab(file: file("b"), asTemporary: false)

        editor.closeSelectedTab()

        #expect(names(editor) == ["a"])
        #expect(editor.selectedTab?.file.url.lastPathComponent == "a")
    }

    @Test
    func openingTheTemporaryTabPermanentlyKeepsItAndClearsTheTemporaryMark() {
        let editor = Editor()
        editor.openTab(file: file("a"), asTemporary: true)
        #expect(editor.temporaryTab?.file.url.lastPathComponent == "a")

        editor.openTab(file: file("a"), asTemporary: false)

        #expect(editor.temporaryTab == nil)
        #expect(names(editor) == ["a"])
    }

    @Test
    func openingAnotherTabPermanentlyKeepsTheTemporaryTab() {
        let editor = Editor()
        editor.openTab(file: file("a"), asTemporary: true)

        editor.openTab(file: file("b"), asTemporary: false)

        #expect(editor.temporaryTab?.file.url.lastPathComponent == "a")
        #expect(names(editor) == ["a", "b"])
    }

    @Test
    func openingAnotherTemporaryTabReplacesTheCurrentOne() {
        let editor = Editor()
        editor.openTab(file: file("a"), asTemporary: true)

        editor.openTab(file: file("b"), asTemporary: true)

        #expect(names(editor) == ["b"])
        #expect(editor.temporaryTab?.file.url.lastPathComponent == "b")
    }

    @Test
    func aTemporaryTabMissingFromTheTabsIsReplacedByAnAppendedTab() {
        let editor = Editor()
        editor.temporaryTab = EditorInstance(workspace: nil, file: file("ghost"))

        editor.openTab(file: file("b"), asTemporary: true)

        #expect(names(editor) == ["b"])
        #expect(editor.temporaryTab?.file.url.lastPathComponent == "b")
        #expect(editor.selectedTab?.file.url.lastPathComponent == "b")
    }

    @Test
    func removingTheTemporaryTabsFileClearsTheTemporaryMark() {
        let editor = Editor()
        editor.openTab(file: file("a"), asTemporary: true)

        editor.removeTab(file("a"))

        #expect(editor.tabs.isEmpty)
        #expect(editor.temporaryTab == nil)
    }

    @Test
    func editorsAreIdentifiedByTheirId() {
        let first = Editor()
        let second = Editor()

        #expect(first == first)
        #expect(first != second)
        #expect(Set([first, second, first]).count == 2)
    }

    @Test
    func aDeclinedCloseConfirmationKeepsTheEditedTabOpenAndAnAcceptedOneClosesIt() throws {
        try withTempDir { dir in
            let url = dir.appending(path: "edited.txt")
            try "hello".write(to: url, atomically: true, encoding: .utf8)
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let editor = try #require(workspace.editorManager).activeEditor
            editor.workspace = workspace
            let file = CEWorkspaceFile(url: url)
            editor.openTab(file: file, asTemporary: false)
            let document = try #require(file.fileDocument)
            document.updateChangeCount(.changeDone)
            var asked = 0
            document.closeConfirmation = { _ in
                asked += 1
                return false
            }

            editor.closeTab(file: file)

            #expect(asked == 1)
            #expect(names(editor) == ["edited.txt"])
            #expect(file.fileDocument === document)

            document.closeConfirmation = { _ in
                asked += 1
                return true
            }
            editor.closeTab(file: file)

            #expect(asked == 2)
            #expect(editor.tabs.isEmpty)
            #expect(file.fileDocument == nil)
        }
    }
}
