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
        UserDefaults.standard.removeObject(forKey: "workspaceState-\(workspace.fileURL?.absoluteString ?? "")")
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

@MainActor
@Suite(.serialized, .uiGate)
struct EditorPinnedTabsActionsTests {
    private static let names = ["a.swift", "b.swift", "c.swift", "d.swift"]

    private func actions(_ harness: EditorTabsCoverageHarness, for name: String) throws -> EditorTabBarItemActions {
        EditorTabBarItemActions(
            item: try harness.file(name),
            editor: harness.editor,
            editorManager: harness.manager,
            workspace: harness.workspace
        )
    }

    private func tabNames(_ harness: EditorTabsCoverageHarness) -> [String] {
        harness.editor.tabs.map(\.file.name)
    }

    private func pin(_ harness: EditorTabsCoverageHarness, _ name: String) throws {
        harness.editor.setPinned(true, file: try harness.file(name))
    }

    @Test
    func closeAllSkipsPinnedTabs() throws {
        try withTempDir { directory in
            let harness = try EditorTabsCoverageHarness.make(in: directory, names: Self.names)
            defer { harness.close() }
            try pin(harness, "b.swift")

            try actions(harness, for: "a.swift").editorActions.closeAll()

            #expect(tabNames(harness) == ["b.swift"])
        }
    }

    @Test
    func closeOthersFromTheTabBarSkipsPinnedTabs() throws {
        try withTempDir { directory in
            let harness = try EditorTabsCoverageHarness.make(in: directory, names: Self.names)
            defer { harness.close() }
            try pin(harness, "a.swift")
            harness.editor.setSelectedTab(try harness.file("c.swift"))

            harness.manager.activeEditor = harness.editor
            try actions(harness, for: "c.swift").editorActions.closeOthers()

            #expect(tabNames(harness) == ["a.swift", "c.swift"])
        }
    }

    @Test
    func closeOtherTabsFromTheContextMenuSkipsPinnedTabs() throws {
        try withTempDir { directory in
            let harness = try EditorTabsCoverageHarness.make(in: directory, names: Self.names)
            defer { harness.close() }
            try pin(harness, "d.swift")

            try actions(harness, for: "b.swift").closeOtherTabs()

            #expect(tabNames(harness) == ["d.swift", "b.swift"])
        }
    }

    @Test
    func closeToTheLeftAndRightSkipPinnedTabs() throws {
        try withTempDir { directory in
            let harness = try EditorTabsCoverageHarness.make(in: directory, names: Self.names)
            defer { harness.close() }
            try pin(harness, "a.swift")
            try pin(harness, "d.swift")
            #expect(tabNames(harness) == ["a.swift", "d.swift", "b.swift", "c.swift"])

            try actions(harness, for: "c.swift").closeTabsToTheLeft()
            #expect(tabNames(harness) == ["a.swift", "d.swift", "c.swift"])

            try actions(harness, for: "a.swift").closeTabsToTheRight()
            #expect(tabNames(harness) == ["a.swift", "d.swift"])
        }
    }

    @Test
    func closeToTheLeftOfTheFirstOrAnUnknownTabKeepsEverything() throws {
        try withTempDir { directory in
            let harness = try EditorTabsCoverageHarness.make(in: directory, names: Self.names)
            defer { harness.close() }
            let ghost = CEWorkspaceFile(url: directory.appending(path: "ghost.swift"))

            try actions(harness, for: "a.swift").closeTabsToTheLeft()
            EditorTabBarItemActions(
                item: ghost,
                editor: harness.editor,
                editorManager: harness.manager,
                workspace: harness.workspace
            ).closeTabsToTheLeft()

            #expect(tabNames(harness) == Self.names)
        }
    }

    @Test
    func closeUnmodifiedKeepsPinnedAndEditedTabs() throws {
        try withTempDir { directory in
            let harness = try EditorTabsCoverageHarness.make(in: directory, names: Self.names)
            defer { harness.close() }
            try pin(harness, "a.swift")
            let edited = try #require(try harness.file("c.swift").fileDocument)
            edited.updateChangeCount(.changeDone)
            defer { edited.updateChangeCount(.changeCleared) }

            try actions(harness, for: "b.swift").closeUnmodifiedTabs()

            #expect(tabNames(harness) == ["a.swift", "c.swift"])
        }
    }

    @Test
    func togglePinnedActionPinsAndUnpinsTheItem() throws {
        try withTempDir { directory in
            let harness = try EditorTabsCoverageHarness.make(in: directory, names: Self.names)
            defer { harness.close() }
            let item = try actions(harness, for: "c.swift")

            item.togglePinned()
            #expect(tabNames(harness) == ["c.swift", "a.swift", "b.swift", "d.swift"])
            let pinnedC = try harness.file("c.swift")
            #expect(harness.editor.isPinned(pinnedC))

            item.togglePinned()
            #expect(tabNames(harness) == ["c.swift", "a.swift", "b.swift", "d.swift"])
            let unpinnedC = try harness.file("c.swift")
            #expect(!harness.editor.isPinned(unpinnedC))
        }
    }

    @Test
    func movingAPinnedTabToANewSplitKeepsItPinnedOnlyThere() throws {
        try withTempDir { directory in
            let harness = try EditorTabsCoverageHarness.make(in: directory, names: ["a.swift", "b.swift"])
            defer { harness.close() }
            let pinned = try harness.file("b.swift")
            let loose = try harness.file("a.swift")
            harness.editor.setPinned(true, file: pinned)

            let moved = try #require(harness.manager.moveTabToNewSplit(
                pinned,
                from: harness.editor,
                edge: .trailing,
                workspace: harness.workspace
            ))

            #expect(moved.isPinned(pinned))
            #expect(moved.pinnedTabCount == 1)
            #expect(harness.editor.pinnedURLs.isEmpty)

            let second = try #require(harness.manager.moveTabToNewSplit(
                loose,
                from: harness.editor,
                edge: .bottom,
                workspace: harness.workspace
            ))
            #expect(!second.isPinned(loose))
            #expect(second.pinnedURLs.isEmpty)
        }
    }

    @Test
    func unsplitCarriesThePinsOfTheMergedEditors() throws {
        try withTempDir { directory in
            let harness = try EditorTabsCoverageHarness.make(in: directory, names: ["a.swift", "b.swift"])
            defer { harness.close() }
            let pinned = try harness.file("b.swift")
            let target = harness.editor
            let moved = try #require(harness.manager.moveTabToNewSplit(
                pinned,
                from: target,
                edge: .trailing,
                workspace: harness.workspace
            ))
            moved.setPinned(true, file: pinned)

            #expect(harness.manager.unsplit(target))

            #expect(target.tabs.map(\.file.name) == ["b.swift", "a.swift"])
            #expect(target.isPinned(pinned))
        }
    }

    @Test
    func pinTitlesFollowThePinState() {
        #expect(EditorTabBarContextMenuItems.pinToggleTitle(isPinned: false) == "Pin Tab")
        #expect(EditorTabBarContextMenuItems.pinToggleTitle(isPinned: true) == "Unpin Tab")
        #expect(EditorTabBarContextMenuItems.pinTitle == "Pin Tab")
        #expect(EditorTabBarContextMenuItems.unpinTitle == "Unpin Tab")
    }

    @Test
    func contextMenuRendersForPinnedAndUnpinnedTabs() async throws {
        try await withTempDir { directory in
            let harness = try EditorTabsCoverageHarness.make(in: directory, names: Self.names)
            defer { harness.close() }
            let item = try harness.file("b.swift")

            for pinned in [false, true] {
                harness.editor.setPinned(pinned, file: item)
                let hosted = try harness.host(size: NSSize(width: 420, height: 900)) {
                    VStack {
                        EditorTabBarContextMenuItems(item: item, isTemporary: false)
                    }
                }
                defer { hosted.close() }
                try await hosted.settle()
                #expect(hosted.renders())
            }
        }
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct EditorPinnedTabViewTests {
    @Test
    func middleClickAndUnpinInteractionsRespectThePin() async throws {
        try await withTempDir { directory in
            let harness = try EditorTabsCoverageHarness.make(in: directory, names: ["a.swift", "b.swift"])
            defer { harness.close() }
            let first = try harness.file("a.swift")
            let context = harness.context(first)
            let interaction = EditorTabInteraction()
            harness.editor.setPinned(true, file: first)
            interaction.isHovering = true

            interaction.middleClicked(buttonNumber: EditorTabInteraction.middleButtonNumber, context)
            try await Task.sleep(for: .milliseconds(150))
            #expect(harness.editor.tabs.count == 2)

            interaction.unpin(context)
            #expect(!harness.editor.isPinned(first))
            #expect(harness.editor.tabs.count == 2)

            interaction.middleClicked(buttonNumber: EditorTabInteraction.middleButtonNumber, context)
            try await eventually(timeout: .seconds(2)) {
                harness.editor.tabs.map(\.file.name) == ["b.swift"]
            }
        }
    }

    @Test
    func pinnedTabsShowThePinInsteadOfTheCloseButton() async throws {
        try await withTempDir { directory in
            let harness = try EditorTabsCoverageHarness.make(in: directory, names: ["a.swift", "b.swift"])
            defer { harness.close() }
            let file = try harness.file("a.swift")
            let hosted = try harness.host(size: NSSize(width: 320, height: 60)) {
                EditorTabView(
                    file: file,
                    index: 0,
                    draggingTabId: nil,
                    closeButtonGestureActive: .constant(false)
                )
            }
            defer { hosted.close() }
            try await hosted.settle()
            let unpinned = hosted.snapshot()

            harness.editor.setPinned(true, file: file)
            try await hosted.settle()

            #expect(HostedView.pixelsDiffer(unpinned, hosted.snapshot()))
        }
    }

    @Test
    func hoveringThePinButtonHighlightsIt() async throws {
        let flags = EditorTabsCoverageFlags()
        let hosted = HostedViewFixture.host(size: NSSize(width: 60, height: 40)) {
            EditorTabPinButton(
                unpinAction: { flags.closed += 1 },
                isHoveringClose: Bindable(flags).hovering
            )
        }
        defer { hosted.close() }
        try await hosted.settle()
        let resting = hosted.snapshot()
        #expect(hosted.renders())

        flags.hovering = true
        try await hosted.settle()

        #expect(HostedView.pixelsDiffer(resting, hosted.snapshot()))
    }

    @Test
    func theStripSyncsPinStateAndRefusesToDragAcrossThePinnedBoundary() throws {
        let editor = Editor(files: OrderedSet(["a", "b", "c"].map {
            CEWorkspaceFile(url: URL(filePath: "/fake/dir/\($0)"))
        }))
        editor.setPinned(true, file: try #require(editor.tabs.last).file)
        let model = EditorTabStripModel()

        model.synchronizeTabs(with: editor)

        #expect(model.openedTabs == editor.tabs.map(\.file.id))
        let pinnedID = try #require(editor.tabs.first).file.id
        #expect(model.pinnedTabs == [pinnedID])

        let ids = model.openedTabs
        for (index, id) in ids.enumerated() {
            model.tabWidth[id] = 100
            model.tabLocations[id] = CGRect(x: CGFloat(index) * 104, y: 0, width: 100, height: 30)
        }

        model.dragChanged(id: ids[1], startX: 150, currentX: 150)
        model.dragChanged(id: ids[1], startX: 150, currentX: 80)
        #expect(model.openedTabs == ids)

        model.dragChanged(id: ids[0], startX: 50, currentX: 50)
        model.dragChanged(id: ids[0], startX: 50, currentX: 160)
        #expect(model.openedTabs == ids)

        model.dragChanged(id: ids[1], startX: 150, currentX: 150)
        model.dragChanged(id: ids[1], startX: 150, currentX: 230)
        #expect(model.openedTabs == [ids[0], ids[2], ids[1]])
    }
}
