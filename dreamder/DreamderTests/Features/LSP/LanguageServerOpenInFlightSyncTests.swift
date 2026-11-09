import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct LanguageServerOpenInFlightSyncTests {
    private struct Fixture {
        let editor: SyncEditorHarness
        let scripted: ScriptedServerConnection
        let gate: GatedOpenConnection
        let server: LanguageServer<SyncTestDocument>
        let open: Task<Void, any Error>
    }

    private func beginOpen(mode: DocumentSyncMode = .incremental) async throws -> Fixture {
        let scripted = ScriptedServerConnection(capabilities: mode.capabilities)
        let gate = GatedOpenConnection(inner: scripted)
        let server = try await SyncTestServer.makeServer(connection: gate, capabilities: mode.capabilities)
        let editor = SyncEditorHarness()
        let document = editor.document
        let open = Task { try await server.openDocument(document) }
        var started = gate.started.makeAsyncIterator()
        _ = await started.next()
        return Fixture(editor: editor, scripted: scripted, gate: gate, server: server, open: open)
    }

    private func syncMethods(_ scripted: ScriptedServerConnection) -> [ClientNotification.Method] {
        scripted.notifications.map(\.method).filter { $0 == .textDocumentDidOpen || $0 == .textDocumentDidChange }
    }

    @Test(arguments: DocumentSyncMode.allCases)
    func editsTypedWhileTheFirstDidOpenIsInFlightAreSentAfterItInOrder(mode: DocumentSyncMode) async throws {
        let fixture = try await beginOpen(mode: mode)
        let editor = fixture.editor

        editor.insert("a", at: 0)
        editor.insert("b", at: 7)

        #expect(editor.coordinator.hasPendingChanges)
        let flush = Task { await editor.coordinator.flushPendingChanges() }
        try await eventually(timeout: .seconds(20)) { !editor.coordinator.hasPendingChanges }
        #expect(fixture.scripted.notifications.map(\.method).contains(.textDocumentDidChange) == false)

        fixture.gate.release()
        try await fixture.open.value
        await flush.value

        let replay = DocumentSyncReplay(fixture.scripted.notifications)
        #expect(syncMethods(fixture.scripted) == [.textDocumentDidOpen, .textDocumentDidChange])
        #expect(editor.text == "ahello\nbworld")
        #expect(replay.text == editor.text)
        #expect(replay.versions == [0, 1])
        #expect(replay.changedBeforeOpen == false)
        #expect(fixture.server.openFiles.documentVersion(for: syncTestDocumentURI) == 1)
        #expect(editor.coordinator.languageServer === fixture.server)
        #expect(editor.coordinator.documentURI == syncTestDocumentURI)
    }

    @Test
    func incrementalEditsKeepTheirOrderAndRangesAcrossTheOpenBoundary() async throws {
        let fixture = try await beginOpen()
        let editor = fixture.editor

        editor.insert("1", at: 0)
        editor.insert("2", at: 1)
        let flush = Task { await editor.coordinator.flushPendingChanges() }
        fixture.gate.release()
        try await fixture.open.value
        await flush.value
        editor.insert("3", at: 2)
        await editor.coordinator.flushPendingChanges()

        let changes = fixture.scripted.notifications.compactMap { notification -> DidChangeTextDocumentParams? in
            if case let .textDocumentDidChange(params) = notification {
                return params
            }
            return nil
        }
        #expect(changes.map(\.textDocument.version) == [1, 2])
        #expect(changes.map { $0.contentChanges.map(\.text) } == [["1", "2"], ["3"]])
        #expect(DocumentSyncReplay(fixture.scripted.notifications).text == editor.text)
        #expect(editor.text == "123hello\nworld")
    }

    @Test
    func aRequestFlushIssuedWhileOpeningWaitsForTheDidOpen() async throws {
        let fixture = try await beginOpen()
        let editor = fixture.editor
        editor.insert("a", at: 0)

        let flush = Task { await fixture.server.flushPendingEdits(for: syncTestDocumentURI) }
        try await eventually(timeout: .seconds(20)) { !editor.coordinator.hasPendingChanges }
        fixture.gate.release()
        try await fixture.open.value
        await flush.value

        #expect(syncMethods(fixture.scripted) == [.textDocumentDidOpen, .textDocumentDidChange])
        #expect(DocumentSyncReplay(fixture.scripted.notifications).text == editor.text)
    }

    @Test
    func aFailedOpenForgetsTheDocumentAndNeverSendsTheEditsTypedMeanwhile() async throws {
        let fixture = try await beginOpen()
        let editor = fixture.editor
        fixture.scripted.failNotifications([.textDocumentDidOpen])
        editor.insert("a", at: 0)
        let flush = Task { await editor.coordinator.flushPendingChanges() }
        try await eventually(timeout: .seconds(20)) { !editor.coordinator.hasPendingChanges }

        fixture.gate.release()
        await #expect(throws: (any Error).self) { try await fixture.open.value }
        await flush.value
        editor.insert("b", at: 0)

        #expect(syncMethods(fixture.scripted) == [.textDocumentDidOpen])
        #expect(fixture.server.openFiles.document(for: syncTestDocumentURI) == nil)
        #expect(editor.coordinator.hasPendingChanges == false)
        #expect(editor.coordinator.documentURI == nil)
        #expect(editor.coordinator.languageServer == nil)
    }

    @Test
    func aDocumentThatFailedToOpenCanBeOpenedAgainAndSyncsFromScratch() async throws {
        let fixture = try await beginOpen()
        let editor = fixture.editor
        fixture.scripted.failNotifications([.textDocumentDidOpen])
        fixture.gate.release()
        await #expect(throws: (any Error).self) { try await fixture.open.value }
        fixture.scripted.failNotifications([])

        let retry = Task { try await fixture.server.openDocument(editor.document) }
        var started = fixture.gate.started.makeAsyncIterator()
        _ = await started.next()
        editor.insert("a", at: 0)
        fixture.gate.release()
        try await retry.value
        await editor.coordinator.flushPendingChanges()

        let replay = DocumentSyncReplay(fixture.scripted.notifications)
        #expect(replay.text == editor.text)
        #expect(replay.versions == [0, 0, 1])
    }
}
