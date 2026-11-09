import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

extension ScriptedServerConnection {
    var selectionRangeRequestParams: [SelectionRangeParams] {
        requests.compactMap { request in
            guard case let .selectionRange(params, _) = request else { return nil }
            return params
        }
    }
}

@MainActor
@Suite(.uiGate)
struct SelectionRangeRequestTests {
    private let uri = syncTestDocumentURI
    private let first = Position(line: 0, character: 2)
    private let second = Position(line: 1, character: 3)

    private func chains() -> [SelectionRange] {
        [
            SelectionRange(range: SyncTestServer.range(0, 2, 4), parent: SelectionRange(range: SyncTestServer.range(0, 0, 8), parent: nil)),
            SelectionRange(range: SyncTestServer.range(1, 3, 5), parent: nil)
        ]
    }

    @Test
    func supportComesFromTheStaticOptionOrADynamicRegistration() async throws {
        let harness = try await SyncTestServer.make()
        let server = harness.server

        #expect(!server.supportsSelectionRange)
        server.serverCapabilities.selectionRangeProvider = .optionA(false)
        #expect(!server.supportsSelectionRange)
        server.serverCapabilities.selectionRangeProvider = .optionA(true)
        #expect(server.supportsSelectionRange)
        server.serverCapabilities.selectionRangeProvider = .optionB(SelectionRangeOptions())
        #expect(server.supportsSelectionRange)
        server.serverCapabilities.selectionRangeProvider = .optionC(
            SelectionRangeRegistrationOptions(
                textDocument: TextDocumentIdentifier(uri: uri),
                position: Position(line: 0, character: 0)
            )
        )
        #expect(server.supportsSelectionRange)
        server.serverCapabilities.selectionRangeProvider = nil
        #expect(!server.supportsSelectionRange)
        server.dynamicCapabilities.register([Registration(id: "1", method: "textDocument/selectionRange")])
        #expect(server.supportsSelectionRange)
    }

    @Test
    func oneRequestCarriesEveryPositionAndTheChainsComeBackInOrder() async throws {
        let harness = try await SyncTestServer.make()
        _ = try await harness.open(text: "ab cd ef\nxyz uvw")
        try harness.connection.script(.textDocumentSelectionRange, chains())

        let response = try await harness.server.requestSelectionRange(for: uri, positions: [first, second])

        #expect(harness.connection.requestCount(.textDocumentSelectionRange) == 1)
        #expect(harness.connection.selectionRangeRequestParams.first?.positions == [first, second])
        #expect(harness.connection.selectionRangeRequestParams.first?.textDocument.uri == uri)
        #expect(response?.map(\.range) == [SyncTestServer.range(0, 2, 4), SyncTestServer.range(1, 3, 5)])
        #expect(response?.first?.parent?.range == SyncTestServer.range(0, 0, 8))
    }

    @Test
    func theSamePositionsAreCachedPerDocumentVersion() async throws {
        let harness = try await SyncTestServer.make()
        _ = try await harness.open(text: "ab cd ef\nxyz uvw")
        try harness.connection.script(.textDocumentSelectionRange, chains())

        let initial = try await harness.server.requestSelectionRange(for: uri, positions: [first, second])
        let repeated = try await harness.server.requestSelectionRange(for: uri, positions: [first, second])
        #expect(harness.connection.requestCount(.textDocumentSelectionRange) == 1)
        #expect(repeated == initial)

        _ = try await harness.server.requestSelectionRange(for: uri, positions: [second, first])
        _ = try await harness.server.requestSelectionRange(for: uri, positions: [first])
        #expect(harness.connection.requestCount(.textDocumentSelectionRange) == 3)
    }

    @Test
    func anEditInvalidatesTheCachedChains() async throws {
        let harness = try await SyncTestServer.make()
        let document = try await harness.open(text: "ab cd ef\nxyz uvw", batchInterval: .seconds(60))
        try harness.connection.script(.textDocumentSelectionRange, chains())

        _ = try await harness.server.requestSelectionRange(for: uri, positions: [first])
        document.languageServerObjects.textCoordinator.recordEdit(
            uri: uri,
            range: SyncTestServer.range(0, 0, 0),
            string: "e"
        )
        _ = try await harness.server.requestSelectionRange(for: uri, positions: [first])

        #expect(harness.connection.requestCount(.textDocumentSelectionRange) == 2)
        #expect(harness.didChanges.count == 1)
    }

    @Test
    func failedRequestsThrowAndAreNotCached() async throws {
        let capabilities = ScriptedServerConnection.incrementalCapabilities()
        let scripted = ScriptedServerConnection(capabilities: capabilities)
        let failing = FaultInjectingConnection(inner: scripted, failingRequests: [.textDocumentSelectionRange])
        let server = try await SyncTestServer.makeServer(connection: failing, capabilities: capabilities)

        await #expect(throws: (any Error).self) {
            _ = try await server.requestSelectionRange(for: uri, positions: [first])
        }
        await #expect(throws: (any Error).self) {
            _ = try await server.requestSelectionRange(for: uri, positions: [first])
        }
        #expect(scripted.requestCount(.textDocumentSelectionRange) == 0)
    }
}
