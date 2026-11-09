import Foundation

nonisolated enum TrailingSpacesMode: String, Codable, Sendable, CaseIterable {
    case none
    case modifiedLines
    case allLines
}

nonisolated struct SaveActionSettings: Equatable, Sendable {
    var trailingSpaces: TrailingSpacesMode = .modifiedLines
    var keepTrailingSpacesOnCaretLine = true
    var ensureFinalNewline = false
}

nonisolated struct SaveTextEdit: Equatable, Sendable {
    let range: NSRange
    let replacement: String

    var lengthDelta: Int {
        (replacement as NSString).length - range.length
    }
}

nonisolated struct SavePlan: Equatable, Sendable {
    var edits: [SaveTextEdit]
    var deferredLines: IndexSet
}

nonisolated struct SaveActions: Equatable, Sendable {
    var trimMode: TrailingSpacesMode
    var keepTrailingSpacesOnCaretLine: Bool
    var insertFinalNewline: Bool
    var fallbackLineEnding: String

    private static let space: UInt16 = 32
    private static let tab: UInt16 = 9
    private static let lineFeed: UInt16 = 10
    private static let carriageReturn: UInt16 = 13

    init(
        trimMode: TrailingSpacesMode,
        keepTrailingSpacesOnCaretLine: Bool,
        insertFinalNewline: Bool,
        fallbackLineEnding: String = "\n"
    ) {
        self.trimMode = trimMode
        self.keepTrailingSpacesOnCaretLine = keepTrailingSpacesOnCaretLine
        self.insertFinalNewline = insertFinalNewline
        self.fallbackLineEnding = fallbackLineEnding
    }

    init(trimTrailingWhitespace: Bool, insertFinalNewline: Bool, fallbackLineEnding: String = "\n") {
        self.init(
            trimMode: trimTrailingWhitespace ? .allLines : .none,
            keepTrailingSpacesOnCaretLine: false,
            insertFinalNewline: insertFinalNewline,
            fallbackLineEnding: fallbackLineEnding
        )
    }

    init(editorConfig: EditorConfigProperties, settings: SaveActionSettings) {
        let lineEnding: String
        switch editorConfig.endOfLine {
        case .crlf:
            lineEnding = "\r\n"
        case .cr:
            lineEnding = "\r"
        case .lf, nil:
            lineEnding = "\n"
        }
        let trimMode: TrailingSpacesMode
        switch editorConfig.trimTrailingWhitespace {
        case true:
            trimMode = .allLines
        case false:
            trimMode = .none
        case nil:
            trimMode = settings.trailingSpaces
        }
        self.init(
            trimMode: trimMode,
            keepTrailingSpacesOnCaretLine: settings.keepTrailingSpacesOnCaretLine,
            insertFinalNewline: editorConfig.insertFinalNewline ?? settings.ensureFinalNewline,
            fallbackLineEnding: lineEnding
        )
    }

    var isEmpty: Bool {
        trimMode == .none && !insertFinalNewline
    }

    func edits(for text: String, modifiedLines: IndexSet = IndexSet(), caretOffsets: [Int] = []) -> [SaveTextEdit] {
        plan(for: text, modifiedLines: modifiedLines, caretOffsets: caretOffsets).edits
    }

    func plan(for text: String, modifiedLines: IndexSet, caretOffsets: [Int]) -> SavePlan {
        guard !isEmpty, !text.isEmpty else { return SavePlan(edits: [], deferredLines: IndexSet()) }
        var scan = LineScan(
            mode: trimMode,
            keepCaretLine: keepTrailingSpacesOnCaretLine,
            modifiedLines: modifiedLines,
            caretOffsets: caretOffsets
        )
        var offset = 0
        for unit in text.utf16 {
            scan.consume(unit, at: offset)
            offset += 1
        }
        scan.finish(at: offset)
        var edits = scan.deletions
        if insertFinalNewline, !Self.endsWithTerminator(text, after: edits) {
            if scan.finalLineIsBlank, trimMode != .none, !scan.finalLineHoldsCaret {
                edits.append(
                    SaveTextEdit(
                        range: NSRange(location: scan.lineStart, length: offset - scan.lineStart),
                        replacement: ""
                    )
                )
            } else {
                edits.append(
                    SaveTextEdit(
                        range: NSRange(location: offset, length: 0),
                        replacement: scan.firstLineEnding ?? fallbackLineEnding
                    )
                )
            }
        }
        return SavePlan(edits: edits.sorted(by: Self.isAppliedBefore), deferredLines: scan.deferredLines)
    }

    static func apply(_ edits: [SaveTextEdit], to text: String) -> String {
        let result = NSMutableString(string: text)
        for edit in edits.sorted(by: isAppliedBefore) {
            result.replaceCharacters(in: edit.range, with: edit.replacement)
        }
        return result as String
    }

    static func map(_ offset: Int, through edits: [SaveTextEdit]) -> Int {
        var result = offset
        for edit in edits {
            if edit.range.length > 0 {
                if offset >= edit.range.upperBound {
                    result += edit.lengthDelta
                } else if offset > edit.range.location {
                    result -= offset - edit.range.location
                }
            } else if offset > edit.range.location {
                result += edit.lengthDelta
            }
        }
        return result
    }

    static func map(_ range: NSRange, through edits: [SaveTextEdit]) -> NSRange {
        let start = map(range.location, through: edits)
        let end = map(range.upperBound, through: edits)
        return NSRange(location: start, length: max(0, end - start))
    }

    private static func isAppliedBefore(_ lhs: SaveTextEdit, _ rhs: SaveTextEdit) -> Bool {
        lhs.range.location > rhs.range.location
    }

    private static func endsWithTerminator(_ text: String, after deletions: [SaveTextEdit]) -> Bool {
        guard let last = apply(deletions, to: text).utf16.last else { return true }
        return last == lineFeed || last == carriageReturn
    }

    private struct LineScan {
        let mode: TrailingSpacesMode
        let keepCaretLine: Bool
        let modifiedLines: IndexSet
        let caretOffsets: [Int]
        var deletions: [SaveTextEdit] = []
        var deferredLines = IndexSet()
        var firstLineEnding: String?
        private(set) var lineStart = 0
        private(set) var finalLineIsBlank = false
        private(set) var finalLineHoldsCaret = false
        private var lineNumber = 0
        private var lineHasContent = false
        private var whitespaceStart: Int?
        private var previous: UInt16 = 0
        private var firstEndingIsLoneCarriageReturn = false

        init(mode: TrailingSpacesMode, keepCaretLine: Bool, modifiedLines: IndexSet, caretOffsets: [Int]) {
            self.mode = mode
            self.keepCaretLine = keepCaretLine
            self.modifiedLines = modifiedLines
            self.caretOffsets = caretOffsets
        }

        mutating func consume(_ unit: UInt16, at offset: Int) {
            switch unit {
            case SaveActions.space, SaveActions.tab:
                if whitespaceStart == nil {
                    whitespaceStart = offset
                }
            case SaveActions.carriageReturn:
                closeLine(at: offset)
                startLine(at: offset + 1)
                firstEndingIsLoneCarriageReturn = firstLineEnding == nil
                firstLineEnding = firstLineEnding ?? "\r"
            case SaveActions.lineFeed:
                if previous == SaveActions.carriageReturn {
                    lineStart = offset + 1
                    if firstEndingIsLoneCarriageReturn {
                        firstLineEnding = "\r\n"
                        firstEndingIsLoneCarriageReturn = false
                    }
                } else {
                    closeLine(at: offset)
                    startLine(at: offset + 1)
                    firstLineEnding = firstLineEnding ?? "\n"
                }
            default:
                whitespaceStart = nil
                lineHasContent = true
            }
            previous = unit
        }

        mutating func finish(at offset: Int) {
            finalLineIsBlank = lineStart < offset && !lineHasContent
            finalLineHoldsCaret = caretOffsets.contains { $0 >= lineStart && $0 <= offset }
            closeLine(at: offset)
        }

        private mutating func startLine(at offset: Int) {
            lineNumber += 1
            lineStart = offset
            lineHasContent = false
        }

        private mutating func closeLine(at lineEnd: Int) {
            defer { whitespaceStart = nil }
            let isModified = modifiedLines.contains(lineNumber)
            let carets = caretOffsets.filter { $0 >= lineStart && $0 <= lineEnd }
            if mode == .modifiedLines, keepCaretLine, isModified, !carets.isEmpty {
                deferredLines.insert(lineNumber)
            }
            guard mode != .none, mode == .allLines || isModified, let start = whitespaceStart, start < lineEnd else {
                return
            }
            if keepCaretLine, carets.contains(where: { start < $0 }) {
                return
            }
            deletions.append(SaveTextEdit(range: NSRange(location: start, length: lineEnd - start), replacement: ""))
        }
    }
}

nonisolated struct ModifiedLineTracker: Equatable, Sendable {
    private(set) var lines = IndexSet()

    mutating func replace(startLine: Int, removedLineBreaks: Int, addedLineBreaks: Int) {
        let removedEnd = startLine + removedLineBreaks
        if removedLineBreaks > 0 {
            lines.remove(integersIn: (startLine + 1)...removedEnd)
        }
        let delta = addedLineBreaks - removedLineBreaks
        if delta != 0 {
            lines.shift(startingAt: removedEnd + 1, by: delta)
        }
        lines.insert(integersIn: startLine...(startLine + addedLineBreaks))
    }

    mutating func reset(keeping retained: IndexSet = IndexSet()) {
        lines = retained
    }

    static func lineBreakCount(in text: String) -> Int {
        var count = 0
        var previousWasCarriageReturn = false
        for unit in text.utf16 {
            if unit == 13 {
                count += 1
            } else if unit == 10, !previousWasCarriageReturn {
                count += 1
            }
            previousWasCarriageReturn = unit == 13
        }
        return count
    }
}
