import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct ProjectNavigatorTabSyncTests {
    typealias Harness = ProjectNavigatorControllerHarness
    typealias Controller = ProjectNavigatorViewController

    private static let folders = ["Sources", "Empty"]
    private static let files = ["a.txt", "b.md", "Sources/main.swift", "Sources/util.swift"]

    private func relative(_ url: URL, in harness: Harness) -> String {
        let rootLength = Controller.normalizedPath(harness.root).count + 1
        return String(Controller.normalizedPath(url).dropFirst(rootLength))
    }

    private func tabPaths(_ editor: Editor, in harness: Harness) -> [String] {
        editor.tabs.map { relative($0.file.url, in: harness) }
    }

    private func open(_ paths: [String], in harness: Harness, editor: Editor? = nil) throws {
        for path in paths {
            (editor ?? harness.editor).openTab(file: try harness.file(path), asTemporary: false)
        }
    }

    private func selectForMenu(_ paths: [String], in harness: Harness) throws {
        let files = try paths.map { try harness.file($0) }
        harness.select(files)
        _ = harness.buildMenu(clicking: files.first)
    }

    private func finishEditing(_ cell: ProjectNavigatorTableViewCell, with name: String) {
        cell.textField?.stringValue = name
        cell.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification))
    }

    private func fileURL(_ path: String) throws -> URL {
        try #require(URL(string: path))
    }

    @Test
    func urlIsWithinHandlesEqualPathsTrailingSlashesAndSiblings() throws {
        let sources = URL(filePath: "/work/Sources")
        let sourcesSlash = try fileURL("file:///work/Sources/")
        let child = URL(filePath: "/work/Sources/main.swift")
        let sibling = URL(filePath: "/work/Sources2/main.swift")
        let parent = URL(filePath: "/work")
        let root = URL(filePath: "/")

        #expect(Controller.url(child, isWithin: sources))
        #expect(Controller.url(child, isWithin: sourcesSlash))
        #expect(Controller.url(sources, isWithin: sources))
        #expect(Controller.url(sourcesSlash, isWithin: sources))
        #expect(Controller.url(sources, isWithin: sourcesSlash))
        #expect(!Controller.url(sibling, isWithin: sources))
        #expect(!Controller.url(parent, isWithin: sources))
        #expect(Controller.url(child, isWithin: root))
        #expect(Controller.url(root, isWithin: root))
        #expect(!Controller.url(root, isWithin: sources))
    }

    @Test
    func normalizedPathStripsTrailingSlashesButKeepsTheRoot() throws {
        #expect(Controller.normalizedPath(URL(filePath: "/work/Sources")) == "/work/Sources")
        #expect(Controller.normalizedPath(try fileURL("file:///work/Sources///")) == "/work/Sources")
        #expect(Controller.normalizedPath(URL(filePath: "/")) == "/")
        #expect(Controller.normalizedPath(URL(filePath: "/work/My File")) == "/work/My File")
    }

    @Test
    func closeTabsWithoutAnEditorManagerDoesNothing() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            try open(["Sources/main.swift", "a.txt"], in: harness)
            let manager = harness.workspace.editorManager
            harness.workspace.editorManager = nil

            harness.controller.closeTabs(under: harness.url("Sources"))
            harness.controller.retargetTabs(from: harness.url("Sources"), to: harness.url("Renamed"))

            harness.workspace.editorManager = manager
            #expect(tabPaths(harness.editor, in: harness) == ["Sources/main.swift", "a.txt"])
        }
    }

    @Test
    func retargetTabsWithoutAFileManagerDoesNothing() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            try open(["Sources/main.swift"], in: harness)
            let manager = harness.workspace.workspaceFileManager
            harness.workspace.workspaceFileManager = nil

            harness.controller.retargetTabs(from: harness.url("Sources"), to: harness.url("Renamed"))

            harness.workspace.workspaceFileManager = manager
            #expect(tabPaths(harness.editor, in: harness) == ["Sources/main.swift"])
        }
    }

    @Test
    func closeTabsClosesOnlyTabsBeneathTheUrlIncludingTheTemporaryTab() async throws {
        try await Harness.run(folders: Self.folders + ["Sources2"], files: Self.files + ["Sources2/x.txt"]) { harness in
            try open(["a.txt", "Sources2/x.txt", "Sources/main.swift"], in: harness)
            harness.editor.openTab(file: try harness.file("Sources/util.swift"), asTemporary: true)
            #expect(harness.editor.temporaryTab != nil)

            harness.controller.closeTabs(under: harness.url("Sources"))

            #expect(tabPaths(harness.editor, in: harness) == ["a.txt", "Sources2/x.txt"])
            #expect(harness.editor.temporaryTab == nil)
        }
    }

    @Test
    func closeTabsClosesTabsInEveryEditorOfASplit() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let manager = try #require(harness.workspace.editorManager)
            let second = try #require(manager.splitActiveEditor(.trailing, workspace: harness.workspace))
            second.workspace = harness.workspace
            try open(["Sources/main.swift", "a.txt"], in: harness)
            try open(["Sources/main.swift", "Sources/util.swift", "b.md"], in: harness, editor: second)

            harness.controller.closeTabs(under: harness.url("Sources"))

            #expect(tabPaths(harness.editor, in: harness) == ["a.txt"])
            #expect(tabPaths(second, in: harness) == ["b.md"])
        }
    }

    @Test
    func closeTabsClosesATemporaryTabHeldByAnotherEditor() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let manager = try #require(harness.workspace.editorManager)
            let second = try #require(manager.splitActiveEditor(.trailing, workspace: harness.workspace))
            second.workspace = harness.workspace
            let main = try harness.file("Sources/main.swift")
            try open(["Sources/main.swift"], in: harness)
            second.temporaryTab = Editor.Tab(workspace: harness.workspace, file: main)

            harness.controller.closeTabs(under: harness.url("Sources"))

            #expect(harness.editor.tabs.isEmpty)
            #expect(second.temporaryTab == nil)
        }
    }

    @Test
    func retargetTabsWithoutAffectedTabsLeavesEditorsUntouched() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            try open(["a.txt", "Sources/main.swift"], in: harness)
            let before = harness.editor.tabs
            let historyBefore = harness.editor.history

            harness.controller.retargetTabs(from: harness.url("Empty"), to: harness.url("Other"))

            #expect(harness.editor.tabs == before)
            #expect(harness.editor.history == historyBefore)
        }
    }

    @Test
    func retargetTabsKeepsOrderSelectionAndRewritesHistory() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            try open(["a.txt", "Sources/main.swift", "b.md", "Sources/util.swift"], in: harness)
            harness.editor.setSelectedTab(try harness.file("Sources/main.swift"))
            try FileManager.default.moveItem(at: harness.url("Sources"), to: harness.url("Renamed"))

            harness.controller.retargetTabs(from: harness.url("Sources"), to: harness.url("Renamed"))

            #expect(tabPaths(harness.editor, in: harness) == [
                "a.txt", "Renamed/main.swift", "b.md", "Renamed/util.swift"
            ])
            let selected = try #require(harness.editor.selectedTab)
            #expect(relative(selected.file.url, in: harness) == "Renamed/main.swift")
            let history = harness.editor.history.map { relative($0.url, in: harness) }
            #expect(!history.isEmpty)
            #expect(history.allSatisfy { !$0.hasPrefix("Sources") })
            #expect(history.contains("Renamed/util.swift"))
            #expect(history.contains("a.txt"))
        }
    }

    @Test
    func retargetTabsKeepsATemporaryTabTemporaryWhenItMoves() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            try open(["a.txt"], in: harness)
            harness.editor.openTab(file: try harness.file("Sources/main.swift"), asTemporary: true)
            try FileManager.default.moveItem(at: harness.url("Sources"), to: harness.url("Renamed"))

            harness.controller.retargetTabs(from: harness.url("Sources"), to: harness.url("Renamed"))

            let temporary = try #require(harness.editor.temporaryTab)
            #expect(relative(temporary.file.url, in: harness) == "Renamed/main.swift")
            #expect(harness.editor.tabs.contains(temporary))
        }
    }

    @Test
    func retargetTabsLeavesAnUnaffectedTemporaryTabAlone() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            try open(["Sources/main.swift"], in: harness)
            harness.editor.openTab(file: try harness.file("a.txt"), asTemporary: true)
            try FileManager.default.moveItem(at: harness.url("Sources"), to: harness.url("Renamed"))

            harness.controller.retargetTabs(from: harness.url("Sources"), to: harness.url("Renamed"))

            #expect(harness.editor.temporaryTab?.file.name == "a.txt")
            #expect(tabPaths(harness.editor, in: harness) == ["Renamed/main.swift", "a.txt"])
        }
    }

    @Test
    func retargetTabsDropsTabsWhoseReplacementLiesOutsideTheProject() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            try open(["a.txt", "Sources/main.swift", "Sources/util.swift"], in: harness)
            let outside = harness.root.deletingLastPathComponent().appending(path: "ElsewhereDir")

            harness.controller.retargetTabs(from: harness.url("Sources"), to: outside)

            #expect(tabPaths(harness.editor, in: harness) == ["a.txt"])
            let history = harness.editor.history.map { relative($0.url, in: harness) }
            #expect(history.allSatisfy { !$0.hasPrefix("Sources") })
        }
    }

    @Test
    func retargetTabsMovesTheUnsavedDocumentToTheNewFile() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let old = try harness.file("a.txt")
            try open(["a.txt"], in: harness)
            let document = try #require(old.fileDocument)
            document.content?.mutableString.append("unsaved")
            try FileManager.default.moveItem(at: harness.url("a.txt"), to: harness.url("moved.txt"))

            harness.controller.retargetTabs(from: harness.url("a.txt"), to: harness.url("moved.txt"))

            let moved = try harness.file("moved.txt")
            #expect(moved.fileDocument === document)
            #expect(document.fileURL?.path(percentEncoded: false) == moved.resolvedURL.path(percentEncoded: false))
            #expect(old.fileDocument == nil)
            #expect(harness.editor.selectedTab?.file == moved)
            #expect(harness.editor.tabs.count == 1)
            document.updateChangeCount(.changeCleared)
        }
    }

    @Test
    func retargetTabsKeepsTheExistingDocumentOfTheReplacementFile() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let a = try harness.file("a.txt")
            let b = try harness.file("b.md")
            try open(["a.txt", "b.md"], in: harness)
            let documentA = try #require(a.fileDocument)
            let documentB = try #require(b.fileDocument)

            harness.controller.retargetTabs(from: a.url, to: b.url)

            #expect(b.fileDocument === documentB)
            #expect(a.fileDocument === documentA)
            #expect(tabPaths(harness.editor, in: harness) == ["b.md"])
        }
    }

    @Test
    func trashingAFolderClosesItsTabsAndKeepsOthers() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            try open(["Sources/main.swift", "Sources/util.swift", "a.txt"], in: harness)
            try selectForMenu(["Sources"], in: harness)

            harness.menu.trash()

            #expect(!harness.exists("Sources"))
            #expect(tabPaths(harness.editor, in: harness) == ["a.txt"])
        }
    }

    @Test
    func trashingAnAlreadyRemovedFileStillClosesItsTab() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            try open(["a.txt", "b.md"], in: harness)
            try selectForMenu(["a.txt"], in: harness)
            try harness.remove("a.txt")

            harness.menu.trash()

            #expect(tabPaths(harness.editor, in: harness) == ["b.md"])
        }
    }

    @Test
    func trashingAFolderNestedTwoLevelsDeepClosesTheDeepTabs() async throws {
        try await Harness.run(folders: ["A/B"], files: ["A/B/deep.txt", "A/top.txt", "a.txt"]) { harness in
            try open(["A/B/deep.txt", "A/top.txt", "a.txt"], in: harness)
            try selectForMenu(["A"], in: harness)

            harness.menu.trash()

            #expect(tabPaths(harness.editor, in: harness) == ["a.txt"])
        }
    }

    @Test
    func trashingClosesTabsInTheSecondEditorOfASplit() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let manager = try #require(harness.workspace.editorManager)
            let second = try #require(manager.splitActiveEditor(.trailing, workspace: harness.workspace))
            second.workspace = harness.workspace
            try open(["a.txt"], in: harness)
            try open(["Sources/util.swift", "b.md"], in: harness, editor: second)
            try selectForMenu(["Sources"], in: harness)

            harness.menu.trash()

            #expect(tabPaths(harness.editor, in: harness) == ["a.txt"])
            #expect(tabPaths(second, in: harness) == ["b.md"])
        }
    }

    @Test
    func deletingAFolderImmediatelyClosesItsTabsAndKeepsOthers() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            harness.menu.confirmsDeletion = false
            try open(["Sources/main.swift", "Sources/util.swift", "a.txt"], in: harness)
            try selectForMenu(["Sources"], in: harness)

            harness.menu.delete()

            #expect(!harness.exists("Sources"))
            #expect(tabPaths(harness.editor, in: harness) == ["a.txt"])
        }
    }

    @Test
    func deletingWithTheConfirmationCancelledKeepsFilesAndTabs() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            #expect(harness.menu.confirmsDeletion)
            try open(["Sources/main.swift", "a.txt"], in: harness)
            try selectForMenu(["Sources"], in: harness)

            harness.menu.delete()

            #expect(harness.exists("Sources/main.swift"))
            #expect(tabPaths(harness.editor, in: harness) == ["Sources/main.swift", "a.txt"])
        }
    }

    @Test
    func deletingSeveralSelectedItemsClosesAllTheirTabs() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            harness.menu.confirmsDeletion = false
            try open(["a.txt", "b.md", "Sources/main.swift"], in: harness)
            try selectForMenu(["a.txt", "b.md"], in: harness)

            harness.menu.delete()

            #expect(!harness.exists("a.txt"))
            #expect(!harness.exists("b.md"))
            #expect(tabPaths(harness.editor, in: harness) == ["Sources/main.swift"])
        }
    }

    @Test
    func deletingAFolderNestedTwoLevelsDeepClosesTheDeepTabs() async throws {
        try await Harness.run(folders: ["A/B"], files: ["A/B/deep.txt", "A/top.txt", "a.txt"]) { harness in
            harness.menu.confirmsDeletion = false
            try open(["A/B/deep.txt", "A/top.txt", "a.txt"], in: harness)
            try selectForMenu(["A"], in: harness)

            harness.menu.delete()

            #expect(!harness.exists("A"))
            #expect(tabPaths(harness.editor, in: harness) == ["a.txt"])
        }
    }

    @Test
    func deletingClosesTabsInTheSecondEditorOfASplit() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            harness.menu.confirmsDeletion = false
            let manager = try #require(harness.workspace.editorManager)
            let second = try #require(manager.splitActiveEditor(.trailing, workspace: harness.workspace))
            second.workspace = harness.workspace
            try open(["Sources/main.swift", "a.txt"], in: harness)
            try open(["Sources/main.swift", "b.md"], in: harness, editor: second)
            try selectForMenu(["Sources"], in: harness)

            harness.menu.delete()

            #expect(tabPaths(harness.editor, in: harness) == ["a.txt"])
            #expect(tabPaths(second, in: harness) == ["b.md"])
        }
    }

    @Test
    func renamingAFolderRetargetsOpenTabsAndKeepsTheSelection() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            try open(["Sources/main.swift", "a.txt", "Sources/util.swift"], in: harness)
            harness.editor.setSelectedTab(try harness.file("Sources/main.swift"))
            let sources = try harness.file("Sources")
            let cell = try #require(harness.cell(for: sources))

            finishEditing(cell, with: "Renamed")

            #expect(harness.exists("Renamed/main.swift"))
            #expect(tabPaths(harness.editor, in: harness) == [
                "Renamed/main.swift", "a.txt", "Renamed/util.swift"
            ])
            let selected = try #require(harness.editor.selectedTab)
            #expect(relative(selected.file.url, in: harness) == "Renamed/main.swift")
            #expect(harness.workspace.listenerModel.highlightedFileItem == nil)
        }
    }

    @Test
    func renamingAFileRetargetsItsTabAndStillHighlightsAndOpensIt() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            try open(["b.md", "a.txt"], in: harness)
            let a = try harness.file("a.txt")
            let cell = try #require(harness.cell(for: a))

            finishEditing(cell, with: "renamed.txt")

            #expect(tabPaths(harness.editor, in: harness) == ["b.md", "renamed.txt"])
            #expect(harness.editor.selectedTab?.file.name == "renamed.txt")
            #expect(harness.workspace.listenerModel.highlightedFileItem?.name == "renamed.txt")
        }
    }

    @Test
    func droppingAFolderRetargetsItsOpenTabsWithoutHighlighting() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            try open(["Sources/main.swift", "a.txt"], in: harness)
            let sources = try harness.file("Sources")
            let empty = try harness.file("Empty")
            let info = harness.dropInfo(urls: [sources.url])

            let accepted = harness.acceptDrop(info, onto: empty)

            #expect(accepted)
            #expect(harness.exists("Empty/Sources/main.swift"))
            #expect(tabPaths(harness.editor, in: harness) == ["Empty/Sources/main.swift", "a.txt"])
            #expect(harness.workspace.listenerModel.highlightedFileItem == nil)
        }
    }

    @Test
    func droppingAFileRetargetsItsTabAndHighlightsIt() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            try open(["a.txt", "b.md"], in: harness)
            let a = try harness.file("a.txt")
            let sources = try harness.file("Sources")
            let info = harness.dropInfo(urls: [a.url])

            let accepted = harness.acceptDrop(info, onto: sources)

            #expect(accepted)
            #expect(tabPaths(harness.editor, in: harness).sorted() == ["Sources/a.txt", "b.md"])
            #expect(harness.workspace.listenerModel.highlightedFileItem?.name == "a.txt")
        }
    }

    @Test
    func moveFileWithoutAFileManagerDoesNothing() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            try open(["a.txt"], in: harness)
            let a = try harness.file("a.txt")
            let manager = harness.workspace.workspaceFileManager
            harness.workspace.workspaceFileManager = nil

            harness.controller.moveFile(file: a, to: harness.url("Sources/a.txt"))

            harness.workspace.workspaceFileManager = manager
            #expect(harness.exists("a.txt"))
            #expect(tabPaths(harness.editor, in: harness) == ["a.txt"])
        }
    }

    @Test
    func moveFileReportingAnErrorKeepsTheTabsUntouched() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            try open(["a.txt", "b.md"], in: harness)
            let a = try harness.file("a.txt")

            harness.controller.moveFile(file: a, to: harness.url("b.md"))

            #expect(DreamderHeadless.suppressedModals.contains("Destination already exists"))
            #expect(tabPaths(harness.editor, in: harness) == ["a.txt", "b.md"])
        }
    }

    @Test
    func moveFileIntoAFolderThatIsNotIndexedYetRetargetsTheTab() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            try open(["a.txt"], in: harness)
            let a = try harness.file("a.txt")

            harness.controller.moveFile(file: a, to: harness.url("Sources/Fresh/Deep/a.txt"))

            #expect(harness.exists("Sources/Fresh/Deep/a.txt"))
            #expect(tabPaths(harness.editor, in: harness) == ["Sources/Fresh/Deep/a.txt"])
        }
    }

    @Test
    func movingAFolderThroughMoveFileRetargetsWithoutOpeningAnything() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            try open(["Sources/main.swift"], in: harness)
            let sources = try harness.file("Sources")

            harness.controller.moveFile(file: sources, to: harness.url("Empty/Sources"))

            #expect(tabPaths(harness.editor, in: harness) == ["Empty/Sources/main.swift"])
            #expect(harness.workspace.listenerModel.highlightedFileItem == nil)
        }
    }

    @Test
    func newFolderFromSelectionRetargetsOpenTabsIntoTheNewFolder() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files, loadsTree: true) { harness in
            try harness.expand("Sources")
            try open(["Sources/main.swift", "Sources/util.swift", "a.txt"], in: harness)
            try selectForMenu(["Sources/main.swift", "Sources/util.swift"], in: harness)

            harness.menu.newFolderFromSelection()

            #expect(harness.exists("Sources/New Folder With Items/main.swift"))
            #expect(harness.exists("Sources/New Folder With Items/util.swift"))
            #expect(tabPaths(harness.editor, in: harness) == [
                "Sources/New Folder With Items/main.swift",
                "Sources/New Folder With Items/util.swift",
                "a.txt"
            ])
        }
    }
}
