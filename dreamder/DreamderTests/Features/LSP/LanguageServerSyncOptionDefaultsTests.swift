import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct LanguageServerSyncOptionDefaultsTests {
    private typealias Change = LanguageServer<SyncTestDocument>.DocumentChange

    private func change(_ text: String) -> Change {
        Change(replacingContentsIn: SyncTestServer.range(0, 0, 0), with: text)
    }

    @Test
    func syncOptionsWithoutAChangeKindNeverSendChanges() async throws {
        let harness = try await SyncTestServer.make(
            capabilities: SyncTestServer.capabilities(sync: .optionA(.init(openClose: true, change: nil)))
        )
        _ = try await harness.open()

        try await harness.server.documentChanged(uri: syncTestDocumentURI, changes: [change("x")])

        #expect(harness.didOpens.count == 1)
        #expect(harness.didChanges.isEmpty)
        #expect(harness.version() == 0)
    }

    @Test
    func syncOptionsWithoutOpenCloseIgnoreOpenAndClose() async throws {
        let harness = try await SyncTestServer.make(
            capabilities: SyncTestServer.capabilities(sync: .optionA(.init(openClose: nil, change: .full)))
        )
        _ = try await harness.open()
        try await harness.server.closeDocument(syncTestDocumentURI)

        #expect(harness.didOpens.isEmpty)
        #expect(harness.connection.notificationCount(.textDocumentDidClose) == 0)
        #expect(harness.server.openFiles.document(for: syncTestDocumentURI) == nil)
    }

    @Test
    func fileMapIgnoresDocumentsWithoutAURIAndReportsVersionZeroForUnknownOnes() async throws {
        let harness = try await SyncTestServer.make()
        let fileMap = LanguageServerFileMap<SyncTestDocument>()

        fileMap.addDocument(SyncTestDocument(uri: nil), for: harness.server)

        #expect(fileMap.uris.isEmpty)
        #expect(fileMap.documents.isEmpty)
        #expect(fileMap.incrementVersion(for: "file:///tmp/sync/unknown.swift") == 0)
        #expect(fileMap.documentVersion(for: "file:///tmp/sync/unknown.swift") == nil)
    }
}
