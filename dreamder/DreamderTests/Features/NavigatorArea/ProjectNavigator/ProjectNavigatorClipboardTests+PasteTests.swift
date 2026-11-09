import AppKit
import Foundation
import Testing
@testable import Dreamder

extension ProjectNavigatorClipboardTests {
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
            let textFile = try harness.file("a.txt")
            let markdownFile = try harness.file("b.md")
            harness.select([textFile, markdownFile])

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
}
