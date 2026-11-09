import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@Suite
struct LSPWorkspaceFileOperationTests {
    @Test
    func createFileReportsAFileSystemThatRefusesTheNewFile() async throws {
        try await withTempDir { directory in
            let fixture = try LSPExecutorFixture(in: directory)
            let locked = try fixture.makeFolder(in: fixture.root, "locked")
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
            let target = locked.appending(path: "new.txt")
            let creation = try LSPExecutorEdits.create(target.absoluteString)

            let result = await fixture.executor().apply(creation)

            #expect(result == ApplyWorkspaceEditResult(
                applied: false,
                failureReason: "The file could not be created: \(target.absoluteString)",
                failedChange: 0
            ))
            #expect(!FileManager.default.fileExists(atPath: target.path))
        }
    }

    @Test
    func createFileHonoursOverwriteAndIgnoreIfExistsAndTrashesWhatItReplaces() async throws {
        try await withTempDir { directory in
            let fixture = try LSPExecutorFixture(in: directory)
            let file = fixture.root.appending(path: "nested/dir/new.txt")
            let uri = file.absoluteString
            let plain = try LSPExecutorEdits.create(uri)
            let ignoring = try LSPExecutorEdits.create(uri, options: #"{"ignoreIfExists":true}"#)
            let overwriting = try LSPExecutorEdits.create(uri, options: #"{"overwrite":true}"#)
            let executor = fixture.executor()

            #expect(await executor.apply(plain).applied)
            #expect(try String(contentsOf: file, encoding: .utf8) == "")

            try "keep".write(to: file, atomically: true, encoding: .utf8)
            let duplicate = await executor.apply(plain)
            #expect(duplicate == ApplyWorkspaceEditResult(
                applied: false,
                failureReason: "The file already exists: \(uri)",
                failedChange: 0
            ))
            #expect(await executor.apply(ignoring).applied)
            #expect(try String(contentsOf: file, encoding: .utf8) == "keep")
            #expect(fixture.trashed.isEmpty)

            #expect(await executor.apply(overwriting).applied)
            #expect(try String(contentsOf: file, encoding: .utf8) == "")
            #expect(fixture.trashed == [file.path])
        }
    }

    @Test
    func renameFileMovesTheFileAndHonoursExistingTargets() async throws {
        try await withTempDir { directory in
            let fixture = try LSPExecutorFixture(in: directory)
            let source = try fixture.makeFile(in: fixture.root, "a.txt", "a")
            let target = fixture.root.appending(path: "sub/b.txt")
            let rename = try LSPExecutorEdits.rename(source, target)
            let executor = fixture.executor()

            #expect(await executor.apply(rename).applied)
            #expect(!FileManager.default.fileExists(atPath: source.path))
            #expect(try String(contentsOf: target, encoding: .utf8) == "a")

            try "again".write(to: source, atomically: true, encoding: .utf8)
            let blocked = await executor.apply(rename)
            #expect(blocked.applied == false)
            #expect(blocked.failureReason == "The file already exists: \(target.absoluteString)")

            let ignoring = try LSPExecutorEdits.rename(source, target, options: #"{"ignoreIfExists":true}"#)
            #expect(await executor.apply(ignoring).applied)
            #expect(try String(contentsOf: target, encoding: .utf8) == "a")
            #expect(FileManager.default.fileExists(atPath: source.path))
            #expect(fixture.trashed.isEmpty)

            let overwriting = try LSPExecutorEdits.rename(source, target, options: #"{"overwrite":true}"#)
            #expect(await executor.apply(overwriting).applied)
            #expect(try String(contentsOf: target, encoding: .utf8) == "again")
            #expect(!FileManager.default.fileExists(atPath: source.path))
            #expect(fixture.trashed == [target.path])
        }
    }

    @Test
    func renameOfAMissingSourceFails() async throws {
        try await withTempDir { directory in
            let fixture = try LSPExecutorFixture(in: directory)
            let source = fixture.root.appending(path: "missing.txt")
            let target = fixture.root.appending(path: "b.txt")
            let rename = try LSPExecutorEdits.rename(source, target)

            let result = await fixture.executor().apply(rename)

            #expect(result.applied == false)
            #expect(result.failureReason == "The file does not exist: \(source.absoluteString)")
        }
    }

    @Test
    func deleteFileRespectsRecursiveAndIgnoreIfNotExistsAndMovesToTheTrash() async throws {
        try await withTempDir { directory in
            let fixture = try LSPExecutorFixture(in: directory)
            let folder = try fixture.makeFolder(in: fixture.root, "folder")
            try fixture.makeFile(in: folder, "inner.txt", "x")
            let missing = fixture.root.appending(path: "missing.txt")
            let executor = fixture.executor()

            let nonEmpty = await executor.apply(LSPExecutorEdits.delete(folder, recursive: false))
            #expect(nonEmpty.applied == false)
            #expect(nonEmpty.failureReason == "The directory is not empty: \(folder.absoluteString)")
            #expect(FileManager.default.fileExists(atPath: folder.path))

            let absent = await executor.apply(LSPExecutorEdits.delete(missing))
            #expect(absent.applied == false)
            #expect(absent.failureReason == "The file does not exist: \(missing.absoluteString)")
            #expect(await executor.apply(LSPExecutorEdits.delete(missing, ignoreIfNotExists: true)).applied)
            #expect(fixture.trashed.isEmpty)

            #expect(await executor.apply(LSPExecutorEdits.delete(folder, recursive: true)).applied)
            #expect(!FileManager.default.fileExists(atPath: folder.path))
            #expect(fixture.trashed == [folder.path])
        }
    }

    @Test
    func emptyDirectoriesAreDeletedWithoutTheRecursiveFlag() async throws {
        try await withTempDir { directory in
            let fixture = try LSPExecutorFixture(in: directory)
            let folder = try fixture.makeFolder(in: fixture.root, "empty")

            let result = await fixture.executor().apply(LSPExecutorEdits.delete(folder))

            #expect(result.applied)
            #expect(fixture.trashed == [folder.path])
        }
    }

    @Test
    func aDeletedFileIsMovedToTheTrashNotRemovedPermanently() async throws {
        try await withTempDir { directory in
            let fixture = try LSPExecutorFixture(in: directory)
            let file = try fixture.makeFile(in: fixture.root, "gone.txt", "recoverable")

            let result = await fixture.executor().apply(LSPExecutorEdits.delete(file))

            #expect(result.applied)
            #expect(!FileManager.default.fileExists(atPath: file.path))
            let kept = try FileManager.default.contentsOfDirectory(atPath: fixture.trashRecorder.trashDirectory.path)
            #expect(kept.count == 1)
        }
    }

    @Test
    func theLiveTrashHandlerReportsAnItemThatDoesNotExist() throws {
        try withTempDir { directory in
            let absent = directory.appending(path: "absent.txt")

            #expect(throws: (any Error).self) {
                try LSPWorkspaceEditExecutor.trashWithFileManager(absent)
            }
        }
    }

    @Test
    func aTrashThatRefusesTheItemLeavesTheItemInPlaceAndReportsTheReason() async throws {
        try await withTempDir { directory in
            let fixture = try LSPExecutorFixture(in: directory, trashFailure: LSPExecutorFailure())
            let file = try fixture.makeFile(in: fixture.root, "keep.txt", "keep")

            let result = await fixture.executor().apply(LSPExecutorEdits.delete(file))

            #expect(result == ApplyWorkspaceEditResult(applied: false, failureReason: "refused", failedChange: 0))
            #expect(try String(contentsOf: file, encoding: .utf8) == "keep")
        }
    }
}
