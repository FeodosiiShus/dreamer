import AppKit
import Foundation
import OrderedCollections
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct EditorPinnedTabsModelTests {
    private func makeEditor(_ names: [String]) -> Editor {
        Editor(files: OrderedSet(names.map { CEWorkspaceFile(url: URL(filePath: "/fake/dir/\($0)")) }))
    }

    private func names(_ editor: Editor) -> [String] {
        editor.tabs.map(\.file.name)
    }

    private func file(_ name: String, in editor: Editor) throws -> CEWorkspaceFile {
        try #require(editor.tabs.first { $0.file.name == name }).file
    }

    @Test
    func pinningMovesTheTabToTheEndOfThePinnedGroup() throws {
        let editor = makeEditor(["a", "b", "c", "d"])

        editor.setPinned(true, file: try file("c", in: editor))
        #expect(names(editor) == ["c", "a", "b", "d"])

        editor.setPinned(true, file: try file("d", in: editor))
        #expect(names(editor) == ["c", "d", "a", "b"])
        #expect(editor.pinnedTabCount == 2)
        let c = try file("c", in: editor)
        let a = try file("a", in: editor)
        #expect(editor.isPinned(c))
        #expect(!editor.isPinned(a))
    }

    @Test
    func unpinningMovesTheTabJustAfterThePinnedGroup() throws {
        let editor = makeEditor(["a", "b", "c", "d"])
        editor.setPinned(true, file: try file("b", in: editor))
        editor.setPinned(true, file: try file("c", in: editor))
        editor.setPinned(true, file: try file("d", in: editor))
        #expect(names(editor) == ["b", "c", "d", "a"])

        editor.togglePinned(file: try file("b", in: editor))

        #expect(names(editor) == ["c", "d", "b", "a"])
        #expect(editor.pinnedTabCount == 2)
        let b = try file("b", in: editor)
        #expect(!editor.isPinned(b))
    }

    @Test
    func pinningKeepsTheSelectionAndIgnoresUnknownOrUnchangedState() throws {
        let editor = makeEditor(["a", "b", "c"])
        let b = try file("b", in: editor)
        editor.setSelectedTab(b)

        editor.setPinned(true, file: b)
        editor.setPinned(true, file: b)
        editor.setPinned(false, file: try file("a", in: editor))
        editor.setPinned(true, file: CEWorkspaceFile(url: URL(filePath: "/fake/dir/ghost")))

        #expect(editor.selectedTab?.file == b)
        #expect(names(editor) == ["b", "a", "c"])
        #expect(editor.pinnedURLs == [b.url])
    }

    @Test
    func openingNewTabsNeverInsertsBeforePinnedOnes() throws {
        let editor = makeEditor(["a", "b", "c"])
        let b = try file("b", in: editor)
        editor.setPinned(true, file: b)
        editor.setSelectedTab(b)
        #expect(names(editor) == ["b", "a", "c"])

        editor.openTab(file: CEWorkspaceFile(url: URL(filePath: "/fake/dir/d")))
        #expect(names(editor) == ["b", "d", "a", "c"])

        editor.openTab(file: CEWorkspaceFile(url: URL(filePath: "/fake/dir/e")), at: 0)
        #expect(names(editor) == ["b", "e", "d", "a", "c"])

        editor.openTab(file: CEWorkspaceFile(url: URL(filePath: "/fake/dir/f")), at: 99)
        #expect(names(editor) == ["b", "e", "d", "a", "c", "f"])
    }

    @Test
    func pinningAPreviewTabMakesItPermanent() throws {
        let editor = makeEditor(["a", "b"])
        let b = try #require(editor.tabs.last)
        editor.temporaryTab = b

        editor.setPinned(true, file: b.file)

        #expect(editor.temporaryTab == nil)
        #expect(editor.isPinned(b.file))
    }

    @Test
    func aPinnedTabCanNeverBecomeThePreviewTab() throws {
        let editor = makeEditor(["a", "b"])
        let a = try #require(editor.tabs.first)
        editor.setPinned(true, file: a.file)

        editor.temporaryTab = a

        #expect(editor.temporaryTab == nil)
    }

    @Test
    func previewTabsReplaceOtherPreviewsButNeverPinnedTabs() throws {
        let editor = makeEditor(["a", "b"])
        let a = try file("a", in: editor)
        editor.setPinned(true, file: a)
        editor.setSelectedTab(a)

        editor.openTab(file: CEWorkspaceFile(url: URL(filePath: "/fake/dir/c")), asTemporary: true)
        #expect(names(editor) == ["a", "c", "b"])
        #expect(editor.temporaryTab?.file.name == "c")

        editor.openTab(file: CEWorkspaceFile(url: URL(filePath: "/fake/dir/d")), asTemporary: true)
        #expect(names(editor) == ["a", "d", "b"])
        #expect(editor.temporaryTab?.file.name == "d")

        editor.openTab(file: a, asTemporary: true)
        #expect(names(editor) == ["a", "d", "b"])
        #expect(editor.temporaryTab?.file.name == "d")
        #expect(editor.isPinned(a))
    }

    @Test
    func closeSelectedTabAndMiddleClickPathIgnorePinnedTabs() throws {
        let editor = makeEditor(["a", "b"])
        let a = try file("a", in: editor)
        editor.setPinned(true, file: a)
        editor.setSelectedTab(a)

        editor.closeSelectedTab()
        editor.closeTabUnlessPinned(file: a)
        #expect(names(editor) == ["a", "b"])

        editor.closeTabUnlessPinned(file: try file("b", in: editor))
        #expect(names(editor) == ["a"])
    }

    @Test
    func explicitCloseOfAPinnedTabClosesAndUnpinsIt() throws {
        let editor = makeEditor(["a", "b"])
        let a = try file("a", in: editor)
        editor.setPinned(true, file: a)

        editor.closeTab(file: a)

        #expect(names(editor) == ["b"])
        #expect(editor.pinnedURLs.isEmpty)
    }

    @Test
    func closeUnpinnedTabsSkipsPinnedOnesAndHonoursTheFilter() throws {
        let editor = makeEditor(["a", "b", "c", "d"])
        editor.setPinned(true, file: try file("c", in: editor))
        #expect(editor.unpinnedFiles.map(\.name) == ["a", "b", "d"])

        editor.closeUnpinnedTabs { $0.name != "d" }
        #expect(names(editor) == ["c", "d"])

        editor.closeUnpinnedTabs()
        #expect(names(editor) == ["c"])
    }
}

@MainActor
@Suite(.uiGate)
struct EditorPinnedTabsRestorationTests {
    private func discardState(of workspace: WorkspaceDocument) {
        guard let url = workspace.fileURL else { return }
        UserDefaults.standard.removeObject(forKey: WorkspaceDocument.workspaceStateKey(for: url))
    }

    @Test
    func pinStateRoundTripsThroughTheCodableEditor() throws {
        let urls = ["a", "b", "c"].map { URL(filePath: "/fake/dir/\($0)") }
        let editor = Editor(files: OrderedSet(urls.map { CEWorkspaceFile(url: $0) }))
        let c = try #require(editor.tabs.last)
        editor.setPinned(true, file: c.file)

        let decoded = try JSONDecoder().decode(Editor.self, from: JSONEncoder().encode(editor))

        #expect(decoded.id == editor.id)
        #expect(decoded.tabs.map(\.file.name) == ["c", "a", "b"])
        #expect(decoded.pinnedURLs.map(\.lastPathComponent) == ["c"])
        #expect(decoded.pinnedTabCount == 1)
    }

    @Test
    func legacyPayloadWithoutThePinKeyDecodesAsUnpinned() throws {
        let id = UUID()
        let json = """
        {"tabs":["file:///fake/dir/a","file:///fake/dir/b"],"selectedTab":null,"id":"\(id.uuidString)"}
        """

        let decoded = try JSONDecoder().decode(Editor.self, from: Data(json.utf8))

        #expect(decoded.id == id)
        #expect(decoded.tabs.map(\.file.name) == ["a", "b"])
        #expect(decoded.pinnedURLs.isEmpty)
    }

    @Test
    func pinnedEntriesWithoutAMatchingTabAreDroppedOnDecode() throws {
        let id = UUID()
        let json = """
        {"tabs":["file:///fake/dir/a"],"pinned":["file:///fake/dir/a","file:///fake/dir/gone"],"id":"\(id.uuidString)"}
        """

        let decoded = try JSONDecoder().decode(Editor.self, from: Data(json.utf8))

        #expect(decoded.pinnedURLs.map(\.lastPathComponent) == ["a"])
    }

    @Test
    func pinStateSurvivesSaveAndRestoreOfTheEditorManager() throws {
        try withTempDir { dir in
            let workspace = WorkspaceDocument()
            workspace.fileURL = dir
            defer { discardState(of: workspace) }
            let first = Editor(files: OrderedSet(["one.txt", "two.txt"].map {
                CEWorkspaceFile(url: dir.appending(path: $0))
            }))
            first.setPinned(true, file: try #require(first.tabs.last).file)
            let source = EditorManager()
            source.editorLayout = .horizontal(SplitViewData(.horizontal, editorLayouts: [.one(first)]))
            source.activeEditor = first
            source.saveRestorationState(workspace)

            let restored = EditorManager()
            restored.restoreFromState(workspace)

            let editor = try #require(restored.flattenedEditors.first)
            #expect(editor.tabs.map(\.file.name) == ["two.txt", "one.txt"])
            #expect(editor.pinnedURLs.map(\.lastPathComponent) == ["two.txt"])
        }
    }

    @Test
    func pinStateSurvivesTheProductionRestorePathThatResolvesFiles() throws {
        try withTempDir { dir in
            for name in ["a.txt", "b.txt"] {
                try name.write(to: dir.appending(path: name), atomically: true, encoding: .utf8)
            }
            let source = try HostedViewFixture.makeWorkspace(in: dir)
            defer { discardState(of: source) }
            let manager = try #require(source.editorManager)
            let fileManager = try #require(source.workspaceFileManager)
            let b = try #require(fileManager.getFile(dir.appending(path: "b.txt").path(percentEncoded: false), createIfNotFound: true))
            let a = try #require(fileManager.getFile(dir.appending(path: "a.txt").path(percentEncoded: false), createIfNotFound: true))
            let editor = Editor(files: OrderedSet([a, b]))
            editor.setPinned(true, file: b)
            manager.editorLayout = .horizontal(SplitViewData(.horizontal, editorLayouts: [.one(editor)]))
            manager.activeEditor = editor
            manager.saveRestorationState(source)

            let restoredWorkspace = try HostedViewFixture.makeWorkspace(in: dir)
            let restored = try #require(restoredWorkspace.editorManager?.flattenedEditors.first)

            #expect(restored.tabs.map(\.file.name) == ["b.txt", "a.txt"])
            let first = try #require(restored.tabs.first)
            #expect(restored.isPinned(first.file))
            #expect(restored.pinnedTabCount == 1)
        }
    }
}
