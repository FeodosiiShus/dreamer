import Foundation
import JSONRPC
import LanguageClient
import LanguageServerProtocol
@testable import Dreamder

enum StructureFakeServerError: Error {
    case rejected
}

final class StructureFakeServerConnection: ServerConnection, Sendable {
    let eventSequence: EventSequence
    private let reply: Data?
    private let isGated: Bool
    private let gate: AsyncStream<Void>
    private let gateContinuation: AsyncStream<Void>.Continuation

    init(reply: Data?, isGated: Bool) {
        let (sequence, _) = EventSequence.makeStream()
        let (gate, continuation) = AsyncStream<Void>.makeStream()
        self.eventSequence = sequence
        self.reply = reply
        self.isGated = isGated
        self.gate = gate
        self.gateContinuation = continuation
    }

    static func encode(_ response: DocumentSymbolResponse) throws -> Data {
        try JSONEncoder().encode(response)
    }

    func release() {
        gateContinuation.yield()
    }

    func sendNotification(_ notif: ClientNotification) async throws {}

    func sendRequest<Response: Decodable & Sendable>(_ request: ClientRequest) async throws -> Response {
        switch request {
        case .initialize:
            let data = try JSONEncoder().encode(InitializationResponse(capabilities: .init(), serverInfo: nil))
            return try JSONDecoder().decode(Response.self, from: data)
        case .documentSymbol:
            if isGated {
                var iterator = gate.makeAsyncIterator()
                _ = await iterator.next()
            }
            guard let reply else { throw StructureFakeServerError.rejected }
            return try JSONDecoder().decode(Response.self, from: reply)
        default:
            throw StructureFakeServerError.rejected
        }
    }
}

@MainActor
final class StructureLSPHarness {
    typealias ServerType = LanguageServer<CodeFileDocument>

    let service = LSPService()
    let server: ServerType
    let connection: StructureFakeServerConnection

    private init(server: ServerType, connection: StructureFakeServerConnection, root: URL) {
        self.server = server
        self.connection = connection
        service.languageClients[.init(.swift, root.path() + "/")] = server
    }

    static func make(root: URL, reply: Data?, isGated: Bool = false) async throws -> StructureLSPHarness {
        let connection = StructureFakeServerConnection(reply: reply, isGated: isGated)
        var capabilities = ServerCapabilities()
        capabilities.textDocumentSync = .optionA(
            TextDocumentSyncOptions(
                openClose: true,
                change: .incremental,
                willSave: true,
                willSaveWaitUntil: false,
                save: nil
            )
        )
        let server = ServerType(
            languageId: .swift,
            binary: .init(execPath: "", args: [], env: nil),
            lspInstance: InitializingServer(
                server: connection,
                initializeParamsProvider: ServerType.getInitParams(workspacePath: root.path())
            ),
            lspPid: -1,
            serverCapabilities: capabilities,
            rootPath: root,
            logContainer: LanguageServerLogContainer(languageID: "swift")
        )
        _ = try await server.lspInstance.initializeIfNeeded()
        return StructureLSPHarness(server: server, connection: connection, root: root)
    }

    func attach(_ document: CodeFileDocument) {
        server.openFiles.addDocument(document, for: server)
    }
}
