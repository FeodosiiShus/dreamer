import AppKit
import Foundation
import Testing
@testable import Dreamder

extension ProjectNavigatorClipboardTests {
    @Test
    func cutOfOnlyTheRootLeavesTheClipboardUntouched() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            harness.writeClipboard(["a.txt"], cut: false)

            harness.controller.cutToClipboard([harness.rootFile])

            #expect(pasteboardNames(harness) == ["a.txt"])
            #expect(harness.controller.clipboard.isCut == false)
        }
    }

    @Test
    func cutExcludesTheRootButKeepsOtherSelectedItems() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            harness.controller.cutToClipboard([harness.rootFile, try harness.file("a.txt")])

            #expect(pasteboardNames(harness) == ["a.txt"])
            #expect(harness.controller.clipboard.isCut)
        }
    }

    @Test
    func cutAndPasteMovesTheItemClearsTheClipboardAndSelectsIt() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files, loadsTree: true) { harness in
            try harness.expand("Sources")
            let moved = try harness.file("Sources/main.swift")
            harness.outlineView.expandItem(harness.rootFile)
            harness.select([moved])

            harness.outlineView.cut(nil)
            #expect(harness.controller.clipboard.isCut)
            harness.outlineView.deselectAll(nil)
            await harness.pasteAndWait(into: harness.rootFile)

            #expect(harness.exists("Sources/main.swift") == false)
            #expect(try harness.contents("main.swift") == "content of Sources/main.swift\n")
            #expect(harness.controller.clipboard.hasFiles == false)
            #expect(harness.controller.clipboard.isCut == false)
            #expect(harness.controller.selectedFiles.map(\.name) == ["main.swift"])
        }
    }

    @Test
    func cutAndPasteIntoTheSameParentIsANoOpAndKeepsTheClipboard() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            harness.controller.cutToClipboard([try harness.file("a.txt")])

            await harness.pasteAndWait(into: harness.rootFile)

            #expect(try harness.contents("a.txt") == "content of a.txt\n")
            #expect(try harness.names(in: "").filter { $0.hasPrefix("a ") }.isEmpty)
            #expect(harness.controller.clipboard.isCut)
            #expect(pasteboardNames(harness) == ["a.txt"])
        }
    }

    @Test
    func cutConflictReplacesWhenConfirmed() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            try harness.write("cutreplace.txt", "new\n")
            try harness.write("Sources/cutreplace.txt", "old\n")
            harness.reload()
            var asked: [String] = []
            harness.controller.confirmReplace = { name in
                asked.append(name)
                return true
            }
            harness.controller.cutToClipboard([try harness.file("cutreplace.txt")])

            await harness.pasteAndWait(into: try harness.file("Sources"))

            #expect(asked == ["cutreplace.txt"])
            #expect(harness.exists("cutreplace.txt") == false)
            #expect(try harness.contents("Sources/cutreplace.txt") == "new\n")
            #expect(harness.controller.clipboard.hasFiles == false)
        }
    }

    @Test
    func cutConflictKeepsBothWhenDeclined() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            try harness.write("cutkeep.txt", "new\n")
            try harness.write("Sources/cutkeep.txt", "old\n")
            harness.reload()
            harness.controller.confirmReplace = { _ in false }
            harness.controller.cutToClipboard([try harness.file("cutkeep.txt")])

            await harness.pasteAndWait(into: try harness.file("Sources"))

            #expect(try harness.contents("cutkeep.txt") == "new\n")
            #expect(try harness.contents("Sources/cutkeep.txt") == "old\n")
            #expect(harness.controller.clipboard.isCut)
            #expect(pasteboardNames(harness) == ["cutkeep.txt"])
        }
    }

    @Test
    func cutConflictWithDefaultDialogIsCancelledHeadless() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            try harness.write("cutdialog-unique.txt", "new\n")
            try harness.write("Sources/cutdialog-unique.txt", "old\n")
            harness.reload()
            #expect(harness.controller.confirmReplace == nil)
            harness.controller.cutToClipboard([try harness.file("cutdialog-unique.txt")])

            await harness.pasteAndWait(into: try harness.file("Sources"))

            #expect(DreamderHeadless.suppressedModals.contains {
                $0.contains("cutdialog-unique.txt") && $0.contains("already exists in the destination folder")
            })
            #expect(try harness.contents("cutdialog-unique.txt") == "new\n")
            #expect(try harness.contents("Sources/cutdialog-unique.txt") == "old\n")
            #expect(harness.controller.clipboard.isCut)
        }
    }

    @Test
    func copyingAFolderIntoItselfIsRejected() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let sources = try harness.file("Sources")
            let before = try harness.names(in: "Sources")
            harness.controller.copyToClipboard([sources])

            await harness.pasteAndWait(into: sources)

            #expect(DreamderHeadless.suppressedModals.contains("Cannot paste Sources into itself"))
            #expect(try harness.names(in: "Sources") == before)
            #expect(try harness.names(in: "").contains("Sources (1)") == false)
        }
    }

    @Test
    func copyingAFolderIntoADescendantIsRejected() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let sources = try harness.file("Sources")
            let inner = try harness.file("Sources/Inner")
            let before = try harness.names(in: "Sources/Inner")
            harness.controller.copyToClipboard([sources])

            await harness.pasteAndWait(into: inner)

            #expect(DreamderHeadless.suppressedModals.contains("Cannot paste Sources into itself"))
            #expect(try harness.names(in: "Sources/Inner") == before)
        }
    }

    @Test
    func cuttingAFolderIntoItselfOrADescendantIsRejected() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let sources = try harness.file("Sources")
            let inner = try harness.file("Sources/Inner")
            harness.controller.cutToClipboard([sources])

            await harness.pasteAndWait(into: sources)
            await harness.pasteAndWait(into: inner)

            #expect(DreamderHeadless.suppressedModals.contains("Cannot paste Sources into itself"))
            #expect(harness.exists("Sources/main.swift"))
            #expect(harness.exists("Sources/Inner/deep.txt"))
            #expect(harness.exists("Sources/Inner/Sources") == false)
            #expect(harness.controller.clipboard.isCut)
        }
    }

    @Test
    func vanishedSourcesAreSkippedSilently() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            try harness.write("vanishing.txt")
            harness.writeClipboard(["vanishing.txt", "b.md"], cut: false)
            try harness.remove("vanishing.txt")

            await harness.pasteAndWait(into: try harness.file("Empty"))

            #expect(try harness.names(in: "Empty") == ["b.md"])
            #expect(!DreamderHeadless.suppressedModals.contains { $0.contains("vanishing.txt") })
        }
    }

    @Test
    func vanishedCutSourceLeavesTheClipboardIntact() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            try harness.write("vanishing-cut.txt")
            harness.writeClipboard(["vanishing-cut.txt"], cut: true)
            try harness.remove("vanishing-cut.txt")

            await harness.pasteAndWait(into: try harness.file("Empty"))

            #expect(try harness.names(in: "Empty").isEmpty)
            #expect(harness.controller.clipboard.isCut)
        }
    }

    @Test
    func copyIntoLockedFolderSurfacesAnAlertAndKeepsTheSource() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            try harness.lock("Locked")
            let before = modalCount()
            harness.controller.copyToClipboard([try harness.file("a.txt")])

            await harness.pasteAndWait(into: try harness.file("Locked"))

            #expect(modalCount() > before)
            #expect(try harness.names(in: "Locked") == ["x.txt"])
            #expect(harness.exists("a.txt"))
        }
    }

    @Test
    func cutIntoLockedFolderSurfacesAnAlertAndKeepsTheSourceAndClipboard() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            try harness.lock("Locked")
            let before = modalCount()
            harness.controller.cutToClipboard([try harness.file("a.txt")])

            await harness.pasteAndWait(into: try harness.file("Locked"))

            #expect(modalCount() > before)
            #expect(harness.exists("a.txt"))
            #expect(try harness.names(in: "Locked") == ["x.txt"])
            #expect(harness.controller.clipboard.isCut)
        }
    }

    @Test
    func copyIntoAFolderThatCannotBeListedStillCopiesAndReportsTheRefreshFailure() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files, loadsTree: true) { harness in
            let empty = try harness.file("Empty")
            harness.controller.copyToClipboard([try harness.file("a.txt")])
            try harness.lock("Empty", permissions: 0o300)
            let before = modalCount()

            await harness.pasteAndWait(into: empty)

            #expect(modalCount() > before)
            #expect(harness.exists("Empty/a.txt"))
            #expect(harness.exists("a.txt"))
        }
    }
}
