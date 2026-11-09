import AppKit
import Observation
import SwiftUI
import Testing
@testable import Dreamder

private struct TableRow: Identifiable, Hashable {
    let id: Int
}

@MainActor
@Observable
private final class TableDriver {
    var rows: [TableRow]
    var selection: TableRow?
    @ObservationIgnored var selectionWrites = 0

    init(rows: [TableRow], selection: TableRow? = nil) {
        self.rows = rows
        self.selection = selection
    }

    var binding: Binding<TableRow?> {
        Binding(
            get: { self.selection },
            set: { newValue in
                self.selectionWrites += 1
                self.selection = newValue
            }
        )
    }

    func makeWrapper(rowHeight: CGFloat = 24) -> NSTableViewWrapper<Text, TableRow> {
        NSTableViewWrapper(
            data: rows,
            rowHeight: rowHeight,
            selection: binding,
            itemView: { Text("row \($0.id)") }
        )
    }
}

private struct TableHost: View {
    let driver: TableDriver

    var body: some View {
        let _ = driver.selection
        driver.makeWrapper()
    }
}

@MainActor
@Suite(.uiGate)
struct NSTableViewWrapperTests {
    private typealias Wrapper = NSTableViewWrapper<Text, TableRow>

    private static let rows = [TableRow(id: 1), TableRow(id: 2), TableRow(id: 3)]

    private func host(_ driver: TableDriver) -> HostedView {
        HostedViewFixture.host(size: NSSize(width: 300, height: 200)) {
            TableHost(driver: driver)
        }
    }

    private func tableView(in hosted: HostedView) throws -> NSTableView {
        try #require(hosted.views(of: NSTableView.self).first)
    }

    private func standaloneTable(for coordinator: Wrapper.Coordinator) -> NSTableView {
        let table = NSTableView()
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("column")))
        table.dataSource = coordinator
        table.reloadData()
        return table
    }

    @Test
    func hostedTableListsTheRowsInASingleHeaderlessColumnThatNeverTakesFocus() async throws {
        let driver = TableDriver(rows: Self.rows)
        let hosted = host(driver)
        defer { hosted.close() }
        try await hosted.settle()

        let table = try tableView(in: hosted)
        #expect(table is Wrapper.NonRespondingTableView)
        #expect(table.acceptsFirstResponder == false)
        #expect(table.headerView == nil)
        #expect(table.tableColumns.map(\.identifier.rawValue) == ["column"])
        #expect(table.numberOfRows == 3)
        #expect(table.delegate != nil)

        let scrollView = try #require(hosted.views(of: Wrapper.NonRespondingScrollView.self).first)
        #expect(scrollView.acceptsFirstResponder == false)
        #expect(scrollView.hasVerticalScroller)
        #expect(scrollView.verticalScroller?.controlSize == .mini)
        #expect(table.selectedRow == -1)
    }

    @Test
    func boundSelectionIsMirroredIntoTheTableAndFollowsLaterChanges() async throws {
        let driver = TableDriver(rows: Self.rows, selection: Self.rows[1])
        let hosted = host(driver)
        defer { hosted.close() }
        try await hosted.settle()
        let table = try tableView(in: hosted)

        try await eventually(timeout: .seconds(30)) {
            hosted.layout()
            return table.selectedRow == 1
        }

        driver.selection = Self.rows[2]
        try await eventually(timeout: .seconds(30)) {
            hosted.layout()
            return table.selectedRow == 2
        }

        driver.selection = nil
        try await eventually(timeout: .seconds(30)) {
            hosted.layout()
            return table.selectedRow == -1
        }

        driver.selection = TableRow(id: 99)
        try await eventually(timeout: .seconds(30)) {
            hosted.layout()
            return table.selectedRow == -1
        }
        #expect(driver.selectionWrites == 0)
    }

    @Test
    func changingTheDataReloadsTheRows() async throws {
        let driver = TableDriver(rows: Self.rows)
        let hosted = host(driver)
        defer { hosted.close() }
        try await hosted.settle()
        let table = try tableView(in: hosted)

        driver.rows = [TableRow(id: 7)]

        try await eventually(timeout: .seconds(30)) {
            hosted.layout()
            return table.numberOfRows == 1
        }
    }

    @Test
    func choosingARowInTheTableWritesTheBindingOnce() async throws {
        let driver = TableDriver(rows: Self.rows)
        let hosted = host(driver)
        defer { hosted.close() }
        try await hosted.settle()
        let table = try tableView(in: hosted)

        table.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false)

        #expect(driver.selection == Self.rows[2])
        #expect(driver.selectionWrites == 1)

        table.deselectAll(nil)
        #expect(driver.selection == nil)
        #expect(driver.selectionWrites == 2)
    }

    @Test
    func hostedTableBuildsHostingCellsForEveryRow() async throws {
        let driver = TableDriver(rows: Self.rows)
        let hosted = host(driver)
        defer { hosted.close() }
        try await hosted.settle()
        let table = try tableView(in: hosted)

        let cell = try #require(table.view(atColumn: 0, row: 1, makeIfNecessary: true) as? NSTableCellView)
        #expect(cell.subviews.count == 1)
        #expect(cell.subviews.first is NSHostingView<Text>)
        let rowView = try #require(table.rowView(atRow: 1, makeIfNecessary: true))
        #expect(rowView is Wrapper.Coordinator.AlwaysActiveTableRowView)
    }

    @Test
    func coordinatorServesRowCountHeightsAndAlwaysEmphasizedRows() {
        let driver = TableDriver(rows: Self.rows)
        let coordinator = driver.makeWrapper(rowHeight: 42).makeCoordinator()
        let table = standaloneTable(for: coordinator)

        #expect(coordinator.numberOfRows(in: table) == 3)
        #expect(coordinator.tableView(table, heightOfRow: 2) == 42)
        let rowView = coordinator.tableView(table, rowViewForRow: 0)
        #expect(rowView is Wrapper.Coordinator.AlwaysActiveTableRowView)
        rowView?.isEmphasized = false
        #expect(rowView?.isEmphasized == true)
    }

    @Test
    func coordinatorBuildsACenteredHostingCellForTheRowItem() throws {
        let driver = TableDriver(rows: Self.rows)
        let coordinator = driver.makeWrapper().makeCoordinator()
        let table = standaloneTable(for: coordinator)

        let cell = try #require(coordinator.tableView(table, viewFor: table.tableColumns.first, row: 2) as? NSTableCellView)

        let hosting = try #require(cell.subviews.first as? NSHostingView<Text>)
        #expect(hosting.translatesAutoresizingMaskIntoConstraints == false)
        let attributes = Set(cell.constraints.map(\.firstAttribute))
        #expect(attributes == [.centerY, .left, .right])
        #expect(cell.constraints.allSatisfy { $0.firstItem === hosting && $0.secondItem === cell })
    }

    @Test
    func coordinatorSelectionChangesUpdateTheBindingOnlyWhenTheItemDiffers() {
        let driver = TableDriver(rows: Self.rows)
        let coordinator = driver.makeWrapper().makeCoordinator()
        let table = standaloneTable(for: coordinator)
        let notification = Notification(name: NSTableView.selectionDidChangeNotification, object: table)

        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        coordinator.tableViewSelectionDidChange(notification)
        #expect(driver.selection == Self.rows[1])
        #expect(driver.selectionWrites == 1)

        coordinator.tableViewSelectionDidChange(notification)
        #expect(driver.selectionWrites == 1)

        table.deselectAll(nil)
        coordinator.tableViewSelectionDidChange(notification)
        #expect(driver.selection == nil)
        #expect(driver.selectionWrites == 2)

        coordinator.tableViewSelectionDidChange(Notification(name: NSTableView.selectionDidChangeNotification))
        #expect(driver.selectionWrites == 2)
    }
}
