import Foundation

nonisolated struct MarkdownReplacement: Equatable, Sendable {
    let start: Int
    let end: Int
    let text: String
}

nonisolated struct MarkdownTextState: Equatable, Sendable {
    var units: [UInt16]
    var caret: Int

    init(units: [UInt16], caret: Int) {
        self.units = units
        self.caret = caret
    }

    init(text: String, caret: Int) {
        self.init(units: Array(text.utf16), caret: caret)
    }

    var text: String {
        String(decoding: units, as: UTF16.self)
    }

    mutating func apply(_ replacements: [MarkdownReplacement]) {
        for replacement in replacements.sorted(by: { $0.start > $1.start }) {
            let inserted = Array(replacement.text.utf16)
            let delta = inserted.count - (replacement.end - replacement.start)
            if caret >= replacement.end {
                caret += delta
            } else if caret > replacement.start {
                caret = replacement.start + min(caret - replacement.start, inserted.count)
            }
            units.replaceSubrange(replacement.start..<replacement.end, with: inserted)
        }
    }

    func applying(_ replacements: [MarkdownReplacement]) -> MarkdownTextState {
        var copy = self
        copy.apply(replacements)
        return copy
    }
}

nonisolated struct MarkdownTypingEdit: Equatable, Sendable {
    let range: NSRange
    let replacement: String
    let caretOffset: Int

    var isCaretOnly: Bool {
        range.length == 0 && replacement.isEmpty
    }

    static func between(_ original: [UInt16], and result: MarkdownTextState) -> MarkdownTypingEdit {
        let updated = result.units
        let shared = min(original.count, updated.count)
        var prefix = 0
        while prefix < shared, original[prefix] == updated[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < shared - prefix, original[original.count - 1 - suffix] == updated[updated.count - 1 - suffix] {
            suffix += 1
        }
        if prefix > 0, isHighSurrogate(original[prefix - 1]) {
            prefix -= 1
        }
        if suffix > 0, isLowSurrogate(original[original.count - suffix]) {
            suffix -= 1
        }
        let base = Span(start: prefix, oldEnd: original.count - suffix, newEnd: updated.count - suffix)
        let span = [(0, 0), (1, 0), (0, 1), (1, 1)]
            .compactMap { base.widened(left: $0.0, right: $0.1, original: original) }
            .first { !$0.isFilterSensitive(original: original, updated: updated) } ?? base
        return MarkdownTypingEdit(
            range: NSRange(location: span.start, length: span.oldEnd - span.start),
            replacement: String(decoding: updated[span.start..<span.newEnd], as: UTF16.self),
            caretOffset: result.caret
        )
    }

    func applied(to text: String) -> (text: String, caret: Int) {
        ((text as NSString).replacingCharacters(in: range, with: replacement), caretOffset)
    }

    private nonisolated struct Span {
        let start: Int
        let oldEnd: Int
        let newEnd: Int

        func widened(left: Int, right: Int, original: [UInt16]) -> Span? {
            var start = start
            var oldEnd = oldEnd
            var newEnd = newEnd
            if left > 0 {
                guard start > 0 else { return nil }
                start -= 1
                if start > 0, MarkdownTypingEdit.isLowSurrogate(original[start]) {
                    start -= 1
                }
            }
            if right > 0 {
                guard oldEnd < original.count else { return nil }
                oldEnd += 1
                newEnd += 1
                if oldEnd < original.count, MarkdownTypingEdit.isHighSurrogate(original[oldEnd - 1]) {
                    oldEnd += 1
                    newEnd += 1
                }
            }
            return Span(start: start, oldEnd: oldEnd, newEnd: newEnd)
        }

        func isFilterSensitive(original: [UInt16], updated: [UInt16]) -> Bool {
            let removed = oldEnd - start
            let inserted = newEnd - start
            if inserted == 1, updated[start] == 10 { return true }
            if removed == 1, inserted == 0, original[start] == 32 || original[start] == 9 { return true }
            return false
        }
    }

    private static func isHighSurrogate(_ unit: UInt16) -> Bool {
        unit >= 0xD800 && unit <= 0xDBFF
    }

    private static func isLowSurrogate(_ unit: UInt16) -> Bool {
        unit >= 0xDC00 && unit <= 0xDFFF
    }
}
