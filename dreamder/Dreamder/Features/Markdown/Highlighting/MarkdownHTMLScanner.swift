import Foundation

nonisolated struct MarkdownHTMLScanner {
    private nonisolated enum Phase: Equatable {
        case text
        case comment
        case declaration
        case tagName
        case insideTag
        case afterAttributeName
        case afterEquals
        case quotedValue(UInt16)
        case unquotedValue
    }

    private var phase = Phase.text
    private let emitsText: Bool

    init(emitsText: Bool) {
        self.emitsText = emitsText
    }

    mutating func scan(_ units: [UInt16], from start: Int, to end: Int, into tokens: inout [MarkdownToken]) {
        var index = start
        var textStart = start
        var needsTextStart = false
        while index < end {
            let wasText = phase == .text
            if wasText, needsTextStart {
                textStart = index
                needsTextStart = false
            }
            switch phase {
            case .text:
                index = scanText(units, index: index, end: end, textStart: &textStart, into: &tokens)
            case .comment:
                index = scanComment(units, from: index, searchFrom: index, end: end, into: &tokens)
            case .declaration:
                index = scanDeclaration(units, from: index, searchFrom: index, end: end, into: &tokens)
            case .tagName:
                var cursor = index
                while cursor < end, Self.isTagNameUnit(units[cursor]) {
                    cursor += 1
                }
                if cursor > index {
                    tokens.append(MarkdownToken(.htmlTagName, from: index, to: cursor))
                }
                phase = .insideTag
                index = cursor
            case .insideTag:
                index = scanInsideTag(units, index: index, end: end, into: &tokens)
            case .afterAttributeName:
                var cursor = index
                while cursor < end, MarkdownChar.isWhitespace(units[cursor]) {
                    cursor += 1
                }
                if cursor < end, units[cursor] == MarkdownChar.equals {
                    tokens.append(MarkdownToken(.htmlAttributeValue, from: cursor, to: cursor + 1))
                    phase = .afterEquals
                    index = cursor + 1
                } else if cursor < end {
                    phase = .insideTag
                    index = cursor
                } else {
                    index = cursor
                }
            case .afterEquals:
                index = scanAfterEquals(units, index: index, end: end, into: &tokens)
            case .quotedValue(let quote):
                var cursor = index
                while cursor < end, units[cursor] != quote {
                    cursor += 1
                }
                if cursor < end {
                    tokens.append(MarkdownToken(.htmlAttributeValue, from: index, to: cursor + 1))
                    phase = .insideTag
                    index = cursor + 1
                } else {
                    tokens.append(MarkdownToken(.htmlAttributeValue, from: index, to: end))
                    index = end
                }
            case .unquotedValue:
                var cursor = index
                while cursor < end, !MarkdownChar.isWhitespace(units[cursor]), units[cursor] != MarkdownChar.greater {
                    cursor += 1
                }
                if cursor > index {
                    tokens.append(MarkdownToken(.htmlAttributeValue, from: index, to: cursor))
                }
                phase = .insideTag
                index = cursor
            }
            if !wasText {
                needsTextStart = true
            }
        }
        if phase == .text, emitsText, !needsTextStart {
            appendText(units, from: textStart, to: end, into: &tokens)
        }
    }

    private mutating func scanText(
        _ units: [UInt16],
        index: Int,
        end: Int,
        textStart: inout Int,
        into tokens: inout [MarkdownToken]
    ) -> Int {
        var cursor = index
        while cursor < end {
            guard units[cursor] == MarkdownChar.less, cursor + 1 < end else {
                cursor += 1
                continue
            }
            let next = units[cursor + 1]
            if next == MarkdownChar.exclamation || next == MarkdownChar.question {
                flushText(units, textStart: &textStart, to: cursor, into: &tokens)
                if Self.hasPrefix(units, at: cursor, end: end, "<!--") {
                    phase = .comment
                    let resume = scanComment(units, from: cursor, searchFrom: cursor + 4, end: end, into: &tokens)
                    textStart = resume
                    return resume
                }
                phase = .declaration
                let resume = scanDeclaration(units, from: cursor, searchFrom: cursor + 2, end: end, into: &tokens)
                textStart = resume
                return resume
            }
            if next == MarkdownChar.slash, cursor + 2 < end, MarkdownChar.isASCIILetter(units[cursor + 2]) {
                flushText(units, textStart: &textStart, to: cursor, into: &tokens)
                tokens.append(MarkdownToken(.htmlTag, from: cursor, to: cursor + 2))
                phase = .tagName
                return cursor + 2
            }
            if MarkdownChar.isASCIILetter(next) {
                flushText(units, textStart: &textStart, to: cursor, into: &tokens)
                tokens.append(MarkdownToken(.htmlTag, from: cursor, to: cursor + 1))
                phase = .tagName
                return cursor + 1
            }
            cursor += 1
        }
        return end
    }

    private mutating func scanComment(
        _ units: [UInt16],
        from segmentStart: Int,
        searchFrom: Int,
        end: Int,
        into tokens: inout [MarkdownToken]
    ) -> Int {
        var cursor = searchFrom
        while cursor + 2 < end {
            if units[cursor] == MarkdownChar.dash, units[cursor + 1] == MarkdownChar.dash,
               units[cursor + 2] == MarkdownChar.greater {
                tokens.append(MarkdownToken(.htmlComment, from: segmentStart, to: cursor + 3))
                phase = .text
                return cursor + 3
            }
            cursor += 1
        }
        if segmentStart < end {
            tokens.append(MarkdownToken(.htmlComment, from: segmentStart, to: end))
        }
        return end
    }

    private mutating func scanDeclaration(
        _ units: [UInt16],
        from segmentStart: Int,
        searchFrom: Int,
        end: Int,
        into tokens: inout [MarkdownToken]
    ) -> Int {
        var cursor = searchFrom
        while cursor < end {
            if units[cursor] == MarkdownChar.greater {
                tokens.append(MarkdownToken(.htmlTag, from: segmentStart, to: cursor + 1))
                phase = .text
                return cursor + 1
            }
            cursor += 1
        }
        if segmentStart < end {
            tokens.append(MarkdownToken(.htmlTag, from: segmentStart, to: end))
        }
        return end
    }

    private mutating func scanInsideTag(
        _ units: [UInt16],
        index: Int,
        end: Int,
        into tokens: inout [MarkdownToken]
    ) -> Int {
        var cursor = index
        while cursor < end, MarkdownChar.isWhitespace(units[cursor]) {
            cursor += 1
        }
        guard cursor < end else { return cursor }
        let unit = units[cursor]
        if unit == MarkdownChar.greater {
            tokens.append(MarkdownToken(.htmlTag, from: cursor, to: cursor + 1))
            phase = .text
            return cursor + 1
        }
        if unit == MarkdownChar.slash, cursor + 1 < end, units[cursor + 1] == MarkdownChar.greater {
            tokens.append(MarkdownToken(.htmlTag, from: cursor, to: cursor + 2))
            phase = .text
            return cursor + 2
        }
        guard Self.isAttributeNameUnit(unit) else { return cursor + 1 }
        var nameEnd = cursor
        while nameEnd < end, Self.isAttributeNameUnit(units[nameEnd]) {
            nameEnd += 1
        }
        tokens.append(MarkdownToken(.htmlAttributeName, from: cursor, to: nameEnd))
        phase = .afterAttributeName
        return nameEnd
    }

    private mutating func scanAfterEquals(
        _ units: [UInt16],
        index: Int,
        end: Int,
        into tokens: inout [MarkdownToken]
    ) -> Int {
        var cursor = index
        while cursor < end, MarkdownChar.isWhitespace(units[cursor]) {
            cursor += 1
        }
        guard cursor < end else { return cursor }
        let unit = units[cursor]
        if unit == MarkdownChar.doubleQuote || unit == MarkdownChar.singleQuote {
            var closing = cursor + 1
            while closing < end, units[closing] != unit {
                closing += 1
            }
            if closing < end {
                tokens.append(MarkdownToken(.htmlAttributeValue, from: cursor, to: closing + 1))
                phase = .insideTag
                return closing + 1
            }
            tokens.append(MarkdownToken(.htmlAttributeValue, from: cursor, to: end))
            phase = .quotedValue(unit)
            return end
        }
        if unit == MarkdownChar.greater {
            phase = .insideTag
            return cursor
        }
        phase = .unquotedValue
        return cursor
    }

    private func flushText(
        _ units: [UInt16],
        textStart: inout Int,
        to end: Int,
        into tokens: inout [MarkdownToken]
    ) {
        if emitsText {
            appendText(units, from: textStart, to: end, into: &tokens)
        }
        textStart = end
    }

    private func appendText(_ units: [UInt16], from start: Int, to end: Int, into tokens: inout [MarkdownToken]) {
        var lower = start
        var upper = end
        while lower < upper, MarkdownChar.isWhitespace(units[lower]) {
            lower += 1
        }
        while upper > lower, MarkdownChar.isWhitespace(units[upper - 1]) {
            upper -= 1
        }
        if lower < upper {
            tokens.append(MarkdownToken(.htmlCode, from: lower, to: upper))
        }
    }

    private static func hasPrefix(_ units: [UInt16], at index: Int, end: Int, _ prefix: StaticString) -> Bool {
        let length = prefix.utf8CodeUnitCount
        guard index + length <= end else { return false }
        return prefix.withUTF8Buffer { buffer in
            for offset in 0..<length where units[index + offset] != UInt16(buffer[offset]) {
                return false
            }
            return true
        }
    }

    private static func isTagNameUnit(_ unit: UInt16) -> Bool {
        MarkdownChar.isASCIIAlphanumeric(unit) || unit == MarkdownChar.dash || unit == MarkdownChar.colon
            || unit == MarkdownChar.underscore || unit == MarkdownChar.dot
    }

    static func tagEnd(in units: [UInt16], from start: Int, to end: Int) -> Int? {
        guard start + 1 < end, units[start] == MarkdownChar.less else { return nil }
        let next = units[start + 1]
        if next == MarkdownChar.slash {
            var index = start + 2
            guard index < end, MarkdownChar.isASCIILetter(units[index]) else { return nil }
            while index < end, MarkdownChar.isASCIIAlphanumeric(units[index]) || units[index] == MarkdownChar.dash {
                index += 1
            }
            index = skipWhitespace(units, from: index, to: end)
            return index < end && units[index] == MarkdownChar.greater ? index + 1 : nil
        }
        guard MarkdownChar.isASCIILetter(next) else { return nil }
        var index = start + 1
        while index < end, MarkdownChar.isASCIIAlphanumeric(units[index]) || units[index] == MarkdownChar.dash {
            index += 1
        }
        while index < end {
            let afterName = index
            index = skipWhitespace(units, from: index, to: end)
            guard index < end else { return nil }
            let unit = units[index]
            if unit == MarkdownChar.greater { return index + 1 }
            if unit == MarkdownChar.slash {
                return index + 1 < end && units[index + 1] == MarkdownChar.greater ? index + 2 : nil
            }
            guard index > afterName,
                  MarkdownChar.isASCIILetter(unit) || unit == MarkdownChar.underscore || unit == MarkdownChar.colon
            else { return nil }
            while index < end, isStrictAttributeUnit(units[index]) {
                index += 1
            }
            let beforeEquals = index
            index = skipWhitespace(units, from: index, to: end)
            if index < end, units[index] == MarkdownChar.equals {
                index = skipWhitespace(units, from: index + 1, to: end)
                guard index < end else { return nil }
                let quote = units[index]
                if quote == MarkdownChar.doubleQuote || quote == MarkdownChar.singleQuote {
                    var cursor = index + 1
                    while cursor < end, units[cursor] != quote {
                        cursor += 1
                    }
                    guard cursor < end else { return nil }
                    index = cursor + 1
                } else {
                    let valueStart = index
                    while index < end, !MarkdownChar.isWhitespace(units[index]), units[index] != MarkdownChar.doubleQuote,
                          units[index] != MarkdownChar.singleQuote, units[index] != MarkdownChar.equals,
                          units[index] != MarkdownChar.less, units[index] != MarkdownChar.greater,
                          units[index] != MarkdownChar.backtick {
                        index += 1
                    }
                    guard index > valueStart else { return nil }
                }
            } else {
                index = beforeEquals
            }
        }
        return nil
    }

    private static func skipWhitespace(_ units: [UInt16], from start: Int, to end: Int) -> Int {
        var index = start
        while index < end, MarkdownChar.isWhitespace(units[index]) {
            index += 1
        }
        return index
    }

    private static func isStrictAttributeUnit(_ unit: UInt16) -> Bool {
        MarkdownChar.isASCIIAlphanumeric(unit) || unit == MarkdownChar.underscore || unit == MarkdownChar.dot
            || unit == MarkdownChar.colon || unit == MarkdownChar.dash
    }

    private static func isAttributeNameUnit(_ unit: UInt16) -> Bool {
        !MarkdownChar.isWhitespace(unit) && unit != MarkdownChar.equals && unit != MarkdownChar.greater
            && unit != MarkdownChar.slash && unit != MarkdownChar.doubleQuote && unit != MarkdownChar.singleQuote
            && unit != MarkdownChar.less && unit != MarkdownChar.backtick
    }
}
