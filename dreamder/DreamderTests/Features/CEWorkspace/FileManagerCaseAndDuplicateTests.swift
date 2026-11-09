import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct FileManagerCaseAndDuplicateTests {
    private func makeManager(_ dir: URL) -> CEWorkspaceFileManager {
        let manager = CEWorkspaceFileManager(folderUrl: dir, ignoredFilesAndFolders: [], sourceControlManager: nil)
        manager.fsEventStream?.cancel()
        return manager
    }

    private func write(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: false, encoding: .utf8)
    }

    private func names(in dir: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: dir.path(percentEncoded: false)).sorted()
    }

    @Test
    func duplicatingAFileWithADottedBaseNameKeepsTheBaseNameIntact() throws {
        try withTempDir { dir in
            try write("lint", to: dir.appending(path: "my.swiftlint.swift"))
            try write("json", to: dir.appending(path: "foo.json5.json"))
            let manager = makeManager(dir)

            try manager.duplicate(file: CEWorkspaceFile(url: dir.appending(path: "my.swiftlint.swift")))
            try manager.duplicate(file: CEWorkspaceFile(url: dir.appending(path: "foo.json5.json")))

            #expect(try names(in: dir) == [
                "foo.json5 copy.json",
                "foo.json5.json",
                "my.swiftlint copy.swift",
                "my.swiftlint.swift"
            ])
            #expect(try String(contentsOf: dir.appending(path: "my.swiftlint copy.swift"), encoding: .utf8) == "lint")
        }
    }

    @Test
    func duplicatingTwiceAppendsCopyAgainBeforeTheExtension() throws {
        try withTempDir { dir in
            try write("a", to: dir.appending(path: "a.b.txt"))
            let manager = makeManager(dir)
            let file = CEWorkspaceFile(url: dir.appending(path: "a.b.txt"))

            try manager.duplicate(file: file)
            try manager.duplicate(file: file)

            #expect(try names(in: dir) == ["a.b copy copy.txt", "a.b copy.txt", "a.b.txt"])
        }
    }

    @Test
    func duplicatingNamesWithoutAnExtensionAppendsCopyToTheWholeName() throws {
        try withTempDir { dir in
            try write("make", to: dir.appending(path: "Makefile"))
            try write("env", to: dir.appending(path: ".env"))
            let manager = makeManager(dir)

            try manager.duplicate(file: CEWorkspaceFile(url: dir.appending(path: "Makefile")))
            try manager.duplicate(file: CEWorkspaceFile(url: dir.appending(path: ".env")))

            #expect(try names(in: dir) == [".env", ".env copy", "Makefile", "Makefile copy"])
        }
    }

    @Test
    func renamingAFileToTheSameNameInADifferentCaseSucceedsAndLeavesOneEntry() async throws {
        try await withTempDir { dir in
            try write("content", to: dir.appending(path: "readme.md"))
            let manager = makeManager(dir)
            let file = try #require(manager.getFile("\(manager.workspaceItem.id)/readme.md"))

            let moved = try await manager.move(file: file, to: dir.appending(path: "README.md"))

            #expect(try names(in: dir) == ["README.md"])
            #expect(try String(contentsOf: dir.appending(path: "README.md"), encoding: .utf8) == "content")
            #expect(moved?.name == "README.md")
            #expect(manager.getFile("\(manager.workspaceItem.id)/readme.md") == nil)
            #expect(manager.childrenMap[manager.workspaceItem.id] == ["\(manager.workspaceItem.id)/README.md"])
        }
    }

    @Test
    func movingOntoAnotherExistingFileOrOntoItselfStillFails() async throws {
        try await withTempDir { dir in
            try write("one", to: dir.appending(path: "one.txt"))
            try write("two", to: dir.appending(path: "two.txt"))
            let manager = makeManager(dir)
            let file = try #require(manager.getFile("\(manager.workspaceItem.id)/one.txt"))

            await #expect(throws: CEWorkspaceFileManager.FileManagerError.destinationFileExists) {
                try await manager.move(file: file, to: dir.appending(path: "two.txt"))
            }
            await #expect(throws: CEWorkspaceFileManager.FileManagerError.destinationFileExists) {
                try await manager.move(file: file, to: dir.appending(path: "one.txt"))
            }

            #expect(try names(in: dir) == ["one.txt", "two.txt"])
            #expect(try String(contentsOf: dir.appending(path: "two.txt"), encoding: .utf8) == "two")
        }
    }

    @Test
    func aDestinationIsFreeWhenMissingOrWhenItIsTheSourceUnderADifferentCase() throws {
        try withTempDir { dir in
            let fileManager = FileManager.default
            try write("x", to: dir.appending(path: "readme.md"))
            try write("y", to: dir.appending(path: "taken.md"))
            let source = dir.appending(path: "readme.md")

            #expect(fileManager.destinationIsFree(dir.appending(path: "missing.md"), whenMoving: source))
            #expect(fileManager.destinationIsFree(dir.appending(path: "README.md"), whenMoving: source))
            #expect(!fileManager.destinationIsFree(dir.appending(path: "taken.md"), whenMoving: source))
            #expect(!fileManager.destinationIsFree(source, whenMoving: source))
        }
    }

    @Test
    func aHardLinkToTheSourceWithAnotherNameIsNotFree() throws {
        try withTempDir { dir in
            let fileManager = FileManager.default
            let source = dir.appending(path: "a.txt")
            let link = dir.appending(path: "b.txt")
            try write("x", to: source)
            try fileManager.linkItem(at: source, to: link)

            #expect(!fileManager.destinationIsFree(link, whenMoving: source))
        }
    }
}
