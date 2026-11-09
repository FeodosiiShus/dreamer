import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct LanguageServerRequestCacheTests {
    private let uri = syncTestDocumentURI
    private let origin = Position(line: 0, character: 0)
    private let elsewhere = Position(line: 1, character: 4)

    private func hoverJSON(_ value: String) -> String {
        #"{"contents":{"kind":"plaintext","value":"\#(value)"}}"#
    }

    private func completionJSON(_ label: String) -> String {
        #"{"isIncomplete":false,"items":[{"label":"\#(label)"}]}"#
    }

    private func edit(_ document: SyncTestDocument) {
        document.languageServerObjects.textCoordinator.recordEdit(
            uri: uri,
            range: SyncTestServer.range(0, 0, 0),
            string: "e"
        )
    }

    @Test
    func definitionAtTwoPositionsRequestsTwiceAndTheSamePositionOnce() async throws {
        let harness = try await SyncTestServer.make()
        _ = try await harness.open()
        let target = try SyncTestServer.location(uri: "file:///tmp/sync/target.swift", line: 3)
        try harness.connection.script(.textDocumentDefinition, target)

        let first = try await harness.server.requestGoToDefinition(for: uri, position: origin)
        let second = try await harness.server.requestGoToDefinition(for: uri, position: elsewhere)
        #expect(harness.connection.requestCount(.textDocumentDefinition) == 2)

        let repeated = try await harness.server.requestGoToDefinition(for: uri, position: origin)
        let repeatedElsewhere = try await harness.server.requestGoToDefinition(for: uri, position: elsewhere)

        #expect(harness.connection.requestCount(.textDocumentDefinition) == 2)
        #expect(first != nil)
        #expect(repeated == first)
        #expect(repeatedElsewhere == second)
    }

    @Test
    func definitionIsRequestedAgainAfterAnEditAndReturnsTheFreshAnswer() async throws {
        let harness = try await SyncTestServer.make()
        let document = try await harness.open(batchInterval: .seconds(60))
        let stale = try SyncTestServer.location(uri: "file:///tmp/sync/old.swift", line: 1)
        let fresh = try SyncTestServer.location(uri: "file:///tmp/sync/new.swift", line: 2)
        try harness.connection.script(.textDocumentDefinition, stale)

        let before = try await harness.server.requestGoToDefinition(for: uri, position: origin)
        try harness.connection.script(.textDocumentDefinition, fresh)
        let cached = try await harness.server.requestGoToDefinition(for: uri, position: origin)
        #expect(cached == before)
        #expect(harness.connection.requestCount(.textDocumentDefinition) == 1)

        edit(document)
        let after = try await harness.server.requestGoToDefinition(for: uri, position: origin)

        #expect(harness.connection.requestCount(.textDocumentDefinition) == 2)
        #expect(after != before)
        #expect(harness.didChanges.count == 1)
    }

    @Test
    func aChangedDocumentVersionIsPartOfTheCacheKey() async throws {
        let harness = try await SyncTestServer.make()
        _ = try await harness.open()
        try harness.connection.script(.textDocumentDefinition, SyncTestServer.location(uri: uri, line: 0))

        _ = try await harness.server.requestGoToDefinition(for: uri, position: origin)
        _ = harness.server.openFiles.incrementVersion(for: uri)
        _ = try await harness.server.requestGoToDefinition(for: uri, position: origin)

        #expect(harness.connection.requestCount(.textDocumentDefinition) == 2)
    }

    @Test
    func requestsForUnopenedDocumentsAreStillCachedWithoutAVersion() async throws {
        let harness = try await SyncTestServer.make()
        let unopened = "file:///tmp/sync/unopened.swift"
        try harness.connection.script(.textDocumentDefinition, SyncTestServer.location(uri: unopened, line: 0))

        _ = try await harness.server.requestGoToDefinition(for: unopened, position: origin)
        _ = try await harness.server.requestGoToDefinition(for: unopened, position: origin)

        #expect(harness.connection.requestCount(.textDocumentDefinition) == 1)
    }

    @Test
    func definitionsOfDifferentDocumentsDoNotShareEntries() async throws {
        let harness = try await SyncTestServer.make()
        let other = "file:///tmp/sync/other.swift"
        _ = try await harness.open()
        _ = try await harness.open(uri: other)

        _ = try await harness.server.requestGoToDefinition(for: uri, position: origin)
        _ = try await harness.server.requestGoToDefinition(for: other, position: origin)

        #expect(harness.connection.requestCount(.textDocumentDefinition) == 2)
    }

    @Test
    func hoverIsCachedPerPositionAndInvalidatedByDocumentChanges() async throws {
        let harness = try await SyncTestServer.make()
        _ = try await harness.open()
        try harness.connection.script(.textDocumentHover, SyncTestServer.decode(Hover.self, hoverJSON("docs")))

        let first = try await harness.server.requestHover(for: uri, origin)
        let repeated = try await harness.server.requestHover(for: uri, origin)
        _ = try await harness.server.requestHover(for: uri, elsewhere)

        #expect(harness.connection.requestCount(.textDocumentHover) == 2)
        #expect(first != nil)
        #expect(repeated != nil)

        try await harness.server.documentChanged(uri: uri, changes: [])
        _ = try await harness.server.requestHover(for: uri, origin)

        #expect(harness.connection.requestCount(.textDocumentHover) == 3)
    }

    @Test
    func hoverFlushesPendingEditsBeforeAskingTheServer() async throws {
        let harness = try await SyncTestServer.make()
        let document = try await harness.open(batchInterval: .seconds(60))
        edit(document)

        _ = try await harness.server.requestHover(for: uri, origin)

        let log = harness.connection.log
        #expect(log.suffix(2) == ["textDocument/didChange", "textDocument/hover"])
    }

    @Test
    func referencesAreCachedPerPositionAndDeclarationFlag() async throws {
        let harness = try await SyncTestServer.make()
        _ = try await harness.open()
        let locations = [try SyncTestServer.location(uri: "file:///tmp/sync/usage.swift", line: 0)]
        try harness.connection.script(.textDocumentReferences, locations)

        let withoutDeclaration = try await harness.server.requestFindReferences(for: uri, origin)
        let explicitlyWithout = try await harness.server.requestFindReferences(for: uri, origin, false)
        #expect(harness.connection.requestCount(.textDocumentReferences) == 1)
        #expect(withoutDeclaration == locations)
        #expect(explicitlyWithout == locations)

        _ = try await harness.server.requestFindReferences(for: uri, origin, true)
        #expect(harness.connection.requestCount(.textDocumentReferences) == 2)

        _ = try await harness.server.requestFindReferences(for: uri, origin, true)
        _ = try await harness.server.requestFindReferences(for: uri, elsewhere, true)
        #expect(harness.connection.requestCount(.textDocumentReferences) == 3)
    }

    @Test
    func referencesAreRequestedAgainAfterAnEdit() async throws {
        let harness = try await SyncTestServer.make()
        let document = try await harness.open(batchInterval: .seconds(60))

        _ = try await harness.server.requestFindReferences(for: uri, origin)
        edit(document)
        _ = try await harness.server.requestFindReferences(for: uri, origin)

        #expect(harness.connection.requestCount(.textDocumentReferences) == 2)
    }

    @Test
    func completionIsCachedPerPositionAndInvalidatedByEdits() async throws {
        let harness = try await SyncTestServer.make()
        let document = try await harness.open(batchInterval: .seconds(60))
        try harness.connection.script(
            .textDocumentCompletion,
            SyncTestServer.decode(CompletionList.self, completionJSON("alpha"))
        )

        let first = try await harness.server.requestCompletion(for: uri, position: origin)
        let repeated = try await harness.server.requestCompletion(for: uri, position: origin)
        _ = try await harness.server.requestCompletion(for: uri, position: elsewhere)

        #expect(harness.connection.requestCount(.textDocumentCompletion) == 2)
        #expect(first != nil)
        #expect(repeated != nil)

        edit(document)
        _ = try await harness.server.requestCompletion(for: uri, position: origin)

        #expect(harness.connection.requestCount(.textDocumentCompletion) == 3)
    }

    @Test
    func completionWithATriggerCharacterBypassesTheCacheInBothDirections() async throws {
        let harness = try await SyncTestServer.make()
        _ = try await harness.open()

        _ = try await harness.server.requestCompletion(for: uri, position: origin, triggerCharacter: ".")
        _ = try await harness.server.requestCompletion(for: uri, position: origin, triggerCharacter: ".")
        #expect(harness.connection.requestCount(.textDocumentCompletion) == 2)

        _ = try await harness.server.requestCompletion(for: uri, position: origin)
        _ = try await harness.server.requestCompletion(for: uri, position: origin)
        #expect(harness.connection.requestCount(.textDocumentCompletion) == 3)

        _ = try await harness.server.requestCompletion(for: uri, position: origin, triggerCharacter: ".")
        #expect(harness.connection.requestCount(.textDocumentCompletion) == 4)
    }

    @Test
    func failedRequestsThrowAndAreNotCached() async throws {
        let capabilities = ScriptedServerConnection.incrementalCapabilities()
        let scripted = ScriptedServerConnection(capabilities: capabilities)
        let failing = FaultInjectingConnection(
            inner: scripted,
            failingRequests: [
                .textDocumentDefinition,
                .textDocumentHover,
                .textDocumentReferences,
                .textDocumentCompletion
            ]
        )
        let server = try await SyncTestServer.makeServer(connection: failing, capabilities: capabilities)

        await #expect(throws: (any Error).self) { _ = try await server.requestGoToDefinition(for: uri, position: origin) }
        await #expect(throws: (any Error).self) { _ = try await server.requestHover(for: uri, origin) }
        await #expect(throws: (any Error).self) { _ = try await server.requestFindReferences(for: uri, origin) }
        await #expect(throws: (any Error).self) { _ = try await server.requestCompletion(for: uri, position: origin) }
        await #expect(throws: (any Error).self) { _ = try await server.requestGoToDefinition(for: uri, position: origin) }
    }
}
