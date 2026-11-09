import Foundation
import LanguageClient
import LanguageServerProtocol
import Synchronization
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct RenameFileOperationsTests {
    private let oldURI = "file:///tmp/sync/old.ts"
    private let newURI = "file:///tmp/sync/new.ts"

    func filters(_ glob: String, matches: FileOperationPatternKind? = nil) -> FileOperationRegistrationOptions {
        FileOperationRegistrationOptions(filters: [
            FileOperationFilter(
                scheme: "file",
                pattern: FileOperationPattern(glob: glob, matches: matches, options: nil)
            )
        ])
    }

    func capabilities(
        will: FileOperationRegistrationOptions? = nil,
        did: FileOperationRegistrationOptions? = nil
    ) -> ServerCapabilities {
        var capabilities = ScriptedServerConnection.incrementalCapabilities()
        capabilities.workspace = ServerCapabilities.Workspace(
            fileOperations: ServerCapabilities.Workspace.FileOperations(didRename: did, willRename: will)
        )
        return capabilities
    }

    func makeClient(
        root: URL,
        connection: any ServerConnection & Sendable,
        capabilities: ServerCapabilities
    ) async throws -> LSPFileOperations.Client {
        let client = LSPFileOperations.Client(
            languageId: .swift,
            binary: LanguageServerBinary(execPath: "", args: [], env: nil),
            lspInstance: InitializingServer(
                server: connection,
                initializeParamsProvider: LSPFileOperations.Client.getInitParams(workspacePath: root.path())
            ),
            lspPid: -1,
            serverCapabilities: capabilities,
            rootPath: root,
            logContainer: LanguageServerLogContainer(languageID: "swift")
        )
        _ = try await client.lspInstance.initializeIfNeeded()
        return client
    }

    func willRenameParams(_ connection: ScriptedServerConnection) -> [RenameFilesParams] {
        connection.requests.compactMap { request in
            if case let .workspaceWillRenameFiles(params, _) = request {
                return params
            }
            return nil
        }
    }

    func didRenameParams(_ connection: ScriptedServerConnection) -> [RenameFilesParams] {
        connection.notifications.compactMap { notification in
            if case let .workspaceDidRenameFiles(params) = notification {
                return params
            }
            return nil
        }
    }

    func renameEdit(path: String) throws -> WorkspaceEdit {
        let uri = URL(fileURLWithPath: path).lspURI
        let json = #"{"changes":{"\#(uri)":[{"range":{"start":{"line":0,"character":0},"#
            + #""end":{"line":0,"character":3}},"newText":"fixed"}]}}"#
        return try SyncTestServer.decode(WorkspaceEdit.self, json)
    }

    func touch(_ url: URL, text: String = "old\n") throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test
    func theClientRequestsSendTheRenamedFilesAndReturnTheServersEdit() async throws {
        let edit = try renameEdit(path: "/tmp/sync/importer.ts")
        let harness = try await SyncTestServer.make()
        try harness.connection.script(.workspaceWillRenameFiles, edit)
        let files = [FileRename(oldUri: oldURI, newUri: newURI)]

        let response = try await harness.server.requestWillRenameFiles(files)
        try await harness.server.notifyDidRenameFiles(files)

        #expect(response == edit)
        #expect(willRenameParams(harness.connection) == [RenameFilesParams(files: files)])
        #expect(didRenameParams(harness.connection) == [RenameFilesParams(files: files)])
    }

    @Test
    func pendingEditsOfRenamedDocumentsAreFlushedBeforeTheRequestAndTheNotification() async throws {
        let harness = try await SyncTestServer.make()
        let document = try await harness.open(batchInterval: .seconds(60))
        let other = try await harness.open(uri: "file:///tmp/elsewhere/x.swift", batchInterval: .seconds(60))
        other.languageServerObjects.textCoordinator.recordEdit(
            uri: "file:///tmp/elsewhere/x.swift",
            range: SyncTestServer.range(0, 0, 0),
            string: "o"
        )
        document.languageServerObjects.textCoordinator.recordEdit(
            uri: syncTestDocumentURI,
            range: SyncTestServer.range(0, 0, 0),
            string: "e"
        )

        _ = try await harness.server.requestWillRenameFiles([
            FileRename(oldUri: "file:///tmp/sync", newUri: "file:///tmp/moved")
        ])

        #expect(harness.connection.log.suffix(2) == ["textDocument/didChange", "workspace/willRenameFiles"])
        #expect(harness.didChanges.map(\.textDocument.uri) == [syncTestDocumentURI])

        document.languageServerObjects.textCoordinator.recordEdit(
            uri: syncTestDocumentURI,
            range: SyncTestServer.range(0, 0, 0),
            string: "f"
        )
        try await harness.server.notifyDidRenameFiles([
            FileRename(oldUri: syncTestDocumentURI, newUri: "file:///tmp/sync/renamed.swift")
        ])

        #expect(harness.connection.log.suffix(2) == ["textDocument/didChange", "workspace/didRenameFiles"])
    }

    @Test
    func failingRenameFileTrafficIsRethrown() async throws {
        let scripted = ScriptedServerConnection()
        let failing = FaultInjectingConnection(
            inner: scripted,
            failingNotifications: [.workspaceDidRenameFiles],
            failingRequests: [.workspaceWillRenameFiles]
        )
        let server = try await SyncTestServer.makeServer(
            connection: failing,
            capabilities: ScriptedServerConnection.incrementalCapabilities()
        )
        let files = [FileRename(oldUri: oldURI, newUri: newURI)]

        await #expect(throws: FaultInjectionError.self) { _ = try await server.requestWillRenameFiles(files) }
        await #expect(throws: FaultInjectionError.self) { try await server.notifyDidRenameFiles(files) }
    }

    @Test
    func registrationsCombineStaticAndDynamicOptionsPerOperation() async throws {
        let harness = try await SyncTestServer.make(
            capabilities: capabilities(will: filters("**/*.ts"), did: filters("**/*.js"))
        )
        let server = harness.server
        #expect(server.fileRenameRegistrations(.will) == [filters("**/*.ts")])
        #expect(server.fileRenameRegistrations(.did) == [filters("**/*.js")])

        server.dynamicCapabilities.register([
            Registration(
                id: "will",
                method: "workspace/willRenameFiles",
                registerOptions: ["filters": [["pattern": ["glob": "**/*.rs"]]]]
            ),
            Registration(
                id: "did",
                method: "workspace/didRenameFiles",
                registerOptions: ["filters": [["scheme": "file", "pattern": ["glob": "**/*.go", "matches": "folder"]]]]
            )
        ])

        #expect(server.fileRenameRegistrations(.will).count == 2)
        #expect(server.fileRenameRegistrations(.will).last?.filters.first?.pattern.glob == "**/*.rs")
        #expect(server.fileRenameRegistrations(.did).count == 2)
        #expect(server.fileRenameRegistrations(.did).last?.filters.first?.pattern.matches == .folder)

        server.serverCapabilities.workspace = nil
        server.dynamicCapabilities.removeAll()
        #expect(server.fileRenameRegistrations(.will).isEmpty)
        #expect(server.fileRenameRegistrations(.did).isEmpty)
    }
}
