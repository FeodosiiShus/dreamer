import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
private final class SearchPanelBuildLog {
    var rows: Set<Int> = []
    var previews: [Int] = []
}

@MainActor
@Suite(.uiGate)
struct SearchPanelViewTests {
    private static let items = (1...3).map { SearchPanelTestItem(id: $0) }

    private func panel(
        options: [SearchPanelTestItem],
        text: String,
        alwaysShowOptions: Bool = false,
        withPreview: Bool = false,
        log: SearchPanelBuildLog
    ) -> AnyView {
        if withPreview {
            return AnyView(
                SearchPanelView<Text, Text, SearchPanelTestItem>(
                    title: "Preview panel",
                    image: Image(systemName: "magnifyingglass"),
                    options: .constant(options),
                    text: .constant(text),
                    alwaysShowOptions: alwaysShowOptions,
                    content: { item in
                        log.rows.insert(item.id)
                        return Text("row \(item.id)")
                    },
                    preview: { item in
                        log.previews.append(item.id)
                        return Text("preview \(item.id)")
                    },
                    onRowClick: { _ in },
                    onClose: {}
                )
            )
        }
        return AnyView(
            SearchPanelView<Text, EmptyView, SearchPanelTestItem>(
                title: "Plain panel",
                image: Image(systemName: "magnifyingglass"),
                options: .constant(options),
                text: .constant(text),
                alwaysShowOptions: alwaysShowOptions,
                content: { item in
                    log.rows.insert(item.id)
                    return Text("row \(item.id)")
                },
                onRowClick: { _ in },
                onClose: {}
            )
        )
    }

    @Test
    func collapsedPanelShowsNoOptionList() async throws {
        let log = SearchPanelBuildLog()
        let hosted = HostedViewFixture.host {
            panel(options: Self.items, text: "", log: log)
        }
        defer { hosted.close() }

        try await hosted.settle(.milliseconds(100))

        #expect(hosted.views(of: NSTableView.self).isEmpty)
        #expect(log.rows.isEmpty)
    }

    @Test
    func alwaysShowOptionsListsEveryRowWithoutAQuery() async throws {
        let log = SearchPanelBuildLog()
        let hosted = HostedViewFixture.host {
            panel(options: Self.items, text: "", alwaysShowOptions: true, log: log)
        }
        defer { hosted.close() }

        try await eventually(timeout: .seconds(30)) {
            hosted.layout()
            return hosted.views(of: NSTableView.self).first?.numberOfRows == Self.items.count
        }
        try await eventually(timeout: .seconds(30)) { log.rows == Set(Self.items.map(\.id)) }
    }

    @Test
    func aQueryWithoutMatchingOptionsShowsNoTable() async throws {
        let log = SearchPanelBuildLog()
        let hosted = HostedViewFixture.host {
            panel(options: [], text: "query", log: log)
        }
        defer { hosted.close() }

        try await hosted.settle(.milliseconds(100))

        #expect(hosted.views(of: NSTableView.self).isEmpty)
        #expect(hosted.renders())
    }

    @Test
    func aQueryWithOptionsShowsTheRows() async throws {
        let log = SearchPanelBuildLog()
        let hosted = HostedViewFixture.host {
            panel(options: Self.items, text: "query", log: log)
        }
        defer { hosted.close() }

        try await eventually(timeout: .seconds(30)) {
            hosted.layout()
            return hosted.views(of: NSTableView.self).first?.numberOfRows == Self.items.count
        }
    }

    @Test
    func previewFollowsTheFirstOptionOnceTheSelectionSyncs() async throws {
        let log = SearchPanelBuildLog()
        let hosted = HostedViewFixture.host {
            panel(options: Self.items, text: "query", withPreview: true, log: log)
        }
        defer { hosted.close() }

        try await eventually(timeout: .seconds(30)) {
            hosted.layout()
            return log.previews.contains(1)
        }
        #expect(log.previews.contains(2) == false)
    }

    @Test
    func previewPaneWithoutOptionsShowsNoTable() async throws {
        let log = SearchPanelBuildLog()
        let hosted = HostedViewFixture.host {
            panel(options: [], text: "query", withPreview: true, log: log)
        }
        defer { hosted.close() }

        try await hosted.settle(.milliseconds(100))

        #expect(hosted.views(of: NSTableView.self).isEmpty)
        #expect(log.previews.isEmpty)
        #expect(hosted.renders())
    }

    @Test
    func previewToggleDrawsDifferentGlyphsForEachState() async throws {
        let visible = HostedViewFixture.host(size: NSSize(width: 60, height: 60)) {
            PreviewToggle(previewVisible: true)
        }
        let hidden = HostedViewFixture.host(size: NSSize(width: 60, height: 60)) {
            PreviewToggle(previewVisible: false)
        }
        defer {
            visible.close()
            hidden.close()
        }
        try await visible.settle(.milliseconds(50))
        try await hidden.settle(.milliseconds(50))

        #expect(visible.renders())
        #expect(hidden.renders())
        #expect(HostedView.pixelsDiffer(visible.snapshot(), hidden.snapshot()))
    }

    @Test
    func previewReservesTheTrailingPaneAndNarrowsTheOptionList() async throws {
        let log = SearchPanelBuildLog()
        let withPreview = HostedViewFixture.host {
            panel(options: Self.items, text: "query", withPreview: true, log: log)
        }
        let withoutPreview = HostedViewFixture.host {
            panel(options: Self.items, text: "query", log: log)
        }
        defer {
            withPreview.close()
            withoutPreview.close()
        }
        func tableWidth(_ hosted: HostedView) -> CGFloat {
            hosted.layout()
            return hosted.views(of: NSTableView.self).first?.enclosingScrollView?.frame.width ?? 0
        }

        try await eventually(timeout: .seconds(30)) { tableWidth(withPreview) > 0 && tableWidth(withoutPreview) > 0 }

        #expect(tableWidth(withPreview) <= 272)
        #expect(tableWidth(withoutPreview) > 600)
    }
}
