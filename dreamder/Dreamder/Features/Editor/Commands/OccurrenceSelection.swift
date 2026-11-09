import Foundation

nonisolated struct OccurrenceSelectionResult: Equatable, Sendable {
    let selections: [NSRange]
    let primary: NSRange
}

nonisolated enum OccurrenceSelection {
    private static let backslash: unichar = 0x5C

    static func selectNext(in text: NSString, selections: [NSRange], primary: NSRange?) -> OccurrenceSelectionResult? {
        guard let index = primaryIndex(selections: selections, primary: primary) else { return nil }
        let current = selections[index]
        if current.length == 0 {
            guard let word = wordRange(in: text, at: current.location) else { return nil }
            let kept = selections.filter { $0 != current && !overlapsStrictly($0, word) }
            return OccurrenceSelectionResult(selections: sorted(kept + [word]), primary: word)
        }
        let needle = text.substring(with: current)
        let wholeWords = isWholeWord(in: text, range: current)
        guard let found = nextOccurrence(
            in: text, needle: needle, wholeWords: wholeWords, after: current, excluding: selections
        ) else { return nil }
        return OccurrenceSelectionResult(selections: sorted(selections + [found]), primary: found)
    }

    static func selectAll(in text: NSString, selections: [NSRange], primary: NSRange?) -> OccurrenceSelectionResult? {
        guard let index = primaryIndex(selections: selections, primary: primary) else { return nil }
        let current = selections[index]
        var target = current
        var wholeWords = false
        if current.length == 0 {
            guard let word = wordRange(in: text, at: current.location) else { return nil }
            target = word
            wholeWords = true
        }
        let needle = text.substring(with: target)
        var matches: [NSRange] = []
        var offset = 0
        while let found = find(needle, in: text, from: offset, wholeWords: wholeWords) {
            matches.append(found)
            offset = found.location + found.length
        }
        guard let last = matches.last else { return nil }
        return OccurrenceSelectionResult(selections: matches, primary: last)
    }

    static func unselectLast(selections: [NSRange], primary: NSRange?) -> OccurrenceSelectionResult? {
        guard let index = primaryIndex(selections: selections, primary: primary) else { return nil }
        if selections.count == 1 {
            let current = selections[index]
            guard current.length > 0 else { return nil }
            let caret = NSRange(location: current.location + current.length, length: 0)
            return OccurrenceSelectionResult(selections: [caret], primary: caret)
        }
        var remaining = selections
        remaining.remove(at: index)
        return OccurrenceSelectionResult(selections: remaining, primary: remaining[max(index - 1, 0)])
    }

    static func wordRange(in text: NSString, at offset: Int) -> NSRange? {
        let length = text.length
        guard length > 0 else { return nil }
        var cursor = offset
        if cursor == length || (cursor > 0 && !isIdentifierPart(text.character(at: cursor)) && isIdentifierPart(text.character(at: cursor - 1))) {
            cursor -= 1
        }
        guard isIdentifierPart(text.character(at: cursor)) else { return nil }
        var start = cursor
        var end = cursor
        while start > 0 && isIdentifierPart(text.character(at: start - 1)) {
            start -= 1
        }
        while end < length && isIdentifierPart(text.character(at: end)) {
            end += 1
        }
        return NSRange(location: start, length: end - start)
    }

    static func isWholeWord(in text: NSString, range: NSRange) -> Bool {
        let start = range.location
        let end = range.location + range.length
        var isWordStart = true
        if start != 0 {
            let previous = text.character(at: start - 1)
            let first = text.character(at: start)
            let previousIsIdentifier = isIdentifierPart(previous) && (start <= 1 || text.character(at: start - 2) != backslash)
            isWordStart = isIdentifierPart(first) ? !previousIsIdentifier : previous != first
        }
        var isWordEnd = true
        if end != text.length {
            let next = text.character(at: end)
            let last = text.character(at: end - 1)
            isWordEnd = isIdentifierPart(last) ? !isIdentifierPart(next) : next != last
        }
        return isWordStart && isWordEnd
    }

    static func isIdentifierPart(_ unit: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else { return false }
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .letterNumber, .currencySymbol, .connectorPunctuation,
             .nonspacingMark, .spacingMark:
            return true
        default:
            return false
        }
    }

    private static func primaryIndex(selections: [NSRange], primary: NSRange?) -> Int? {
        if let primary, let index = selections.firstIndex(of: primary) {
            return index
        }
        return selections.indices.last
    }

    private static func sorted(_ ranges: [NSRange]) -> [NSRange] {
        ranges.sorted { $0.location < $1.location }
    }

    private static func overlapsStrictly(_ lhs: NSRange, _ rhs: NSRange) -> Bool {
        lhs.location < rhs.location + rhs.length && rhs.location < lhs.location + lhs.length
    }

    private static func find(_ needle: String, in text: NSString, from offset: Int, wholeWords: Bool) -> NSRange? {
        let found = text.range(
            of: needle,
            options: .literal,
            range: NSRange(location: offset, length: text.length - offset)
        )
        guard found.location != NSNotFound else { return nil }
        if !wholeWords || isWholeWord(in: text, range: found) {
            return found
        }
        return find(needle, in: text, from: found.location + 1, wholeWords: wholeWords)
    }

    private static func nextOccurrence(
        in text: NSString,
        needle: String,
        wholeWords: Bool,
        after current: NSRange,
        excluding selections: [NSRange]
    ) -> NSRange? {
        var offset = current.location + current.length
        while let found = find(needle, in: text, from: offset, wholeWords: wholeWords) {
            if !selections.contains(found) {
                return found
            }
            offset = found.location + found.length
        }
        offset = 0
        while let found = find(needle, in: text, from: offset, wholeWords: wholeWords), found.location < current.location {
            if !selections.contains(found) {
                return found
            }
            offset = found.location + found.length
        }
        return nil
    }
}
