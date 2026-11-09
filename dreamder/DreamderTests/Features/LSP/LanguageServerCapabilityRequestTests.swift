import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct LanguageServerCapabilityRequestTests {
    private let uri = syncTestDocumentURI
    private let origin = Position(line: 0, character: 0)
    private let elsewhere = Position(line: 2, character: 3)
    private let formatOptions = FormattingOptions(tabSize: 4, insertSpaces: true)

    private func failingServer(
        _ requests: Set<ClientRequest.Method>,
        capabilities: ServerCapabilities = ScriptedServerConnection.incrementalCapabilities()
    ) async throws -> SyncTestServer.Server {
        let failing = FaultInjectingConnection(
            inner: ScriptedServerConnection(capabilities: capabilities),
            failingRequests: requests
        )
        return try await SyncTestServer.makeServer(connection: failing, capabilities: capabilities)
    }

    private func edit(_ text: String) -> TextEdit {
        TextEdit(range: SyncTestServer.range(0, 0, 1), newText: text)
    }

    @Test
    func formattingRequestsReturnTheServerEdits() async throws {
        let harness = try await SyncTestServer.make()
        try harness.connection.script(.textDocumentFormatting, [edit("whole")])
        try harness.connection.script(.textDocumentRangeFormatting, [edit("range")])
        try harness.connection.script(.textDocumentOnTypeFormatting, [edit("typed")])

        let whole = try await harness.server.requestFormatting(for: uri, withFormat: formatOptions)
        let range = try await harness.server.requestRangeFormatting(
            for: uri,
            SyncTestServer.range(1, 0, 4),
            withFormat: formatOptions
        )
        let typed = try await harness.server.requestOnTypeFormatting(
            for: uri,
            elsewhere,
            character: "}",
            withFormat: formatOptions
        )

        #expect(whole == [edit("whole")])
        #expect(range == [edit("range")])
        #expect(typed == [edit("typed")])
    }

    @Test
    func formattingRequestsSurfaceServerFailures() async throws {
        let server = try await failingServer(
            [.textDocumentFormatting, .textDocumentRangeFormatting, .textDocumentOnTypeFormatting]
        )

        await #expect(throws: (any Error).self) {
            try await server.requestFormatting(for: uri, withFormat: formatOptions)
        }
        await #expect(throws: (any Error).self) {
            try await server.requestRangeFormatting(for: uri, SyncTestServer.range(0, 0, 1), withFormat: formatOptions)
        }
        await #expect(throws: (any Error).self) {
            try await server.requestOnTypeFormatting(for: uri, origin, character: ";", withFormat: formatOptions)
        }
    }

    @Test
    func pullDiagnosticsCarryThePreviousResultId() async throws {
        var capabilities = ScriptedServerConnection.incrementalCapabilities()
        capabilities.diagnosticProvider = .optionA(
            DiagnosticOptions(identifier: nil, interFileDependencies: false, workspaceDiagnostics: false)
        )
        let harness = try await SyncTestServer.make(capabilities: capabilities)
        try harness.connection.script(.textDocumentDiagnostic, DocumentDiagnosticReport(kind: .unchanged))

        let report = try await harness.server.requestPullDiagnostics(document: uri, previousResultId: "r7")

        #expect(report.kind == .unchanged)
        let params = harness.connection.requests.compactMap { request -> DocumentDiagnosticParams? in
            guard case let .diagnostics(params, _) = request else { return nil }
            return params
        }
        #expect(params.map(\.previousResultId) == ["r7"])
        #expect(params.map(\.textDocument.uri) == [uri])
    }

    @Test
    func diagnosticRequestsSurfaceServerFailures() async throws {
        let server = try await failingServer([.textDocumentDiagnostic, .custom])

        await #expect(throws: (any Error).self) {
            try await server.requestPullDiagnostics(document: uri)
        }
        await #expect(throws: (any Error).self) {
            try await server.requestWorkspaceDiagnostics(
                WorkspaceDiagnosticParams(identifier: nil, previousResultIds: [])
            )
        }
    }

    @Test
    func aMalformedWorkspaceDiagnosticsReplyThrows() async throws {
        let harness = try await SyncTestServer.make()

        await #expect(throws: (any Error).self) {
            try await harness.server.requestWorkspaceDiagnostics(
                WorkspaceDiagnosticParams(identifier: nil, previousResultIds: [])
            )
        }
        #expect(harness.connection.requestCount(.custom) == 1)
    }

    @Test
    func codeActionProvidersWithoutAResolveFlagDoNotResolveEdits() async throws {
        var capabilities = ScriptedServerConnection.incrementalCapabilities()
        var options = CodeActionOptions(workDoneProgress: nil, codeActionKinds: nil, resolveProvider: false)
        options.resolveProvider = nil
        capabilities.codeActionProvider = .optionB(options)
        let harness = try await SyncTestServer.make(capabilities: capabilities)

        #expect(harness.server.supportsCodeActions)
        #expect(!harness.server.resolvesCodeActionEdits)
    }

    @Test
    func inlayHintsAreRequestedForTheGivenRange() async throws {
        let harness = try await SyncTestServer.make()
        let hint = InlayHint(position: Position(line: 1, character: 4), label: .optionA(": Int"), kind: .type)
        try harness.connection.script(.textDocumentInlayHint, [hint])

        let hints = try await harness.server.requestInlayHint(for: uri, SyncTestServer.range(0, 0, 5))

        #expect(hints == [hint])
        let params = harness.connection.requests.compactMap { request -> InlayHintParams? in
            guard case let .inlayHint(params, _) = request else { return nil }
            return params
        }
        #expect(params.map(\.range) == [SyncTestServer.range(0, 0, 5)])
        #expect(params.map(\.textDocument.uri) == [uri])
    }

    @Test
    func inlayHintRequestsSurfaceServerFailures() async throws {
        let server = try await failingServer([.textDocumentInlayHint])

        await #expect(throws: (any Error).self) {
            try await server.requestInlayHint(for: uri, SyncTestServer.range(0, 0, 5))
        }
    }

    @Test
    func declarationIsCachedPerPositionAndRequestedAgainAfterAVersionChange() async throws {
        let harness = try await SyncTestServer.make()
        _ = try await harness.open()
        let target = try SyncTestServer.location(uri: "file:///tmp/sync/target.swift", line: 3)
        try harness.connection.script(.textDocumentDeclaration, target)

        let first = try await harness.server.requestGoToDeclaration(for: uri, position: origin)
        let repeated = try await harness.server.requestGoToDeclaration(for: uri, position: origin)
        #expect(harness.connection.requestCount(.textDocumentDeclaration) == 1)
        #expect(first != nil)
        #expect(repeated == first)

        _ = try await harness.server.requestGoToDeclaration(for: uri, position: elsewhere)
        #expect(harness.connection.requestCount(.textDocumentDeclaration) == 2)

        _ = harness.server.openFiles.incrementVersion(for: uri)
        _ = try await harness.server.requestGoToDeclaration(for: uri, position: origin)
        #expect(harness.connection.requestCount(.textDocumentDeclaration) == 3)
    }

    @Test
    func failedDeclarationRequestsThrowAndAreNotCached() async throws {
        let scripted = ScriptedServerConnection()
        let capabilities = ScriptedServerConnection.incrementalCapabilities()
        let failing = FaultInjectingConnection(inner: scripted, failingRequests: [.textDocumentDeclaration])
        let server = try await SyncTestServer.makeServer(connection: failing, capabilities: capabilities)

        await #expect(throws: (any Error).self) {
            try await server.requestGoToDeclaration(for: uri, position: origin)
        }
        await #expect(throws: (any Error).self) {
            try await server.requestGoToDeclaration(for: uri, position: origin)
        }
        #expect(scripted.requestCount(.textDocumentDeclaration) == 0)
    }
}
