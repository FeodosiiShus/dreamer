import Foundation

nonisolated struct MarkdownTableNavigation: Sendable, Equatable {
    let caret: Int
}

nonisolated struct MarkdownTableEnterResult: Sendable, Equatable {
    let action: MarkdownActionResult
    let previousBreakCaret: Int?
}

nonisolated extension MarkdownTable {
    private static let lineBreakTag = "<br/>"

    static func navigate(text: String, caret: Int, forward: Bool) -> MarkdownTableNavigation? {
        let document = MarkdownDocument(text)
        guard let context = cellContext(document: document, caret: caret),
              !context.layout.isInsideListItem(document: document) else {
            return nil
        }
        let units = document.text.units
        let layout = context.layout
        let row = layout.rows[context.rowPosition]
        if let target = adjacentCell(
            layout: layout,
            rowPosition: context.rowPosition,
            cell: context.cell,
            forward: forward
        ) {
            let range = layout.rows[target.row].cells[target.cell]
            let caret = forward ? firstNonSpace(units, range) : min(lastNonSpace(units, range) + 1, range.upperBound)
            return MarkdownTableNavigation(caret: caret)
        }
        return forward ? MarkdownTableNavigation(caret: row.end) : nil
    }

    static func enterInCell(text: String, caret: Int, previousBreakCaret: Int?) -> MarkdownTableEnterResult? {
        let document = MarkdownDocument(text)
        guard let context = cellContext(document: document, caret: caret) else { return nil }
        let tag = Array(lineBreakTag.utf16)
        var buffer = MarkdownEditBuffer(text)
        if caret == previousBreakCaret {
            guard caret > tag.count, Array(document.text.units[(caret - tag.count)..<caret]) == tag else { return nil }
            let start = caret - tag.count
            let row = context.layout.rows[context.rowPosition]
            let prefix = document.text.string(row.lineStart..<row.bodyStart)
            buffer.delete(start..<caret)
            let lineBreak = "\n" + prefix
            buffer.insert(lineBreak, at: start)
            let afterBreak = start + lineBreak.utf16.count
            var trailing = afterBreak
            while trailing < buffer.length, MarkdownText.isSpaceOrTab(buffer.units[trailing]) {
                trailing += 1
            }
            buffer.delete(afterBreak..<trailing)
            let result = buffer.result(selections: [NSRange(location: afterBreak, length: 0)])
            return MarkdownTableEnterResult(action: result, previousBreakCaret: nil)
        }
        buffer.insert(lineBreakTag, at: caret)
        let newCaret = caret + tag.count
        let result = buffer.result(selections: [NSRange(location: newCaret, length: 0)])
        return MarkdownTableEnterResult(action: result, previousBreakCaret: newCaret)
    }

    static func shiftEnter(
        text: String,
        caret: Int,
        style: MarkdownTableStyle = .aligned
    ) -> MarkdownActionResult? {
        let document = MarkdownDocument(text)
        let units = document.text.units
        guard caret > 0, caret <= units.count else { return nil }
        let lineIndex = document.text.lineIndex(containing: caret)
        let line = document.text.lines[lineIndex]
        guard isProbablyInsideCell(document.text, caret: caret) || isAtRowEnd(document.text, caret: caret, line: line),
              let layout = MarkdownTableLayout.find(in: document, containing: caret),
              let position = layout.rowPosition(ofLine: lineIndex),
              position != 0 else {
            return nil
        }
        let row = layout.rows[position]
        let emptyRow = layout.emptyRow(style: style, units: units)
        let prefix = document.text.string(row.lineStart..<row.bodyStart)
        let insertion = "\n" + prefix + emptyRow
        var buffer = MarkdownEditBuffer(text)
        buffer.insert(insertion, at: line.contentEnd)
        let newRowStart = line.contentEnd + 1 + prefix.utf16.count
        let secondCharacter = emptyRow.utf16.dropFirst().first
        let firstCellContent = newRowStart + 1 + (secondCharacter == MarkdownText.space ? 1 : 0)
        return buffer.result(selections: [NSRange(location: firstCellContent, length: 0)])
    }

    private static func isAtRowEnd(_ text: MarkdownText, caret: Int, line: MarkdownText.Line) -> Bool {
        guard caret <= line.contentEnd else { return false }
        return text.units[caret..<line.contentEnd].allSatisfy { MarkdownText.isSpaceOrTab($0) }
    }

    private static func adjacentCell(
        layout: MarkdownTableLayout,
        rowPosition: Int,
        cell: Int,
        forward: Bool
    ) -> (row: Int, cell: Int)? {
        let siblingCell = cell + (forward ? 1 : -1)
        if layout.rows[rowPosition].cells.indices.contains(siblingCell) {
            return (rowPosition, siblingCell)
        }
        let nextRow: Int
        if forward {
            nextRow = rowPosition == 0 ? 2 : rowPosition + 1
        } else {
            guard rowPosition > 0 else { return nil }
            nextRow = rowPosition == 2 ? 0 : rowPosition - 1
        }
        guard layout.rows.indices.contains(nextRow) else { return nil }
        let cells = layout.rows[nextRow].cells
        guard !cells.isEmpty else { return nil }
        return (nextRow, forward ? 0 : cells.count - 1)
    }

    private static func firstNonSpace(_ units: [UInt16], _ cell: Range<Int>) -> Int {
        cell.first { units[$0] != MarkdownText.space } ?? cell.lowerBound
    }

    private static func lastNonSpace(_ units: [UInt16], _ cell: Range<Int>) -> Int {
        cell.last { units[$0] != MarkdownText.space } ?? cell.lowerBound
    }
}
