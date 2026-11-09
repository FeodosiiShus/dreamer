import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct ProjectNavigatorReplaceSafetyTests {
    typealias Harness = ProjectNavigatorControllerHarness

    static let twinFolders = ["Twin/Twin"]
    static let twinFiles = ["Twin/Twin/keep.txt"]
    static let twinContents = "content of Twin/Twin/keep.txt\n"
    static let replaceFolders = ["Incoming/Item", "Library/Item"]
    static let replaceFiles = ["Incoming/Item/new.txt", "Library/Item/old.txt"]
    static let newContents = "content of Incoming/Item/new.txt\n"
    static let oldContents = "content of Library/Item/old.txt\n"

    func mask(copying: Bool) -> NSDragOperation {
        copying ? .copy : .move
    }

    func marker(_ text: String) -> NSError {
        NSError(
            domain: "ProjectNavigatorReplaceSafetyTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: text]
        )
    }

    func modalCount() -> Int {
        DreamderHeadless.suppressedModals.count
    }

    func expectTwinIntact(_ harness: Harness) throws {
        #expect(try harness.names(in: "").contains("Twin"))
        #expect(try harness.names(in: "Twin") == ["Twin"])
        #expect(try harness.names(in: "Twin/Twin") == ["keep.txt"])
        #expect(try harness.contents("Twin/Twin/keep.txt") == Self.twinContents)
    }

    func expectReplaceFixtureUntouched(_ harness: Harness) throws {
        #expect(try harness.names(in: "Incoming") == ["Item"])
        #expect(try harness.names(in: "Incoming/Item") == ["new.txt"])
        #expect(try harness.names(in: "Library") == ["Item"])
        #expect(try harness.names(in: "Library/Item") == ["old.txt"])
        #expect(try harness.contents("Incoming/Item/new.txt") == Self.newContents)
        #expect(try harness.contents("Library/Item/old.txt") == Self.oldContents)
    }

    @Test(arguments: [false, true])
    func droppingAFolderOntoTheFolderThatContainsItIsRejectedBeforeAskingToReplace(copying: Bool) async throws {
        try await Harness.run(folders: Self.twinFolders, files: Self.twinFiles) { harness in
            var asked: [String] = []
            harness.controller.confirmReplace = { name in
                asked.append(name)
                return true
            }
            let inner = try harness.file("Twin/Twin")
            let drop = harness.dropInfo(urls: [inner.url], mask: mask(copying: copying))

            let accepted = harness.acceptDrop(drop, onto: harness.rootFile)

            #expect(!accepted)
            #expect(asked.isEmpty)
            try expectTwinIntact(harness)
        }
    }

    @Test(arguments: [false, true])
    func droppingAFolderIntoItsOwnDescendantIsRejected(copying: Bool) async throws {
        try await Harness.run(folders: Self.twinFolders, files: Self.twinFiles) { harness in
            var asked: [String] = []
            harness.controller.confirmReplace = { name in
                asked.append(name)
                return true
            }
            let outer = try harness.file("Twin")
            let inner = try harness.file("Twin/Twin")
            let drop = harness.dropInfo(urls: [outer.url], mask: mask(copying: copying))

            let accepted = harness.acceptDrop(drop, onto: inner)

            #expect(!accepted)
            #expect(asked.isEmpty)
            try expectTwinIntact(harness)
        }
    }

    @Test
    func droppingAFolderWithATrailingSlashOntoItselfIsRejected() async throws {
        try await Harness.run(folders: Self.twinFolders, files: Self.twinFiles) { harness in
            let outer = try harness.file("Twin")
            let slashed = URL(filePath: outer.url.path(percentEncoded: false), directoryHint: .isDirectory)

            let accepted = harness.acceptDrop(harness.dropInfo(urls: [slashed]), onto: outer)

            #expect(!accepted)
            try expectTwinIntact(harness)
        }
    }

    @Test
    func cuttingAFolderAndPastingItIntoTheFolderThatContainsItIsRejectedBeforeAskingToReplace() async throws {
        try await Harness.run(folders: Self.twinFolders, files: Self.twinFiles) { harness in
            var asked: [String] = []
            harness.controller.confirmReplace = { name in
                asked.append(name)
                return true
            }
            harness.controller.cutToClipboard([try harness.file("Twin/Twin")])

            await harness.pasteAndWait(into: harness.rootFile)

            #expect(asked.isEmpty)
            #expect(DreamderHeadless.suppressedModals.contains("Cannot paste Twin into itself"))
            #expect(harness.controller.clipboard.isCut)
            try expectTwinIntact(harness)
        }
    }

    @Test
    func copyingAnInnerFolderIntoTheFolderThatContainsItKeepsBothAndNumbersTheCopy() async throws {
        try await Harness.run(folders: Self.twinFolders, files: Self.twinFiles) { harness in
            var asked: [String] = []
            harness.controller.confirmReplace = { name in
                asked.append(name)
                return true
            }
            harness.controller.copyToClipboard([try harness.file("Twin/Twin")])

            await harness.pasteAndWait(into: harness.rootFile)

            #expect(asked.isEmpty)
            let rootNames = try harness.names(in: "")
            #expect(rootNames.contains("Twin"))
            #expect(rootNames.contains("Twin (1)"))
            #expect(try harness.contents("Twin/Twin/keep.txt") == Self.twinContents)
            #expect(try harness.contents("Twin (1)/keep.txt") == Self.twinContents)
        }
    }
}
