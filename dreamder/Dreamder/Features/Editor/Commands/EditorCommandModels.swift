import Foundation

nonisolated struct EditorTextEdit: Equatable, Sendable {
    let range: NSRange
    let replacement: String
}

nonisolated struct EditorCommandResult: Equatable, Sendable {
    let edits: [EditorTextEdit]
    let selections: [NSRange]

    var resultingLengthDelta: Int {
        edits.reduce(0) { $0 + $1.replacement.utf16.count - $1.range.length }
    }
}

nonisolated struct EditorLine: Equatable, Sendable {
    let index: Int
    let start: Int
    let contentEnd: Int
    let end: Int

    var contentRange: NSRange { NSRange(location: start, length: contentEnd - start) }
    var fullRange: NSRange { NSRange(location: start, length: end - start) }
    var contentLength: Int { contentEnd - start }
    var hasTerminator: Bool { end > contentEnd }
}

nonisolated struct EditorLineIndex: Sendable {
    let lines: [EditorLine]
    let length: Int

    init(_ text: NSString) {
        let length = text.length
        var lines: [EditorLine] = []
        var start = 0
        var offset = 0
        while offset < length {
            let unit = text.character(at: offset)
            guard unit == 0x0A || unit == 0x0D else {
                offset += 1
                continue
            }
            var next = offset + 1
            if unit == 0x0D, next < length, text.character(at: next) == 0x0A {
                next += 1
            }
            lines.append(EditorLine(index: lines.count, start: start, contentEnd: offset, end: next))
            start = next
            offset = next
        }
        lines.append(EditorLine(index: lines.count, start: start, contentEnd: length, end: length))
        self.lines = lines
        self.length = length
    }

    var count: Int { lines.count }

    func lineIndex(containing offset: Int) -> Int {
        let clamped = min(max(offset, 0), length)
        var low = 0
        var high = lines.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if lines[middle].start <= clamped {
                low = middle
            } else {
                high = middle - 1
            }
        }
        return low
    }

    func line(containing offset: Int) -> EditorLine {
        lines[lineIndex(containing: offset)]
    }

    func touchedLines(by selection: NSRange) -> ClosedRange<Int> {
        let first = lineIndex(containing: selection.location)
        guard selection.length > 0 else { return first...first }
        var last = lineIndex(containing: selection.location + selection.length)
        if last > first, lines[last].start == selection.location + selection.length {
            last -= 1
        }
        return first...last
    }

    func touchedLineBlocks(by selections: [NSRange], mergingAdjacent: Bool) -> [ClosedRange<Int>] {
        var blocks: [ClosedRange<Int>] = []
        for selection in selections.sorted(by: { $0.location < $1.location }) {
            let touched = touchedLines(by: selection)
            guard let previous = blocks.last else {
                blocks.append(touched)
                continue
            }
            let joinThreshold = previous.upperBound + (mergingAdjacent ? 1 : 0)
            if touched.lowerBound <= joinThreshold {
                blocks[blocks.count - 1] = previous.lowerBound...max(previous.upperBound, touched.upperBound)
            } else {
                blocks.append(touched)
            }
        }
        return blocks
    }

    func fullRange(of block: ClosedRange<Int>) -> NSRange {
        let start = lines[block.lowerBound].start
        let end = lines[block.upperBound].end
        return NSRange(location: start, length: end - start)
    }

    func column(of offset: Int) -> Int {
        offset - line(containing: offset).start
    }
}
