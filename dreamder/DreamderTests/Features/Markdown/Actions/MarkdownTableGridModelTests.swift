import Foundation
import Testing
@testable import Dreamder

struct MarkdownTableGridModelTests {
    @Test
    func startsWithFourByFourGridAndOneByOneSelection() {
        let model = MarkdownTableGridModel()

        #expect(model.rows == 4)
        #expect(model.columns == 4)
        #expect(model.label == "1×1")
        #expect(model.contentRows == 0)
        #expect(model.tableColumns == 1)
    }

    @Test
    func selectingTheLastRowExpandsTheGridByTwo() {
        var model = MarkdownTableGridModel()

        model.select(row: 3, column: 1)

        #expect(model.rows == 6)
        #expect(model.columns == 4)
        #expect(model.label == "4×2")
        #expect(model.contentRows == 3)
        #expect(model.tableColumns == 2)
    }

    @Test
    func selectingTheLastColumnExpandsTheGridByTwo() {
        var model = MarkdownTableGridModel()

        model.select(row: 0, column: 3)

        #expect(model.rows == 4)
        #expect(model.columns == 6)
    }

    @Test
    func expansionStopsAtTenByTen() {
        var model = MarkdownTableGridModel()

        for _ in 0..<6 {
            model.select(row: model.rows - 1, column: model.columns - 1)
        }

        #expect(model.rows == 10)
        #expect(model.columns == 10)
        #expect(model.label == "10×10")
    }

    @Test
    func selectionIsClampedIntoTheGrid() {
        var model = MarkdownTableGridModel()

        model.select(row: -5, column: -5)
        #expect(model.label == "1×1")

        model.select(row: 99, column: 0)
        #expect(model.selectedRow == 3)
    }

    @Test
    func arrowMovesSelectionRelativeToTheCurrentCell() {
        var model = MarkdownTableGridModel()
        model.select(row: 1, column: 1)

        model.move(rowDelta: 1, columnDelta: -1)

        #expect(model.selectedRow == 2)
        #expect(model.selectedColumn == 0)
    }

    @Test
    func highlightCoversTheRectangleFromTheOrigin() {
        var model = MarkdownTableGridModel()
        model.select(row: 1, column: 2)

        #expect(model.isHighlighted(row: 1, column: 2))
        #expect(model.isHighlighted(row: 0, column: 0))
        #expect(model.isHighlighted(row: 2, column: 0) == false)
        #expect(model.isHighlighted(row: 0, column: 3) == false)
    }
}
