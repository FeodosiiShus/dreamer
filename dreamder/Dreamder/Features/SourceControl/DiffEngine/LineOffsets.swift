import Foundation

nonisolated struct LineOffsets: Sendable, Equatable {
    private let lineEnds: [Int]
    let textLength: Int

    init(text: DiffUnits) {
        var ends: [Int] = []
        for (index, unit) in text.enumerated() where unit == 10 {
            ends.append(index)
        }
        ends.append(text.count)
        self.lineEnds = ends
        self.textLength = text.count
    }

    init(lines: [DiffUnits]) {
        var ends: [Int] = []
        ends.reserveCapacity(lines.count)
        var start = 0
        for line in lines {
            let end = start + line.count
            ends.append(end)
            start = end + 1
        }
        self.lineEnds = ends
        self.textLength = ends.last ?? 0
    }

    var lineCount: Int { lineEnds.count }

    func lineStart(_ line: Int) -> Int {
        guard line > 0, line - 1 < lineEnds.count else { return 0 }
        return lineEnds[line - 1] + 1
    }

    func lineEnd(_ line: Int, includeNewline: Bool = false) -> Int {
        guard line >= 0, line < lineEnds.count else { return textLength }
        return lineEnds[line] + (includeNewline && line != lineEnds.count - 1 ? 1 : 0)
    }

    func lineNumber(containing offset: Int) -> Int {
        if lineEnds.isEmpty || offset <= 0 { return 0 }
        if offset >= textLength { return max(lineEnds.count - 1, 0) }
        var low = 0
        var high = lineEnds.count - 1
        while low < high {
            let middle = (low + high) / 2
            if lineEnds[middle] < offset {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }

    func lineContents(in text: DiffUnits) -> [DiffUnits] {
        lineContents(in: text, lines: 0..<lineCount)
    }

    func lineContents(in text: DiffUnits, lines: Range<Int>) -> [DiffUnits] {
        var result: [DiffUnits] = []
        result.reserveCapacity(lines.count)
        for line in lines {
            result.append(Array(text[lineStart(line)..<lineEnd(line)]))
        }
        return result
    }
}
