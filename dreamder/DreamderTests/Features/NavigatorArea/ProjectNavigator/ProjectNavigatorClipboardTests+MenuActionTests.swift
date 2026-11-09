import AppKit
import Foundation
import Testing
@testable import Dreamder

extension ProjectNavigatorClipboardTests {
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
            let textFile = try harness.file("a.txt")
            harness.controller.clipboard.clear()
            let empty = harness.buildMenu(clicking: textFile)
            #expect(harness.menuItem(titled: "Paste", in: empty)?.isEnabled == false)

            harness.writeClipboard(["b.md"], cut: false)
            let withFiles = harness.buildMenu(clicking: textFile)
            #expect(harness.menuItem(titled: "Paste", in: withFiles)?.isEnabled == true)

            harness.pasteboard.replaceContents(withText: "text")
            let withText = harness.buildMenu(clicking: textFile)
            #expect(harness.menuItem(titled: "Paste", in: withText)?.isEnabled == true)
        }
    }

    @Test
    func cutMenuItemIsDisabledWhenTheRootIsSelected() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let textFile = try harness.file("a.txt")
            harness.select([textFile])
            let plain = harness.buildMenu(clicking: textFile)
            #expect(harness.menuItem(titled: "Cut", in: plain)?.isEnabled == true)
            #expect(harness.menuItem(titled: "Copy", in: plain)?.isEnabled == true)

            harness.select([harness.rootFile, textFile])
            let withRoot = harness.buildMenu(clicking: textFile)
            #expect(harness.menuItem(titled: "Cut", in: withRoot)?.isEnabled == false)
            #expect(harness.menuItem(titled: "Copy", in: withRoot)?.isEnabled == true)
        }
    }

    @Test
    func copyMenuActionWritesSelectionInPathOrderRegardlessOfSelectionOrder() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let textFile = try harness.file("a.txt")
            let markdownFile = try harness.file("b.md")
            harness.select([markdownFile, textFile])
            let menu = harness.buildMenu(clicking: markdownFile)

            try harness.perform("Copy", in: menu)

            #expect(pasteboardNames(harness) == ["a.txt", "b.md"])
            #expect(harness.controller.clipboard.isCut == false)
        }
    }

    @Test
    func cutMenuActionWritesACutClipboardAndPasteMenuActionMovesIt() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let textFile = try harness.file("a.txt")
            let markdownFile = try harness.file("b.md")
            let empty = try harness.file("Empty")
            harness.select([markdownFile, textFile])
            let cutMenu = harness.buildMenu(clicking: textFile)

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
            let textFile = try harness.file("a.txt")
            harness.editor.openTab(file: textFile, asTemporary: false)
            harness.controller.cutToClipboard([textFile])

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
            let textFile = try harness.file("a.txt")
            #expect(harness.childNames(of: harness.rootFile).contains("copied-direct.txt") == false)

            try harness.fileManager.copy(file: textFile, to: harness.url("copied-direct.txt"))

            #expect(harness.childNames(of: harness.rootFile).contains("copied-direct.txt"))
            #expect(throws: (any Error).self) {
                try harness.fileManager.copy(file: textFile, to: harness.url("copied-direct.txt"))
            }
        }
    }

    @Test
    func clipboardActionsOfAnOutlineViewWithoutAControllerDoNothing() {
        let outline = ProjectNavigatorNSOutlineView()
        let pasteItem = NSMenuItem(
            title: "Paste",
            action: #selector(ProjectNavigatorNSOutlineView.paste(_:)),
            keyEquivalent: ""
        )

        outline.copy(nil)
        outline.cut(nil)
        outline.paste(nil)

        #expect(outline.delegate == nil)
        #expect(outline.selectedRowIndexes.isEmpty)
        #expect(!outline.validateMenuItem(pasteItem))
    }
}
