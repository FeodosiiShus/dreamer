import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .isolatedDefaults, .uiGate)
struct SearchEverywhereViewTests {
    private static let windowSize = NSSize(width: 700, height: 540)

    private func makeModel(
        workspace: WorkspaceDocument? = nil,
        mode: SearchEverywhereMode = .everywhere
    ) throws -> SearchEverywhereViewModel {
        let defaults = try IsolatedDefaults.require()
        return SearchEverywhereViewModel(
            workspace: workspace,
            mode: mode,
            defaults: defaults,
            recentFiles: SearchEverywhereRecentFilesStore(defaults: defaults),
            actions: { [] }
        )
    }

    private func host(_ model: SearchEverywhereViewModel) -> HostedView {
        HostedViewFixture.host(size: Self.windowSize) {
            SearchEverywhereView(model: model)
        }
    }

    private func snapshotOfRow(_ item: SearchEverywhereItem, isSelected: Bool) async throws -> NSBitmapImageRep? {
        let hosted = HostedViewFixture.host(size: NSSize(width: 520, height: 80)) {
            SearchEverywhereRow(item: item, isSelected: isSelected, onSelect: { _ in }, onOpen: {})
        }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(100))
        return hosted.snapshot()
    }

    @Test
    func everywhereAndRecentFilesModesRenderTheirOwnChrome() async throws {
        let everywhere = try makeModel()
        everywhere.start(on: .all)
        let recent = try makeModel(mode: .recentFiles)
        recent.start(on: .all)
        let everywhereHosted = host(everywhere)
        defer { everywhereHosted.close() }
        let recentHosted = host(recent)
        defer { recentHosted.close() }

        try await everywhereHosted.settle()
        try await recentHosted.settle()

        #expect(everywhereHosted.renders())
        #expect(recentHosted.renders())
        #expect(HostedView.pixelsDiffer(everywhereHosted.snapshot(), recentHosted.snapshot()))
    }

    @Test
    func emptyMessagesFollowTheModeAndTheQuery() async throws {
        for mode in [SearchEverywhereMode.everywhere, .recentFiles] {
            let model = try makeModel(mode: mode)
            model.start(on: .all)
            let hosted = host(model)
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(100))
            let hint = hosted.snapshot()

            model.query = "zzzz"
            try await hosted.settle(.milliseconds(100))

            #expect(model.flatItems.isEmpty)
            #expect(HostedView.pixelsDiffer(hint, hosted.snapshot()))
        }
    }

    @Test
    func indexingLabelAppearsWhileTheSymbolIndexBuilds() async throws {
        try await withTempDir { dir in
            let workspace = try SearchEverywhereFixtures.makeWorkspace(dir)
            defer { workspace.tearDownFileScope() }
            let model = try makeModel(workspace: workspace)
            model.start(on: .all)
            let index = try #require(workspace.symbolIndex)
            index.ensureIndexed()
            #expect(model.isIndexing)
            let hosted = host(model)
            defer { hosted.close() }
            let building = hosted.snapshot()

            try await eventually { !model.isIndexing }
            try await hosted.settle(.milliseconds(100))

            #expect(HostedView.pixelsDiffer(building, hosted.snapshot()))
        }
    }

    @Test
    func populatedResultsShowThePreviewAndFollowTheSelection() async throws {
        try await withTempDir { dir in
            let workspace = try SearchEverywhereFixtures.makeWorkspace(dir)
            defer { workspace.tearDownFileScope() }
            let model = try makeModel(workspace: workspace)
            model.start(on: .files)
            model.query = "s"
            try await eventually { model.flatItems.count >= 2 }
            try await eventually { model.preview != nil }
            let hosted = host(model)
            defer { hosted.close() }
            try await hosted.settle()
            let firstSelected = hosted.snapshot()

            model.moveSelection(by: 1)
            try await hosted.settle()
            #expect(model.selection == 1)
            #expect(HostedView.pixelsDiffer(firstSelected, hosted.snapshot()))

            model.query = "zzzzqqq"
            try await eventually { model.flatItems.isEmpty }
            try await hosted.settle()
            #expect(model.selection == 0)
            #expect(model.selectedItem == nil)
            #expect(model.preview == nil)
        }
    }

    @Test
    func disablingThePreviewRemovesItFromTheLayout() async throws {
        try await withTempDir { dir in
            let workspace = try SearchEverywhereFixtures.makeWorkspace(dir)
            defer { workspace.tearDownFileScope() }
            let model = try makeModel(workspace: workspace)
            model.start(on: .files)
            model.query = "AppDelegate"
            try await eventually { model.preview != nil }
            let hosted = host(model)
            defer { hosted.close() }
            try await hosted.settle()
            let withPreview = hosted.snapshot()

            model.togglePreview()
            try await hosted.settle()

            #expect(model.preview == nil)
            #expect(HostedView.pixelsDiffer(withPreview, hosted.snapshot()))
        }
    }

    @Test
    func previewViewMarksTheTargetLine() async throws {
        func render(targetLine: Int) async throws -> NSBitmapImageRep? {
            let hosted = HostedViewFixture.host(size: NSSize(width: 520, height: 240)) {
                SearchEverywherePreviewView(preview: SearchEverywhereFixtures.preview(targetLine: targetLine))
            }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(100))
            #expect(hosted.renders())
            return hosted.snapshot()
        }

        let first = try await render(targetLine: 1)
        let third = try await render(targetLine: 3)

        #expect(HostedView.pixelsDiffer(first, third))
    }

    @Test
    func rowsRenderSelectionKindsDetailsAndShortcuts() async throws {
        let plain = SearchEverywhereFixtures.item()
        let unselected = try await snapshotOfRow(plain, isSelected: false)
        let selected = try await snapshotOfRow(plain, isSelected: true)
        #expect(HostedView.pixelsDiffer(unselected, selected))

        let withoutDetail = SearchEverywhereFixtures.item(detail: "")
        let detailless = try await snapshotOfRow(withoutDetail, isSelected: false)
        #expect(HostedView.pixelsDiffer(unselected, detailless))

        let text = SearchEverywhereFixtures.item(id: "text:a:1", kind: .text, title: "let needle = 1")
        let textual = try await snapshotOfRow(text, isSelected: false)
        #expect(HostedView.pixelsDiffer(unselected, textual))

        let shortcutAction = SearchEverywhereFixtures.action("File | Open", shortcut: "\u{2318}O")
        let withShortcut = SearchEverywhereFixtures.item(id: "action:open", kind: .action, title: "Open", action: shortcutAction)
        let withoutShortcutAction = SearchEverywhereFixtures.action("File | Close")
        let withoutShortcut = SearchEverywhereFixtures.item(
            id: "action:close",
            kind: .action,
            title: "Open",
            action: withoutShortcutAction
        )
        let shortcutSnapshot = try await snapshotOfRow(withShortcut, isSelected: false)
        let plainActionSnapshot = try await snapshotOfRow(withoutShortcut, isSelected: false)
        #expect(HostedView.pixelsDiffer(shortcutSnapshot, plainActionSnapshot))
    }

    @Test
    func activatingARowSelectsItBeforeOpening() {
        let recorder = SearchEverywhereCallRecorder()
        let item = SearchEverywhereFixtures.item(id: "file:picked.swift")
        let row = SearchEverywhereRow(
            item: item,
            isSelected: false,
            onSelect: recorder.select,
            onOpen: recorder.open
        )

        row.activate()

        #expect(recorder.events == ["select", "open"])
        #expect(recorder.selectedItems == ["file:picked.swift"])
    }

    @Test
    func hoveringARowNeverActivatesIt() {
        let recorder = SearchEverywhereCallRecorder()
        let row = SearchEverywhereRow(
            item: SearchEverywhereFixtures.item(),
            isSelected: false,
            onSelect: recorder.select,
            onOpen: recorder.open
        )

        row.setHovering(true)
        row.setHovering(false)

        #expect(recorder.events.isEmpty)
    }

    @Test
    func tabButtonsReportTheirTabAndRenderTheirSelection() async throws {
        let recorder = SearchEverywhereCallRecorder()
        func render(isSelected: Bool) async throws -> NSBitmapImageRep? {
            let hosted = HostedViewFixture.host(size: NSSize(width: 160, height: 60)) {
                SearchEverywhereTabButton(tab: .symbols, isSelected: isSelected, onSelect: recorder.selectTab)
            }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(100))
            return hosted.snapshot()
        }

        let unselected = try await render(isSelected: false)
        let selected = try await render(isSelected: true)
        SearchEverywhereTabButton(tab: .classes, isSelected: false, onSelect: recorder.selectTab).select()

        #expect(HostedView.pixelsDiffer(unselected, selected))
        #expect(recorder.selectedTabs == [.classes])
    }

    @Test
    func highlightedTextSplitsTheTitleAroundMatches() {
        func segments(_ text: String, _ ranges: [NSRange]) -> [SearchEverywhereHighlightedText.Segment] {
            SearchEverywhereHighlightedText(text: text, ranges: ranges).segments
        }
        typealias Segment = SearchEverywhereHighlightedText.Segment

        #expect(segments("abcdefg", []) == [Segment(text: "abcdefg", isMatch: false)])
        #expect(segments("", [NSRange(location: 0, length: 2)]) == [Segment(text: "", isMatch: false)])
        #expect(segments("abcdefg", [NSRange(location: 2, length: 3)]) == [
            Segment(text: "ab", isMatch: false),
            Segment(text: "cde", isMatch: true),
            Segment(text: "fg", isMatch: false)
        ])
        #expect(segments("abcdef", [NSRange(location: 4, length: 1), NSRange(location: 0, length: 2)]) == [
            Segment(text: "ab", isMatch: true),
            Segment(text: "cd", isMatch: false),
            Segment(text: "e", isMatch: true),
            Segment(text: "f", isMatch: false)
        ])
        #expect(segments("abcde", [NSRange(location: 3, length: 10)]) == [
            Segment(text: "abc", isMatch: false),
            Segment(text: "de", isMatch: true)
        ])
        #expect(segments("abcd", [NSRange(location: -2, length: 4)]) == [
            Segment(text: "ab", isMatch: true),
            Segment(text: "cd", isMatch: false)
        ])
        #expect(segments("abc", [NSRange(location: 0, length: 3)]) == [Segment(text: "abc", isMatch: true)])
        #expect(segments("abcd", [NSRange(location: 2, length: 0)]) == [
            Segment(text: "ab", isMatch: false),
            Segment(text: "cd", isMatch: false)
        ])
    }

    @Test
    func highlightedTextRendersMatchesInADifferentColor() async throws {
        func render(ranges: [NSRange]) async throws -> NSBitmapImageRep? {
            let hosted = HostedViewFixture.host(size: NSSize(width: 240, height: 40)) {
                SearchEverywhereHighlightedText(text: "AppDelegate.swift", ranges: ranges)
            }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(100))
            return hosted.snapshot()
        }

        let plain = try await render(ranges: [])
        let highlighted = try await render(ranges: [NSRange(location: 0, length: 3)])

        #expect(HostedView.pixelsDiffer(plain, highlighted))
    }
}
