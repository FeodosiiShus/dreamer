import Foundation
import LanguageClient
import LanguageServerProtocol
import Testing
@testable import Dreamder

@MainActor
enum FoldingTestServer {
    typealias Server = LanguageServer<CodeFileDocument>
    typealias Provider = ThreeTypeOption<Bool, FoldingRangeOptions, FoldingRangeRegistrationOptions>

    static let sourceText = "import A\nimport B\n\n/// doc\n/// doc\nfunc f() {\n    body\n}\n"

    static let scriptedRanges = [
        FoldingRange(startLine: 0, endLine: 1, kind: .imports),
        FoldingRange(startLine: 3, endLine: 4, kind: .comment),
        FoldingRange(startLine: 5, endLine: 6)
    ]

    static func capabilities(provider: Provider?) -> ServerCapabilities {
        var capabilities = ScriptedServerConnection.incrementalCapabilities()
        capabilities.foldingRangeProvider = provider
        return capabilities
    }

    static func make(
        in directory: URL,
        connection: any ServerConnection & Sendable = ScriptedServerConnection(),
        provider: Provider?
    ) async throws -> Server {
        let server = Server(
            languageId: .swift,
            binary: LanguageServerBinary(execPath: "", args: [], env: nil),
            lspInstance: InitializingServer(
                server: connection,
                initializeParamsProvider: Server.getInitParams(workspacePath: directory.path())
            ),
            lspPid: -1,
            serverCapabilities: capabilities(provider: provider),
            rootPath: directory,
            logContainer: LanguageServerLogContainer(languageID: "swift")
        )
        _ = try await server.lspInstance.initializeIfNeeded()
        return server
    }

    static func openDocument(
        in directory: URL,
        server: Server,
        contents: String = sourceText
    ) async throws -> (document: CodeFileDocument, uri: String) {
        let fixture = try HostedSourceEditorFixture.make(
            in: directory,
            fileName: "Notes.txt",
            typeIdentifier: "public.plain-text",
            contents: contents
        )
        try await server.openDocument(fixture.document)
        let uri = try #require(fixture.document.languageServerURI)
        return (fixture.document, uri)
    }
}

@MainActor
@Suite(.uiGate)
struct FoldingRangeRequestTests {
    private let registration = FoldingRangeRegistrationOptions(
        textDocument: TextDocumentIdentifier(uri: "file:///x"),
        position: Position(line: 0, character: 0)
    )

    @Test
    func supportIsAdvertisedByEveryStaticProviderShape() async throws {
        try await withTempDir { directory in
            let cases: [(FoldingTestServer.Provider?, Bool)] = [
                (nil, false),
                (.optionA(true), true),
                (.optionA(false), false),
                (.optionB(FoldingRangeOptions()), true),
                (.optionC(registration), true)
            ]
            for (provider, expected) in cases {
                let server = try await FoldingTestServer.make(in: directory, provider: provider)
                #expect(server.supportsFoldingRange == expected)
            }
        }
    }

    @Test
    func dynamicRegistrationEnablesSupportOnlyWithoutAStaticProvider() async throws {
        try await withTempDir { directory in
            let method = FoldingTestServer.Server.foldingRangeMethod
            let dynamic = try await FoldingTestServer.make(in: directory, provider: nil)
            let disabled = try await FoldingTestServer.make(in: directory, provider: .optionA(false))
            #expect(method == "textDocument/foldingRange")
            #expect(!dynamic.supportsFoldingRange)

            dynamic.dynamicCapabilities.register([Registration(id: "fold", method: method)])
            disabled.dynamicCapabilities.register([Registration(id: "fold", method: method)])

            #expect(dynamic.supportsFoldingRange)
            #expect(!disabled.supportsFoldingRange)
        }
    }

    @Test
    func rangesAreRequestedOncePerDocumentVersion() async throws {
        try await withTempDir { directory in
            let connection = ScriptedServerConnection()
            try connection.script(.textDocumentFoldingRange, FoldingTestServer.scriptedRanges)
            let server = try await FoldingTestServer.make(in: directory, connection: connection, provider: .optionA(true))
            let opened = try await FoldingTestServer.openDocument(in: directory, server: server)

            let first = try await server.requestFoldingRange(for: opened.uri)
            let second = try await server.requestFoldingRange(for: opened.uri)

            #expect(first == FoldingTestServer.scriptedRanges)
            #expect(second == first)
            #expect(connection.requestCount(.textDocumentFoldingRange) == 1)

            _ = server.openFiles.incrementVersion(for: opened.uri)
            _ = try await server.requestFoldingRange(for: opened.uri)

            #expect(connection.requestCount(.textDocumentFoldingRange) == 2)
        }
    }

    @Test
    func editsInvalidateTheCachedRanges() async throws {
        try await withTempDir { directory in
            let connection = ScriptedServerConnection()
            try connection.script(.textDocumentFoldingRange, FoldingTestServer.scriptedRanges)
            let server = try await FoldingTestServer.make(in: directory, connection: connection, provider: .optionA(true))
            let opened = try await FoldingTestServer.openDocument(in: directory, server: server)

            _ = try await server.requestFoldingRange(for: opened.uri)
            server.lspCache.invalidate(uri: opened.uri)
            _ = try await server.requestFoldingRange(for: opened.uri)

            #expect(connection.requestCount(.textDocumentFoldingRange) == 2)
        }
    }

    @Test
    func emptyAnswersAreNotCached() async throws {
        try await withTempDir { directory in
            let connection = ScriptedServerConnection()
            let server = try await FoldingTestServer.make(in: directory, connection: connection, provider: .optionA(true))
            let opened = try await FoldingTestServer.openDocument(in: directory, server: server)

            let first = try await server.requestFoldingRange(for: opened.uri)
            let second = try await server.requestFoldingRange(for: opened.uri)

            #expect(first == nil)
            #expect(second == nil)
            #expect(connection.requestCount(.textDocumentFoldingRange) == 2)
        }
    }

    @Test
    func failuresAreThrownAndNotCached() async throws {
        try await withTempDir { directory in
            let inner = ScriptedServerConnection()
            let failing = FaultInjectingConnection(inner: inner, failingRequests: [.textDocumentFoldingRange])
            let server = try await FoldingTestServer.make(in: directory, connection: failing, provider: .optionA(true))
            let opened = try await FoldingTestServer.openDocument(in: directory, server: server)

            await #expect(throws: (any Error).self) {
                try await server.requestFoldingRange(for: opened.uri)
            }
            await #expect(throws: (any Error).self) {
                try await server.requestFoldingRange(for: opened.uri)
            }
        }
    }
}

@MainActor
@Suite(.uiGate)
struct FoldRegionLoaderTests {
    private let indentationRegions = [FoldRegion(startLine: 5, endLine: 6, kind: .block)]

    private func load(
        in directory: URL,
        connection: any ServerConnection & Sendable,
        provider: FoldingTestServer.Provider?,
        registersDynamically: Bool = false
    ) async throws -> [FoldRegion] {
        let server = try await FoldingTestServer.make(in: directory, connection: connection, provider: provider)
        if registersDynamically {
            server.dynamicCapabilities.register([
                Registration(id: "fold", method: FoldingTestServer.Server.foldingRangeMethod)
            ])
        }
        let opened = try await FoldingTestServer.openDocument(in: directory, server: server)
        return await FoldRegionLoader.load(
            text: FoldingTestServer.sourceText,
            tabWidth: 4,
            client: server,
            uri: opened.uri
        )
    }

    @Test
    func serverRangesBecomeRegionsWithTheirKinds() async throws {
        try await withTempDir { directory in
            let connection = ScriptedServerConnection()
            try connection.script(.textDocumentFoldingRange, FoldingTestServer.scriptedRanges)

            let regions = try await load(in: directory, connection: connection, provider: .optionA(true))

            #expect(regions == [
                FoldRegion(startLine: 0, endLine: 1, kind: .imports),
                FoldRegion(startLine: 3, endLine: 4, kind: .comment),
                FoldRegion(startLine: 5, endLine: 6, kind: .block)
            ])
            #expect(connection.requestCount(.textDocumentFoldingRange) == 1)
        }
    }

    @Test
    func dynamicallyRegisteredProvidersAreAsked() async throws {
        try await withTempDir { directory in
            let connection = ScriptedServerConnection()
            try connection.script(.textDocumentFoldingRange, FoldingTestServer.scriptedRanges)

            let regions = try await load(in: directory, connection: connection, provider: nil, registersDynamically: true)

            #expect(regions.count == 3)
            #expect(connection.requestCount(.textDocumentFoldingRange) == 1)
        }
    }

    @Test
    func serversWithoutAProviderAreNeverAskedAndIndentationIsUsed() async throws {
        try await withTempDir { directory in
            let connection = ScriptedServerConnection()
            try connection.script(.textDocumentFoldingRange, FoldingTestServer.scriptedRanges)

            let regions = try await load(in: directory, connection: connection, provider: nil)

            #expect(regions == indentationRegions)
            #expect(connection.requestCount(.textDocumentFoldingRange) == 0)
        }
    }

    @Test
    func failedRequestsFallBackToIndentation() async throws {
        try await withTempDir { directory in
            let inner = ScriptedServerConnection()
            let failing = FaultInjectingConnection(inner: inner, failingRequests: [.textDocumentFoldingRange])

            let regions = try await load(in: directory, connection: failing, provider: .optionA(true))

            #expect(regions == indentationRegions)
        }
    }

    @Test
    func emptyAndMissingAnswersFallBackToIndentation() async throws {
        try await withTempDir { directory in
            let empty = ScriptedServerConnection()
            try empty.script(.textDocumentFoldingRange, [FoldingRange]())
            let missing = ScriptedServerConnection()

            let fromEmpty = try await load(in: directory, connection: empty, provider: .optionA(true))
            let fromMissing = try await load(in: directory, connection: missing, provider: .optionA(true))

            #expect(fromEmpty == indentationRegions)
            #expect(fromMissing == indentationRegions)
            #expect(empty.requestCount(.textDocumentFoldingRange) == 1)
            #expect(missing.requestCount(.textDocumentFoldingRange) == 1)
        }
    }

    @Test
    func unusableServerRangesFallBackToIndentation() async throws {
        try await withTempDir { directory in
            let connection = ScriptedServerConnection()
            try connection.script(.textDocumentFoldingRange, [FoldingRange(startLine: 90, endLine: 99)])

            let regions = try await load(in: directory, connection: connection, provider: .optionA(true))

            #expect(regions == indentationRegions)
        }
    }

    @Test
    func missingClientOrURIUseIndentationWithoutRequests() async throws {
        try await withTempDir { directory in
            let connection = ScriptedServerConnection()
            try connection.script(.textDocumentFoldingRange, FoldingTestServer.scriptedRanges)
            let server = try await FoldingTestServer.make(in: directory, connection: connection, provider: .optionA(true))

            let withoutClient = await FoldRegionLoader.load(
                text: FoldingTestServer.sourceText,
                tabWidth: 4,
                client: nil,
                uri: "file:///x"
            )
            let withoutURI = await FoldRegionLoader.load(
                text: FoldingTestServer.sourceText,
                tabWidth: 4,
                client: server,
                uri: nil
            )

            #expect(withoutClient == indentationRegions)
            #expect(withoutURI == indentationRegions)
            #expect(connection.requestCount(.textDocumentFoldingRange) == 0)
        }
    }
}
