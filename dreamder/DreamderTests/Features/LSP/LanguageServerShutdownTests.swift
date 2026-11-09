import Foundation
import JSONRPC
import LanguageClient
import LanguageServerProtocol
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct LanguageServerShutdownTests {
    private func gatedServer(
        gate: InitializationGatedConnection?,
        connection: ScriptedServerConnection
    ) async throws -> SyncTestServer.Server {
        let capabilities = ScriptedServerConnection.incrementalCapabilities()
        let server = SyncTestServer.Server(
            languageId: .swift,
            binary: LanguageServerBinary(execPath: "", args: [], env: nil),
            lspInstance: InitializingServer(
                server: connection,
                initializeParamsProvider: SyncTestServer.Server.getInitParams(workspacePath: "/")
            ),
            lspPid: -1,
            serverCapabilities: capabilities,
            rootPath: URL(fileURLWithPath: "/"),
            logContainer: LanguageServerLogContainer(languageID: "swift"),
            connectionGate: gate
        )
        _ = try await server.lspInstance.initializeIfNeeded()
        return server
    }

    @Test
    func shutdownClosesTheConnectionGateSoLateServerRequestsNeverReachTheClient() async throws {
        let connection = ScriptedServerConnection()
        let source = ScriptedServerConnection()
        let gate = InitializationGatedConnection(source)
        gate.open()
        let server = try await gatedServer(gate: gate, connection: connection)

        try await server.shutdown()
        source.emit(.request(
            id: .numericId(1),
            request: .workspaceConfiguration(ConfigurationParams(items: []), { _ in })
        ))
        source.emit(.notification(.windowLogMessage(LogMessageParams(type: .info, message: "sentinel"))))

        let firstEventAfterShutdown = try await withTimeout(duration: .seconds(30)) { () -> String in
            for await event in gate.eventSequence {
                switch event {
                case .request:
                    return "request"
                case .notification(.windowLogMessage(let params)):
                    return params.message
                default:
                    continue
                }
            }
            return "finished"
        }

        #expect(firstEventAfterShutdown == "sentinel")
        #expect(connection.requestCount(.shutdown) == 1)
    }

    @Test
    func shutdownWithoutAGateStillShutsTheServerDown() async throws {
        let connection = ScriptedServerConnection()
        let server = try await gatedServer(gate: nil, connection: connection)

        try await server.shutdown()

        #expect(connection.requestCount(.shutdown) == 1)
        #expect(connection.notificationCount(.exit) == 1)
        #expect(server.workDoneProgress.isShutDown)
    }
}
