import Foundation
import LanguageClient
import LanguageServerProtocol
import Testing
@testable import Dreamder

@MainActor
private final class RenameFileOperationsApplier {
    var calls: [(edit: WorkspaceEdit, client: LSPFileOperations.Client)] = []
    var result = ApplyWorkspaceEditResult(applied: true)

    func apply(_ edit: WorkspaceEdit, _ client: LSPFileOperations.Client) async -> ApplyWorkspaceEditResult {
        calls.append((edit, client))
        return result
    }
}

@MainActor
@Suite(.uiGate)
struct RenameFileOperationsTests {
    private let oldURI = "file:///tmp/sync/old.ts"
    private let newURI = "file:///tmp/sync/new.ts"

    private func filters(_ glob: String, matches: FileOperationPatternKind? = nil) -> FileOperationRegistrationOptions {
        FileOperationRegistrationOptions(filters: [
            FileOperationFilter(
                scheme: "file",
                pattern: FileOperationPattern(glob: glob, matches: matches, options: nil)
            )
        ])
    }

    private func capabilities(
        will: FileOperationRegistrationOptions? = nil,
        did: FileOperationRegistrationOptions? = nil
    ) -> ServerCapabilities {
        var capabilities = ScriptedServerConnection.incrementalCapabilities()
        capabilities.workspace = ServerCapabilities.Workspace(
            fileOperations: ServerCapabilities.Workspace.FileOperations(didRename: did, willRename: will)
        )
        return capabilities
    }

    private func makeClient(
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

    private func willRenameParams(_ connection: ScriptedServerConnection) -> [RenameFilesParams] {
        connection.requests.compactMap { request in
            if case let .workspaceWillRenameFiles(params, _) = request {
                return params
            }
            return nil
        }
    }

    private func didRenameParams(_ connection: ScriptedServerConnection) -> [RenameFilesParams] {
        connection.notifications.compactMap { notification in
            if case let .workspaceDidRenameFiles(params) = notification {
                return params
            }
            return nil
        }
    }

    private func renameEdit(path: String) throws -> WorkspaceEdit {
        let uri = URL(fileURLWithPath: path).lspURI
        return try SyncTestServer.decode(
            WorkspaceEdit.self,
            #"{"changes":{"\#(uri)":[{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":3}},"newText":"fixed"}]}}"#
        )
    }

    private func touch(_ url: URL, text: String = "old\n") throws {
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

    @Test
    func willRenameIsRequestedOnlyFromRegisteredClientsAndTheEditReachesTheApplierUntouched() async throws {
        try await withTempDir { dir in
            let old = dir.appending(path: "old.ts")
            let new = dir.appending(path: "new.ts")
            try touch(new)
            let edit = try renameEdit(path: dir.appending(path: "importer.ts").path)
            let registered = ScriptedServerConnection()
            let unregistered = ScriptedServerConnection()
            let mismatched = ScriptedServerConnection()
            let clients = [
                try await makeClient(root: dir, connection: registered, capabilities: capabilities(will: filters("**/*.ts"))),
                try await makeClient(root: dir, connection: unregistered, capabilities: capabilities()),
                try await makeClient(root: dir, connection: mismatched, capabilities: capabilities(will: filters("**/*.rs")))
            ]
            try registered.script(.workspaceWillRenameFiles, edit)
            let applier = RenameFileOperationsApplier()

            await LSPFileOperations.willRename(
                from: old,
                to: new,
                clients: clients,
                apply: { edit, client in await applier.apply(edit, client) }
            )

            #expect(willRenameParams(registered) == [
                RenameFilesParams(files: [FileRename(oldUri: old.lspURI, newUri: new.lspURI)])
            ])
            #expect(willRenameParams(unregistered).isEmpty)
            #expect(willRenameParams(mismatched).isEmpty)
            #expect(applier.calls.count == 1)
            #expect(applier.calls.first?.edit == edit)
            #expect(applier.calls.first?.client === clients[0])
        }
    }

    @Test
    func dynamicRegistrationsAndFolderFiltersAreRespected() async throws {
        try await withTempDir { dir in
            let oldFolder = dir.appending(path: "oldFolder")
            let newFolder = dir.appending(path: "newFolder")
            try FileManager.default.createDirectory(at: newFolder, withIntermediateDirectories: true)
            let connection = ScriptedServerConnection()
            let client = try await makeClient(root: dir, connection: connection, capabilities: capabilities())
            client.dynamicCapabilities.register([
                Registration(
                    id: "files",
                    method: "workspace/willRenameFiles",
                    registerOptions: ["filters": [["pattern": ["glob": "**/oldFolder", "matches": "folder"]]]]
                ),
                Registration(
                    id: "filesOnly",
                    method: "workspace/didRenameFiles",
                    registerOptions: ["filters": [["pattern": ["glob": "**/oldFolder", "matches": "file"]]]]
                )
            ])
            let applier = RenameFileOperationsApplier()

            await LSPFileOperations.willRename(
                from: oldFolder,
                to: newFolder,
                clients: [client],
                apply: { edit, client in await applier.apply(edit, client) }
            )
            await LSPFileOperations.didRename(from: oldFolder, to: newFolder, clients: [client])

            #expect(willRenameParams(connection).count == 1)
            #expect(applier.calls.isEmpty)
            #expect(didRenameParams(connection).isEmpty)
        }
    }

    @Test
    func clientsWhoseRootDoesNotContainTheOldFileAreSkipped() async throws {
        try await withTempDir { dir in
            let root = dir.appending(path: "project")
            let outside = dir.appending(path: "elsewhere")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            let connection = ScriptedServerConnection()
            let client = try await makeClient(
                root: root,
                connection: connection,
                capabilities: capabilities(will: filters("**/*.ts"), did: filters("**/*.ts"))
            )
            let applier = RenameFileOperationsApplier()

            await LSPFileOperations.willRename(
                from: outside.appending(path: "a.ts"),
                to: outside.appending(path: "b.ts"),
                clients: [client],
                apply: { edit, client in await applier.apply(edit, client) }
            )
            await LSPFileOperations.didRename(
                from: outside.appending(path: "a.ts"),
                to: outside.appending(path: "b.ts"),
                clients: [client]
            )

            #expect(connection.requestCount(.workspaceWillRenameFiles) == 0)
            #expect(connection.notificationCount(.workspaceDidRenameFiles) == 0)
        }
    }

    @Test
    func aNullEditAFailedApplicationAndAFailingRequestNeverStopTheRename() async throws {
        try await withTempDir { dir in
            let old = dir.appending(path: "old.ts")
            let new = dir.appending(path: "new.ts")
            try touch(new)
            let registeredForBoth = capabilities(will: filters("**/*.ts"), did: filters("**/*.ts"))
            let nullEdit = ScriptedServerConnection()
            let rejected = ScriptedServerConnection()
            try rejected.script(.workspaceWillRenameFiles, try renameEdit(path: dir.appending(path: "x.ts").path))
            let failingInner = ScriptedServerConnection()
            let failing = FaultInjectingConnection(
                inner: failingInner,
                failingNotifications: [.workspaceDidRenameFiles],
                failingRequests: [.workspaceWillRenameFiles]
            )
            let clients = [
                try await makeClient(root: dir, connection: nullEdit, capabilities: registeredForBoth),
                try await makeClient(root: dir, connection: rejected, capabilities: registeredForBoth),
                try await makeClient(root: dir, connection: failing, capabilities: registeredForBoth)
            ]
            let applier = RenameFileOperationsApplier()
            applier.result = ApplyWorkspaceEditResult(applied: false, failureReason: "denied")

            await LSPFileOperations.willRename(
                from: old,
                to: new,
                clients: clients,
                apply: { edit, client in await applier.apply(edit, client) }
            )
            await LSPFileOperations.didRename(from: old, to: new, clients: clients)

            #expect(applier.calls.count == 1)
            #expect(applier.calls.first?.client === clients[1])
            #expect(willRenameParams(nullEdit).count == 1)
            #expect(didRenameParams(nullEdit).count == 1)
            #expect(didRenameParams(rejected).count == 1)
            #expect(failingInner.requestCount(.workspaceWillRenameFiles) == 0)
            #expect(failingInner.notificationCount(.workspaceDidRenameFiles) == 0)
        }
    }

    @Test
    func aRejectedEditWithoutAReasonNeverStopsTheRename() async throws {
        try await withTempDir { dir in
            let old = dir.appending(path: "old.ts")
            let new = dir.appending(path: "new.ts")
            try touch(new)
            let connection = ScriptedServerConnection()
            try connection.script(.workspaceWillRenameFiles, try renameEdit(path: dir.appending(path: "x.ts").path))
            let client = try await makeClient(
                root: dir,
                connection: connection,
                capabilities: capabilities(will: filters("**/*.ts"), did: filters("**/*.ts"))
            )
            let applier = RenameFileOperationsApplier()
            applier.result = ApplyWorkspaceEditResult(applied: false, failureReason: nil)

            await LSPFileOperations.willRename(
                from: old,
                to: new,
                clients: [client],
                apply: { edit, client in await applier.apply(edit, client) }
            )

            #expect(applier.calls.count == 1)
        }
    }

    @Test
    func didRenameIsSentOnlyToRegisteredClients() async throws {
        try await withTempDir { dir in
            let old = dir.appending(path: "old.ts")
            let new = dir.appending(path: "new.ts")
            try touch(new)
            let registered = ScriptedServerConnection()
            let other = ScriptedServerConnection()
            let clients = [
                try await makeClient(root: dir, connection: registered, capabilities: capabilities(did: filters("**/*.ts"))),
                try await makeClient(root: dir, connection: other, capabilities: capabilities(will: filters("**/*.ts")))
            ]

            await LSPFileOperations.didRename(from: old, to: new, clients: clients)

            #expect(didRenameParams(registered) == [
                RenameFilesParams(files: [FileRename(oldUri: old.lspURI, newUri: new.lspURI)])
            ])
            #expect(didRenameParams(other).isEmpty)
        }
    }

    @Test
    func fileMovedSendsWillBeforeDidThroughTheSharedServiceAndAppliesTheServersEdit() async throws {
        let service = LSPService.shared
        try await withTempDir { dir in
            let old = dir.appending(path: "old.ts")
            let new = dir.appending(path: "new.ts")
            let importer = dir.appending(path: "importer.ts")
            try touch(new)
            try touch(importer, text: "old\n")
            let connection = ScriptedServerConnection()
            let client = try await makeClient(
                root: dir,
                connection: connection,
                capabilities: capabilities(will: filters("**/*.ts"), did: filters("**/*.ts"))
            )
            try connection.script(.workspaceWillRenameFiles, try renameEdit(path: importer.path))
            let key = LSPService.ClientKey(.swift, dir.path())
            service.languageClients[key] = client
            defer { service.languageClients[key] = nil }

            await LSPFileOperations.fileMoved(from: old, to: new).value

            let methods = connection.log.filter { $0.hasPrefix("workspace/") }
            #expect(methods == ["workspace/willRenameFiles", "workspace/didRenameFiles"])
            #expect(try String(contentsOf: importer, encoding: .utf8) == "fixed\n")
        }
    }

    @Test
    func withoutAServiceNothingIsSent() async {
        let old = URL(fileURLWithPath: "/tmp/nowhere/old.ts")
        let new = URL(fileURLWithPath: "/tmp/nowhere/new.ts")

        await LSPFileOperations.willRename(from: old, to: new, service: nil)
        await LSPFileOperations.didRename(from: old, to: new, service: nil)
    }

    @Test
    func theRootContainsItselfAndItsDescendantsButNotSiblingsWithACommonPrefix() {
        let root = URL(fileURLWithPath: "/tmp/project")

        #expect(LSPFileOperations.contains(root: root, url: URL(fileURLWithPath: "/tmp/project")))
        #expect(LSPFileOperations.contains(root: root, url: URL(fileURLWithPath: "/tmp/project/src/a.ts")))
        #expect(!LSPFileOperations.contains(root: root, url: URL(fileURLWithPath: "/tmp/project2/a.ts")))
        #expect(!LSPFileOperations.contains(root: root, url: URL(fileURLWithPath: "/tmp/other/a.ts")))
        #expect(LSPFileOperations.contains(root: URL(fileURLWithPath: "/"), url: URL(fileURLWithPath: "/tmp/a.ts")))
    }

    @Test
    func theKindOfTheMovedItemComesFromTheNewLocationThenTheOldOne() throws {
        try withTempDir { dir in
            let folder = dir.appending(path: "folder")
            let file = dir.appending(path: "file.txt")
            let missing = dir.appending(path: "missing")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try touch(file)

            #expect(LSPFileOperations.isDirectory(folder, missing))
            #expect(!LSPFileOperations.isDirectory(file, folder))
            #expect(LSPFileOperations.isDirectory(missing, folder))
            #expect(!LSPFileOperations.isDirectory(missing, file))
            #expect(!LSPFileOperations.isDirectory(missing, dir.appending(path: "gone")))
        }
    }
}
