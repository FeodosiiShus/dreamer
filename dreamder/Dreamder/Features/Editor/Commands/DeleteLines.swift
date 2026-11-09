import Foundation

nonisolated enum DeleteLines {
    private struct Group {
        var start: Int
        var end: Int
        var columns: [Int]
    }

    static func perform(in text: NSString, selections: [NSRange]) -> EditorCommandResult? {
        guard !selections.isEmpty else { return nil }
        let index = EditorLineIndex(text)
        var groups: [Group] = []
        for selection in selections {
            let range = deletionRange(for: selection, in: index)
            let caret = NSMaxRange(selection)
            let column = index.column(of: caret)
            if let last = groups.last, range.lowerBound <= last.end {
                groups[groups.count - 1] = Group(
                    start: min(last.start, range.lowerBound),
                    end: max(last.end, range.upperBound),
                    columns: last.columns + [column]
                )
            } else {
                groups.append(Group(start: range.lowerBound, end: range.upperBound, columns: [column]))
            }
        }

        let edits = groups.filter { $0.end > $0.start }.map {
            EditorTextEdit(range: NSRange(location: $0.start, length: $0.end - $0.start), replacement: "")
        }
        guard !edits.isEmpty else { return nil }

        let resulting = NSMutableString(string: text as String)
        for edit in edits.reversed() {
            resulting.replaceCharacters(in: edit.range, with: "")
        }
        let resultingIndex = EditorLineIndex(resulting)
        var deletedBefore = 0
        var carets = Set<Int>()
        for group in groups {
            let line = resultingIndex.line(containing: group.start - deletedBefore)
            for column in group.columns {
                carets.insert(line.start + min(column, line.contentLength))
            }
            deletedBefore += group.end - group.start
        }
        return EditorCommandResult(
            edits: edits,
            selections: carets.sorted().map { NSRange(location: $0, length: 0) }
        )
    }

    private static func deletionRange(for selection: NSRange, in index: EditorLineIndex) -> Range<Int> {
        let first = index.line(containing: selection.location)
        let lastProbe = selection.length > 0 ? NSMaxRange(selection) - 1 : selection.location
        let last = index.line(containing: lastProbe)
        var start = first.start
        var end = last.contentEnd
        if end < index.length {
            end = last.end
        } else if start > 0 {
            start = index.lines[first.index - 1].contentEnd
        }
        return start..<end
    }
}
