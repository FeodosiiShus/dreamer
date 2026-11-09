import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct LanguageServerPullDiagnosticsTests {
    private func capabilities() -> ServerCapabilities {
        var capabilities = ScriptedServerConnection.incrementalCapabilities()
        capabilities.diagnosticProvider = .optionA(
            DiagnosticOptions(identifier: nil, interFileDependencies: false, workspaceDiagnostics: false)
        )
        return capabilities
    }

    private func diagnostic(_ message: String) -> Diagnostic {
        Diagnostic(range: SyncTestServer.range(0, 0, 3), severity: .warning, source: "test", message: message)
    }

    @Test
    func openingAndChangingADocumentPublishesFullReportsAndKeepsThemOnUnchangedReports() async throws {
        try await withTempDir { dir in
            let workspace = try LSPServiceWorkspace(directory: dir, files: ["a.swift": "let a = 1\n"])
            defer { workspace.close() }
            let uri = workspace.uri("a.swift")
            let fileURL = dir.appending(path: "a.swift")
            let store = workspace.workspace.diagnosticsStore
            let harness = try await SyncTestServer.make(capabilities: capabilities())
            try harness.connection.script(
                .textDocumentDiagnostic,
                DocumentDiagnosticReport(kind: .full, items: [diagnostic("opened")])
            )

            _ = try await harness.open(uri: uri, text: "let a = 1\n")

            #expect(harness.connection.requestCount(.textDocumentDiagnostic) == 1)
            #expect(store.diagnostics(for: fileURL).map(\.message) == ["opened"])

            try harness.connection.script(
                .textDocumentDiagnostic,
                DocumentDiagnosticReport(kind: .full, items: [diagnostic("changed"), diagnostic("second")])
            )
            try await harness.server.documentChanged(uri: uri, changes: [])

            #expect(harness.connection.requestCount(.textDocumentDiagnostic) == 2)
            #expect(store.diagnostics(for: fileURL).map(\.message) == ["changed", "second"])

            try harness.connection.script(.textDocumentDiagnostic, DocumentDiagnosticReport(kind: .unchanged))
            try await harness.server.documentChanged(uri: uri, changes: [])

            #expect(harness.connection.requestCount(.textDocumentDiagnostic) == 3)
            #expect(store.diagnostics(for: fileURL).map(\.message) == ["changed", "second"])
        }
    }

    @Test
    func aFailingPullDoesNotFailOpeningTheDocument() async throws {
        let capabilities = capabilities()
        let scripted = ScriptedServerConnection(capabilities: capabilities)
        let failing = FaultInjectingConnection(inner: scripted, failingRequests: [.textDocumentDiagnostic])
        let server = try await SyncTestServer.makeServer(connection: failing, capabilities: capabilities)
        let harness = SyncTestServer(connection: scripted, server: server)

        _ = try await harness.open()

        #expect(harness.didOpens.count == 1)
        #expect(scripted.requestCount(.textDocumentDiagnostic) == 0)
    }
}
