import AppKit
import Foundation
import Testing
@testable import Dreamder

@Suite
struct CopyNamingTests {
    private func uniqueName(
        _ name: String,
        isDirectory: Bool = false,
        existing: Set<String>
    ) -> String {
        let directory = URL(fileURLWithPath: "/tmp/copy-naming", isDirectory: true)
        let source = URL(fileURLWithPath: "/elsewhere/\(name)")
        let result = CopyNaming.uniqueURL(for: source, isDirectory: isDirectory, in: directory) {
            existing.contains($0.lastPathComponent)
        }
        return result.lastPathComponent
    }

    @Test
    func freeNameIsKeptAsIs() {
        #expect(uniqueName("a.txt", existing: []) == "a.txt")
    }

    @Test
    func conflictingFileGetsNumberedBeforeExtension() {
        #expect(uniqueName("a.txt", existing: ["a.txt"]) == "a (1).txt")
        #expect(uniqueName("a.txt", existing: ["a.txt", "a (1).txt"]) == "a (2).txt")
    }

    @Test
    func extensionlessNameGetsNumberAppended() {
        #expect(uniqueName("Makefile", existing: ["Makefile"]) == "Makefile (1)")
    }

    @Test
    func dottedNameKeepsOnlyTheLastExtensionAfterTheNumber() {
        #expect(uniqueName("archive.tar.gz", existing: ["archive.tar.gz"]) == "archive.tar (1).gz")
    }

    @Test
    func directoryNeverSplitsItsExtension() {
        #expect(uniqueName("Sources", isDirectory: true, existing: ["Sources"]) == "Sources (1)")
        #expect(uniqueName("v1.2", isDirectory: true, existing: ["v1.2"]) == "v1.2 (1)")
    }

    @Test
    func existingCounterSuffixIsReplacedNotStacked() {
        #expect(uniqueName("a (1).txt", existing: ["a.txt", "a (1).txt"]) == "a (2).txt")
        #expect(uniqueName("Sources (3)", isDirectory: true, existing: ["Sources (3)"]) == "Sources (1)")
    }

    @Test
    func counterOnlyNameKeepsItsStem() {
        #expect(uniqueName(" (1)", existing: [" (1)"]) == " (1) (1)")
    }

    @Test
    func counterWithoutLeadingSpaceIsPartOfTheStem() {
        #expect(uniqueName("x(1).txt", existing: ["x(1).txt"]) == "x(1) (1).txt")
    }
}

@MainActor
@Suite(.uiGate)
struct ProjectNavigatorClipboardTests {
    typealias Harness = ProjectNavigatorControllerHarness

    private static let folders = ["Sources", "Sources/Inner", "Empty", "Locked"]
    private static let files = [
        "a.txt", "b.md", "Makefile", "archive.tar.gz",
        "Sources/main.swift", "Sources/Inner/deep.txt", "Locked/x.txt"
    ]

    private func pasteboardNames(_ harness: Harness) -> [String] {
        ProjectNavigatorClipboard(pasteboard: harness.pasteboard).fileURLs.map(\.lastPathComponent)
    }

    private func modalCount() -> Int {
        DreamderHeadless.suppressedModals.count
    }

    @Test
    func clipboardReportsNoFilesAndNoTextWhenEmpty() {
        let clipboard = ProjectNavigatorClipboard(pasteboard: InMemoryPasteboard())

        #expect(clipboard.fileURLs.isEmpty)
        #expect(clipboard.hasFiles == false)
        #expect(clipboard.isCut == false)
        #expect(clipboard.text == nil)
    }

    @Test
    func clipboardTextIsNilForEmptyStringAndPresentOtherwise() {
        let board = InMemoryPasteboard()
        let clipboard = ProjectNavigatorClipboard(pasteboard: board)

        board.replaceContents(withText: "")
        #expect(clipboard.text == nil)

        board.replaceContents(withText: "hello")
        #expect(clipboard.text == "hello")
    }

    @Test
    func clipboardWritesTheURLsAndRemembersWhetherTheyWereCut() {
        let board = InMemoryPasteboard()
        let clipboard = ProjectNavigatorClipboard(pasteboard: board)
        let urls = [URL(fileURLWithPath: "/tmp/one.txt"), URL(fileURLWithPath: "/tmp/two.txt")]

        clipboard.write(urls, isCut: false)
        #expect(clipboard.fileURLs == urls)
        #expect(clipboard.hasFiles)
        #expect(clipboard.isCut == false)

        clipboard.write(urls, isCut: true)
        #expect(clipboard.fileURLs == urls)
        #expect(clipboard.isCut)
    }

    @Test
    func clipboardClearRemovesEverything() {
        let clipboard = ProjectNavigatorClipboard(pasteboard: InMemoryPasteboard())
        clipboard.write([URL(fileURLWithPath: "/tmp/one.txt")], isCut: true)

        clipboard.clear()

        #expect(clipboard.hasFiles == false)
        #expect(clipboard.isCut == false)
    }

    @Test
    func copyFilePastesIntoFolderKeepingTheSource() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let a = try harness.file("a.txt")
            let sources = try harness.file("Sources")

            harness.controller.copyToClipboard([a])
            #expect(harness.controller.clipboard.hasFiles)
            #expect(harness.controller.clipboard.isCut == false)
            await harness.pasteAndWait(into: sources)

            #expect(harness.exists("a.txt"))
            #expect(try harness.contents("Sources/a.txt") == "content of a.txt\n")
            #expect(harness.controller.clipboard.hasFiles)
        }
    }

    @Test
    func copyFolderWithContentPastesRecursively() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let sources = try harness.file("Sources")
            let empty = try harness.file("Empty")

            harness.controller.copyToClipboard([sources])
            await harness.pasteAndWait(into: empty)

            #expect(try harness.contents("Empty/Sources/main.swift") == "content of Sources/main.swift\n")
            #expect(try harness.contents("Empty/Sources/Inner/deep.txt") == "content of Sources/Inner/deep.txt\n")
            #expect(harness.exists("Sources/main.swift"))
        }
    }

    @Test
    func repeatedCopyIntoTheSameFolderNumbersTheCopies() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let root = harness.rootFile
            harness.controller.copyToClipboard([try harness.file("a.txt")])

            await harness.pasteAndWait(into: root)
            await harness.pasteAndWait(into: root)

            let names = try harness.names(in: "")
            #expect(names.contains("a (1).txt"))
            #expect(names.contains("a (2).txt"))
        }
    }

    @Test
    func copyOfExtensionlessDottedAndFolderNamesAreNumberedCorrectly() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let root = harness.rootFile
            harness.controller.copyToClipboard([
                try harness.file("Makefile"),
                try harness.file("archive.tar.gz"),
                try harness.file("Sources")
            ])

            await harness.pasteAndWait(into: root)

            let names = try harness.names(in: "")
            #expect(names.contains("Makefile (1)"))
            #expect(names.contains("archive.tar (1).gz"))
            #expect(names.contains("Sources (1)"))
            #expect(try harness.contents("Sources (1)/Inner/deep.txt") == "content of Sources/Inner/deep.txt\n")
        }
    }

    @Test
    func copyOfAnAlreadyNumberedFileUsesTheNextFreeNumber() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            try harness.write("a (1).txt", "numbered\n")
            harness.reload()
            harness.controller.copyToClipboard([try harness.file("a (1).txt")])

            await harness.pasteAndWait(into: harness.rootFile)

            #expect(try harness.contents("a (2).txt") == "numbered\n")
            #expect(try harness.contents("a (1).txt") == "numbered\n")
        }
    }

    @Test
    func copyOfSeveralSelectedItemsUsesOutlineOrderAndPastesAll() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let a = try harness.file("a.txt")
            let b = try harness.file("b.md")
            let empty = try harness.file("Empty")
            harness.select([b, a])

            harness.outlineView.copy(nil)

            let expected = harness.outlineView.selectedRowIndexes
                .compactMap { (harness.outlineView.item(atRow: $0) as? CEWorkspaceFile)?.name }
            #expect(pasteboardNames(harness) == expected)
            #expect(Set(expected) == ["a.txt", "b.md"])

            await harness.pasteAndWait(into: empty)
            #expect(try harness.names(in: "Empty") == ["a.txt", "b.md"])
        }
    }

    @Test
    func copyWithEmptySelectionLeavesTheClipboardUntouched() throws {
        let board = InMemoryPasteboard()
        board.replaceContents(withText: "keep")
        let controller = ProjectNavigatorViewController()
        controller.pasteboard = board

        controller.copyToClipboard([])

        #expect(controller.clipboard.text == "keep")
        #expect(controller.clipboard.hasFiles == false)
    }

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

    @Test
    func pastingNextToAParentlessFileDoesNothing() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            harness.writeClipboard(["a.txt"], cut: false)
            let ghost = CEWorkspaceFile(url: harness.url("ghost-anchor.txt"))

            let pasted = harness.controller.pasteFromClipboard(into: ghost)

            #expect(!pasted)
            #expect(harness.controller.pasteTask == nil)
            #expect(harness.controller.pendingCreation == nil)
        }
    }

    @Test
    func copiedFileFromOutsideTheWorkspacePastesAsCopy() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let external = try makeTemporaryDirectory(label: "ClipboardExternalCopy")
            defer { removeTemporaryDirectory(external) }
            let source = external.appending(path: "outside-copy.txt")
            try "outside\n".write(to: source, atomically: true, encoding: .utf8)
            harness.controller.clipboard.write([source], isCut: false)

            await harness.pasteAndWait(into: try harness.file("Empty"))

            #expect(try harness.contents("Empty/outside-copy.txt") == "outside\n")
            #expect(FileManager.default.fileExists(atPath: source.path))
        }
    }

    @Test
    func cutFileFromOutsideTheWorkspacePastesAsMove() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let external = try makeTemporaryDirectory(label: "ClipboardExternalCut")
            defer { removeTemporaryDirectory(external) }
            let source = external.appending(path: "outside-cut.txt")
            try "outside\n".write(to: source, atomically: true, encoding: .utf8)
            harness.controller.clipboard.write([source], isCut: true)

            await harness.pasteAndWait(into: try harness.file("Empty"))

            #expect(try harness.contents("Empty/outside-cut.txt") == "outside\n")
            #expect(FileManager.default.fileExists(atPath: source.path) == false)
            #expect(harness.controller.clipboard.hasFiles == false)
        }
    }

    @Test
    func pasteTargetIsTheParentOfASelectedFileAndTheFolderItselfOtherwise() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            harness.controller.copyToClipboard([try harness.file("a.txt")])

            #expect(harness.controller.pasteFromClipboard(into: try harness.file("Sources/main.swift")))
            await harness.controller.pasteTask?.value
            #expect(harness.exists("Sources/a.txt"))

            #expect(harness.controller.pasteFromClipboard(into: try harness.file("Empty")))
            await harness.controller.pasteTask?.value
            #expect(harness.exists("Empty/a.txt"))

            #expect(harness.controller.pasteFromClipboard(into: nil))
            await harness.controller.pasteTask?.value
            #expect(harness.exists("a (1).txt"))

            #expect(harness.controller.pasteFromClipboard(into: harness.rootFile))
            await harness.controller.pasteTask?.value
            #expect(harness.exists("a (2).txt"))
        }
    }

    @Test
    func pasteWithNothingOnTheClipboardReturnsFalse() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            harness.controller.clipboard.clear()

            #expect(harness.controller.pasteFromClipboard(into: nil) == false)
            #expect(harness.controller.canPaste == false)
            #expect(harness.controller.pendingCreation == nil)
        }
    }

    @Test
    func pasteOfTextStartsAnInlineFileCreationCarryingTheText() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            harness.pasteboard.replaceContents(withText: "snippet")
            let sources = try harness.file("Sources")

            #expect(harness.controller.canPaste)
            #expect(harness.controller.pasteFromClipboard(into: sources))

            let pending = try #require(harness.controller.pendingCreation)
            #expect(pending.kind == .file)
            #expect(pending.folder === sources)
            #expect(pending.contents == Data("snippet".utf8))
            #expect(harness.controller.pasteTask == nil)
            harness.controller.cancelCreation()
        }
    }

    @Test
    func pasteOfFilesStartsAPasteTask() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            harness.writeClipboard(["b.md"], cut: false)
            #expect(harness.controller.canPaste)

            let empty = try harness.file("Empty")
            #expect(harness.controller.pasteFromClipboard(into: empty))
            #expect(harness.controller.pasteTask != nil)
            await harness.controller.pasteTask?.value

            let names = try harness.names(in: "Empty")
            #expect(names == ["b.md"])
        }
    }

    @Test
    func selectedFilesFollowsTheOutlineSelection() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            #expect(harness.controller.selectedFiles.isEmpty)
            let a = try harness.file("a.txt")
            let b = try harness.file("b.md")
            harness.select([a, b])

            #expect(Set(harness.controller.selectedFiles.map(\.name)) == ["a.txt", "b.md"])
        }
    }

    @Test
    func pasteWithoutWorkspaceDoesNothing() async throws {
        let controller = ProjectNavigatorViewController()
        let folder = CEWorkspaceFile(url: URL(fileURLWithPath: "/tmp/no-workspace"))

        await controller.paste(into: folder)

        #expect(controller.pasteFromClipboard(into: nil) == false)
    }

    @Test
    func outlineResponderMethodsDoNothingWithoutController() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            harness.select([try harness.file("a.txt")])
            let delegate = harness.outlineView.delegate
            harness.outlineView.delegate = nil
            defer { harness.outlineView.delegate = delegate }

            harness.outlineView.copy(nil)
            harness.outlineView.cut(nil)
            harness.outlineView.paste(nil)

            #expect(harness.controller.clipboard.hasFiles == false)
        }
    }

    @Test
    func outlinePasteUsesTheFirstSelectedItemAsTarget() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            harness.writeClipboard(["b.md"], cut: false)
            harness.select([try harness.file("Empty")])

            harness.outlineView.paste(nil)
            await harness.controller.pasteTask?.value

            #expect(try harness.names(in: "Empty") == ["b.md"])
        }
    }

    @Test
    func outlineMenuValidationReflectsSelectionAndClipboard() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let copyItem = NSMenuItem(
                title: "Copy",
                action: #selector(ProjectNavigatorNSOutlineView.copy(_:)),
                keyEquivalent: ""
            )
            let cutItem = NSMenuItem(
                title: "Cut",
                action: #selector(ProjectNavigatorNSOutlineView.cut(_:)),
                keyEquivalent: ""
            )
            let pasteItem = NSMenuItem(
                title: "Paste",
                action: #selector(ProjectNavigatorNSOutlineView.paste(_:)),
                keyEquivalent: ""
            )
            let newFromClipboard = NSMenuItem(
                title: "New",
                action: #selector(ProjectNavigatorMenu.newFileFromClipboard),
                keyEquivalent: ""
            )
            let unrelated = NSMenuItem(title: "Other", action: nil, keyEquivalent: "")

            harness.outlineView.deselectAll(nil)
            #expect(harness.outlineView.validateMenuItem(copyItem) == false)
            #expect(harness.outlineView.validateMenuItem(cutItem) == false)
            #expect(harness.outlineView.validateMenuItem(newFromClipboard) == false)
            #expect(harness.outlineView.validateMenuItem(pasteItem) == false)
            #expect(harness.outlineView.validateMenuItem(unrelated) == false)

            harness.select([try harness.file("a.txt")])
            harness.writeClipboard(["b.md"], cut: false)
            #expect(harness.outlineView.validateMenuItem(copyItem))
            #expect(harness.outlineView.validateMenuItem(cutItem))
            #expect(harness.outlineView.validateMenuItem(newFromClipboard))
            #expect(harness.outlineView.validateMenuItem(pasteItem))
        }
    }

    @Test
    func pasteMenuItemIsEnabledOnlyWhenTheClipboardHasFilesOrText() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let a = try harness.file("a.txt")
            harness.controller.clipboard.clear()
            let empty = harness.buildMenu(clicking: a)
            #expect(harness.menuItem(titled: "Paste", in: empty)?.isEnabled == false)

            harness.writeClipboard(["b.md"], cut: false)
            let withFiles = harness.buildMenu(clicking: a)
            #expect(harness.menuItem(titled: "Paste", in: withFiles)?.isEnabled == true)

            harness.pasteboard.replaceContents(withText: "text")
            let withText = harness.buildMenu(clicking: a)
            #expect(harness.menuItem(titled: "Paste", in: withText)?.isEnabled == true)
        }
    }

    @Test
    func cutMenuItemIsDisabledWhenTheRootIsSelected() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let a = try harness.file("a.txt")
            harness.select([a])
            let plain = harness.buildMenu(clicking: a)
            #expect(harness.menuItem(titled: "Cut", in: plain)?.isEnabled == true)
            #expect(harness.menuItem(titled: "Copy", in: plain)?.isEnabled == true)

            harness.select([harness.rootFile, a])
            let withRoot = harness.buildMenu(clicking: a)
            #expect(harness.menuItem(titled: "Cut", in: withRoot)?.isEnabled == false)
            #expect(harness.menuItem(titled: "Copy", in: withRoot)?.isEnabled == true)
        }
    }

    @Test
    func copyMenuActionWritesSelectionInPathOrderRegardlessOfSelectionOrder() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let a = try harness.file("a.txt")
            let b = try harness.file("b.md")
            harness.select([b, a])
            let menu = harness.buildMenu(clicking: b)

            try harness.perform("Copy", in: menu)

            #expect(pasteboardNames(harness) == ["a.txt", "b.md"])
            #expect(harness.controller.clipboard.isCut == false)
        }
    }

    @Test
    func cutMenuActionWritesACutClipboardAndPasteMenuActionMovesIt() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let a = try harness.file("a.txt")
            let b = try harness.file("b.md")
            let empty = try harness.file("Empty")
            harness.select([b, a])
            let cutMenu = harness.buildMenu(clicking: a)

            try harness.perform("Cut", in: cutMenu)
            #expect(harness.controller.clipboard.isCut)
            #expect(pasteboardNames(harness) == ["a.txt", "b.md"])

            harness.select([empty])
            let pasteMenu = harness.buildMenu(clicking: empty)
            try harness.perform("Paste", in: pasteMenu)
            await harness.controller.pasteTask?.value

            #expect(try harness.names(in: "Empty") == ["a.txt", "b.md"])
            #expect(harness.exists("a.txt") == false)
            #expect(harness.exists("b.md") == false)
        }
    }

    @Test
    func menuActionsWithoutSenderDoNothing() async throws {
        let menu = ProjectNavigatorMenu(ProjectNavigatorViewController())

        menu.cutFiles()
        menu.copyFiles()
        menu.pasteFiles()

        #expect(menu.item == nil)
    }

    @Test
    func cutOfAnOpenFileRetargetsItsTab() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let a = try harness.file("a.txt")
            harness.editor.openTab(file: a, asTemporary: false)
            harness.controller.cutToClipboard([a])

            await harness.pasteAndWait(into: try harness.file("Sources"))

            #expect(harness.editor.tabs.map(\.file.url.lastPathComponent) == ["a.txt"])
            let selected = try #require(harness.editor.selectedTab)
            #expect(selected.file.url.deletingLastPathComponent().lastPathComponent == "Sources")
            #expect(selected.file.url.lastPathComponent == "a.txt")
        }
    }

    @Test
    func fileManagerCopyRefreshesTheDestinationDirectoryImmediately() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let a = try harness.file("a.txt")
            #expect(harness.childNames(of: harness.rootFile).contains("copied-direct.txt") == false)

            try harness.fileManager.copy(file: a, to: harness.url("copied-direct.txt"))

            #expect(harness.childNames(of: harness.rootFile).contains("copied-direct.txt"))
            #expect(throws: (any Error).self) {
                try harness.fileManager.copy(file: a, to: harness.url("copied-direct.txt"))
            }
        }
    }
}
