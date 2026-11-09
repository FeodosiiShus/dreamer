import AppKit
import CodeEditTextView
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct CodeFileDocumentUndoHistoryTests {
    private static let original = "alpha\nbeta\n"

    @MainActor
    fileprivate struct OpenFile {
        let workspace: WorkspaceDocument
        let document: CodeFileDocument
        let url: URL
        let view: TextView
        let manager: CEUndoManager

        func type(_ string: String, at location: Int) {
            manager.beginUndoGrouping()
            view.replaceCharacters(in: NSRange(location: location, length: 0), with: string)
            manager.endUndoGrouping()
        }
    }

    fileprivate func openFile(in directory: URL) throws -> OpenFile {
        try "root = true\n".write(to: directory.appending(path: ".editorconfig"), atomically: true, encoding: .utf8)
        let workspace = try HostedSourceEditorFixture.registerWorkspace(at: directory)
        let fixture = try HostedSourceEditorFixture.make(
            in: directory,
            fileName: "history.txt",
            typeIdentifier: "public.plain-text",
            contents: Self.original
        )
        let url = try #require(fixture.document.fileURL)
        let view = TextView(string: "")
        view.setTextStorage(try #require(fixture.document.content))
        let manager = workspace.undoRegistration.manager(forFile: url)
        view.setUndoManager(manager)
        return OpenFile(workspace: workspace, document: fixture.document, url: url, view: view, manager: manager)
    }

    @Test
    func closingTheDocumentDiscardsTheUndoManagerOfItsFile() throws {
        try withTempDir { dir in
            let file = try openFile(in: dir)
            defer { file.workspace.close() }
            file.type("xyz", at: 5)
            #expect(file.manager.canUndo)

            file.document.close()

            #expect(file.workspace.undoRegistration.managerIfExists(forFile: file.url) == nil)
            #expect(file.workspace.undoRegistration.manager(forFile: file.url) !== file.manager)
        }
    }

    @Test
    func reopeningAfterClosingWithoutSavingHasNothingToUndo() throws {
        try withTempDir { dir in
            let file = try openFile(in: dir)
            defer { file.workspace.close() }
            file.type("xyz", at: 5)
            #expect(file.view.string == "alphaxyz\nbeta\n")
            file.document.close()

            let reopened = try CodeFileDocument(for: file.url, withContentsOf: file.url, ofType: "public.plain-text")
            defer { reopened.close() }
            let reopenedView = TextView(string: "")
            reopenedView.setTextStorage(try #require(reopened.content))
            let reopenedManager = file.workspace.undoRegistration.manager(forFile: file.url)
            reopenedView.setUndoManager(reopenedManager)

            #expect(reopened.content?.string == Self.original)
            #expect(!reopenedManager.canUndo)
            #expect(reopenedManager.undoCount == 0)
            #expect(reopenedView.string == Self.original)
        }
    }

    @Test
    func closingOneDocumentKeepsTheUndoManagersOfOtherFiles() throws {
        try withTempDir { dir in
            let file = try openFile(in: dir)
            defer { file.workspace.close() }
            let otherURL = dir.appending(path: "other.txt")
            let otherManager = file.workspace.undoRegistration.manager(forFile: otherURL)

            file.document.close()

            #expect(file.workspace.undoRegistration.managerIfExists(forFile: otherURL) === otherManager)
        }
    }

    @Test
    func closingADocumentWithoutAFileURLLeavesTheRegistrationAlone() throws {
        try withTempDir { dir in
            let file = try openFile(in: dir)
            defer { file.workspace.close() }
            let document = CodeFileDocument()

            document.close()

            #expect(file.workspace.undoRegistration.managerIfExists(forFile: file.url) === file.manager)
        }
    }

    @Test
    func anExternalChangeClearsTheUndoHistoryOfTheOpenDocument() async throws {
        try await withTempDir { dir in
            let file = try openFile(in: dir)
            defer {
                file.document.close()
                file.workspace.close()
            }
            file.type("xyz", at: 5)
            #expect(file.manager.undoCount == 1)

            try "changed\nelsewhere\n".write(to: file.url, atomically: true, encoding: .utf8)
            file.document.presentedItemDidChange()
            try await eventually(timeout: .seconds(20)) { file.document.content?.string == "changed\nelsewhere\n" }

            #expect(file.view.string == "changed\nelsewhere\n")
            #expect(!file.manager.canUndo)
            #expect(!file.manager.canRedo)
            #expect(file.manager.undoCount == 0)
        }
    }

    @Test
    func reloadingDiscardingEditsClearsTheUndoHistory() throws {
        try withTempDir { dir in
            let file = try openFile(in: dir)
            defer {
                file.document.close()
                file.workspace.close()
            }
            file.type("xyz", at: 5)
            #expect(file.manager.canUndo)

            file.document.reloadContentDiscardingEdits()

            #expect(file.view.string == Self.original)
            #expect(!file.manager.canUndo)
            #expect(!file.manager.canRedo)
        }
    }
}
