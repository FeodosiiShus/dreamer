import AppKit
import Foundation
import Testing
@testable import Dreamder

extension ProjectNavigatorReplaceSafetyTests {
    @Test
    func aConfirmedDropReplacesTheDestinationFolderWithTheMovedFolder() async throws {
        try await Harness.run(folders: Self.replaceFolders, files: Self.replaceFiles) { harness in
            var asked: [String] = []
            harness.controller.confirmReplace = { name in
                asked.append(name)
                return true
            }
            let incoming = try harness.file("Incoming/Item")

            let accepted = harness.acceptDrop(harness.dropInfo(urls: [incoming.url]), onto: try harness.file("Library"))

            #expect(accepted)
            #expect(asked == ["Item"])
            #expect(try harness.names(in: "Library") == ["Item"])
            #expect(try harness.names(in: "Library/Item") == ["new.txt"])
            #expect(try harness.contents("Library/Item/new.txt") == Self.newContents)
            #expect(try harness.names(in: "Incoming").isEmpty)
        }
    }

    @Test
    func aConfirmedCopyDropReplacesTheDestinationFolderAndKeepsTheSource() async throws {
        try await Harness.run(folders: Self.replaceFolders, files: Self.replaceFiles) { harness in
            harness.controller.confirmReplace = { _ in true }
            let incoming = try harness.file("Incoming/Item")

            let accepted = harness.acceptDrop(
                harness.dropInfo(urls: [incoming.url], mask: .copy),
                onto: try harness.file("Library")
            )

            #expect(accepted)
            #expect(try harness.names(in: "Library") == ["Item"])
            #expect(try harness.names(in: "Library/Item") == ["new.txt"])
            #expect(try harness.names(in: "Incoming/Item") == ["new.txt"])
        }
    }

    @Test
    func aDeclinedDropLeavesBothFoldersUntouched() async throws {
        try await Harness.run(folders: Self.replaceFolders, files: Self.replaceFiles) { harness in
            var asked: [String] = []
            harness.controller.confirmReplace = { name in
                asked.append(name)
                return false
            }
            let incoming = try harness.file("Incoming/Item")

            let accepted = harness.acceptDrop(harness.dropInfo(urls: [incoming.url]), onto: try harness.file("Library"))

            #expect(!accepted)
            #expect(asked == ["Item"])
            try expectReplaceFixtureUntouched(harness)
        }
    }

    @Test(arguments: [false, true])
    func aFailingDropReplacementRestoresTheDestinationAndKeepsTheSource(copying: Bool) async throws {
        try await Harness.run(folders: Self.replaceFolders, files: Self.replaceFiles) { harness in
            var asked: [String] = []
            harness.controller.confirmReplace = { name in
                asked.append(name)
                return true
            }
            try harness.failTransfers(with: marker("drop replacement failure")) { source, destination in
                source.lastPathComponent == "Item" && destination.lastPathComponent == "Item"
            }
            let incoming = try harness.file("Incoming/Item")
            let drop = harness.dropInfo(urls: [incoming.url], mask: mask(copying: copying))

            _ = harness.acceptDrop(drop, onto: try harness.file("Library"))

            #expect(asked == ["Item"])
            #expect(DreamderHeadless.suppressedModals.contains("drop replacement failure"))
            try expectReplaceFixtureUntouched(harness)
        }
    }

    @Test
    func aConfirmedDropReplacementRetargetsTheTabOfTheMovedFile() async throws {
        try await Harness.run(folders: ["Library"], files: ["Library/a.txt", "a.txt"]) { harness in
            harness.controller.confirmReplace = { _ in true }
            let moved = try harness.file("a.txt")
            harness.editor.openTab(file: moved, asTemporary: false)

            let accepted = harness.acceptDrop(harness.dropInfo(urls: [moved.url]), onto: try harness.file("Library"))

            #expect(accepted)
            let tabPaths = harness.editor.tabs.map { $0.file.url.path(percentEncoded: false) }
            #expect(tabPaths == [harness.url("Library/a.txt").path(percentEncoded: false)])
            #expect(try harness.contents("Library/a.txt") == "content of a.txt\n")
            #expect(!harness.exists("a.txt"))
            #expect(try harness.names(in: "Library") == ["a.txt"])
        }
    }

    @Test
    func aDropReplacementReportsAFailureToRefreshTheDestinationFolder() async throws {
        try await Harness.run(
            folders: ["ReplaceLocked"],
            files: ["ReplaceLocked/a.txt", "a.txt"],
            loadsTree: true
        ) { harness in
            harness.controller.confirmReplace = { _ in true }
            let target = try harness.file("ReplaceLocked")
            let moved = try harness.file("a.txt")
            try harness.lock("ReplaceLocked", permissions: 0o300)
            let before = modalCount()

            let accepted = harness.acceptDrop(harness.dropInfo(urls: [moved.url]), onto: target)

            #expect(accepted)
            #expect(modalCount() > before)
            #expect(!harness.exists("a.txt"))
            #expect(try harness.contents("ReplaceLocked/a.txt") == "content of a.txt\n")
        }
    }

    @Test
    func droppingWithoutAFileManagerChangesNothing() async throws {
        try await Harness.run(folders: ["Library"], files: ["Library/a.txt", "a.txt"]) { harness in
            harness.controller.confirmReplace = { _ in true }
            let moved = try harness.file("a.txt")
            let target = try harness.file("Library")
            harness.workspace.workspaceFileManager = nil

            let accepted = harness.acceptDrop(harness.dropInfo(urls: [moved.url]), onto: target)

            #expect(!accepted)
            #expect(harness.exists("a.txt"))
            #expect(try harness.contents("Library/a.txt") == "content of Library/a.txt\n")
        }
    }
}
