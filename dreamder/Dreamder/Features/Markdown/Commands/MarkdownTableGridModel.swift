import Foundation

nonisolated struct MarkdownTableGridModel: Equatable, Sendable {
    static let initialSize = 4
    static let expandFactor = 2
    static let maximumSize = 10

    private(set) var rows = MarkdownTableGridModel.initialSize
    private(set) var columns = MarkdownTableGridModel.initialSize
    private(set) var selectedRow = 0
    private(set) var selectedColumn = 0

    var label: String {
        "\(selectedRow + 1)×\(selectedColumn + 1)"
    }

    var contentRows: Int { selectedRow }
    var tableColumns: Int { selectedColumn + 1 }

    mutating func select(row: Int, column: Int) {
        selectedRow = min(max(row, 0), rows - 1)
        selectedColumn = min(max(column, 0), columns - 1)
        if rows < Self.maximumSize, selectedRow + 1 == rows {
            rows += Self.expandFactor
        }
        if columns < Self.maximumSize, selectedColumn + 1 == columns {
            columns += Self.expandFactor
        }
    }

    mutating func move(rowDelta: Int, columnDelta: Int) {
        select(row: selectedRow + rowDelta, column: selectedColumn + columnDelta)
    }

    func isHighlighted(row: Int, column: Int) -> Bool {
        row <= selectedRow && column <= selectedColumn
    }
}
