import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import LanguageClient
import LanguageServerProtocol
import Testing
@testable import Dreamder

enum ApplierEdits {
    static func replace(_ text: String, line: Int = 0, columns: Range<Int> = 4..<5) -> TextEdit {
        let range = LSPRange(startPair: (line, columns.lowerBound), endPair: (line, columns.upperBound))
        return TextEdit(range: range, newText: text)
    }

    static func versioned(_ uri: String, version: Int?, _ edits: [TextEdit]) -> WorkspaceEditDocumentChange {
        .textDocumentEdit(TextDocumentEdit(
            textDocument: VersionedTextDocumentIdentifier(uri: uri, version: version),
            edits: edits
        ))
    }

    static func single(_ uri: String, version: Int?, _ text: String) -> WorkspaceEdit {
        WorkspaceEdit(changes: nil, documentChanges: [versioned(uri, version: version, [replace(text)])])
    }

    static func plain(_ uri: String, _ edits: [TextEdit]) -> WorkspaceEdit {
        WorkspaceEdit(changes: [uri: edits], documentChanges: nil)
    }

    static func rejection(_ reason: String, at index: UInt = 0) -> ApplyWorkspaceEditResult {
        ApplyWorkspaceEditResult(applied: false, failureReason: reason, failedChange: index)
    }
}

@MainActor
@Suite("WorkspaceEditApplier", .serialized, .uiGate)
struct WorkspaceEditApplierTests {
    private let originalText = "let a = 1\nlet b = 2\n"

    private func apply(_ edit: WorkspaceEdit, _ harness: CodeActionsHarness) async -> ApplyWorkspaceEditResult {
        await harness.service.applyWorkspaceEdit(edit, via: harness.client)
    }

    @Test
    func aVersionedEditForAnOlderVersionIsRejectedAndTheTextStaysUntouched() async throws {
        try await withTempDir { directory in
            let harness = try await CodeActionsHarness.make(in: directory)
            defer { harness.workspace.close() }
            let uri = harness.uri
            let first = await apply(harness.replaceFirstLineEdit("x"), harness)
            #expect(first.applied)
            #expect(harness.client.openFiles.documentVersion(for: uri) == 1)

            let result = await apply(ApplierEdits.single(uri, version: 0, "y"), harness)

            #expect(result == ApplierEdits.rejection("The document changed after the edit was computed: \(uri)"))
            #expect(harness.document.content?.string == "let x = 1\nlet b = 2\n")
            #expect(harness.client.openFiles.documentVersion(for: uri) == 1)
        }
    }

    @Test
    func anEditForTheCurrentVersionOrWithoutAVersionIsApplied() async throws {
        try await withTempDir { directory in
            let harness = try await CodeActionsHarness.make(in: directory)
            defer { harness.workspace.close() }
            let uri = harness.uri
            _ = await apply(harness.replaceFirstLineEdit("x"), harness)

            let current = await apply(ApplierEdits.single(uri, version: 1, "y"), harness)
            #expect(current.applied)
            #expect(harness.document.content?.string == "let y = 1\nlet b = 2\n")

            let unversioned = await apply(ApplierEdits.single(uri, version: nil, "z"), harness)
            #expect(unversioned.applied)
            #expect(harness.document.content?.string == "let z = 1\nlet b = 2\n")
        }
    }

    @Test
    func localEditsTheServerHasNotSeenYetRejectTheEditUntilTheyAreFlushed() async throws {
        try await withTempDir { directory in
            let harness = try await CodeActionsHarness.make(in: directory)
            defer { harness.workspace.close() }
            let uri = harness.uri
            let coordinator = LSPContentCoordinator<CodeFileDocument>(
                documentURI: uri,
                languageServer: harness.client,
                batchInterval: .seconds(60)
            )
            harness.document.languageServerObjects.textCoordinator = coordinator
            defer { coordinator.discardPendingChanges() }
            coordinator.recordEdit(uri: uri, range: LSPRange(startPair: (1, 0), endPair: (1, 0)), string: "typed")
            let changesBefore = harness.connection.lspServiceChanges.count

            let rejected = await apply(harness.replaceFirstLineEdit("server"), harness)

            #expect(rejected == ApplierEdits.rejection(
                "The document has local edits the language server has not seen yet: \(uri)"
            ))
            #expect(harness.document.content?.string == originalText)
            #expect(harness.connection.lspServiceChanges.count == changesBefore)

            await coordinator.flushPendingChanges()
            let accepted = await apply(harness.replaceFirstLineEdit("server"), harness)

            #expect(accepted.applied)
            #expect(harness.document.content?.string == "let server = 1\nlet b = 2\n")
        }
    }

    @Test
    func aStaleEditRejectsTheWholeRequestAndLeavesEveryDocumentAndFileByteIdentical() async throws {
        try await withTempDir { directory in
            let harness = try await CodeActionsHarness.make(in: directory, extraFiles: ["other.swift": "old\ntext\n"])
            defer { harness.workspace.close() }
            let otherURL = directory.appending(path: "other.swift")
            let mainURL = directory.appending(path: "main.swift")
            let mainBytes = try Data(contentsOf: mainURL)
            let otherBytes = try Data(contentsOf: otherURL)
            let edit = WorkspaceEdit(changes: nil, documentChanges: [
                ApplierEdits.versioned(otherURL.lspURI, version: nil, [ApplierEdits.replace("new", columns: 0..<3)]),
                ApplierEdits.versioned(harness.uri, version: 5, [ApplierEdits.replace("y")])
            ])

            let result = await apply(edit, harness)

            #expect(result == ApplierEdits.rejection(
                "The document changed after the edit was computed: \(harness.uri)",
                at: 1
            ))
            #expect(harness.document.content?.string == originalText)
            #expect(try Data(contentsOf: mainURL) == mainBytes)
            #expect(try Data(contentsOf: otherURL) == otherBytes)
            #expect(harness.connection.lspServiceChanges.isEmpty)
        }
    }

    @Test
    func everySpellingOfAnOpenFilesUriResolvesToTheSameTrackedDocument() async throws {
        try await withTempDir { directory in
            let harness = try await CodeActionsHarness.make(in: directory, extraFiles: ["my file.swift": "let a = 1\n"])
            defer { harness.workspace.close() }
            let spaced = try harness.workspace.document("my file.swift")
            harness.service.openDocument(spaced)
            await harness.service.waitForDocumentOperations()
            let url = directory.appending(path: "my file.swift")
            let trackedURI = url.lspURI
            let encodedURI = url.absoluteString
            let decodedURI = "file://" + url.path(percentEncoded: false)
            #expect(decodedURI != trackedURI)

            let encoded = await apply(ApplierEdits.single(encodedURI, version: nil, "b"), harness)
            let decoded = await apply(ApplierEdits.single(decodedURI, version: nil, "c"), harness)

            #expect(encoded.applied)
            #expect(decoded.applied)
            #expect(spaced.content?.string == "let c = 1\n")
            #expect(harness.connection.lspServiceChanges.map(\.textDocument.uri) == [trackedURI, trackedURI])
        }
    }

    @Test
    func uriesThatAreNotFilesFailBeforeAnyDocumentLookupSucceeds() async throws {
        try await withTempDir { directory in
            let harness = try await CodeActionsHarness.make(in: directory)
            defer { harness.workspace.close() }
            let edit = ApplierEdits.plain("untitled:Untitled-1", [ApplierEdits.replace("x")])

            let result = await apply(edit, harness)

            #expect(result == ApplierEdits.rejection("Unsupported document URI: untitled:Untitled-1"))
            #expect(harness.document.content?.string == originalText)
        }
    }

    @Test
    func anOpenDocumentTheClientDoesNotTrackIsEditedInItsBufferAndNeverOnDisk() async throws {
        try await withTempDir { directory in
            let harness = try await CodeActionsHarness.make(in: directory, extraFiles: ["other.swift": "old\ntext\n"])
            defer { harness.workspace.close() }
            let other = try harness.workspace.document("other.swift")
            harness.workspace.setText("other.swift", "dirty\ntext\n")
            DreamderDocumentController.shared.addDocument(other)
            defer { DreamderDocumentController.shared.removeDocument(other) }
            let otherURL = directory.appending(path: "other.swift")
            let diskBytes = try Data(contentsOf: otherURL)
            let edit = ApplierEdits.plain(otherURL.lspURI, [ApplierEdits.replace("clean", columns: 0..<5)])

            let result = await apply(edit, harness)

            #expect(result.applied)
            #expect(other.content?.string == "clean\ntext\n")
            #expect(other.isDocumentEdited)
            #expect(try Data(contentsOf: otherURL) == diskBytes)
            #expect(harness.connection.lspServiceChanges.isEmpty)
        }
    }

    @Test
    func theDefaultLookupListsTheCodeFilesRegisteredWithTheSharedDocumentController() async throws {
        try await withTempDir { directory in
            let harness = try await CodeActionsHarness.make(in: directory)
            defer { harness.workspace.close() }
            DreamderDocumentController.shared.addDocument(harness.document)
            defer { DreamderDocumentController.shared.removeDocument(harness.document) }

            let registered = WorkspaceEditApplier.registeredDocuments()

            #expect(registered.contains { $0 === harness.document })
        }
    }

    @Test
    func theInjectedLookupDecidesWhichOpenDocumentReceivesTheEdit() async throws {
        try await withTempDir { directory in
            let harness = try await CodeActionsHarness.make(in: directory, extraFiles: ["other.swift": "old\ntext\n"])
            defer { harness.workspace.close() }
            let other = try harness.workspace.document("other.swift")
            let otherURL = directory.appending(path: "other.swift")
            let edit = ApplierEdits.plain(otherURL.lspURI, [ApplierEdits.replace("new", columns: 0..<3)])

            let ignored = await WorkspaceEditApplier(client: harness.client, openDocuments: { [] }).apply(edit)
            #expect(ignored.applied)
            #expect(other.content?.string == "old\ntext\n")
            #expect(try String(contentsOf: otherURL, encoding: .utf8) == "new\ntext\n")

            try "old\ntext\n".write(to: otherURL, atomically: true, encoding: .utf8)
            let routed = await WorkspaceEditApplier(client: harness.client, openDocuments: { [other] }).apply(edit)
            #expect(routed.applied)
            #expect(other.content?.string == "new\ntext\n")
            #expect(try String(contentsOf: otherURL, encoding: .utf8) == "old\ntext\n")
        }
    }
}

@MainActor
@Suite("WorkspaceEditApplierHostedEditor", .serialized, .uiGate)
struct WorkspaceEditApplierHostedEditorTests {
    @Test
    func anUntrackedDocumentShownInAnEditorIsEditedThroughItsTextViewAsOneUndoStep() async throws {
        try await withTempDir { directory in
            let harness = try await CodeActionsHarness.make(in: directory, extraFiles: ["other.swift": "old\ntext\n"])
            defer { harness.workspace.close() }
            let other = try harness.workspace.document("other.swift")
            let otherURL = directory.appending(path: "other.swift")
            let diskBytes = try Data(contentsOf: otherURL)
            let fixture = HostedSourceEditorFixture(
                document: other,
                editorInstance: EditorInstance(workspace: nil, file: CEWorkspaceFile(url: otherURL))
            )
            let hosted = fixture.host(
                coordinators: [other.contentCoordinator, other.textViewBinder],
                size: NSSize(width: 900, height: 600)
            )
            defer { hosted.close() }
            try await eventually(timeout: .seconds(20)) { other.attachedTextView != nil }
            let textView = try #require(other.attachedTextView)
            let edit = ApplierEdits.plain(otherURL.lspURI, [
                ApplierEdits.replace("new", line: 0, columns: 0..<3),
                ApplierEdits.replace("TEXT", line: 1, columns: 0..<4)
            ])

            let result = await WorkspaceEditApplier(client: harness.client, openDocuments: { [other] }).apply(edit)

            #expect(result.applied)
            #expect(textView.string == "new\nTEXT\n")
            #expect(try Data(contentsOf: otherURL) == diskBytes)
            #expect(harness.connection.lspServiceChanges.isEmpty)

            textView.undoManager?.undo()

            #expect(textView.string == "old\ntext\n")
            #expect(try Data(contentsOf: otherURL) == diskBytes)
        }
    }
}
