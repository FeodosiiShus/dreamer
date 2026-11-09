import AppKit
import CodeEditLanguages
import Foundation
import JSONRPC
import LanguageClient
import LanguageServerProtocol
import Testing
@testable import Dreamder

let syncTestDocumentURI = "file:///tmp/sync/doc.swift"

@MainActor
final class SyncTestDocument: LanguageServerDocument {
    var content: NSTextStorage?
    var languageServerURI: String?
    var languageServerObjects = LanguageServerDocumentObjects<SyncTestDocument>()
    var language: CodeLanguage

    init(uri: String? = syncTestDocumentURI, text: String = "hello world", language: CodeLanguage = .swift) {
        self.content = NSTextStorage(string: text)
        self.languageServerURI = uri
        self.language = language
    }

    func getLanguage() -> CodeLanguage {
        language
    }
}

final class GatedChangeConnection: ServerConnection, Sendable {
    let inner: ScriptedServerConnection
    let started: AsyncStream<Void>
    private let startedContinuation: AsyncStream<Void>.Continuation
    private let releases: AsyncStream<Void>
    private let releaseContinuation: AsyncStream<Void>.Continuation

    init(inner: ScriptedServerConnection) {
        self.inner = inner
        (started, startedContinuation) = AsyncStream<Void>.makeStream()
        (releases, releaseContinuation) = AsyncStream<Void>.makeStream()
    }

    var eventSequence: EventSequence {
        inner.eventSequence
    }

    func release() {
        releaseContinuation.yield()
    }

    func sendNotification(_ notif: ClientNotification) async throws {
        if notif.method == .textDocumentDidChange {
            startedContinuation.yield()
            var iterator = releases.makeAsyncIterator()
            _ = await iterator.next()
        }
        try await inner.sendNotification(notif)
    }

    func sendRequest<Response: Decodable & Sendable>(_ request: ClientRequest) async throws -> Response {
        try await inner.sendRequest(request)
    }
}

enum FaultInjectionError: Error {
    case injected
}

final class FaultInjectingConnection: ServerConnection, Sendable {
    let inner: ScriptedServerConnection
    let failingNotifications: Set<ClientNotification.Method>
    let failingRequests: Set<ClientRequest.Method>

    init(
        inner: ScriptedServerConnection,
        failingNotifications: Set<ClientNotification.Method> = [],
        failingRequests: Set<ClientRequest.Method> = []
    ) {
        self.inner = inner
        self.failingNotifications = failingNotifications
        self.failingRequests = failingRequests
    }

    var eventSequence: EventSequence {
        inner.eventSequence
    }

    func sendNotification(_ notif: ClientNotification) async throws {
        if failingNotifications.contains(notif.method) {
            throw FaultInjectionError.injected
        }
        try await inner.sendNotification(notif)
    }

    func sendRequest<Response: Decodable & Sendable>(_ request: ClientRequest) async throws -> Response {
        if failingRequests.contains(request.method) {
            throw FaultInjectionError.injected
        }
        return try await inner.sendRequest(request)
    }
}

@MainActor
final class SyncTestServer {
    typealias Server = LanguageServer<SyncTestDocument>

    let connection: ScriptedServerConnection
    let server: Server
    private var openedDocuments: [SyncTestDocument] = []

    init(connection: ScriptedServerConnection, server: Server) {
        self.connection = connection
        self.server = server
    }

    static func capabilities(
        sync: TwoTypeOption<TextDocumentSyncOptions, TextDocumentSyncKind>?,
        semanticTokens: Bool = false
    ) -> ServerCapabilities {
        var capabilities = ServerCapabilities()
        capabilities.textDocumentSync = sync
        if semanticTokens {
            capabilities.semanticTokensProvider = .optionA(.init(legend: .init(tokenTypes: [], tokenModifiers: [])))
        }
        return capabilities
    }

    static func makeServer(
        connection: any ServerConnection & Sendable,
        capabilities: ServerCapabilities
    ) async throws -> Server {
        let server = Server(
            languageId: .swift,
            binary: LanguageServerBinary(execPath: "", args: [], env: nil),
            lspInstance: InitializingServer(
                server: connection,
                initializeParamsProvider: Server.getInitParams(workspacePath: "/")
            ),
            lspPid: -1,
            serverCapabilities: capabilities,
            rootPath: URL(fileURLWithPath: "/"),
            logContainer: LanguageServerLogContainer(languageID: "swift")
        )
        _ = try await server.lspInstance.initializeIfNeeded()
        return server
    }

    static func make(
        capabilities: ServerCapabilities = ScriptedServerConnection.incrementalCapabilities()
    ) async throws -> SyncTestServer {
        let connection = ScriptedServerConnection(capabilities: capabilities)
        let server = try await makeServer(connection: connection, capabilities: capabilities)
        return SyncTestServer(connection: connection, server: server)
    }

    static func makeIncremental(semanticTokens: Bool = false) async throws -> SyncTestServer {
        var capabilities = ScriptedServerConnection.incrementalCapabilities()
        if semanticTokens {
            capabilities.semanticTokensProvider = .optionA(.init(legend: .init(tokenTypes: [], tokenModifiers: [])))
        }
        return try await make(capabilities: capabilities)
    }

    static func decode<Value: Decodable>(_ type: Value.Type = Value.self, _ json: String) throws -> Value {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    static func range(_ line: Int, _ start: Int, _ end: Int) -> LSPRange {
        LSPRange(start: Position(line: line, character: start), end: Position(line: line, character: end))
    }

    static func location(uri: String, line: Int) throws -> Location {
        try decode(
            Location.self,
            #"{"uri":"\#(uri)","range":{"start":{"line":\#(line),"character":0},"end":{"line":\#(line),"character":1}}}"#
        )
    }

    func open(
        uri: String = syncTestDocumentURI,
        text: String = "hello world",
        language: CodeLanguage = .swift,
        batchInterval: Duration? = nil
    ) async throws -> SyncTestDocument {
        let document = SyncTestDocument(uri: uri, text: text, language: language)
        if let batchInterval {
            document.languageServerObjects.textCoordinator = LSPContentCoordinator(batchInterval: batchInterval)
        }
        openedDocuments.append(document)
        try await server.openDocument(document)
        return document
    }

    func count(_ rawMethod: String) -> Int {
        connection.log.filter { $0 == rawMethod }.count
    }

    var didChanges: [DidChangeTextDocumentParams] {
        connection.notifications.compactMap { notification in
            if case let .textDocumentDidChange(params) = notification {
                return params
            }
            return nil
        }
    }

    var didOpens: [DidOpenTextDocumentParams] {
        connection.notifications.compactMap { notification in
            if case let .textDocumentDidOpen(params) = notification {
                return params
            }
            return nil
        }
    }

    func version(of uri: String = syncTestDocumentURI) -> Int? {
        server.openFiles.documentVersion(for: uri)
    }
}

@MainActor
@Suite(.uiGate)
struct LanguageServerDocumentSyncTests {
    private typealias Change = LanguageServer<SyncTestDocument>.DocumentChange

    private func change(_ line: Int, _ start: Int, _ end: Int, _ text: String) -> Change {
        LanguageServer<SyncTestDocument>.DocumentChange(
            replacingContentsIn: SyncTestServer.range(line, start, end),
            with: text
        )
    }

    @Test
    func incrementalChangesIncrementVersionsAndCarryRanges() async throws {
        let harness = try await SyncTestServer.make()
        _ = try await harness.open()
        #expect(harness.version() == 0)

        try await harness.server.documentChanged(
            uri: syncTestDocumentURI,
            changes: [change(0, 0, 0, "a"), change(0, 1, 1, "b")]
        )
        try await harness.server.documentChanged(uri: syncTestDocumentURI, changes: [change(0, 2, 2, "c")])

        #expect(harness.version() == 2)
        let changes = harness.didChanges
        #expect(changes.map(\.textDocument.version) == [1, 2])
        #expect(changes[0].contentChanges.map(\.text) == ["a", "b"])
        #expect(changes[0].contentChanges.map(\.range) == [SyncTestServer.range(0, 0, 0), SyncTestServer.range(0, 1, 1)])
        #expect(changes[1].contentChanges.map(\.text) == ["c"])
    }

    @Test
    func fullSyncSendsWholeTextWithPositiveVersions() async throws {
        let options: [TwoTypeOption<TextDocumentSyncOptions, TextDocumentSyncKind>] = [
            .optionA(.init(openClose: true, change: .full)),
            .optionB(.full)
        ]
        for option in options {
            let harness = try await SyncTestServer.make(capabilities: SyncTestServer.capabilities(sync: option))
            let document = try await harness.open(text: "alpha")
            document.content?.replaceCharacters(in: NSRange(location: 5, length: 0), with: " beta")

            try await harness.server.documentChanged(uri: syncTestDocumentURI, changes: [])
            document.content?.replaceCharacters(in: NSRange(location: 0, length: 0), with: ">")
            try await harness.server.documentChanged(uri: syncTestDocumentURI, changes: [])

            let changes = harness.didChanges
            #expect(changes.map(\.textDocument.version) == [1, 2])
            #expect(changes.map { $0.contentChanges.count } == [1, 1])
            #expect(changes[0].contentChanges.first?.range == nil)
            #expect(changes[0].contentChanges.first?.text == "alpha beta")
            #expect(changes[1].contentChanges.first?.text == ">alpha beta")
            #expect(harness.version() == 2)
        }
    }

    @Test
    func fullSyncWithoutDocumentContentSendsNothing() async throws {
        let harness = try await SyncTestServer.make(
            capabilities: SyncTestServer.capabilities(sync: .optionA(.init(openClose: true, change: .full)))
        )
        let document = try await harness.open()
        document.content = nil

        try await harness.server.documentChanged(uri: syncTestDocumentURI, changes: [])

        #expect(harness.didChanges.isEmpty)
        #expect(harness.version() == 0)
    }

    @Test
    func documentChangedOnAnUnopenedURIOnlyInvalidatesTheCache() async throws {
        let harness = try await SyncTestServer.make()
        let uri = "file:///tmp/sync/unopened.swift"
        let key = CacheKey(uri: uri, requestType: "hover")
        harness.server.lspCache.set(key: key, value: ["cached"])

        try await harness.server.documentChanged(uri: uri, changes: [change(0, 0, 0, "x")])

        #expect(harness.server.lspCache.get(key: key, as: [String].self) == nil)
        #expect(harness.didChanges.isEmpty)
    }

    @Test
    func syncKindNoneNeverSendsChanges() async throws {
        let options: [TwoTypeOption<TextDocumentSyncOptions, TextDocumentSyncKind>?] = [
            .optionA(.init(openClose: true, change: TextDocumentSyncKind.none)),
            .optionB(TextDocumentSyncKind.none),
            nil
        ]
        for option in options {
            let harness = try await SyncTestServer.make(capabilities: SyncTestServer.capabilities(sync: option))
            let document = try await harness.open()
            let key = CacheKey(uri: syncTestDocumentURI, requestType: "hover")
            harness.server.lspCache.set(key: key, value: ["cached"])

            try await harness.server.documentChanged(uri: syncTestDocumentURI, changes: [change(0, 0, 0, "x")])
            try await harness.server.reloadDocument(document)

            #expect(harness.didChanges.isEmpty)
            #expect(harness.version() == 0)
            #expect(harness.server.lspCache.get(key: key, as: [String].self) == nil)
        }
    }

    @Test
    func reloadEmitsFullTextDidChangeNotDidOpenForIncrementalServers() async throws {
        let harness = try await SyncTestServer.make()
        let document = try await harness.open(text: "before")
        document.content?.replaceCharacters(in: NSRange(location: 0, length: 6), with: "after reload")

        try await harness.server.reloadDocument(document)
        try await harness.server.reloadDocument(document)

        #expect(harness.didOpens.count == 1)
        let changes = harness.didChanges
        #expect(changes.map(\.textDocument.version) == [1, 2])
        #expect(changes.allSatisfy { $0.contentChanges.count == 1 })
        #expect(changes.allSatisfy { $0.contentChanges.first?.range == nil })
        #expect(changes.allSatisfy { $0.contentChanges.first?.text == "after reload" })
        #expect(harness.version() == 2)
    }

    @Test
    func reloadInvalidatesTheCacheAndDiscardsPendingEdits() async throws {
        let harness = try await SyncTestServer.make()
        let document = try await harness.open(batchInterval: .seconds(60))
        let coordinator = document.languageServerObjects.textCoordinator
        let key = CacheKey(uri: syncTestDocumentURI, requestType: "hover")
        coordinator.recordEdit(uri: syncTestDocumentURI, range: SyncTestServer.range(0, 0, 0), string: "stale")
        harness.server.lspCache.set(key: key, value: ["cached"])

        try await harness.server.reloadDocument(document)
        await coordinator.flushPendingChanges()

        #expect(coordinator.hasPendingChanges == false)
        #expect(harness.server.lspCache.get(key: key, as: [String].self) == nil)
        #expect(harness.didChanges.count == 1)
        #expect(harness.didChanges.first?.contentChanges.first?.text == "hello world")
    }

    @Test
    func reloadIsANoOpForUnopenedDocumentsMissingURIsAndMissingContent() async throws {
        let harness = try await SyncTestServer.make()
        let unopened = SyncTestDocument(uri: "file:///tmp/sync/unopened.swift")
        let withoutURI = SyncTestDocument(uri: nil)
        let opened = try await harness.open()
        opened.content = nil

        try await harness.server.reloadDocument(unopened)
        try await harness.server.reloadDocument(withoutURI)
        try await harness.server.reloadDocument(opened)

        #expect(harness.didChanges.isEmpty)
        #expect(harness.version() == 0)
    }

    @Test
    func closeDocumentInvalidatesTheCacheAndStopsTracking() async throws {
        let harness = try await SyncTestServer.make()
        _ = try await harness.open()
        let key = CacheKey(uri: syncTestDocumentURI, requestType: "hover")
        harness.server.lspCache.set(key: key, value: ["cached"])

        try await harness.server.closeDocument(syncTestDocumentURI)

        #expect(harness.server.lspCache.get(key: key, as: [String].self) == nil)
        #expect(harness.server.openFiles.document(for: syncTestDocumentURI) == nil)
        #expect(harness.connection.notificationCount(.textDocumentDidClose) == 1)
    }

    @Test
    func closingAnUnopenedDocumentSendsNothing() async throws {
        let harness = try await SyncTestServer.make()

        try await harness.server.closeDocument(syncTestDocumentURI)

        #expect(harness.connection.notificationCount(.textDocumentDidClose) == 0)
    }

    @Test
    func serversWithoutOpenCloseSupportIgnoreOpenAndClose() async throws {
        let harness = try await SyncTestServer.make(
            capabilities: SyncTestServer.capabilities(sync: .optionA(.init(openClose: false, change: .full)))
        )
        _ = try await harness.open()
        try await harness.server.closeDocument(syncTestDocumentURI)

        #expect(harness.didOpens.isEmpty)
        #expect(harness.connection.notificationCount(.textDocumentDidClose) == 0)
        #expect(harness.server.openFiles.document(for: syncTestDocumentURI) == nil)
    }

    @Test
    func openingADocumentWithoutContentOrURIDoesNothing() async throws {
        let harness = try await SyncTestServer.make()
        let withoutContent = SyncTestDocument()
        withoutContent.content = nil
        let withoutURI = SyncTestDocument(uri: nil)

        try await harness.server.openDocument(withoutContent)
        try await harness.server.openDocument(withoutURI)

        #expect(harness.didOpens.isEmpty)
    }

    @Test
    func didOpenCarriesTheSpecLanguageIdentifier() async throws {
        let cases: [(language: CodeLanguage, languageId: String)] = [
            (.tsx, "typescriptreact"),
            (.jsx, "javascriptreact"),
            (.bash, "shellscript"),
            (.kotlin, "kotlin"),
            (.toml, "toml"),
            (.swift, "swift"),
            (.default, "plaintext")
        ]
        for testCase in cases {
            let harness = try await SyncTestServer.make()
            _ = try await harness.open(language: testCase.language)

            let item = try #require(harness.didOpens.first?.textDocument)
            #expect(item.languageId == testCase.languageId)
            #expect(item.version == 0)
            #expect(item.uri == syncTestDocumentURI)
            #expect(item.text == "hello world")
        }
    }

    @Test
    func failingConnectionsSurfaceErrorsFromEveryNotificationPath() async throws {
        let capabilities = ScriptedServerConnection.incrementalCapabilities()
        let scripted = ScriptedServerConnection(capabilities: capabilities)
        let failing = FaultInjectingConnection(
            inner: scripted,
            failingNotifications: [.textDocumentDidOpen, .textDocumentDidChange, .textDocumentDidClose]
        )
        let server = try await SyncTestServer.makeServer(connection: failing, capabilities: capabilities)
        let document = SyncTestDocument()

        await #expect(throws: (any Error).self) { try await server.openDocument(document) }

        let workingConnection = ScriptedServerConnection(capabilities: capabilities)
        let workingFailing = FaultInjectingConnection(
            inner: workingConnection,
            failingNotifications: [.textDocumentDidChange, .textDocumentDidClose]
        )
        let openServer = try await SyncTestServer.makeServer(connection: workingFailing, capabilities: capabilities)
        let openDocument = SyncTestDocument()
        try await openServer.openDocument(openDocument)

        await #expect(throws: (any Error).self) {
            try await openServer.documentChanged(uri: syncTestDocumentURI, changes: [])
        }
        await #expect(throws: (any Error).self) { try await openServer.reloadDocument(openDocument) }
        await #expect(throws: (any Error).self) { try await openServer.closeDocument(syncTestDocumentURI) }
    }
}
