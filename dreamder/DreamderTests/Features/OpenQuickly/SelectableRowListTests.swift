import AppKit
import Observation
import SwiftUI
import Testing
@testable import Dreamder

private struct ListRow: Identifiable, Hashable {
    let id: Int
}

@MainActor
private final class ListRowLog {
    var sizes: [Int: CGSize] = [:]
}

@MainActor
@Observable
private final class ListDriver {
    var rows: [ListRow]
    var selection: ListRow?
    @ObservationIgnored var selectionWrites = 0
    @ObservationIgnored var activations = 0
    @ObservationIgnored let log = ListRowLog()

    init(rows: [ListRow], selection: ListRow? = nil) {
        self.rows = rows
        self.selection = selection
    }

    var binding: Binding<ListRow?> {
        Binding(
            get: { self.selection },
            set: { newValue in
                self.selectionWrites += 1
                self.selection = newValue
            }
        )
    }

    func makeList(rowHeight: CGFloat = 24) -> SelectableRowList<ListRow, ListProbeRow> {
        SelectableRowList(
            data: rows,
            rowHeight: rowHeight,
            selection: binding,
            onActivate: { self.activations += 1 },
            itemView: { ListProbeRow(row: $0, log: self.log) }
        )
    }
}

private struct ListProbeRow: View {
    let row: ListRow
    let log: ListRowLog

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onGeometryChange(for: CGSize.self, of: { $0.size }, action: { log.sizes[row.id] = $0 })
    }
}

private struct ListHost: View {
    let driver: ListDriver
    let rowHeight: CGFloat

    var body: some View {
        trackedList()
    }

    private func trackedList() -> SelectableRowList<ListRow, ListProbeRow> {
        _ = driver.selection
        _ = driver.rows
        return driver.makeList(rowHeight: rowHeight)
    }
}

@MainActor
@Suite(.uiGate)
struct SelectableRowListTests {
    private static let first = ListRow(id: 1)
    private static let second = ListRow(id: 2)
    private static let rows = [first, second, ListRow(id: 3)]

    private func host(_ driver: ListDriver, rowHeight: CGFloat = 24) -> HostedView {
        HostedViewFixture.host(size: NSSize(width: 300, height: 200)) {
            ListHost(driver: driver, rowHeight: rowHeight)
        }
    }

    @Test
    func everyRowIsBuiltAtTheRequestedHeightAndTheFullWidth() async throws {
        let driver = ListDriver(rows: Self.rows)
        let hosted = host(driver, rowHeight: 42)
        defer { hosted.close() }

        try await eventually(timeout: .seconds(30)) {
            hosted.layout()
            return driver.log.sizes.count == Self.rows.count
        }

        let heights = Set(driver.log.sizes.values.map(\.height))
        let widths = Set(driver.log.sizes.values.map(\.width))
        #expect(heights == [42])
        #expect(widths.count == 1)
        #expect((widths.first ?? 0) > 250)
        #expect(driver.selectionWrites == 0)
    }

    @Test
    func theListUsesNoAppKitTableAndHostsNoNestedHostingViews() async throws {
        let driver = ListDriver(rows: Self.rows)
        let hosted = host(driver)
        defer { hosted.close() }
        try await eventually(timeout: .seconds(30)) {
            hosted.layout()
            return driver.log.sizes.count == Self.rows.count
        }

        #expect(hosted.views(of: NSTableView.self).isEmpty)
        #expect(hosted.views(of: NSTableCellView.self).isEmpty)
    }

    @Test
    func aSelectionBelowTheFoldIsScrolledIntoView() async throws {
        let many = (1...100).map { ListRow(id: $0) }
        let driver = ListDriver(rows: many)
        let hosted = host(driver)
        defer { hosted.close() }
        try await eventually(timeout: .seconds(30)) {
            hosted.layout()
            return driver.log.sizes[1] != nil
        }
        #expect(driver.log.sizes[90] == nil)

        driver.selection = ListRow(id: 90)
        try await eventually(timeout: .seconds(30)) {
            hosted.layout()
            return driver.log.sizes[90] != nil
        }

        driver.selection = ListRow(id: 50)
        try await eventually(timeout: .seconds(30)) {
            hosted.layout()
            return driver.log.sizes[50] != nil
        }
        #expect(driver.selectionWrites == 0)
    }

    @Test
    func aStaleSelectionAndChangingDataNeverWriteTheBinding() async throws {
        let driver = ListDriver(rows: Self.rows, selection: ListRow(id: 99))
        let hosted = host(driver)
        defer { hosted.close() }
        try await eventually(timeout: .seconds(30)) {
            hosted.layout()
            return driver.log.sizes.count == Self.rows.count
        }

        driver.rows = [ListRow(id: 7), ListRow(id: 8)]
        try await eventually(timeout: .seconds(30)) {
            hosted.layout()
            return driver.log.sizes[7] != nil && driver.log.sizes[8] != nil
        }
        driver.selection = nil
        driver.rows = [ListRow(id: 9)]
        try await eventually(timeout: .seconds(30)) {
            hosted.layout()
            return driver.log.sizes[9] != nil
        }

        #expect(driver.selectionWrites == 0)
    }

    @Test
    func rowsMirrorTheBoundSelectionAndWriteItBackOnSelectAndActivate() {
        let driver = ListDriver(rows: Self.rows, selection: Self.second)
        let list = driver.makeList(rowHeight: 31)

        let first = list.rowView(for: Self.first)
        let selected = list.rowView(for: Self.second)
        #expect(!first.isSelected)
        #expect(selected.isSelected)
        #expect(first.height == 31)

        first.onSelect()
        #expect(driver.selection == Self.first)
        #expect(driver.selectionWrites == 1)
        #expect(driver.activations == 0)

        selected.onActivate()
        #expect(driver.selection == Self.second)
        #expect(driver.selectionWrites == 2)
        #expect(driver.activations == 1)
    }

    @Test
    func rowBackgroundPrefersSelectionThenHoverThenClear() {
        typealias Row = SelectableRow<EmptyView>
        #expect(Row.backgroundColor(isSelected: true, isHovering: true) == Islands.selection)
        #expect(Row.backgroundColor(isSelected: true, isHovering: false) == Islands.selection)
        #expect(Row.backgroundColor(isSelected: false, isHovering: true) == Islands.hover)
        #expect(Row.backgroundColor(isSelected: false, isHovering: false) == .clear)
    }

    @Test
    func hoverChangesNeverTouchTheSelectionOrActivation() {
        let driver = ListDriver(rows: Self.rows, selection: Self.second)
        let row = driver.makeList().rowView(for: Self.first)

        row.hoverChanged(true)
        row.hoverChanged(false)

        #expect(driver.selection == Self.second)
        #expect(driver.selectionWrites == 0)
        #expect(driver.activations == 0)
    }
}
