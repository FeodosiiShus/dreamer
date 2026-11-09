import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
private final class SearchPanelBuildLog {
    var rows: Set<Int> = []
    var widths: [Int: CGFloat] = [:]
    var previews: [Int] = []
}

private struct SearchPanelProbeRow: View {
    let id: Int
    let log: SearchPanelBuildLog

    var body: some View {
        recordBuild()
        return Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: { log.widths[id] = $0 })
    }

    private func recordBuild() {
        log.rows.insert(id)
    }
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
                SearchPanelView<SearchPanelProbeRow, Text, SearchPanelTestItem>(
                    title: "Preview panel",
                    image: Image(systemName: "magnifyingglass"),
                    options: .constant(options),
                    text: .constant(text),
                    alwaysShowOptions: alwaysShowOptions,
                    content: { item in
                        SearchPanelProbeRow(id: item.id, log: log)
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
            SearchPanelView<SearchPanelProbeRow, EmptyView, SearchPanelTestItem>(
                title: "Plain panel",
                image: Image(systemName: "magnifyingglass"),
                options: .constant(options),
                text: .constant(text),
                alwaysShowOptions: alwaysShowOptions,
                content: { item in
                    SearchPanelProbeRow(id: item.id, log: log)
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

        #expect(log.rows.isEmpty)
    }

    @Test
    func alwaysShowOptionsListsEveryRowWithoutAQuery() async throws {
        let log = SearchPanelBuildLog()
        let hosted = HostedViewFixture.host {
            panel(options: Self.items, text: "", alwaysShowOptions: true, log: log)
        }
        defer { hosted.close() }

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

        #expect(log.rows.isEmpty)
        #expect(hosted.renders())
    }

    @Test
    func aQueryWithOptionsShowsTheRows() async throws {
        let log = SearchPanelBuildLog()
        let hosted = HostedViewFixture.host {
            panel(options: Self.items, text: "query", log: log)
        }
        defer { hosted.close() }

        try await eventually(timeout: .seconds(30)) { log.rows == Set(Self.items.map(\.id)) }
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

        #expect(log.rows.isEmpty)
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
        let withPreviewLog = SearchPanelBuildLog()
        let withoutPreviewLog = SearchPanelBuildLog()
        let withPreview = HostedViewFixture.host {
            panel(options: Self.items, text: "query", withPreview: true, log: withPreviewLog)
        }
        let withoutPreview = HostedViewFixture.host {
            panel(options: Self.items, text: "query", log: withoutPreviewLog)
        }
        defer {
            withPreview.close()
            withoutPreview.close()
        }
        func rowWidth(_ hosted: HostedView, _ log: SearchPanelBuildLog) -> CGFloat {
            hosted.layout()
            return log.widths[1] ?? 0
        }

        try await eventually(timeout: .seconds(30)) {
            rowWidth(withPreview, withPreviewLog) > 0 && rowWidth(withoutPreview, withoutPreviewLog) > 0
        }

        #expect(rowWidth(withPreview, withPreviewLog) <= 272)
        #expect(rowWidth(withoutPreview, withoutPreviewLog) > 600)
    }
}
