import Foundation

nonisolated enum DuplicateLines {
    private enum Kind: Int {
        case selection = 0
        case line = 1
    }

    private struct Insertion {
        let location: Int
        let kind: Kind
        let sequence: Int
        let text: String
        let resultingSelection: NSRange
    }

    static func perform(in text: NSString, selections: [NSRange]) -> EditorCommandResult? {
        guard !selections.isEmpty else { return nil }
        let index = EditorLineIndex(text)
        var insertions: [Insertion] = []
        for selection in selections {
            let sequence = insertions.count
            if selection.length > 0 {
                let copy = text.substring(with: selection)
                insertions.append(
                    Insertion(
                        location: NSMaxRange(selection),
                        kind: .selection,
                        sequence: sequence,
                        text: copy,
                        resultingSelection: NSRange(location: 0, length: copy.utf16.count)
                    )
                )
            } else {
                insertions.append(lineInsertion(at: selection.location, sequence: sequence, in: text, index: index))
            }
        }
        insertions.sort { ($0.location, $0.kind.rawValue, $0.sequence) < ($1.location, $1.kind.rawValue, $1.sequence) }

        var edits: [EditorTextEdit] = []
        var resultingSelections: [NSRange] = []
        var shift = 0
        for insertion in insertions {
            let absolute = insertion.location + shift + insertion.resultingSelection.location
            resultingSelections.append(NSRange(location: absolute, length: insertion.resultingSelection.length))
            if let last = edits.last, last.range.location == insertion.location {
                edits[edits.count - 1] = EditorTextEdit(range: last.range, replacement: last.replacement + insertion.text)
            } else {
                edits.append(EditorTextEdit(range: NSRange(location: insertion.location, length: 0), replacement: insertion.text))
            }
            shift += insertion.text.utf16.count
        }
        resultingSelections.sort { $0.location < $1.location }
        return EditorCommandResult(edits: edits, selections: resultingSelections)
    }

    private static func lineInsertion(at caret: Int, sequence: Int, in text: NSString, index: EditorLineIndex) -> Insertion {
        let line = index.line(containing: caret)
        let column = caret - line.start
        if line.hasTerminator {
            return Insertion(
                location: line.end,
                kind: .line,
                sequence: sequence,
                text: text.substring(with: line.fullRange),
                resultingSelection: NSRange(location: column, length: 0)
            )
        }
        return Insertion(
            location: line.end,
            kind: .line,
            sequence: sequence,
            text: "\n" + text.substring(with: line.contentRange),
            resultingSelection: NSRange(location: column + 1, length: 0)
        )
    }
}
