import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct ProjectNavigatorMenuActionsTests {
    typealias Harness = ProjectNavigatorControllerHarness

    private static let folders = ["Sources", "Empty", "Locked"]
    private static let files = ["a.txt", "b.md", "Sources/main.swift", "Locked/x.txt"]

    private func openMenu(_ harness: Harness, selecting selected: [CEWorkspaceFile], clicking clicked: CEWorkspaceFile)
        -> ProjectNavigatorMenu {
        harness.select(selected)
        return harness.buildMenu(clicking: clicked)
    }

    private func untitledNames(_ harness: Harness, in folder: String) throws -> [String] {
        try harness.names(in: folder).filter { $0.hasPrefix("untitled") }
    }

    @Test
    func showInFinderRevealsEverySelectedFile() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let a = try harness.file("a.txt")
            let b = try harness.file("b.md")
            let menu = openMenu(harness, selecting: [a, b], clicking: a)

            try harness.perform("Show in Finder", in: menu)

            #expect(DreamderHeadless.suppressedExternalOpens.contains(a.url.absoluteString))
            #expect(DreamderHeadless.suppressedExternalOpens.contains(b.url.absoluteString))
        }
    }

    @Test
    func openWithExternalEditorOpensEverySelectedFile() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let a = try harness.file("a.txt")
            let b = try harness.file("b.md")
            let menu = openMenu(harness, selecting: [a, b], clicking: b)

            try harness.perform("Open with External Editor", in: menu)

            #expect(DreamderHeadless.suppressedExternalOpens.contains(a.url.absoluteString))
            #expect(DreamderHeadless.suppressedExternalOpens.contains(b.url.absoluteString))
        }
    }

    @Test
    func openInTabOpensTheSelectedFilesInOutlineOrder() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files, loadsTree: true) { harness in
            try harness.expand("Sources")
            let a = try harness.file("a.txt")
            let b = try harness.file("b.md")
            let main = try harness.file("Sources/main.swift")
            let menu = openMenu(harness, selecting: [main, b, a], clicking: b)

            try harness.perform("Open in Tab", in: menu)

            let opened = harness.editor.tabs.map { $0.file.name }
            #expect(opened.contains("a.txt"))
            #expect(opened.contains("b.md"))
            #expect(opened.contains("main.swift"))
        }
    }

    @Test
    func newFileStartsAnInlineEntryInsideTheFolderWithoutCreatingAFile() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let sources = try harness.file("Sources")
            let menu = harness.buildMenu(clicking: sources)

            try harness.perform("New File...", in: menu)

            let pending = try #require(harness.controller.pendingCreation)
            #expect(pending.kind == .file)
            #expect(pending.folder == sources)
            #expect(try harness.names(in: "Sources") == ["main.swift"])
            #expect(harness.outlineView.isItemExpanded(sources))
            #expect(harness.placeholderCell?.textField?.stringValue == "")
            #expect(harness.window.firstResponder is NSTextView)
            #expect(try untitledNames(harness, in: "Sources").isEmpty)
            harness.window.makeFirstResponder(harness.outlineView)
        }
    }

    @Test
    func newFileNextToAFileLandsInItsParent() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let a = try harness.file("a.txt")
            let menu = harness.buildMenu(clicking: a)

            try harness.perform("New File...", in: menu)
            try harness.submitCreation("fresh.txt")

            #expect(harness.exists("fresh.txt"))
            #expect(harness.workspace.listenerModel.highlightedFileItem?.name == "fresh.txt")
            #expect(harness.editor.tabs.contains { $0.file.name == "fresh.txt" })
        }
    }

    @Test
    func newFileReportsAnErrorWhenTheFolderVanished() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let empty = try harness.file("Empty")
            let menu = harness.buildMenu(clicking: empty)
            try harness.perform("New File...", in: menu)
            try harness.remove("Empty")

            try harness.submitCreation("late.txt")

            #expect(!harness.exists("Empty"))
            #expect(harness.controller.pendingCreation == nil)
            #expect(harness.workspace.listenerModel.highlightedFileItem == nil)
        }
    }

    @Test
    func actionsWithoutAnItemDoNothing() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let before = try harness.names(in: "")
            harness.pasteboard.replaceContents(withText: "ignored")
            let menu = harness.buildMenu(clicking: nil)

            menu.newFile()
            menu.newFolder()
            menu.newFileFromClipboard()

            #expect(try harness.names(in: "") == before)
        }
    }

    @Test
    func renameFocusesTheNameFieldOfTheHighlightedRow() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let a = try harness.file("a.txt")
            let menu = harness.buildMenu(clicking: a)
            menu.renameFile()
            #expect(!(harness.window.firstResponder is NSTextView))

            harness.workspace.listenerModel.highlightedFileItem = harness.rootFile
            menu.renameFile()
            #expect(!(harness.window.firstResponder is NSTextView))

            let stray = CEWorkspaceFile(url: harness.url("not-in-outline.txt"))
            harness.workspace.listenerModel.highlightedFileItem = stray
            menu.renameFile()
            #expect(!(harness.window.firstResponder is NSTextView))

            let cell = try #require(harness.cell(for: a))
            harness.workspace.listenerModel.highlightedFileItem = a
            try harness.perform("Rename", in: menu)

            let editor = try #require(harness.window.firstResponder as? NSTextView)
            #expect(editor.delegate === cell.textField)
            harness.window.makeFirstResponder(nil)
        }
    }

    @Test
    func newFileFromClipboardStartsAnInlineEntryThatWritesTheClipboardText() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let sources = try harness.file("Sources")
            let menu = harness.buildMenu(clicking: sources)
            harness.pasteboard.replaceContents(withText: "from the clipboard")

            try harness.perform("New File from Clipboard", in: menu)
            #expect(try untitledNames(harness, in: "Sources").isEmpty)
            try harness.submitCreation("pasted.txt")

            #expect(try harness.contents("Sources/pasted.txt") == "from the clipboard")
            #expect(harness.workspace.listenerModel.highlightedFileItem?.name == "pasted.txt")
        }
    }

    @Test
    func newFileFromClipboardIgnoresAnEmptyClipboard() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let sources = try harness.file("Sources")
            let menu = harness.buildMenu(clicking: sources)
            harness.pasteboard.removeAllContents()

            try harness.perform("New File from Clipboard", in: menu)

            #expect(harness.controller.pendingCreation == nil)
            #expect(try untitledNames(harness, in: "Sources").isEmpty)
        }
    }

    @Test
    func newFileFromClipboardReportsAnErrorWhenTheFolderVanished() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let empty = try harness.file("Empty")
            let menu = harness.buildMenu(clicking: empty)
            harness.pasteboard.replaceContents(withText: "lost")
            try harness.perform("New File from Clipboard", in: menu)
            try harness.remove("Empty")

            try harness.submitCreation("lost.txt")

            #expect(!harness.exists("Empty"))
        }
    }

    @Test
    func newFolderStartsAnInlineEntryAndCreatesTheNamedFolder() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let sources = try harness.file("Sources")
            let menu = harness.buildMenu(clicking: sources)

            try harness.perform("New Folder", in: menu)
            #expect(harness.controller.pendingCreation?.kind == .directory)
            #expect(try harness.names(in: "Sources") == ["main.swift"])
            try harness.submitCreation("Generated")

            #expect(harness.exists("Sources/Generated"))
            #expect(try untitledNames(harness, in: "Sources").isEmpty)
            #expect(harness.workspace.listenerModel.highlightedFileItem?.name == "Generated")
        }
    }

    @Test
    func newFolderReportsAnErrorWhenTheParentIsNoLongerAFolder() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let empty = try harness.file("Empty")
            let menu = harness.buildMenu(clicking: empty)
            try harness.perform("New Folder", in: menu)
            try harness.remove("Empty")
            try harness.write("Empty", "now a file")

            try harness.submitCreation("child")

            #expect(try harness.contents("Empty") == "now a file")
        }
    }

    @Test
    func newFolderFromSelectionMovesTheSelectedItemsIntoNumberedFolders() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files + ["c.txt", "d.txt"]) { harness in
            let a = try harness.file("a.txt")
            let b = try harness.file("b.md")
            let first = openMenu(harness, selecting: [a, b], clicking: a)

            try harness.perform("New Folder from Selection", in: first)

            #expect(try harness.names(in: "New Folder With Items") == ["a.txt", "b.md"])
            #expect(!harness.exists("a.txt"))

            let c = try harness.file("c.txt")
            let d = try harness.file("d.txt")
            let second = openMenu(harness, selecting: [c, d], clicking: c)

            try harness.perform("New Folder from Selection", in: second)

            #expect(try harness.names(in: "New Folder With Items 1") == ["c.txt", "d.txt"])
        }
    }

    @Test
    func newFolderFromSelectionNeedsAParentAndAWorkspace() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let before = try harness.names(in: "")
            let rootMenu = openMenu(harness, selecting: [harness.rootFile], clicking: harness.rootFile)

            rootMenu.newFolderFromSelection()

            #expect(try harness.names(in: "") == before)

            let a = try harness.file("a.txt")
            let menu = openMenu(harness, selecting: [a], clicking: a)
            menu.workspace = nil
            menu.newFolderFromSelection()

            #expect(try harness.names(in: "") == before)
        }
    }

    @Test
    func newFolderFromSelectionReportsAMissingSource() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let a = try harness.file("a.txt")
            let b = try harness.file("b.md")
            let menu = openMenu(harness, selecting: [a, b], clicking: a)
            try harness.remove("b.md")

            try harness.perform("New Folder from Selection", in: menu)

            #expect(!harness.exists("New Folder With Items/b.md"))
        }
    }

    @Test
    func trashMovesTheSelectedFilesAndClosesTheirTabs() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let a = try harness.file("a.txt")
            let b = try harness.file("b.md")
            harness.editor.openTab(file: a, asTemporary: false)
            let menu = openMenu(harness, selecting: [a, b], clicking: a)

            try harness.perform("Move to Trash", in: menu)

            #expect(!harness.exists("a.txt"))
            #expect(!harness.exists("b.md"))
            #expect(FileManager.default.fileExists(atPath: harness.trashDirectory.appending(path: "a.txt").path))
            #expect(FileManager.default.fileExists(atPath: harness.trashDirectory.appending(path: "b.md").path))
            #expect(!harness.editor.tabs.contains { $0.file == a })
        }
    }

    @Test
    func trashSkipsFilesThatAreAlreadyGone() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let b = try harness.file("b.md")
            let menu = openMenu(harness, selecting: [b], clicking: b)
            try harness.remove("b.md")

            try harness.perform("Move to Trash", in: menu)

            #expect(!FileManager.default.fileExists(atPath: harness.trashDirectory.appending(path: "b.md").path))
        }
    }

    @Test
    func trashReportsAnErrorWhenTheFileCannotBeMoved() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files, loadsTree: true) { harness in
            try harness.expand("Locked")
            let locked = try harness.file("Locked/x.txt")
            let menu = openMenu(harness, selecting: [locked], clicking: locked)
            try harness.lock("Locked")

            try harness.perform("Move to Trash", in: menu)

            #expect(harness.exists("Locked/x.txt"))
        }
    }

    @Test
    func deleteAsksForConfirmationAndKeepsFilesUntilConfirmed() async throws {
        try await Harness.run(folders: Self.folders, files: ["only-one.txt", "first.txt", "second.txt"]) { harness in
            let only = try harness.file("only-one.txt")
            let first = try harness.file("first.txt")
            let second = try harness.file("second.txt")
            let single = openMenu(harness, selecting: [only], clicking: only)

            try harness.perform("Delete Immediately...", in: single)

            #expect(harness.exists("only-one.txt"))
            #expect(DreamderHeadless.suppressedModals.contains("Do you want to delete “only-one.txt”?"))

            let several = openMenu(harness, selecting: [first, second], clicking: first)

            try harness.perform("Delete Immediately...", in: several)

            #expect(harness.exists("first.txt"))
            #expect(harness.exists("second.txt"))
            #expect(
                DreamderHeadless.suppressedModals.contains("Are you sure you want to delete the 2 selected items?")
            )
        }
    }

    @Test
    func confirmedDeleteRemovesSingleAndMultipleSelections() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files + ["c.txt", "d.txt"]) { harness in
            harness.menu.confirmsDeletion = false
            let a = try harness.file("a.txt")
            let b = try harness.file("b.md")
            let c = try harness.file("c.txt")
            let d = try harness.file("d.txt")
            harness.editor.openTab(file: a, asTemporary: false)

            let single = openMenu(harness, selecting: [a], clicking: a)
            try harness.perform("Delete Immediately...", in: single)

            #expect(!harness.exists("a.txt"))
            #expect(!harness.editor.tabs.contains { $0.file == a })

            let several = openMenu(harness, selecting: [c, d], clicking: c)
            try harness.perform("Delete Immediately...", in: several)

            #expect(!harness.exists("c.txt"))
            #expect(!harness.exists("d.txt"))
            #expect(harness.exists("b.md"))
            #expect(b.doesExist)
        }
    }

    @Test
    func deleteReportsAnErrorWhenTheFileCannotBeRemoved() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files, loadsTree: true) { harness in
            harness.menu.confirmsDeletion = false
            try harness.expand("Locked")
            let locked = try harness.file("Locked/x.txt")
            let menu = openMenu(harness, selecting: [locked], clicking: locked)
            try harness.lock("Locked")

            try harness.perform("Delete Immediately...", in: menu)

            #expect(harness.exists("Locked/x.txt"))
        }
    }

    @Test
    func duplicateCopiesFilesAndFolders() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let a = try harness.file("a.txt")
            let sources = try harness.file("Sources")
            let menu = openMenu(harness, selecting: [a, sources], clicking: a)

            try harness.perform("Duplicate File", in: menu)

            #expect(try harness.contents("a copy.txt") == "content of a.txt\n")
            #expect(harness.exists("Sources copy/main.swift"))
        }
    }

    @Test
    func duplicateReportsAnErrorWhenTheCopyCannotBeWritten() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files, loadsTree: true) { harness in
            try harness.expand("Locked")
            let locked = try harness.file("Locked/x.txt")
            let menu = openMenu(harness, selecting: [locked], clicking: locked)
            try harness.lock("Locked")

            try harness.perform("Duplicate File", in: menu)

            #expect(try harness.names(in: "Locked") == ["x.txt"])
        }
    }

    @Test
    func copyPathPutsTheSortedAbsolutePathsOnThePasteboard() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let a = try harness.file("a.txt")
            let b = try harness.file("b.md")
            let menu = openMenu(harness, selecting: [b, a], clicking: a)

            try harness.perform("Copy Path", in: menu)

            let expected = [a, b].map { $0.url.standardizedFileURL.path }.sorted().joined(separator: "\n")
            #expect(harness.pasteboard.plainText == expected)
        }
    }

    @Test
    func copyRelativePathPutsTheSortedPathsRelativeToTheRoot() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files, loadsTree: true) { harness in
            try harness.expand("Sources")
            let a = try harness.file("a.txt")
            let main = try harness.file("Sources/main.swift")
            let menu = openMenu(harness, selecting: [a, main], clicking: a)

            try harness.perform("Copy Relative Path", in: menu)

            let expected = ["a.txt", "Sources/main.swift"].sorted().joined(separator: "\n")
            #expect(harness.pasteboard.plainText == expected)
        }
    }

    @Test
    func copyRelativePathWithoutAWorkspaceLeavesThePasteboardAlone() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let a = try harness.file("a.txt")
            let menu = openMenu(harness, selecting: [a], clicking: a)
            harness.pasteboard.replaceContents(withText: "sentinel")
            menu.workspace = nil

            menu.copyRelativePath()

            #expect(harness.pasteboard.plainText == "sentinel")
        }
    }

    private func menuWithReleasedSender(_ harness: Harness, item: CEWorkspaceFile) -> ProjectNavigatorMenu {
        let menu = ProjectNavigatorMenu(ProjectNavigatorViewController())
        menu.item = item
        menu.workspace = harness.workspace
        return menu
    }

    @Test
    func pathCopiesAndRebuildsWithAReleasedSenderLeaveThePasteboardAloneAndKeepTheNameSort() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let sources = try harness.file("Sources")
            let menu = menuWithReleasedSender(harness, item: sources)
            harness.pasteboard.replaceContents(withText: "sentinel")

            menu.copyPath()
            menu.copyRelativePath()
            menu.rebuild()

            #expect(harness.pasteboard.plainText == "sentinel")
            #expect(harness.menuItem(titled: "Sort by Name", in: menu)?.state == .on)
            #expect(harness.menuItem(titled: "Sort by Type", in: menu)?.state == .off)
        }
    }

    @Test
    func openWithExternalEditorSkipsFilesThatTheSystemOpened() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files + ["opened-externally.txt"]) { harness in
            let opened = try harness.file("opened-externally.txt")
            var requested: [String] = []
            harness.menu.opensExternally = { file in
                requested.append(file.name)
                return true
            }
            let menu = openMenu(harness, selecting: [opened], clicking: opened)

            try harness.perform("Open with External Editor", in: menu)

            #expect(requested == ["opened-externally.txt"])
            #expect(!DreamderHeadless.suppressedModals.contains { $0.contains("opened-externally.txt") })
        }
    }
}
