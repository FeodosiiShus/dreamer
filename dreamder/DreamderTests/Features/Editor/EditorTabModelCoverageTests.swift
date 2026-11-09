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

    private struct EditedTabs {
        let workspace: WorkspaceDocument
        let editor: Editor
        let files: [CEWorkspaceFile]
        let documents: [CodeFileDocument]
    }

    private func makeEditedTabs(in directory: URL, names: [String], edited: Set<String>) throws -> EditedTabs {
        let workspace = try HostedViewFixture.makeWorkspace(in: directory)
        let editor = try #require(workspace.editorManager).activeEditor
        editor.workspace = workspace
        var files: [CEWorkspaceFile] = []
        var documents: [CodeFileDocument] = []
        for name in names {
            let url = directory.appending(path: name)
            try "hello".write(to: url, atomically: true, encoding: .utf8)
            let file = CEWorkspaceFile(url: url)
            editor.openTab(file: file, asTemporary: false)
            let document = try #require(file.fileDocument)
            document.autosavingInPlace = { false }
            if edited.contains(name) {
                document.content?.replaceCharacters(in: NSRange(location: 0, length: 0), with: "X")
                document.updateChangeCount(.changeDone)
            }
            files.append(file)
            documents.append(document)
        }
        return EditedTabs(workspace: workspace, editor: editor, files: files, documents: documents)
    }

    @Test
    func aCancelledCloseKeepsTheEditedTabItsDocumentAndItsEdits() throws {
        try withTempDir { dir in
            let tabs = try makeEditedTabs(in: dir, names: ["edited.txt"], edited: ["edited.txt"])
            defer { tabs.workspace.close() }
            let confirmation = CloseConfirmationDouble()
            confirmation.install(on: tabs.documents)
            let file = try #require(tabs.files.first)
            let document = try #require(tabs.documents.first)

            tabs.editor.closeTab(file: file)

            #expect(confirmation.pendingCount == 1)
            #expect(names(tabs.editor) == ["edited.txt"])
            #expect(document.isDocumentEdited)

            confirmation.answerNext(.cancel)

            #expect(names(tabs.editor) == ["edited.txt"])
            #expect(file.fileDocument === document)
            #expect(document.isDocumentEdited)
            #expect(document.content?.string == "Xhello")
        }
    }

    @Test
    func aSavedOrDiscardedCloseRemovesTheTabAndClosesTheDocumentOnlyAfterTheAnswer() throws {
        try withTempDir { dir in
            let tabs = try makeEditedTabs(in: dir, names: ["a.txt", "b.txt"], edited: ["a.txt", "b.txt"])
            defer { tabs.workspace.close() }
            let confirmation = CloseConfirmationDouble()
            confirmation.install(on: tabs.documents)
            let first = try #require(tabs.files.first)
            let last = try #require(tabs.files.last)
            let firstDocument = try #require(tabs.documents.first)

            tabs.editor.closeTab(file: first)
            tabs.editor.closeTab(file: last)

            #expect(confirmation.pendingCount == 2)
            #expect(names(tabs.editor) == ["a.txt", "b.txt"])
            #expect(firstDocument.isDocumentEdited)

            confirmation.answerNext(.save)

            #expect(names(tabs.editor) == ["b.txt"])
            #expect(first.fileDocument == nil)
            #expect(!DreamderDocumentController.shared.documents.contains { $0 === firstDocument })

            confirmation.answerNext(.discard)

            #expect(tabs.editor.tabs.isEmpty)
            #expect(last.fileDocument == nil)
        }
    }

    @Test
    func askingToCloseATabWhoseConfirmationIsPendingDoesNotAskAgain() throws {
        try withTempDir { dir in
            let tabs = try makeEditedTabs(in: dir, names: ["edited.txt"], edited: ["edited.txt"])
            defer { tabs.workspace.close() }
            let confirmation = CloseConfirmationDouble()
            confirmation.install(on: tabs.documents)
            let file = try #require(tabs.files.first)
            var results: [Bool] = []

            tabs.editor.closeTab(file: file) { results.append($0) }
            tabs.editor.closeTab(file: file) { results.append($0) }

            #expect(confirmation.askedNames == ["edited.txt"])
            #expect(results == [false])

            confirmation.answerNext(.discard)

            #expect(results == [false, true])
            #expect(tabs.editor.tabs.isEmpty)
        }
    }

    @Test
    func closingSeveralTabsStopsAtTheFirstCancelledConfirmation() throws {
        try withTempDir { dir in
            let tabs = try makeEditedTabs(
                in: dir,
                names: ["a.txt", "b.txt", "c.txt"],
                edited: ["b.txt"]
            )
            defer { tabs.workspace.close() }
            let confirmation = CloseConfirmationDouble()
            confirmation.install(on: tabs.documents)

            tabs.editor.closeUnpinnedTabs()

            #expect(names(tabs.editor) == ["b.txt", "c.txt"])
            #expect(confirmation.pendingCount == 1)

            confirmation.answerNext(.cancel)

            #expect(names(tabs.editor) == ["b.txt", "c.txt"])
            #expect(confirmation.askedNames == ["b.txt"])

            tabs.editor.closeUnpinnedTabs()
            confirmation.answerNext(.discard)

            #expect(tabs.editor.tabs.isEmpty)
            #expect(confirmation.askedNames == ["b.txt", "b.txt"])
        }
    }

    @Test
    func anAnswerArrivingAfterTheEditorIsGoneChangesNothing() throws {
        try withTempDir { dir in
            let tabs = try makeEditedTabs(in: dir, names: ["edited.txt"], edited: ["edited.txt"])
            defer { tabs.workspace.close() }
            let url = dir.appending(path: "orphan.txt")
            try "orphan".write(to: url, atomically: true, encoding: .utf8)
            let file = CEWorkspaceFile(url: url)
            var orphan: Editor? = Editor()
            weak let probe = orphan
            orphan?.workspace = tabs.workspace
            orphan?.openTab(file: file, asTemporary: false)
            let document = try #require(file.fileDocument)
            defer { document.close() }
            document.autosavingInPlace = { false }
            document.updateChangeCount(.changeDone)
            let confirmation = CloseConfirmationDouble()
            confirmation.install(on: [document])
            var results: [Bool] = []

            orphan?.closeTab(file: file) { results.append($0) }
            orphan = nil
            #expect(probe == nil)
            confirmation.answerNext(.discard)

            #expect(results == [false])
            #expect(DreamderDocumentController.shared.documents.contains { $0 === document })
        }
    }
}
