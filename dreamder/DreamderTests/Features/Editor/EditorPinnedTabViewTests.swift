import AppKit
import Foundation
import OrderedCollections
import SwiftUI
import Testing
@testable import Dreamder

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
