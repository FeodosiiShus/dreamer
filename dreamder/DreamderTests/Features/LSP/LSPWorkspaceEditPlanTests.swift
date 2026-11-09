import Foundation
import JSONRPC
import LanguageServerProtocol
import Synchronization
import Testing
@testable import Dreamder

@Suite
struct LSPTextEditApplierTests {
    private func apply(_ text: String, _ edits: [TextEdit]) throws -> String {
        try LSPTextEditApplier.apply(edits, to: text)
    }

    @Test
    func editsUseCoordinatesOfTheOriginalText() throws {
        let result = try apply("hello world", [
            lspTextEdit((0, 6), (0, 11), "there"),
            lspTextEdit((0, 0), (0, 5), "goodbye")
        ])
        #expect(result == "goodbye there")
    }

    @Test
    func insertionsAtTheSamePositionKeepArrayOrder() throws {
        let result = try apply("ab", [
            lspTextEdit((0, 1), (0, 1), "X"),
            lspTextEdit((0, 1), (0, 1), "Y")
        ])
        #expect(result == "aXYb")
    }

    @Test
    func insertionAtTheStartOfAReplacementComesFirstWhateverTheOrder() throws {
        let result = try apply("abc", [
            lspTextEdit((0, 0), (0, 1), "X"),
            lspTextEdit((0, 0), (0, 0), "Y")
        ])
        #expect(result == "YXbc")
    }

    @Test
    func overlappingEditsAreRejected() {
        #expect(throws: LSPWorkspaceEditError.overlappingEdits) {
            try apply("abcdef", [lspTextEdit((0, 0), (0, 4), "x"), lspTextEdit((0, 2), (0, 5), "y")])
        }
        #expect(throws: LSPWorkspaceEditError.overlappingEdits) {
            try apply("abcdef", [lspTextEdit((0, 0), (0, 4), "x"), lspTextEdit((0, 2), (0, 2), "y")])
        }
    }

    @Test
    func adjacentEditsAreAllowed() throws {
        #expect(try apply("abcd", [lspTextEdit((0, 0), (0, 2), "X"), lspTextEdit((0, 2), (0, 4), "Y")]) == "XY")
    }

    @Test
    func rangesThatEndBeforeTheyStartAreRejected() {
        let range = LSPRange(startPair: (0, 3), endPair: (0, 1))
        #expect(throws: LSPWorkspaceEditError.invalidRange(range)) {
            try apply("abcd", [TextEdit(range: range, newText: "x")])
        }
    }

    @Test
    func linesOutsideTheDocumentAreRejectedButTheLineAfterATrailingNewlineIsValid() throws {
        #expect(try apply("a\n", [lspTextEdit((1, 0), (1, 0), "b")]) == "a\nb")
        #expect(throws: LSPWorkspaceEditError.lineOutOfRange(line: 2, lineCount: 2)) {
            try apply("a\n", [lspTextEdit((2, 0), (2, 0), "b")])
        }
        #expect(throws: LSPWorkspaceEditError.lineOutOfRange(line: -1, lineCount: 1)) {
            try apply("a", [lspTextEdit((-1, 0), (0, 0), "b")])
        }
    }

    @Test
    func charactersBeyondTheLineEndClampToTheLineEnd() throws {
        #expect(try apply("ab\ncd", [lspTextEdit((0, 99), (0, 99), "!")]) == "ab!\ncd")
    }

    @Test
    func lineTerminatorsOfAllKindsStartNewLines() throws {
        #expect(try apply("a\r\nb", [lspTextEdit((1, 0), (1, 0), "X")]) == "a\r\nXb")
        #expect(try apply("a\rb", [lspTextEdit((1, 0), (1, 0), "X")]) == "a\rXb")
        #expect(try apply("a\nb", [lspTextEdit((1, 1), (1, 1), "X")]) == "a\nbX")
        #expect(try apply("a\r\n\r\nb", [lspTextEdit((2, 0), (2, 1), "X")]) == "a\r\n\r\nX")
    }

    @Test
    func positionsCountUTF16CodeUnits() throws {
        #expect(try apply("😀x", [lspTextEdit((0, 2), (0, 3), "y")]) == "😀y")
        #expect(try apply("é😀", [lspTextEdit((0, 1), (0, 3), "")]) == "é")
    }

    @Test
    func noEditsLeaveTheTextUntouched() throws {
        #expect(try apply("same\ntext", []) == "same\ntext")
    }

    @Test
    func resolvedEditsAreSortedAndCarryTheirNSRanges() throws {
        let first = lspTextEdit((1, 0), (1, 1), "B")
        let second = lspTextEdit((0, 0), (0, 1), "A")
        let resolved = try LSPTextEditApplier.resolve([first, second], in: "xx\nyy")
        #expect(resolved == [
            LSPResolvedTextEdit(edit: second, range: NSRange(location: 0, length: 1)),
            LSPResolvedTextEdit(edit: first, range: NSRange(location: 3, length: 1))
        ])
    }
}

@Suite
struct LSPWorkspaceEditPlanTests {
    @Test
    func changesAreOrderedByUri() {
        let edit = WorkspaceEdit(
            changes: [
                "file:///b": [lspTextEdit((0, 0), (0, 0), "b")],
                "file:///a": [lspTextEdit((0, 0), (0, 0), "a")]
            ],
            documentChanges: nil
        )
        #expect(LSPWorkspaceEditPlan.operations(for: edit) == [
            .editText(uri: "file:///a", edits: [lspTextEdit((0, 0), (0, 0), "a")], version: nil),
            .editText(uri: "file:///b", edits: [lspTextEdit((0, 0), (0, 0), "b")], version: nil)
        ])
    }

    @Test
    func documentChangesTakePrecedenceOverChanges() throws {
        let edit = try lspDecode(WorkspaceEdit.self, """
        {
          "changes": {"file:///ignored": []},
          "documentChanges": [
            {"textDocument": {"uri": "file:///a", "version": 3},
             "edits": [{"range": {"start": {"line": 0, "character": 0},
                                  "end": {"line": 0, "character": 1}}, "newText": "x"}]},
            {"kind": "create", "uri": "file:///new", "options": {"overwrite": true}},
            {"kind": "rename", "oldUri": "file:///old", "newUri": "file:///renamed",
             "options": {"ignoreIfExists": true}}
          ]
        }
        """)
        #expect(LSPWorkspaceEditPlan.operations(for: edit) == [
            .editText(uri: "file:///a", edits: [lspTextEdit((0, 0), (0, 1), "x")], version: 3),
            .createFile(uri: "file:///new", overwrite: true, ignoreIfExists: false),
            .renameFile(oldURI: "file:///old", newURI: "file:///renamed", overwrite: false, ignoreIfExists: true)
        ])
    }

    @Test
    func deleteDecodedAsCreateFileByThePackageBecomesADelete() throws {
        let edit = try lspDecode(WorkspaceEdit.self, """
        {"documentChanges": [{"kind": "delete", "uri": "file:///gone"}]}
        """)
        #expect(LSPWorkspaceEditPlan.operations(for: edit) == [
            .deleteFile(uri: "file:///gone", recursive: false, ignoreIfNotExists: false)
        ])
    }

    @Test
    func deleteOptionsAreCarriedOver() {
        let delete = DeleteFile(
            kind: "delete",
            uri: "file:///dir",
            options: DeleteFileOptions(recursive: true, ignoreIfNotExists: true)
        )
        let edit = WorkspaceEdit(changes: nil, documentChanges: [.deleteFile(delete)])
        #expect(LSPWorkspaceEditPlan.operations(for: edit) == [
            .deleteFile(uri: "file:///dir", recursive: true, ignoreIfNotExists: true)
        ])
    }

    @Test
    func emptyEditHasNoOperations() {
        #expect(LSPWorkspaceEditPlan.operations(for: WorkspaceEdit(changes: nil, documentChanges: nil)).isEmpty)
    }
}

@Suite
struct LSPShowDocumentPlanTests {
    @Test
    func webAndMailUrisOpenExternally() throws {
        let docs = try #require(URL(string: "https://example.com/docs"))
        let plain = try #require(URL(string: "http://example.com"))
        let mail = try #require(URL(string: "mailto:a@example.com"))
        #expect(LSPShowDocumentPlan.make(for: ShowDocumentParams(uri: docs.absoluteString)) == .external(docs))
        #expect(LSPShowDocumentPlan.make(
            for: ShowDocumentParams(uri: plain.absoluteString, takeFocus: false)
        ) == .external(plain))
        #expect(LSPShowDocumentPlan.make(for: ShowDocumentParams(uri: mail.absoluteString)) == .external(mail))
    }

    @Test
    func fileUrisOpenInTheEditorWithTheSelectionAndFocusPreference() {
        let selection = LSPRange(startPair: (2, 1), endPair: (2, 5))
        let plan = LSPShowDocumentPlan.make(
            for: ShowDocumentParams(uri: "file:///project/a.swift", takeFocus: false, selection: selection)
        )
        #expect(plan == .editor(URL(fileURLWithPath: "/project/a.swift"), selection: selection, takeFocus: false))
    }

    @Test
    func takeFocusDefaultsToTrue() {
        let plan = LSPShowDocumentPlan.make(for: ShowDocumentParams(uri: "file:///project/a.swift"))
        #expect(plan == .editor(URL(fileURLWithPath: "/project/a.swift"), selection: nil, takeFocus: true))
    }

    @Test
    func externalFlagSendsFilesToTheSystem() {
        let plan = LSPShowDocumentPlan.make(for: ShowDocumentParams(uri: "file:///project/a.pdf", external: true))
        #expect(plan == .external(URL(fileURLWithPath: "/project/a.pdf")))
    }

    @Test
    func unsupportedSchemesAreInvalid() {
        #expect(LSPShowDocumentPlan.make(for: ShowDocumentParams(uri: "untitled:Untitled-1")) == .invalid)
        #expect(LSPShowDocumentPlan.make(for: ShowDocumentParams(uri: "jar:file:///a.jar!/B.class")) == .invalid)
        #expect(LSPShowDocumentPlan.make(for: ShowDocumentParams(uri: "")) == .invalid)
    }

    @Test
    func fileUriWithUnencodedSpacesResolvesToThePath() {
        let plan = LSPShowDocumentPlan.make(for: ShowDocumentParams(uri: "file:///tmp/a b.swift"))
        guard case let .editor(url, _, _) = plan else {
            Issue.record("Expected an editor plan")
            return
        }
        #expect(url.path == "/tmp/a b.swift")
    }
}

@Suite
struct LSPFileURITests {
    @Test
    func wellFormedFileUrisParseDirectly() {
        #expect(LSPFileURI.fileURL(from: "file:///tmp/a.swift")?.path == "/tmp/a.swift")
    }

    @Test
    func fileUrisWithMalformedAuthoritiesFallBackToThePathAfterThePrefix() throws {
        let url = try #require(LSPFileURI.fileURL(from: "file://localhost:abc/tmp/a.swift"))
        #expect(url.isFileURL)
        #expect(url.lastPathComponent == "a.swift")
    }

    @Test
    func otherSchemesAreRejected() {
        #expect(LSPFileURI.fileURL(from: "untitled:Untitled-1") == nil)
        #expect(LSPFileURI.fileURL(from: "https://example.com/a.swift") == nil)
        #expect(LSPFileURI.fileURL(from: "") == nil)
    }
}
