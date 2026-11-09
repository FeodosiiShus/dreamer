import Foundation

nonisolated enum SelectionLadder {
    private static let wordCategories: Set<Unicode.GeneralCategory> = [
        .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
        .letterNumber, .decimalNumber, .connectorPunctuation, .currencySymbol,
        .nonspacingMark, .spacingMark
    ]

    private static let lineBreaks: Set<UInt16> = [0x0A, 0x0D, 0x85, 0x2028, 0x2029]

    private struct LineBounds {
        let start: Int
        let contentsEnd: Int
    }

    static func isWordPart(_ unit: UInt16) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else { return false }
        return wordCategories.contains(scalar.properties.generalCategory)
    }

    static func strictlyContains(_ outer: NSRange, _ inner: NSRange) -> Bool {
        outer != inner
            && outer.location <= inner.location
            && NSMaxRange(outer) >= NSMaxRange(inner)
    }

    static func wordRange(in text: NSString, at offset: Int) -> NSRange? {
        let length = text.length
        guard length > 0, offset >= 0, offset <= length else { return nil }
        var index = offset
        if index == length || (index > 0 && !isWordPart(text.character(at: index)) && isWordPart(text.character(at: index - 1))) {
            index -= 1
        }
        guard isWordPart(text.character(at: index)) else { return nil }
        var start = index
        var end = index
        while start > 0, isWordPart(text.character(at: start - 1)) {
            start -= 1
        }
        while end < length, isWordPart(text.character(at: end)) {
            end += 1
        }
        return NSRange(location: start, length: end - start)
    }

    static func blankRange(in text: NSString, at offset: Int) -> NSRange? {
        let length = text.length
        guard offset >= 0, offset < length, isBlank(text.character(at: offset)) else { return nil }
        if offset > 0, !isWhitespace(text.character(at: offset - 1)) { return nil }
        var start = offset
        var end = offset
        while start > 0, isBlank(text.character(at: start - 1)) {
            start -= 1
        }
        while end < length, isBlank(text.character(at: end)) {
            end += 1
        }
        return NSRange(location: start, length: end - start)
    }

    static func ranges(in text: NSString, at offset: Int) -> [NSRange] {
        guard offset >= 0, offset <= text.length else { return [] }
        var result: [NSRange] = []
        if let word = wordRange(in: text, at: offset) {
            result.append(word)
        }
        if let blank = blankRange(in: text, at: offset) {
            result.append(blank)
        }
        let line = lineBounds(in: text, at: offset)
        if let trimmed = trimmedRange(in: text, line: line) {
            result.append(trimmed)
        }
        result.append(NSRange(location: line.start, length: line.contentsEnd - line.start))
        return result
    }

    static func lines(in text: NSString, covering selection: NSRange) -> NSRange? {
        guard selection.location >= 0, NSMaxRange(selection) <= text.length else { return nil }
        let first = lineBounds(in: text, at: selection.location)
        let end: Int
        if selection.length > 0, lineBreaks.contains(text.character(at: NSMaxRange(selection) - 1)) {
            end = NSMaxRange(selection)
        } else {
            end = Swift.max(lineBounds(in: text, at: NSMaxRange(selection)).contentsEnd, NSMaxRange(selection))
        }
        return NSRange(location: first.start, length: end - first.start)
    }

    static func next(in text: NSString, anchors: [Int], selection: NSRange) -> NSRange? {
        guard let coveringLines = lines(in: text, covering: selection) else { return nil }
        var best = NSRange(location: 0, length: text.length)
        var candidates = anchors.flatMap { ranges(in: text, at: $0) }
        candidates.append(coveringLines)
        for candidate in candidates where strictlyContains(candidate, selection) && candidate.length < best.length {
            best = candidate
        }
        return strictlyContains(best, selection) ? best : nil
    }

    static func previous(in text: NSString, anchors: [Int], selection: NSRange) -> NSRange {
        guard selection.length > 0, selection.location >= 0, NSMaxRange(selection) <= text.length else {
            return selection
        }
        var best: NSRange?
        for anchor in anchors.reversed() {
            for range in ranges(in: text, at: anchor)
            where strictlyContains(selection, range) && anchor >= range.location && anchor <= NSMaxRange(range) {
                if let current = best {
                    if strictlyContains(range, current) {
                        best = range
                    }
                } else {
                    best = range
                }
            }
        }
        if let best {
            return best
        }
        let caret = anchors.last ?? NSMaxRange(selection)
        return NSRange(location: caret, length: 0)
    }

    private static func isBlank(_ unit: UInt16) -> Bool {
        unit == 0x20 || unit == 0x09
    }

    private static func isWhitespace(_ unit: UInt16) -> Bool {
        Unicode.Scalar(unit)?.properties.isWhitespace ?? false
    }

    private static func lineBounds(in text: NSString, at offset: Int) -> LineBounds {
        var start = 0
        var end = 0
        var contentsEnd = 0
        text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: offset, length: 0))
        return LineBounds(start: start, contentsEnd: contentsEnd)
    }

    private static func trimmedRange(in text: NSString, line: LineBounds) -> NSRange? {
        var start = line.start
        var end = line.contentsEnd
        while start < end, isWhitespace(text.character(at: start)) {
            start += 1
        }
        while end > start, isWhitespace(text.character(at: end - 1)) {
            end -= 1
        }
        return start < end ? NSRange(location: start, length: end - start) : nil
    }
}
