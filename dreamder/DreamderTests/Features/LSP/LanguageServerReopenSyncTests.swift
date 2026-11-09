import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct LanguageServerReopenSyncTests {
    @Test(arguments: DocumentSyncMode.allCases)
    func editsTypedJustBeforeAReopenAreNotSentAgainToTheNewServer(mode: DocumentSyncMode) async throws {
        let editor = SyncEditorHarness()
        let first = try await SyncTestServer.make(capabilities: mode.capabilities)
        try await first.server.openDocument(editor.document)
        editor.insert("X", at: 0)
        #expect(editor.coordinator.hasPendingChanges)

        let second = try await SyncTestServer.make(capabilities: mode.capabilities)
        try await second.server.openDocument(editor.document)
        await editor.coordinator.flushPendingChanges()

        let replay = DocumentSyncReplay(second.connection.notifications)
        #expect(editor.text == "Xhello\nworld")
        #expect(replay.text == editor.text)
        #expect(second.didOpens.count == 1)
        #expect(second.didChanges.isEmpty)
        #expect(second.version() == 0)
        #expect(editor.coordinator.hasPendingChanges == false)
        #expect(first.didChanges.isEmpty)
    }

    @Test(arguments: DocumentSyncMode.allCases)
    func aReopenDropsPendingEditsButKeepsSyncingLaterOnes(mode: DocumentSyncMode) async throws {
        let editor = SyncEditorHarness()
        let first = try await SyncTestServer.make(capabilities: mode.capabilities)
        try await first.server.openDocument(editor.document)
        editor.insert("X", at: 0)
        await editor.coordinator.flushPendingChanges()
        editor.insert("Y", at: 1)

        let second = try await SyncTestServer.make(capabilities: mode.capabilities)
        try await second.server.openDocument(editor.document)
        editor.insert("Z", at: 2)
        await editor.coordinator.flushPendingChanges()

        let replay = DocumentSyncReplay(second.connection.notifications)
        #expect(editor.text == "XYZhello\nworld")
        #expect(replay.text == editor.text)
        #expect(replay.versions == [0, 1])
        #expect(second.didChanges.count == 1)
        #expect(second.version() == 1)
        #expect(DocumentSyncReplay(first.connection.notifications).versions == [0, 1])
    }

    @Test
    func theReopenedServerTracksTheDocumentAgainFromVersionZero() async throws {
        let editor = SyncEditorHarness()
        let first = try await SyncTestServer.make()
        try await first.server.openDocument(editor.document)
        editor.insert("a", at: 0)
        await editor.coordinator.flushPendingChanges()
        editor.insert("b", at: 0)
        await editor.coordinator.flushPendingChanges()
        #expect(first.version() == 2)

        let second = try await SyncTestServer.make()
        try await second.server.openDocument(editor.document)
        editor.insert("c", at: 0)
        await editor.coordinator.flushPendingChanges()

        let replay = DocumentSyncReplay(second.connection.notifications)
        #expect(replay.versions == [0, 1])
        #expect(replay.text == editor.text)
        #expect(editor.coordinator.languageServer === second.server)
        #expect(editor.coordinator.documentURI == syncTestDocumentURI)
    }
}
