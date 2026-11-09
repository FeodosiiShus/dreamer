import Foundation
import LanguageClient
import LanguageServerProtocol
import Synchronization
import Testing
@testable import Dreamder

extension RenameFileOperationsTests {
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
                try await makeClient(
                    root: dir,
                    connection: registered,
                    capabilities: capabilities(will: filters("**/*.ts"))
                ),
                try await makeClient(root: dir, connection: unregistered, capabilities: capabilities()),
                try await makeClient(
                    root: dir,
                    connection: mismatched,
                    capabilities: capabilities(will: filters("**/*.rs"))
                )
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
                try await makeClient(
                    root: dir,
                    connection: registered,
                    capabilities: capabilities(did: filters("**/*.ts"))
                ),
                try await makeClient(root: dir, connection: other, capabilities: capabilities(will: filters("**/*.ts")))
            ]

            await LSPFileOperations.didRename(from: old, to: new, clients: clients)

            #expect(didRenameParams(registered) == [
                RenameFilesParams(files: [FileRename(oldUri: old.lspURI, newUri: new.lspURI)])
            ])
            #expect(didRenameParams(other).isEmpty)
        }
    }
}
