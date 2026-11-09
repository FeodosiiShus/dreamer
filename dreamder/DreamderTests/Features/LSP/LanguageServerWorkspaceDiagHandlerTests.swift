import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct LanguageServerWorkspaceDiagHandlerTests {
    @Test
    func workspaceDiagnosticsRequestsCarryAHandlerThatIgnoresResponses() async throws {
        let harness = try await SyncTestServer.make()
        try harness.connection.script(.custom, WorkspaceDiagnosticReport(items: []))

        let report = try await harness.server.requestWorkspaceDiagnostics(
            WorkspaceDiagnosticParams(identifier: nil, previousResultIds: [])
        )

        #expect(report.items.isEmpty)
        let handlers = harness.connection.requests.compactMap { request -> ClientRequest.Handler<LSPAny>? in
            guard case let .custom(method, _, handler) = request else { return nil }
            return method == WorkspaceDiagnosticsSupport.requestMethod ? handler : nil
        }
        let handler = try #require(handlers.first)
        await handler(.success(.null))
        #expect(handlers.count == 1)
    }
}
