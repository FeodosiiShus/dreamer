import Foundation

nonisolated enum CloneCaret {
    static func perform(in text: NSString, selections: [NSRange], above: Bool) -> [NSRange]? {
        let lines = EditorLineIndex(text)
        let lineShift = above ? -1 : 1
        var result = selections
        var caretOffsets = Set(selections.map { $0.location + $0.length })
        var cloned = false
        for source in selections {
            guard let clone = cloneOf(source, lines: lines, lineShift: lineShift, caretOffsets: caretOffsets, selections: result) else {
                continue
            }
            result.append(clone.range)
            caretOffsets.insert(clone.caretOffset)
            cloned = true
        }
        return cloned ? result.sorted { $0.location < $1.location } : nil
    }

    private struct Clone {
        let range: NSRange
        let caretOffset: Int
    }

    private static func cloneOf(
        _ source: NSRange,
        lines: EditorLineIndex,
        lineShift: Int,
        caretOffsets: Set<Int>,
        selections: [NSRange]
    ) -> Clone? {
        let caretOffset = source.location + source.length
        return cloneOf(
            source,
            lines: lines,
            lineShift: lineShift,
            caretOffsets: caretOffsets,
            selections: selections,
            caretLine: lines.lineIndex(containing: caretOffset),
            startLine: lines.lineIndex(containing: source.location)
        )
    }

    private static func cloneOf(
        _ source: NSRange,
        lines: EditorLineIndex,
        lineShift: Int,
        caretOffsets: Set<Int>,
        selections: [NSRange],
        caretLine: Int,
        startLine: Int
    ) -> Clone? {
        let caretOffset = source.location + source.length
        let caretColumn = lines.column(of: caretOffset)
        let startColumn = lines.column(of: source.location)
        let targetLine = caretLine + lineShift
        guard lines.lines.indices.contains(targetLine) else { return nil }
        let targetCaret = offset(line: targetLine, column: caretColumn, lines: lines)
        guard !caretOffsets.contains(targetCaret) else { return nil }
        if source.length == 0 {
            return Clone(range: NSRange(location: targetCaret, length: 0), caretOffset: targetCaret)
        }
        let first = startLine + lineShift < 0 ? 0 : offset(line: startLine + lineShift, column: startColumn, lines: lines)
        let second = offset(line: targetLine, column: caretColumn, lines: lines)
        guard first == second else {
            let range = NSRange(location: first, length: second - first)
            let collides = selections.contains {
                $0.location < range.location + range.length && range.location < $0.location + $0.length
            }
            return collides ? nil : Clone(range: range, caretOffset: targetCaret)
        }
        return cloneOf(
            source,
            lines: lines,
            lineShift: lineShift,
            caretOffsets: caretOffsets,
            selections: selections,
            caretLine: targetLine,
            startLine: targetLine
        )
    }

    private static func offset(line: Int, column: Int, lines: EditorLineIndex) -> Int {
        let target = lines.lines[line]
        return target.start + min(column, target.contentLength)
    }
}
