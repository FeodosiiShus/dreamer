import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct CEWorkspaceFileManagerFileManagementTests {
    typealias ManagerError = CEWorkspaceFileManager.FileManagerError

    private func makeManager(_ dir: URL) -> CEWorkspaceFileManager {
        let manager = CEWorkspaceFileManager(folderUrl: dir, ignoredFilesAndFolders: [], sourceControlManager: nil)
        manager.fsEventStream?.cancel()
        return manager
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: url, atomically: false, encoding: .utf8)
    }

    private func failure(_ body: () throws -> Void) -> (any Error)? {
        do {
            try body()
            return nil
        } catch {
            return error
        }
    }

    private func setPermissions(_ mode: Int, at url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path(percentEncoded: false))
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    private func rootChild(_ manager: CEWorkspaceFileManager, _ name: String) -> CEWorkspaceFile? {
        manager.getFile("\(manager.workspaceItem.id)/\(name)")
    }

    @Test
    func addingTheSameNameRepeatedlyNumbersTheNewFiles() throws {
        try withTempDir { dir in
            let manager = makeManager(dir)

            let created = try (0..<3).map { _ in
                try manager.addFile(fileName: "note", toFile: manager.workspaceItem, useExtension: "txt")
            }

            #expect(created.map(\.name) == ["note.txt", "note1.txt", "note2.txt"])
        }
    }

    @Test
    func creatingAnItemOverAnExistingTargetFailsAndKeepsTheFile() throws {
        try withTempDir { dir in
            let target = dir.appending(path: "keep.txt")
            try write("original", to: target)
            let manager = makeManager(dir)
            let plan = NewItemPlan(kind: .file, target: target, directoriesToCreate: [])

            let error = failure { _ = try manager.create(plan, contents: Data("replacement".utf8)) }

            #expect(error as? ManagerError == .destinationFileExists)
            let remaining = try String(contentsOf: target, encoding: .utf8)
            #expect(remaining == "original")
        }
    }

    @Test
    func anOverlongNameIsRejectedWithoutCreatingAnything() throws {
        try withTempDir { dir in
            let manager = makeManager(dir)
            let overlong = String(repeating: "a", count: 300) + ".txt"

            let error = failure { _ = try manager.addFile(fileName: overlong, toFile: manager.workspaceItem) }

            #expect(error as? ManagerError == .invalidFileName)
            let remaining = try FileManager.default.contentsOfDirectory(atPath: dir.path(percentEncoded: false))
            #expect(remaining.isEmpty)
        }
    }

    @Test
    func aFolderThatCannotBeWrittenToReportsAWriteFailure() throws {
        try withTempDir { dir in
            let locked = dir.appending(path: "locked", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
            let manager = makeManager(dir)
            let lockedFile = try #require(rootChild(manager, "locked"))
            try setPermissions(0o555, at: locked)
            defer { try? setPermissions(0o755, at: locked) }

            let error = failure { _ = try manager.addFile(fileName: "x.txt", toFile: lockedFile) }

            #expect((error as? CocoaError)?.code == .fileWriteUnknown)
            #expect(!exists(locked.appending(path: "x.txt")))
        }
    }

    @Test
    func aFileCreatedOutsideTheWorkspaceIsNotIndexed() throws {
        try withTempDir { dir in
            let outside = try makeTemporaryDirectory(label: "outside")
            defer { removeTemporaryDirectory(outside) }
            let manager = makeManager(dir)

            let error = failure {
                _ = try manager.addFile(fileName: "stray.txt", toFile: CEWorkspaceFile(url: outside))
            }

            #expect(error as? ManagerError == .fileNotIndexed)
            #expect(exists(outside.appending(path: "stray.txt")))
        }
    }

    @Test
    func addingNextToAFileUsesTheExtensionMostSiblingsShare() throws {
        try withTempDir { dir in
            try write("a", to: dir.appending(path: "a.swift"))
            try write("b", to: dir.appending(path: "b.swift"))
            try write("c", to: dir.appending(path: "c.md"))
            let manager = makeManager(dir)
            let sibling = try #require(rootChild(manager, "a.swift"))

            let created = try manager.addFile(fileName: "d", toFile: sibling)

            #expect(created.name == "d.swift")
            #expect(created.parent?.id == manager.workspaceItem.id)
            #expect(manager.childrenOfFile(manager.workspaceItem)?.contains { $0.name == "d.swift" } == true)
        }
    }

    @Test
    func addingNextToAStandaloneFileCreatesAnExtensionlessFileInItsFolder() throws {
        try withTempDir { dir in
            try write("a", to: dir.appending(path: "a.txt"))
            let manager = makeManager(dir)
            let standalone = CEWorkspaceFile(url: dir.appending(path: "a.txt"))

            let created = try manager.addFile(fileName: "n", toFile: standalone)

            #expect(created.name == "n")
            #expect(exists(dir.appending(path: "n")))
        }
    }

    @Test
    func extensionlessSiblingsMakeTheNewFileExtensionless() throws {
        try withTempDir { dir in
            try write("r", to: dir.appending(path: "README"))
            try write("l", to: dir.appending(path: "LICENSE"))
            try write("a", to: dir.appending(path: "a.swift"))
            let manager = makeManager(dir)

            let created = try manager.addFile(fileName: "NEW", toFile: manager.workspaceItem)

            #expect(created.name == "NEW")
        }
    }

    @Test
    func anEmptyFolderGivesTheNewFileNoExtension() throws {
        try withTempDir { dir in
            let manager = makeManager(dir)

            let created = try manager.addFile(fileName: "first", toFile: manager.workspaceItem)

            #expect(created.name == "first")
        }
    }

    @Test
    func trashingAMissingFileFails() throws {
        try withTempDir { dir in
            let manager = makeManager(dir)
            let missing = CEWorkspaceFile(url: dir.appending(path: "gone.txt"))

            let error = failure { try manager.trash(file: missing) }

            #expect(error as? ManagerError == .fileNotFound)
        }
    }

    @Test
    func deletingFromAFolderThatCannotBeModifiedFailsAndKeepsTheFile() throws {
        try withTempDir { dir in
            let locked = dir.appending(path: "locked", directoryHint: .isDirectory)
            let target = locked.appending(path: "a.txt")
            try write("a", to: target)
            let manager = makeManager(dir)
            let file = CEWorkspaceFile(url: target)
            try setPermissions(0o555, at: locked)
            defer { try? setPermissions(0o755, at: locked) }

            let deleteError = failure { try manager.delete(file: file, confirmDelete: false) }
            let batchError = failure { try manager.batchDelete(files: [file], confirmDelete: false) }

            #expect(deleteError != nil)
            #expect(batchError != nil)
            #expect(exists(target))
        }
    }

    @Test
    func duplicatingIntoAFolderThatCannotBeModifiedFails() throws {
        try withTempDir { dir in
            let locked = dir.appending(path: "locked", directoryHint: .isDirectory)
            let target = locked.appending(path: "a.txt")
            try write("a", to: target)
            let manager = makeManager(dir)
            let file = CEWorkspaceFile(url: target)
            try setPermissions(0o555, at: locked)
            defer { try? setPermissions(0o755, at: locked) }

            let error = failure { try manager.duplicate(file: file) }

            #expect(error != nil)
            #expect(!exists(locked.appending(path: "a copy.txt")))
        }
    }

    @Test
    func everyErrorHasADescriptionAndARecoverySuggestion() {
        let expected: [(ManagerError, String, String)] = [
            (.fileNotFound, "File not found", "The file may have moved during the operation, try again."),
            (.fileNotIndexed, "File not found in Dreamder", "Reopen the workspace to reindex the file system."),
            (
                .originFileNotFound,
                "Failed to find origin file",
                "The file may have moved during the operation, try again."
            ),
            (
                .destinationFileExists,
                "Destination already exists",
                "Use a different file name or remove the conflicting file."
            ),
            (
                .invalidFileName,
                "Invalid file name",
                "File names must not contain the : character and be less than 256 characters."
            )
        ]

        for (error, description, suggestion) in expected {
            #expect(error.errorDescription == description)
            #expect(error.recoverySuggestion == suggestion)
        }
    }
}
