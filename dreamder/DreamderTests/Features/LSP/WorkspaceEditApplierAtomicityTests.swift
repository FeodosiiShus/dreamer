import AppKit
import Foundation
import LanguageClient
import LanguageServerProtocol
import Testing
@testable import Dreamder

@MainActor
private final class TypingProbe {
    var snapshots: [String] = []
    var tasks: [Task<Void, Never>] = []
    func queueTyping(
        into document: CodeFileDocument,
        coordinator: LSPContentCoordinator<CodeFileDocument>,
        uri: String
    ) {
        tasks.append(Task { @MainActor [self] in
            snapshots.append(document.content?.string ?? "")
            coordinator.recordEdit(uri: uri, range: LSPRange(startPair: (1, 0), endPair: (1, 0)), string: "typed")
        })
    }

    func finish() async {
        for task in tasks {
            await task.value
        }
    }
}

@MainActor
@Suite("WorkspaceEditApplierAtomicity", .serialized, .uiGate)
struct WorkspaceEditApplierAtomicityTests {
    private let editedText = "let x = 1\nlet b = 2\n"

    private func makeCoordinator(
        _ harness: CodeActionsHarness
    ) -> LSPContentCoordinator<CodeFileDocument> {
        let coordinator = LSPContentCoordinator<CodeFileDocument>(
            documentURI: harness.uri,
            languageServer: harness.client,
            batchInterval: .seconds(60)
        )
        harness.document.languageServerObjects.textCoordinator = coordinator
        return coordinator
    }

    @Test
    func typingQueuedWhileTheEditIsBeingPreparedCannotSlipInBetweenTheCheckAndTheApply() async throws {
        try await withTempDir { directory in
            let harness = try await CodeActionsHarness.make(in: directory, extraFiles: ["other.swift": "old\ntext\n"])
            defer { harness.workspace.close() }
            let other = try harness.workspace.document("other.swift")
            let otherURL = directory.appending(path: "other.swift")
            let coordinator = makeCoordinator(harness)
            defer { coordinator.discardPendingChanges() }
            let probe = TypingProbe()
            let applier = WorkspaceEditApplier(client: harness.client, openDocuments: {
                probe.queueTyping(into: harness.document, coordinator: coordinator, uri: harness.uri)
                return [other]
            })
            let edit = WorkspaceEdit(changes: nil, documentChanges: [
                ApplierEdits.versioned(harness.uri, version: 0, [ApplierEdits.replace("x")]),
                ApplierEdits.versioned(otherURL.lspURI, version: nil, [ApplierEdits.replace("new", columns: 0..<3)])
            ])

            let result = await applier.apply(edit)
            await probe.finish()

            #expect(result.applied)
            #expect(probe.snapshots == [editedText])
            #expect(harness.document.content?.string == editedText)
            #expect(coordinator.hasPendingChanges)
        }
    }

    @Test
    func typingQueuedBeforeTheApplierRunsRejectsTheWholeEdit() async throws {
        try await withTempDir { directory in
            let harness = try await CodeActionsHarness.make(in: directory)
            defer { harness.workspace.close() }
            let coordinator = makeCoordinator(harness)
            defer { coordinator.discardPendingChanges() }
            let probe = TypingProbe()
            probe.queueTyping(into: harness.document, coordinator: coordinator, uri: harness.uri)

            let result = await WorkspaceEditApplier(client: harness.client).apply(harness.replaceFirstLineEdit("x"))
            await probe.finish()

            #expect(result == ApplierEdits.rejection(
                "The document has local edits the language server has not seen yet: \(harness.uri)"
            ))
            #expect(harness.document.content?.string == "let a = 1\nlet b = 2\n")
        }
    }

    @Test
    func severalEditsToOneOpenDocumentApplyInOrderEachSeeingTheResultOfThePrevious() async throws {
        try await withTempDir { directory in
            let harness = try await CodeActionsHarness.make(in: directory)
            defer { harness.workspace.close() }
            let edit = WorkspaceEdit(changes: nil, documentChanges: [
                ApplierEdits.versioned(harness.uri, version: nil, [ApplierEdits.replace("xyz")]),
                ApplierEdits.versioned(harness.uri, version: nil, [ApplierEdits.replace("q", columns: 4..<7)])
            ])

            let result = await WorkspaceEditApplier(client: harness.client).apply(edit)

            #expect(result.applied)
            #expect(harness.document.content?.string == "let q = 1\nlet b = 2\n")
            #expect(harness.connection.lspServiceChanges.count == 2)
        }
    }

    @Test
    func anEditThatCannotBeResolvedRejectsTheRequestBeforeAnyOpenDocumentChanges() async throws {
        try await withTempDir { directory in
            let harness = try await CodeActionsHarness.make(in: directory)
            defer { harness.workspace.close() }
            let edit = WorkspaceEdit(changes: nil, documentChanges: [
                ApplierEdits.versioned(harness.uri, version: nil, [ApplierEdits.replace("x")]),
                ApplierEdits.versioned(harness.uri, version: nil, [ApplierEdits.replace("y", line: 9)])
            ])

            let result = await WorkspaceEditApplier(client: harness.client).apply(edit)

            #expect(result.applied == false)
            #expect(result.failedChange == 1)
            #expect(harness.document.content?.string == "let a = 1\nlet b = 2\n")
            #expect(harness.connection.lspServiceChanges.isEmpty)
        }
    }

    @Test
    func directEditsLikeFormattingIgnorePendingEditsAndReportClosedDocuments() async throws {
        try await withTempDir { directory in
            let harness = try await CodeActionsHarness.make(in: directory)
            defer { harness.workspace.close() }
            let coordinator = makeCoordinator(harness)
            defer { coordinator.discardPendingChanges() }
            let typedRange = LSPRange(startPair: (1, 0), endPair: (1, 0))
            coordinator.recordEdit(uri: harness.uri, range: typedRange, string: "typed")
            let applier = WorkspaceEditApplier(client: harness.client, openDocuments: { [] })

            let applied = try await applier.editOpenDocument(uri: harness.uri, edits: [ApplierEdits.replace("x")])
            let closed = try await applier.editOpenDocument(
                uri: directory.appending(path: "closed.swift").lspURI,
                edits: [ApplierEdits.replace("x")]
            )

            #expect(applied)
            #expect(harness.document.content?.string == editedText)
            #expect(closed == false)
        }
    }
}
