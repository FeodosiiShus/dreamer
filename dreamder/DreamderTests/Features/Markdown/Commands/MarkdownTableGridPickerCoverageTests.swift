import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
final class MarkdownTableGridPickerCoverageRecorder {
    private(set) var selections: [[Int]] = []

    func record(contentRows: Int, columns: Int) {
        selections.append([contentRows, columns])
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct MarkdownTableGridPickerCoverage {
    private let step = MarkdownTableGridPicker.cellSize + MarkdownTableGridPicker.cellSpacing

    private func center(row: Int, column: Int) -> CGPoint {
        CGPoint(x: CGFloat(column) * step + step / 2, y: CGFloat(row) * step + step / 2)
    }

    private func makePicker(
        selection: MarkdownTableGridSelection,
        recorder: MarkdownTableGridPickerCoverageRecorder
    ) -> MarkdownTableGridPicker {
        MarkdownTableGridPicker(selection: selection) { contentRows, columns in
            recorder.record(contentRows: contentRows, columns: columns)
        }
    }

    @Test
    func selectionStartsOnTheFirstCellOfAFourByFourGrid() {
        let selection = MarkdownTableGridSelection()

        #expect(selection.grid == MarkdownTableGridModel())
        #expect(selection.grid.label == "1×1")
    }

    @Test
    func selectionSelectsAndMovesLikeTheGridModel() {
        let selection = MarkdownTableGridSelection()

        selection.select(row: 2, column: 1)
        #expect(selection.grid.selectedRow == 2)
        #expect(selection.grid.selectedColumn == 1)

        selection.move(rowDelta: 1, columnDelta: 2)
        #expect(selection.grid.selectedRow == 3)
        #expect(selection.grid.selectedColumn == 3)
        #expect(selection.grid.rows == 6)
        #expect(selection.grid.columns == 6)
    }

    @Test
    func defaultPickerOwnsAFreshSelection() {
        let recorder = MarkdownTableGridPickerCoverageRecorder()
        let picker = MarkdownTableGridPicker { contentRows, columns in
            recorder.record(contentRows: contentRows, columns: columns)
        }

        picker.tap(at: center(row: 1, column: 1))

        #expect(recorder.selections == [[1, 2]])
    }

    @Test
    func hostedPickerRendersTheInitialGridAndLabel() async throws {
        let recorder = MarkdownTableGridPickerCoverageRecorder()
        let hosted = HostedViewFixture.host(size: NSSize(width: 200, height: 200)) {
            makePicker(selection: MarkdownTableGridSelection(), recorder: recorder)
        }
        defer { hosted.close() }

        try await hosted.settle()

        #expect(hosted.renders())
        #expect(recorder.selections.isEmpty)
    }

    @Test
    func hoveringACellMovesTheHighlightAndRedraws() async throws {
        let selection = MarkdownTableGridSelection()
        let recorder = MarkdownTableGridPickerCoverageRecorder()
        let picker = makePicker(selection: selection, recorder: recorder)
        let hosted = HostedViewFixture.host(size: NSSize(width: 200, height: 200)) { picker }
        defer { hosted.close() }
        try await hosted.settle()
        let initial = hosted.snapshot()

        picker.hover(.active(center(row: 2, column: 3)))
        try await hosted.settle()

        #expect(selection.grid.selectedRow == 2)
        #expect(selection.grid.selectedColumn == 3)
        #expect(selection.grid.label == "3×4")
        #expect(HostedView.pixelsDiffer(initial, hosted.snapshot()))
        #expect(recorder.selections.isEmpty)
    }

    @Test
    func endingTheHoverKeepsTheSelection() {
        let selection = MarkdownTableGridSelection()
        let picker = makePicker(selection: selection, recorder: MarkdownTableGridPickerCoverageRecorder())
        picker.hover(.active(center(row: 1, column: 1)))

        picker.hover(.ended)

        #expect(selection.grid.selectedRow == 1)
        #expect(selection.grid.selectedColumn == 1)
    }

    @Test
    func hoveringTheLastRowAndColumnGrowsTheGridUpToTheMaximum() async throws {
        let selection = MarkdownTableGridSelection()
        let picker = makePicker(selection: selection, recorder: MarkdownTableGridPickerCoverageRecorder())
        let hosted = HostedViewFixture.host(size: NSSize(width: 300, height: 300)) { picker }
        defer { hosted.close() }
        try await hosted.settle()
        let initial = hosted.snapshot()

        picker.hover(.active(center(row: 3, column: 3)))
        try await hosted.settle()
        #expect(selection.grid.rows == 6)
        #expect(selection.grid.columns == 6)
        let grown = hosted.snapshot()
        #expect(HostedView.pixelsDiffer(initial, grown))

        picker.hover(.active(center(row: 5, column: 5)))
        picker.hover(.active(center(row: 7, column: 7)))
        picker.hover(.active(center(row: 9, column: 9)))
        try await hosted.settle()
        #expect(selection.grid.rows == MarkdownTableGridModel.maximumSize)
        #expect(selection.grid.columns == MarkdownTableGridModel.maximumSize)
        #expect(selection.grid.label == "10×10")
        #expect(HostedView.pixelsDiffer(grown, hosted.snapshot()))
    }

    @Test
    func tappingACellSelectsItAndConfirmsTheTableSize() {
        let selection = MarkdownTableGridSelection()
        let recorder = MarkdownTableGridPickerCoverageRecorder()
        let picker = makePicker(selection: selection, recorder: recorder)

        picker.tap(at: center(row: 2, column: 3))

        #expect(selection.grid.selectedRow == 2)
        #expect(selection.grid.selectedColumn == 3)
        #expect(recorder.selections == [[2, 4]])
    }

    @Test
    func tappingOutsideTheGridClampsToTheNearestCell() {
        let selection = MarkdownTableGridSelection()
        let recorder = MarkdownTableGridPickerCoverageRecorder()
        let picker = makePicker(selection: selection, recorder: recorder)

        picker.tap(at: CGPoint(x: -40, y: -40))
        picker.tap(at: CGPoint(x: 5_000, y: 5_000))

        #expect(recorder.selections.count == 2)
        #expect(recorder.selections[0] == [0, 1])
        #expect(recorder.selections[1][0] > 0)
        #expect(recorder.selections[1][1] > 1)
    }

    @Test
    func arrowKeysMoveTheSelectionAndAreHandled() {
        let selection = MarkdownTableGridSelection()
        let picker = makePicker(selection: selection, recorder: MarkdownTableGridPickerCoverageRecorder())

        #expect(picker.moveRight() == .handled)
        #expect(picker.moveRight() == .handled)
        #expect(picker.moveDown() == .handled)
        #expect(selection.grid.selectedRow == 1)
        #expect(selection.grid.selectedColumn == 2)

        #expect(picker.moveLeft() == .handled)
        #expect(picker.moveUp() == .handled)
        #expect(selection.grid.selectedRow == 0)
        #expect(selection.grid.selectedColumn == 1)

        #expect(picker.moveUp() == .handled)
        #expect(picker.moveLeft() == .handled)
        #expect(picker.moveLeft() == .handled)
        #expect(selection.grid.selectedRow == 0)
        #expect(selection.grid.selectedColumn == 0)
    }

    @Test
    func returnKeyConfirmsTheCurrentSelection() {
        let selection = MarkdownTableGridSelection()
        let recorder = MarkdownTableGridPickerCoverageRecorder()
        let picker = makePicker(selection: selection, recorder: recorder)
        _ = picker.moveDown()
        _ = picker.moveRight()
        _ = picker.moveRight()

        #expect(picker.confirmFromKeyboard() == .handled)

        #expect(recorder.selections == [[1, 3]])
    }
}
