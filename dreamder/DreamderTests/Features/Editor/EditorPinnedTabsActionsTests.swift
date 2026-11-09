import AppKit
import Foundation
import OrderedCollections
import SwiftUI
import Testing
@testable import Dreamder

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
