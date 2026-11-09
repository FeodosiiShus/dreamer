import Foundation
import Testing
@testable import Dreamder

@Suite
struct ProjectNavigatorItemReplacementTests {
    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func names(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    private func contents(of url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private func makeFailingOperations(
        failing condition: @escaping @Sendable (URL, URL) -> Bool
    ) -> ProjectNavigatorFileOperations {
        let failure = NSError(
            domain: "ProjectNavigatorItemReplacementTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "injected transfer failure"]
        )
        return .failing(with: failure, where: condition)
    }

    @Test
    func movingReplacesTheDestinationFileAndLeavesNoBackup() throws {
        try withTempDir { directory in
            let source = directory.appending(path: "incoming/a.txt")
            let destination = directory.appending(path: "library/a.txt")
            try write("new", to: source)
            try write("old", to: destination)

            try ProjectNavigatorItemReplacement.replace(
                destination,
                with: source,
                mode: .move,
                using: .live
            )

            #expect(try contents(of: destination) == "new")
            #expect(try names(in: directory.appending(path: "library")) == ["a.txt"])
            #expect(try names(in: directory.appending(path: "incoming")).isEmpty)
        }
    }

    @Test
    func copyingReplacesTheDestinationFolderAndKeepsTheSource() throws {
        try withTempDir { directory in
            let source = directory.appending(path: "incoming/Item")
            let destination = directory.appending(path: "library/Item")
            try write("new", to: source.appending(path: "new.txt"))
            try write("old", to: destination.appending(path: "old.txt"))

            try ProjectNavigatorItemReplacement.replace(
                destination,
                with: source,
                mode: .copy,
                using: .live
            )

            #expect(try names(in: destination) == ["new.txt"])
            #expect(try names(in: source) == ["new.txt"])
            #expect(try names(in: directory.appending(path: "library")) == ["Item"])
        }
    }

    @Test(arguments: [ProjectNavigatorItemReplacement.Mode.move, .copy])
    func aFailingTransferRestoresTheDestinationAndKeepsTheSource(mode: ProjectNavigatorItemReplacement.Mode) throws {
        try withTempDir { directory in
            let source = directory.appending(path: "incoming/a.txt")
            let destination = directory.appending(path: "library/a.txt")
            try write("new", to: source)
            try write("old", to: destination)
            let operations = makeFailingOperations { from, target in
                from.lastPathComponent == "a.txt" && target.lastPathComponent == "a.txt"
            }

            #expect(throws: NSError.self) {
                try ProjectNavigatorItemReplacement.replace(destination, with: source, mode: mode, using: operations)
            }

            #expect(try contents(of: destination) == "old")
            #expect(try contents(of: source) == "new")
            #expect(try names(in: directory.appending(path: "library")) == ["a.txt"])
        }
    }

    @Test
    func whenRestoringFailsTooTheOriginalSurvivesInTheBackup() throws {
        try withTempDir { directory in
            let source = directory.appending(path: "incoming/a.txt")
            let destination = directory.appending(path: "library/a.txt")
            try write("new", to: source)
            try write("old", to: destination)
            let operations = makeFailingOperations { _, target in
                target.lastPathComponent == "a.txt"
            }

            #expect(throws: NSError.self) {
                try ProjectNavigatorItemReplacement.replace(destination, with: source, mode: .move, using: operations)
            }

            let remaining = try names(in: directory.appending(path: "library"))
            let backupName = try #require(remaining.first)
            #expect(remaining.count == 1)
            #expect(backupName.hasPrefix(".a.txt.replaced-"))
            #expect(try contents(of: directory.appending(path: "library/\(backupName)")) == "old")
            #expect(try contents(of: source) == "new")
        }
    }

    @Test
    func aDestinationThatCannotBeSetAsideIsLeftUntouched() throws {
        try withTempDir { directory in
            let source = directory.appending(path: "incoming/a.txt")
            let destination = directory.appending(path: "library/a.txt")
            try write("new", to: source)
            try write("old", to: destination)
            let operations = makeFailingOperations { _, target in
                target.lastPathComponent.hasPrefix(".a.txt.replaced-")
            }

            #expect(throws: NSError.self) {
                try ProjectNavigatorItemReplacement.replace(destination, with: source, mode: .move, using: operations)
            }

            #expect(try contents(of: destination) == "old")
            #expect(try contents(of: source) == "new")
            #expect(try names(in: directory.appending(path: "library")) == ["a.txt"])
        }
    }
}
