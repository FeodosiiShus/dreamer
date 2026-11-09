import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct DefinitionRequestCacheTests {
    private let uri = syncTestDocumentURI
    private let origin = Position(line: 0, character: 0)
    private let elsewhere = Position(line: 1, character: 4)
    private let firstURI = "file:///tmp/sync/first.swift"
    private let secondURI = "file:///tmp/sync/second.swift"

    private func edit(_ document: SyncTestDocument) {
        document.languageServerObjects.textCoordinator.recordEdit(
            uri: uri,
            range: SyncTestServer.range(0, 0, 0),
            string: "e"
        )
    }

    @Test
    func implementationAtTwoPositionsRequestsTwiceAndTheSamePositionOnce() async throws {
        let harness = try await SyncTestServer.make()
        _ = try await harness.open()
        try harness.connection.script(.textDocumentImplementation, SyncTestServer.location(uri: firstURI, line: 3))

        let first = try await harness.server.requestImplementation(for: uri, origin)
        let second = try await harness.server.requestImplementation(for: uri, elsewhere)
        #expect(harness.connection.requestCount(.textDocumentImplementation) == 2)

        let repeated = try await harness.server.requestImplementation(for: uri, origin)
        let repeatedElsewhere = try await harness.server.requestImplementation(for: uri, elsewhere)

        #expect(harness.connection.requestCount(.textDocumentImplementation) == 2)
        #expect(first != nil)
        #expect(repeated == first)
        #expect(repeatedElsewhere == second)
    }

    @Test
    func implementationIsRequestedAgainAfterAnEditAndReturnsTheFreshAnswer() async throws {
        let harness = try await SyncTestServer.make()
        let document = try await harness.open(batchInterval: .seconds(60))
        let stale = try SyncTestServer.location(uri: firstURI, line: 1)
        let fresh = try SyncTestServer.location(uri: secondURI, line: 2)
        try harness.connection.script(.textDocumentImplementation, stale)

        let before = try await harness.server.requestImplementation(for: uri, origin)
        try harness.connection.script(.textDocumentImplementation, fresh)
        let cached = try await harness.server.requestImplementation(for: uri, origin)
        #expect(cached == before)
        #expect(harness.connection.requestCount(.textDocumentImplementation) == 1)

        edit(document)
        let after = try await harness.server.requestImplementation(for: uri, origin)

        #expect(harness.connection.requestCount(.textDocumentImplementation) == 2)
        #expect(after != before)
        #expect(harness.didChanges.count == 1)
    }

    @Test
    func implementationCacheKeyIncludesTheDocumentVersionAndTheDocument() async throws {
        let harness = try await SyncTestServer.make()
        let other = "file:///tmp/sync/other.swift"
        _ = try await harness.open()
        _ = try await harness.open(uri: other)
        try harness.connection.script(.textDocumentImplementation, SyncTestServer.location(uri: firstURI, line: 0))

        _ = try await harness.server.requestImplementation(for: uri, origin)
        _ = harness.server.openFiles.incrementVersion(for: uri)
        _ = try await harness.server.requestImplementation(for: uri, origin)
        _ = try await harness.server.requestImplementation(for: other, origin)

        #expect(harness.connection.requestCount(.textDocumentImplementation) == 3)
    }

    @Test
    func typeDefinitionAtTwoPositionsRequestsTwiceAndTheSamePositionOnce() async throws {
        let harness = try await SyncTestServer.make()
        _ = try await harness.open()
        try harness.connection.script(.textDocumentTypeDefinition, SyncTestServer.location(uri: firstURI, line: 3))

        let first = try await harness.server.requestTypeDefinition(for: uri, origin)
        let second = try await harness.server.requestTypeDefinition(for: uri, elsewhere)
        #expect(harness.connection.requestCount(.textDocumentTypeDefinition) == 2)

        let repeated = try await harness.server.requestTypeDefinition(for: uri, origin)
        let repeatedElsewhere = try await harness.server.requestTypeDefinition(for: uri, elsewhere)

        #expect(harness.connection.requestCount(.textDocumentTypeDefinition) == 2)
        #expect(first != nil)
        #expect(repeated == first)
        #expect(repeatedElsewhere == second)
    }

    @Test
    func typeDefinitionIsRequestedAgainAfterAnEditAndReturnsTheFreshAnswer() async throws {
        let harness = try await SyncTestServer.make()
        let document = try await harness.open(batchInterval: .seconds(60))
        let stale = try SyncTestServer.location(uri: firstURI, line: 1)
        let fresh = try SyncTestServer.location(uri: secondURI, line: 2)
        try harness.connection.script(.textDocumentTypeDefinition, stale)

        let before = try await harness.server.requestTypeDefinition(for: uri, origin)
        try harness.connection.script(.textDocumentTypeDefinition, fresh)
        let cached = try await harness.server.requestTypeDefinition(for: uri, origin)
        #expect(cached == before)
        #expect(harness.connection.requestCount(.textDocumentTypeDefinition) == 1)

        edit(document)
        let after = try await harness.server.requestTypeDefinition(for: uri, origin)

        #expect(harness.connection.requestCount(.textDocumentTypeDefinition) == 2)
        #expect(after != before)
        #expect(harness.didChanges.count == 1)
    }

    @Test
    func typeDefinitionCacheKeyIncludesTheDocumentVersionAndTheDocument() async throws {
        let harness = try await SyncTestServer.make()
        let other = "file:///tmp/sync/other.swift"
        _ = try await harness.open()
        _ = try await harness.open(uri: other)
        try harness.connection.script(.textDocumentTypeDefinition, SyncTestServer.location(uri: firstURI, line: 0))

        _ = try await harness.server.requestTypeDefinition(for: uri, origin)
        _ = harness.server.openFiles.incrementVersion(for: uri)
        _ = try await harness.server.requestTypeDefinition(for: uri, origin)
        _ = try await harness.server.requestTypeDefinition(for: other, origin)

        #expect(harness.connection.requestCount(.textDocumentTypeDefinition) == 3)
    }

    @Test
    func failedImplementationAndTypeRequestsThrowAndAreNotCached() async throws {
        let capabilities = ScriptedServerConnection.incrementalCapabilities()
        let scripted = ScriptedServerConnection(capabilities: capabilities)
        let failing = FaultInjectingConnection(
            inner: scripted,
            failingRequests: [.textDocumentImplementation, .textDocumentTypeDefinition]
        )
        let server = try await SyncTestServer.makeServer(connection: failing, capabilities: capabilities)

        await #expect(throws: (any Error).self) { _ = try await server.requestImplementation(for: uri, origin) }
        await #expect(throws: (any Error).self) { _ = try await server.requestImplementation(for: uri, origin) }
        await #expect(throws: (any Error).self) { _ = try await server.requestTypeDefinition(for: uri, origin) }
        await #expect(throws: (any Error).self) { _ = try await server.requestTypeDefinition(for: uri, origin) }
    }

    @Test
    func declarationTargetsPreferTheDefinitionAnswer() async throws {
        let harness = try await SyncTestServer.make()
        _ = try await harness.open()
        try harness.connection.script(.textDocumentDefinition, SyncTestServer.location(uri: firstURI, line: 3))
        try harness.connection.script(.textDocumentDeclaration, SyncTestServer.location(uri: secondURI, line: 9))

        let targets = await harness.server.navigationTargets(for: .declaration, uri: uri, position: origin)

        #expect(targets.map(\.uri) == [firstURI])
        #expect(harness.connection.requestCount(.textDocumentDeclaration) == 0)
    }

    @Test
    func declarationTargetsFallBackToTheDeclarationAnswerWhenTheDefinitionIsEmpty() async throws {
        let harness = try await SyncTestServer.make()
        _ = try await harness.open()
        try harness.connection.script(.textDocumentDeclaration, SyncTestServer.location(uri: secondURI, line: 9))

        let targets = await harness.server.navigationTargets(for: .declaration, uri: uri, position: origin)

        #expect(targets.map(\.uri) == [secondURI])
        #expect(harness.connection.requestCount(.textDocumentDefinition) == 1)
        #expect(harness.connection.requestCount(.textDocumentDeclaration) == 1)
    }

    @Test
    func declarationTargetsFallBackWhenTheDefinitionRequestFails() async throws {
        let capabilities = ScriptedServerConnection.incrementalCapabilities()
        let scripted = ScriptedServerConnection(capabilities: capabilities)
        try scripted.script(.textDocumentDeclaration, SyncTestServer.location(uri: secondURI, line: 2))
        let failing = FaultInjectingConnection(inner: scripted, failingRequests: [.textDocumentDefinition])
        let server = try await SyncTestServer.makeServer(connection: failing, capabilities: capabilities)

        let targets = await server.navigationTargets(for: .declaration, uri: uri, position: origin)

        #expect(targets.map(\.uri) == [secondURI])
    }

    @Test
    func declarationTargetsAreEmptyWhenNothingAnswers() async throws {
        let harness = try await SyncTestServer.make()
        _ = try await harness.open()

        let targets = await harness.server.navigationTargets(for: .declaration, uri: uri, position: origin)

        #expect(targets.isEmpty)
    }

    @Test
    func implementationTargetsAskOnlyForImplementations() async throws {
        let harness = try await SyncTestServer.make()
        _ = try await harness.open()
        try harness.connection.script(
            .textDocumentImplementation,
            [SyncTestServer.location(uri: firstURI, line: 1), SyncTestServer.location(uri: secondURI, line: 2)]
        )

        let targets = await harness.server.navigationTargets(for: .implementation, uri: uri, position: origin)

        #expect(targets.map(\.uri) == [firstURI, secondURI])
        #expect(harness.connection.requestCount(.textDocumentDefinition) == 0)
        #expect(harness.connection.requestCount(.textDocumentImplementation) == 1)
    }

    @Test
    func typeTargetsNeverFallBackToTheDefinition() async throws {
        let harness = try await SyncTestServer.make()
        _ = try await harness.open()
        try harness.connection.script(.textDocumentDefinition, SyncTestServer.location(uri: firstURI, line: 1))

        let empty = await harness.server.navigationTargets(for: .typeDeclaration, uri: uri, position: origin)
        #expect(empty.isEmpty)

        try harness.connection.script(.textDocumentTypeDefinition, SyncTestServer.location(uri: secondURI, line: 2))
        let found = await harness.server.navigationTargets(for: .typeDeclaration, uri: uri, position: elsewhere)

        #expect(found.map(\.uri) == [secondURI])
        #expect(harness.connection.requestCount(.textDocumentDefinition) == 0)
        #expect(harness.connection.requestCount(.textDocumentDeclaration) == 0)
    }

    @Test
    func failingImplementationAndTypeRequestsYieldNoTargets() async throws {
        let capabilities = ScriptedServerConnection.incrementalCapabilities()
        let failing = FaultInjectingConnection(
            inner: ScriptedServerConnection(capabilities: capabilities),
            failingRequests: [.textDocumentImplementation, .textDocumentTypeDefinition]
        )
        let server = try await SyncTestServer.makeServer(connection: failing, capabilities: capabilities)

        let implementations = await server.navigationTargets(for: .implementation, uri: uri, position: origin)
        let types = await server.navigationTargets(for: .typeDeclaration, uri: uri, position: origin)

        #expect(implementations.isEmpty)
        #expect(types.isEmpty)
    }

    @Test
    func locationLinksKeepTheirSelectionRangeAsTheTarget() async throws {
        let harness = try await SyncTestServer.make()
        _ = try await harness.open()
        let link = LocationLink(
            originSelectionRange: nil,
            targetUri: firstURI,
            targetRange: SyncTestServer.range(0, 0, 30),
            targetSelectionRange: SyncTestServer.range(4, 5, 9)
        )
        try harness.connection.script(.textDocumentTypeDefinition, [link])

        let targets = await harness.server.navigationTargets(for: .typeDeclaration, uri: uri, position: origin)

        #expect(targets == [
            LSPDefinitionTarget(
                uri: firstURI,
                range: SyncTestServer.range(0, 0, 30),
                selectionRange: SyncTestServer.range(4, 5, 9)
            )
        ])
    }
}
