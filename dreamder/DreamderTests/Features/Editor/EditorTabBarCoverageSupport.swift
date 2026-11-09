import Foundation
import JSONRPC
import LanguageClient
import LanguageServerProtocol
@testable import Dreamder

final class TabBarCoverageSymbolConnection: ServerConnection, Sendable {
    let eventSequence: EventSequence
    private let documentSymbolPayload: Data

    init(documentSymbolPayload: Data) {
        let (sequence, _) = EventSequence.makeStream()
        self.eventSequence = sequence
        self.documentSymbolPayload = documentSymbolPayload
    }

    func sendNotification(_ notif: ClientNotification) async throws {}

    func sendRequest<Response: Decodable & Sendable>(_ request: ClientRequest) async throws -> Response {
        let payload: Data
        switch request {
        case .initialize:
            payload = try JSONEncoder().encode(InitializationResponse(capabilities: .init(), serverInfo: nil))
        case .documentSymbol:
            payload = documentSymbolPayload
        default:
            throw CancellationError()
        }
        return try JSONDecoder().decode(Response.self, from: payload)
    }
}

@MainActor
enum TabBarCoverageLanguageServer {
    typealias Server = LSPService.LanguageServerType

    static let nullSymbols = Data("null".utf8)

    static func symbols(_ symbols: [DocumentSymbol]) throws -> Data {
        try JSONEncoder().encode(symbols)
    }

    static func install(
        symbolPayload: Data,
        tracking document: CodeFileDocument,
        in service: LSPService
    ) async throws {
        let server = Server(
            languageId: .swift,
            binary: .init(execPath: "", args: [], env: nil),
            lspInstance: InitializingServer(
                server: TabBarCoverageSymbolConnection(documentSymbolPayload: symbolPayload),
                initializeParamsProvider: Server.getInitParams(workspacePath: "/")
            ),
            lspPid: -1,
            serverCapabilities: ServerCapabilities(),
            rootPath: URL(fileURLWithPath: "/"),
            logContainer: LanguageServerLogContainer(languageID: "swift")
        )
        _ = try await server.lspInstance.initializeIfNeeded()
        server.openFiles.addDocument(document, for: server)
        service.languageClients[LSPService.ClientKey(.swift, "/tab-bar-coverage/\(UUID().uuidString)")] = server
    }

    static func makeDocument(at url: URL, contents: String, typeIdentifier: String) throws -> CodeFileDocument {
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return try CodeFileDocument(for: url, withContentsOf: url, ofType: typeIdentifier)
    }

    static func range(_ startLine: Int, _ endLine: Int) -> LSPRange {
        LSPRange(start: Position(line: startLine, character: 0), end: Position(line: endLine, character: 0))
    }

    static func outerInnerSymbols() -> [DocumentSymbol] {
        [
            DocumentSymbol(
                name: "ServerOuter",
                detail: nil,
                kind: .struct,
                range: range(0, 4),
                selectionRange: range(0, 0),
                children: [
                    DocumentSymbol(
                        name: "serverInner",
                        detail: nil,
                        kind: .method,
                        range: range(2, 3),
                        selectionRange: range(2, 2),
                        children: nil
                    )
                ]
            )
        ]
    }
}
