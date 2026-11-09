import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct ShowUsagesViewCoverageTests {
    private func row(
        _ line: Int,
        lineText: String = "let value = helper()",
        matchRange: NSRange? = NSRange(location: 4, length: 5),
        relativeDirectory: String = "Sources"
    ) -> LSPUsageRow {
        LSPUsageRow(
            uri: "file:///tmp/project/Sources/Main.swift",
            fileURL: URL(fileURLWithPath: "/tmp/project/Sources/Main.swift"),
            fileName: "Main.swift",
            fileIconName: IntelliJIcon.fileIcon(for: "Main.swift"),
            relativeDirectory: relativeDirectory,
            line: line,
            column: 4,
            lineText: lineText,
            matchRange: matchRange
        )
    }

    private func populatedModel(count: Int = 4) -> ShowUsagesViewModel {
        ShowUsagesViewModel(rows: (0..<count).map { row($0) }, symbol: "value")
    }

    @Test
    func populatedListRendersAndSelectionChangeRepaintsTheRows() async throws {
        let model = populatedModel()
        let hosted = HostedViewFixture.host(size: NSSize(width: 620, height: 200)) {
            ShowUsagesView(model: model)
        }
        defer { hosted.close() }
        try await hosted.settle()
        let before = hosted.snapshot()

        model.select(3)
        try await hosted.settle()
        let after = hosted.snapshot()

        #expect(hosted.renders())
        #expect(HostedView.pixelsDiffer(before, after))
        #expect(model.selectedRow?.line == 3)
    }

    @Test
    func singleUsageAndMessageStatesRenderDifferentlyFromTheList() async throws {
        let single = ShowUsagesViewModel(rows: [row(0)], symbol: "")
        let message = ShowUsagesViewModel(message: "No usages found for 'value'")

        let listHosted = HostedViewFixture.host(size: NSSize(width: 620, height: 120)) {
            ShowUsagesView(model: single)
        }
        defer { listHosted.close() }
        let messageHosted = HostedViewFixture.host(size: NSSize(width: 620, height: 120)) {
            ShowUsagesView(model: message)
        }
        defer { messageHosted.close() }
        try await listHosted.settle()
        try await messageHosted.settle()

        #expect(listHosted.renders())
        #expect(messageHosted.renders())
        #expect(HostedView.pixelsDiffer(listHosted.snapshot(), messageHosted.snapshot()))
    }

    @Test
    func rowCallbacksSelectAndOpenTheirOwnUsage() {
        let model = populatedModel()
        var opened: [Int] = []
        model.openRow = { opened.append($0.line) }
        let view = ShowUsagesView(model: model)

        let selectedRow = view.rowView(at: 0, row: row(0))
        let otherRow = view.rowView(at: 2, row: row(2))
        otherRow.onSelect()
        #expect(model.selectedIndex == 2)
        otherRow.onOpen()
        selectedRow.onOpen()

        #expect(opened == [2, 0])
        #expect(model.selectedIndex == 0)
        #expect(selectedRow.isSelected)
        #expect(!otherRow.isSelected)
    }

    @Test
    func rowBackgroundPrefersSelectionThenHoverThenClear() {
        #expect(ShowUsagesRowView.backgroundColor(isSelected: true, isHovering: true) == Islands.selection)
        #expect(ShowUsagesRowView.backgroundColor(isSelected: true, isHovering: false) == Islands.selection)
        #expect(ShowUsagesRowView.backgroundColor(isSelected: false, isHovering: true) == Islands.hover)
        #expect(ShowUsagesRowView.backgroundColor(isSelected: false, isHovering: false) == .clear)
    }

    @Test
    func rowRendersMatchHighlightAndFallsBackToPlainTextForInvalidRanges() async throws {
        let variants: [LSPUsageRow] = [
            row(0),
            row(1, matchRange: nil),
            row(2, matchRange: NSRange(location: 4, length: 400)),
            row(3, matchRange: NSRange(location: -1, length: 2)),
            row(4, relativeDirectory: "")
        ]
        for variant in variants {
            let hosted = HostedViewFixture.host(size: NSSize(width: 620, height: 40)) {
                ShowUsagesRowView(row: variant, isSelected: variant.line == 0, onSelect: {}, onOpen: {})
            }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(50))

            #expect(hosted.renders())
        }
    }

    @Test
    func highlightedRowDiffersFromPlainRow() async throws {
        let highlighted = HostedViewFixture.host(size: NSSize(width: 620, height: 40)) {
            ShowUsagesRowView(row: row(0), isSelected: false, onSelect: {}, onOpen: {})
        }
        defer { highlighted.close() }
        let plain = HostedViewFixture.host(size: NSSize(width: 620, height: 40)) {
            ShowUsagesRowView(row: row(0, matchRange: nil), isSelected: false, onSelect: {}, onOpen: {})
        }
        defer { plain.close() }
        try await highlighted.settle(.milliseconds(50))
        try await plain.settle(.milliseconds(50))

        #expect(HostedView.pixelsDiffer(highlighted.snapshot(), plain.snapshot()))
    }

    @Test
    func hoverChangesAreAcceptedWhileTheRowIsRendered() async throws {
        let hosted = HostedViewFixture.host(size: NSSize(width: 620, height: 40)) {
            ShowUsagesRowView(row: row(0), isSelected: false, onSelect: {}, onOpen: {})
        }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(50))
        let view = ShowUsagesRowView(row: row(0), isSelected: false, onSelect: {}, onOpen: {})

        view.hoverChanged(true)
        view.hoverChanged(false)

        #expect(hosted.renders())
    }

    @Test
    func rowHeightFollowsTheUiDensity() {
        #expect(ShowUsagesRowView.rowHeight(isCompact: true) == 22)
        #expect(ShowUsagesRowView.rowHeight(isCompact: false) == 24)
    }
}
