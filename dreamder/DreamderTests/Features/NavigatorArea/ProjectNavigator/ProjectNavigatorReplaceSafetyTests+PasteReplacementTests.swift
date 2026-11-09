import AppKit
import Foundation
import Testing
@testable import Dreamder

extension ProjectNavigatorReplaceSafetyTests {
    @Test
    func aConfirmedPasteReplacesTheDestinationFolderWithTheCutFolder() async throws {
        try await Harness.run(folders: Self.replaceFolders, files: Self.replaceFiles) { harness in
            var asked: [String] = []
            harness.controller.confirmReplace = { name in
                asked.append(name)
                return true
            }
            harness.controller.cutToClipboard([try harness.file("Incoming/Item")])

            await harness.pasteAndWait(into: try harness.file("Library"))

            #expect(asked == ["Item"])
            #expect(try harness.names(in: "Library") == ["Item"])
            #expect(try harness.names(in: "Library/Item") == ["new.txt"])
            #expect(try harness.contents("Library/Item/new.txt") == Self.newContents)
            #expect(try harness.names(in: "Incoming").isEmpty)
            #expect(!harness.controller.clipboard.hasFiles)
        }
    }

    @Test
    func aDeclinedPasteLeavesBothFoldersUntouchedAndKeepsTheClipboard() async throws {
        try await Harness.run(folders: Self.replaceFolders, files: Self.replaceFiles) { harness in
            harness.controller.confirmReplace = { _ in false }
            harness.controller.cutToClipboard([try harness.file("Incoming/Item")])

            await harness.pasteAndWait(into: try harness.file("Library"))

            try expectReplaceFixtureUntouched(harness)
            #expect(harness.controller.clipboard.isCut)
        }
    }

    @Test
    func aFailingPasteReplacementLeavesBothFoldersUntouchedAndReportsTheError() async throws {
        try await Harness.run(folders: Self.replaceFolders, files: Self.replaceFiles) { harness in
            harness.controller.confirmReplace = { _ in true }
            let failure = marker("paste replacement failure")
            try harness.failTransfers(with: failure) { source, destination in
                source.lastPathComponent == "Item" && destination.lastPathComponent == "Item"
            }
            harness.controller.cutToClipboard([try harness.file("Incoming/Item")])

            await harness.pasteAndWait(into: try harness.file("Library"))

            try expectReplaceFixtureUntouched(harness)
            #expect(harness.controller.clipboard.isCut)
            #expect(DreamderHeadless.suppressedModals.contains("paste replacement failure"))
        }
    }
}
