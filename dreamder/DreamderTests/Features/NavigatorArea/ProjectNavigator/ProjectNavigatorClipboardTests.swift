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

    static let folders = ["Sources", "Sources/Inner", "Empty", "Locked"]
    static let files = [
        "a.txt", "b.md", "Makefile", "archive.tar.gz",
        "Sources/main.swift", "Sources/Inner/deep.txt", "Locked/x.txt"
    ]

    func pasteboardNames(_ harness: Harness) -> [String] {
        ProjectNavigatorClipboard(pasteboard: harness.pasteboard).fileURLs.map(\.lastPathComponent)
    }

    func modalCount() -> Int {
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
}
