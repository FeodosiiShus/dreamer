import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct CodeFileSaveActionsUndoTests {
    private static let silentEditorConfig = "root = true\n"

    private static let trimAllLines = SaveActionSettings(
        trailingSpaces: .allLines,
        keepTrailingSpacesOnCaretLine: false,
        ensureFinalNewline: false
    )

    private static let trimAllLinesAndEndWithNewline = SaveActionSettings(
        trailingSpaces: .allLines,
        keepTrailingSpacesOnCaretLine: false,
        ensureFinalNewline: true
    )

    @MainActor
    fileprivate struct Session {
        let workspace: WorkspaceDocument
        let fixture: HostedSourceEditorFixture
        let hosted: HostedSourceEditor
        let textView: TextView
        let manager: CEUndoManager

        var document: CodeFileDocument { fixture.document }

        var text: String { textView.string }

        func type(_ string: String, at location: Int) {
            manager.beginUndoGrouping()
            textView.replaceCharacters(in: NSRange(location: location, length: 0), with: string)
            manager.endUndoGrouping()
        }

        func close() {
            hosted.close()
            workspace.close()
        }
    }

    fileprivate func openSession(in directory: URL, contents: String) async throws -> Session {
        try Self.silentEditorConfig.write(
            to: directory.appending(path: ".editorconfig"),
            atomically: true,
            encoding: .utf8
        )
        let workspace = try HostedSourceEditorFixture.registerWorkspace(at: directory)
        let fixture = try HostedSourceEditorFixture.make(
            in: directory,
            fileName: "undo.txt",
            typeIdentifier: "public.plain-text",
            contents: contents
        )
        let hosted = fixture.host(
            coordinators: [fixture.document.contentCoordinator, fixture.document.textViewBinder],
            size: NSSize(width: 900, height: 600)
        )
        try await eventually(timeout: .seconds(20)) { hosted.controller?.textView != nil }
        let textView = try #require(hosted.controller?.textView)
        let url = try #require(fixture.document.fileURL)
        let manager = workspace.undoRegistration.manager(forFile: url)
        textView.setUndoManager(manager)
        return Session(workspace: workspace, fixture: fixture, hosted: hosted, textView: textView, manager: manager)
    }

    @Test
    func trimmingSeveralLinesIsOneUndoStepWhileTheTextViewIsAttached() async throws {
        try await withTempDir { dir in
            let session = try await openSession(in: dir, contents: "a  \nb  \nc  \n")
            defer { session.close() }
            #expect(session.document.attachedTextView === session.textView)

            #expect(session.document.applySaveActions(settings: Self.trimAllLines))
            #expect(session.text == "a\nb\nc\n")
            #expect(session.manager.undoCount == 1)

            session.manager.undo()
            #expect(session.text == "a  \nb  \nc  \n")
            #expect(session.document.content?.string == "a  \nb  \nc  \n")
            #expect(!session.manager.canUndo)

            session.manager.redo()
            #expect(session.text == "a\nb\nc\n")
            #expect(!session.manager.canRedo)
        }
    }

    @Test
    func saveActionsStayASeparateUndoStepFromTheUsersTyping() async throws {
        try await withTempDir { dir in
            let session = try await openSession(in: dir, contents: "a\nb\n")
            defer { session.close() }
            session.type("  ", at: 1)
            session.type(" ", at: 5)
            #expect(session.text == "a  \nb \n")

            #expect(session.document.applySaveActions(settings: Self.trimAllLines))
            #expect(session.text == "a\nb\n")
            #expect(session.manager.undoCount == 3)

            session.manager.undo()
            #expect(session.text == "a  \nb \n")
            session.manager.undo()
            #expect(session.text == "a  \nb\n")
            session.manager.undo()
            #expect(session.text == "a\nb\n")
            #expect(!session.manager.canUndo)

            session.manager.redo()
            #expect(session.text == "a  \nb\n")
            session.manager.redo()
            #expect(session.text == "a  \nb \n")
            session.manager.redo()
            #expect(session.text == "a\nb\n")
            #expect(!session.manager.canRedo)
        }
    }

    @Test
    func trimmingAndTheFinalNewlineAreOneUndoStep() async throws {
        try await withTempDir { dir in
            let session = try await openSession(in: dir, contents: "ab  \ncd")
            defer { session.close() }

            #expect(session.document.applySaveActions(settings: Self.trimAllLinesAndEndWithNewline))
            #expect(session.text == "ab\ncd\n")
            #expect(session.manager.undoCount == 1)

            session.manager.undo()
            #expect(session.text == "ab  \ncd")

            session.manager.redo()
            #expect(session.text == "ab\ncd\n")
        }
    }

    @Test
    func saveActionsWithoutAttachedTextViewKeepTheUndoStackAligned() async throws {
        try await withTempDir { dir in
            let session = try await openSession(in: dir, contents: "alpha\nbeta\n")
            defer { session.close() }
            session.type("  ", at: 5)
            session.type(" ", at: 12)
            #expect(session.text == "alpha  \nbeta \n")
            session.document.attachedController = nil
            #expect(session.document.attachedTextView == nil)

            #expect(session.document.applySaveActions(settings: Self.trimAllLines))
            #expect(session.document.content?.string == "alpha\nbeta\n")
            #expect(session.manager.undoCount == 3)

            session.textView.setUndoManager(session.manager)
            session.manager.undo()
            #expect(session.text == "alpha  \nbeta \n")
            session.manager.undo()
            #expect(session.text == "alpha  \nbeta\n")
            session.manager.undo()
            #expect(session.text == "alpha\nbeta\n")
            #expect(!session.manager.canUndo)

            session.manager.redo()
            #expect(session.text == "alpha  \nbeta\n")
            session.manager.redo()
            #expect(session.text == "alpha  \nbeta \n")
            session.manager.redo()
            #expect(session.text == "alpha\nbeta\n")
            #expect(!session.manager.canRedo)
        }
    }

    @Test
    func aDocumentThatWasNeverDisplayedRegistersItsSaveActionsWithTheFilesUndoManager() throws {
        try withTempDir { dir in
            try Self.silentEditorConfig.write(
                to: dir.appending(path: ".editorconfig"),
                atomically: true,
                encoding: .utf8
            )
            let workspace = try HostedSourceEditorFixture.registerWorkspace(at: dir)
            defer { workspace.close() }
            let fixture = try HostedSourceEditorFixture.make(
                in: dir,
                fileName: "bare.txt",
                typeIdentifier: "public.plain-text",
                contents: "a  \nb  \n"
            )
            let document = fixture.document
            let manager = workspace.undoRegistration.manager(forFile: try #require(document.fileURL))
            #expect(document.attachedTextView == nil)

            #expect(document.applySaveActions(settings: Self.trimAllLines))
            #expect(document.content?.string == "a\nb\n")
            #expect(manager.undoCount == 1)

            let view = TextView(string: "")
            view.setTextStorage(try #require(document.content))
            view.setUndoManager(manager)
            manager.undo()
            #expect(view.string == "a  \nb  \n")
            manager.redo()
            #expect(view.string == "a\nb\n")
        }
    }

    @Test
    func aNonEditableTextViewKeepsItsUndoManagerBoundAfterTheSaveActions() async throws {
        try await withTempDir { dir in
            let session = try await openSession(in: dir, contents: "a  \n")
            defer { session.close() }
            session.type("x", at: 0)
            #expect(session.text == "xa  \n")
            session.textView.isEditable = false

            #expect(session.document.applySaveActions(settings: Self.trimAllLines))
            #expect(session.text == "xa\n")

            session.textView.isEditable = true
            session.manager.undo()
            #expect(session.text == "xa  \n")
            session.manager.undo()
            #expect(session.text == "a  \n")
            session.manager.redo()
            #expect(session.text == "xa  \n")
            session.manager.redo()
            #expect(session.text == "xa\n")
        }
    }
}
