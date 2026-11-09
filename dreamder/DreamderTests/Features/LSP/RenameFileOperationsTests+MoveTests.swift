import Foundation
import LanguageClient
import LanguageServerProtocol
import Synchronization
import Testing
@testable import Dreamder

extension RenameFileOperationsTests {
    @Test
    func movingAFileSendsWillRenameBeforeTheMoveAndDidRenameAfterIt() async throws {
        let service = LSPService.shared
        try await withTempDir { dir in
            let importer = dir.appending(path: "importer.ts")
            let old = dir.appending(path: "old.ts")
            let new = dir.appending(path: "nested/new.ts")
            let workspace = try LSPServiceWorkspace(
                directory: dir,
                files: ["old.ts": "export {}\n", "importer.ts": "old\n"]
            )
            defer { workspace.close() }
            let scripted = ScriptedServerConnection()
            let connection = RenameOrderObservingConnection(inner: scripted, old: old, new: new)
            let client = try await makeClient(
                root: dir,
                connection: connection,
                capabilities: capabilities(will: filters("**/*.ts"), did: filters("**/*.ts"))
            )
            try scripted.script(.workspaceWillRenameFiles, try renameEdit(path: importer.path))
            let key = LSPService.ClientKey(.swift, dir.path())
            service.languageClients[key] = client
            defer { service.languageClients[key] = nil }
            let file = try #require(workspace.fileManager.getFile(old.path, createIfNotFound: true))

            try await workspace.fileManager.move(file: file, to: new)

            #expect(connection.observations == [
                "willRenameFiles old=exists new=missing",
                "didRenameFiles old=missing new=exists"
            ])
            #expect(try String(contentsOf: importer, encoding: .utf8) == "fixed\n")
            #expect(FileManager.default.fileExists(atPath: new.path))
            #expect(!FileManager.default.fileExists(atPath: old.path))
        }
    }

    @Test
    func aMoveThatCannotHappenSendsNothingToTheServers() async throws {
        let service = LSPService.shared
        try await withTempDir { dir in
            let old = dir.appending(path: "old.ts")
            let taken = dir.appending(path: "taken.ts")
            let workspace = try LSPServiceWorkspace(
                directory: dir,
                files: ["old.ts": "export {}\n", "taken.ts": "export {}\n"]
            )
            defer { workspace.close() }
            let scripted = ScriptedServerConnection()
            let connection = RenameOrderObservingConnection(inner: scripted, old: old, new: taken)
            let client = try await makeClient(
                root: dir,
                connection: connection,
                capabilities: capabilities(will: filters("**/*.ts"), did: filters("**/*.ts"))
            )
            let key = LSPService.ClientKey(.swift, dir.path())
            service.languageClients[key] = client
            defer { service.languageClients[key] = nil }
            let file = try #require(workspace.fileManager.getFile(old.path, createIfNotFound: true))

            await #expect(throws: CEWorkspaceFileManager.FileManagerError.destinationFileExists) {
                try await workspace.fileManager.move(file: file, to: taken)
            }
            try FileManager.default.removeItem(at: old)
            await #expect(throws: CEWorkspaceFileManager.FileManagerError.originFileNotFound) {
                try await workspace.fileManager.move(file: file, to: dir.appending(path: "other.ts"))
            }

            #expect(connection.observations.isEmpty)
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
