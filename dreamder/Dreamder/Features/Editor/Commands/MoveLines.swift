import Foundation

nonisolated enum MoveLines {
    private struct Move {
        let block: ClosedRange<Int>
        let firstLine: Int
        let order: [Int]
        let slotStarts: [Int]
        let blockSlotOffset: Int

        func slot(ofLine line: Int) -> Int {
            line - block.lowerBound + blockSlotOffset
        }
    }

    static func perform(in text: NSString, selections: [NSRange], up: Bool) -> EditorCommandResult? {
        guard !selections.isEmpty else { return nil }
        let index = EditorLineIndex(text)
        let movableCount = index.lines[index.count - 1].contentLength == 0 ? index.count - 1 : index.count
        let moves = index.touchedLineBlocks(by: selections, mergingAdjacent: true)
            .compactMap { clipped($0, movableCount: movableCount) }
            .filter { up ? $0.lowerBound > 0 : $0.upperBound + 1 < movableCount }
            .map { makeMove(block: $0, up: up, index: index) }
        guard !moves.isEmpty else { return nil }

        let edits = moves.map { edit(for: $0, in: text, index: index) }
        let resultingSelections = selections.map { selection -> NSRange in
            let line = index.lineIndex(containing: selection.location)
            guard let move = moves.first(where: { $0.block.contains(line) }) else { return selection }
            let start = mappedOffset(selection.location, move: move, index: index)
            let end = mappedOffset(NSMaxRange(selection), move: move, index: index)
            return NSRange(location: start, length: end - start)
        }
        return EditorCommandResult(edits: edits, selections: resultingSelections.sorted { $0.location < $1.location })
    }

    private static func clipped(_ block: ClosedRange<Int>, movableCount: Int) -> ClosedRange<Int>? {
        guard block.lowerBound < movableCount else { return nil }
        return block.lowerBound...min(block.upperBound, movableCount - 1)
    }

    private static func makeMove(block: ClosedRange<Int>, up: Bool, index: EditorLineIndex) -> Move {
        let blockLines = Array(block)
        let order: [Int]
        let firstLine: Int
        if up {
            firstLine = block.lowerBound - 1
            order = blockLines + [firstLine]
        } else {
            firstLine = block.lowerBound
            order = [block.upperBound + 1] + blockLines
        }
        var slotStarts: [Int] = []
        var cursor = index.lines[firstLine].start
        for (slot, line) in order.enumerated() {
            slotStarts.append(cursor)
            cursor += index.lines[line].contentLength + terminatorLength(ofSlot: firstLine + slot, index: index)
        }
        return Move(
            block: block,
            firstLine: firstLine,
            order: order,
            slotStarts: slotStarts,
            blockSlotOffset: up ? 0 : 1
        )
    }

    private static func edit(for move: Move, in text: NSString, index: EditorLineIndex) -> EditorTextEdit {
        let lastLine = move.firstLine + move.order.count - 1
        var replacement = ""
        for (slot, line) in move.order.enumerated() {
            replacement += text.substring(with: index.lines[line].contentRange)
            if move.firstLine + slot < lastLine {
                replacement += text.substring(with: terminatorRange(ofSlot: move.firstLine + slot, index: index))
            }
        }
        let start = index.lines[move.firstLine].start
        return EditorTextEdit(
            range: NSRange(location: start, length: index.lines[lastLine].contentEnd - start),
            replacement: replacement
        )
    }

    private static func mappedOffset(_ offset: Int, move: Move, index: EditorLineIndex) -> Int {
        let line = index.lineIndex(containing: offset)
        if line > move.block.upperBound {
            let slot = move.slot(ofLine: move.block.upperBound)
            return move.slotStarts[slot]
                + index.lines[move.block.upperBound].contentLength
                + terminatorLength(ofSlot: move.firstLine + slot, index: index)
        }
        let slot = move.slot(ofLine: line)
        return move.slotStarts[slot] + offset - index.lines[line].start
    }

    private static func terminatorLength(ofSlot line: Int, index: EditorLineIndex) -> Int {
        index.lines[line].end - index.lines[line].contentEnd
    }

    private static func terminatorRange(ofSlot line: Int, index: EditorLineIndex) -> NSRange {
        NSRange(location: index.lines[line].contentEnd, length: terminatorLength(ofSlot: line, index: index))
    }
}
