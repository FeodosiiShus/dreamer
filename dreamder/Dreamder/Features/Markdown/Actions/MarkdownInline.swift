import Foundation

nonisolated struct MarkdownInlineNode: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case emphasis
        case strong
        case strikethrough
        case highlight
        case codeSpan
        case linkText
        case linkDestination
        case inlineLink
        case image
        case autolink
        case htmlTag
    }

    let kind: Kind
    let range: NSRange
    let openLength: Int
    let closeLength: Int

    var contentRange: NSRange {
        NSRange(location: range.location + openLength, length: max(range.length - openLength - closeLength, 0))
    }

    var upperBound: Int { range.location + range.length }

    func containsChar(at offset: Int) -> Bool {
        offset >= range.location && offset < upperBound
    }
}

nonisolated enum MarkdownInlineParser {
    private struct Delimiter {
        let marker: UInt16
        let position: Int
        let originalCount: Int
        var count: Int
        var consumedFromStart: Int = 0
        let canOpen: Bool
        let canClose: Bool

        var remainingStart: Int { position + consumedFromStart }
    }

    private struct Bracket {
        let position: Int
        let isImage: Bool
        let delimiterCount: Int
        var active: Bool
    }

    private static let backslash: UInt16 = 0x5C
    private static let backtick: UInt16 = 0x60
    private static let asterisk: UInt16 = 0x2A
    private static let underscore: UInt16 = 0x5F
    private static let tilde: UInt16 = 0x7E
    private static let equals: UInt16 = 0x3D
    private static let openBracket: UInt16 = 0x5B
    private static let closeBracket: UInt16 = 0x5D
    private static let openParen: UInt16 = 0x28
    private static let closeParen: UInt16 = 0x29
    private static let lessThan: UInt16 = 0x3C
    private static let greaterThan: UInt16 = 0x3E
    private static let bang: UInt16 = 0x21

    static func parse(_ units: [UInt16], base: Int) -> [MarkdownInlineNode] {
        var nodes: [MarkdownInlineNode] = []
        var delimiters: [Delimiter] = []
        var brackets: [Bracket] = []
        var index = 0
        let count = units.count

        while index < count {
            let unit = units[index]
            switch unit {
            case backslash:
                index += index + 1 < count && isASCIIPunctuation(units[index + 1]) ? 2 : 1
            case backtick:
                let runStop = endOfRun(units, from: index, marker: backtick)
                let length = runStop - index
                if let closeStart = findClosingBacktickRun(units, from: runStop, length: length) {
                    nodes.append(
                        MarkdownInlineNode(
                            kind: .codeSpan,
                            range: NSRange(location: base + index, length: closeStart + length - index),
                            openLength: length,
                            closeLength: length
                        )
                    )
                    index = closeStart + length
                } else {
                    index = runStop
                }
            case lessThan:
                if let (end, kind) = angleConstruct(units, from: index) {
                    nodes.append(
                        MarkdownInlineNode(
                            kind: kind,
                            range: NSRange(location: base + index, length: end - index),
                            openLength: 0,
                            closeLength: 0
                        )
                    )
                    index = end
                } else {
                    index += 1
                }
            case asterisk, underscore, tilde, equals:
                let end = endOfRun(units, from: index, marker: unit)
                let length = end - index
                if (unit == tilde || unit == equals) && length != 2 {
                    index = end
                    continue
                }
                let flags = flanking(units, start: index, end: end, marker: unit)
                delimiters.append(
                    Delimiter(
                        marker: unit,
                        position: base + index,
                        originalCount: length,
                        count: length,
                        canOpen: flags.canOpen,
                        canClose: flags.canClose
                    )
                )
                index = end
            case openBracket:
                brackets.append(
                    Bracket(position: index, isImage: false, delimiterCount: delimiters.count, active: true)
                )
                index += 1
            case bang:
                if index + 1 < count, units[index + 1] == openBracket {
                    brackets.append(
                        Bracket(position: index + 1, isImage: true, delimiterCount: delimiters.count, active: true)
                    )
                    index += 2
                } else {
                    index += 1
                }
            case closeBracket:
                index = closeBracketHandling(
                    units,
                    at: index,
                    base: base,
                    nodes: &nodes,
                    delimiters: &delimiters,
                    brackets: &brackets
                )
            case 0x68, 0x77, 0x66:
                if let end = bareAutolinkEnd(units, from: index) {
                    nodes.append(
                        MarkdownInlineNode(
                            kind: .autolink,
                            range: NSRange(location: base + index, length: end - index),
                            openLength: 0,
                            closeLength: 0
                        )
                    )
                    index = end
                } else {
                    index += 1
                }
            default:
                index += 1
            }
        }
        processEmphasis(delimiters: &delimiters, from: 0, base: base, nodes: &nodes, units: units)
        return nodes.sorted {
            if $0.range.location != $1.range.location { return $0.range.location < $1.range.location }
            return $0.range.length > $1.range.length
        }
    }

    private static func endOfRun(_ units: [UInt16], from start: Int, marker: UInt16) -> Int {
        var index = start
        while index < units.count, units[index] == marker { index += 1 }
        return index
    }

    private static func findClosingBacktickRun(_ units: [UInt16], from start: Int, length: Int) -> Int? {
        var index = start
        while index < units.count {
            if units[index] == backtick {
                let end = endOfRun(units, from: index, marker: backtick)
                if end - index == length { return index }
                index = end
            } else {
                index += 1
            }
        }
        return nil
    }

    private static func isASCIIPunctuation(_ unit: UInt16) -> Bool {
        (unit >= 0x21 && unit <= 0x2F) || (unit >= 0x3A && unit <= 0x40) || (unit >= 0x5B && unit <= 0x60)
            || (unit >= 0x7B && unit <= 0x7E)
    }

    private static func isUnicodeWhitespace(_ unit: UInt16?) -> Bool {
        guard let unit else { return true }
        if unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D || unit == 0x0C { return true }
        guard let scalar = Unicode.Scalar(unit) else { return false }
        return scalar.properties.generalCategory == .spaceSeparator
    }

    private static func isUnicodePunctuation(_ unit: UInt16?) -> Bool {
        guard let unit else { return false }
        if isASCIIPunctuation(unit) { return true }
        guard let scalar = Unicode.Scalar(unit) else { return false }
        switch scalar.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation, .initialPunctuation,
             .finalPunctuation, .otherPunctuation, .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol:
            return true
        default:
            return false
        }
    }

    private static func flanking(
        _ units: [UInt16],
        start: Int,
        end: Int,
        marker: UInt16
    ) -> (canOpen: Bool, canClose: Bool) {
        let before: UInt16? = start > 0 ? units[start - 1] : nil
        let after: UInt16? = end < units.count ? units[end] : nil
        let beforeWhitespace = isUnicodeWhitespace(before)
        let afterWhitespace = isUnicodeWhitespace(after)
        let beforePunctuation = isUnicodePunctuation(before)
        let afterPunctuation = isUnicodePunctuation(after)
        let leftFlanking = !afterWhitespace && (!afterPunctuation || beforeWhitespace || beforePunctuation)
        let rightFlanking = !beforeWhitespace && (!beforePunctuation || afterWhitespace || afterPunctuation)
        if marker == underscore {
            return (
                leftFlanking && (!rightFlanking || beforePunctuation),
                rightFlanking && (!leftFlanking || afterPunctuation)
            )
        }
        return (leftFlanking, rightFlanking)
    }

    private static func processEmphasis(
        delimiters: inout [Delimiter],
        from bottom: Int,
        base: Int,
        nodes: inout [MarkdownInlineNode],
        units: [UInt16]
    ) {
        var openersBottom: [String: Int] = [:]
        var current = bottom
        while current < delimiters.count {
            let closer = delimiters[current]
            guard closer.canClose, closer.count > 0 else {
                current += 1
                continue
            }
            let key = "\(closer.marker)-\(closer.originalCount % 3)-\(closer.canOpen)"
            let floor = max(openersBottom[key] ?? bottom - 1, bottom - 1)
            var openerIndex = current - 1
            var found: Int?
            while openerIndex > floor {
                let opener = delimiters[openerIndex]
                if opener.marker == closer.marker, opener.canOpen, opener.count > 0 {
                    let oddMatch = (opener.canClose || closer.canOpen)
                        && (opener.originalCount + closer.originalCount) % 3 == 0
                        && !(opener.originalCount % 3 == 0 && closer.originalCount % 3 == 0)
                    let isLinear = closer.marker == asterisk || closer.marker == underscore
                    if !(isLinear && oddMatch) {
                        found = openerIndex
                        break
                    }
                }
                openerIndex -= 1
            }
            if let openerIndex = found {
                let opener = delimiters[openerIndex]
                let isLinear = closer.marker == asterisk || closer.marker == underscore
                let use: Int
                if isLinear {
                    use = (closer.count >= 2 && opener.count >= 2) ? 2 : 1
                } else {
                    use = 2
                }
                let openStart = opener.remainingStart + opener.count - use
                let closeStart = closer.remainingStart
                let kind: MarkdownInlineNode.Kind
                switch closer.marker {
                case tilde: kind = .strikethrough
                case equals: kind = .highlight
                default: kind = use == 2 ? .strong : .emphasis
                }
                nodes.append(
                    MarkdownInlineNode(
                        kind: kind,
                        range: NSRange(location: openStart, length: closeStart + use - openStart),
                        openLength: use,
                        closeLength: use
                    )
                )
                delimiters[openerIndex].count -= use
                delimiters[current].count -= use
                delimiters[current].consumedFromStart += use
                if openerIndex + 1 < current {
                    for between in (openerIndex + 1)..<current {
                        delimiters[between].count = 0
                    }
                }
                if delimiters[current].count == 0 {
                    current += 1
                }
            } else {
                openersBottom[key] = current - 1
                if !closer.canOpen {
                    delimiters[current].count = 0
                }
                current += 1
            }
        }
        if bottom < delimiters.count {
            for index in bottom..<delimiters.count {
                delimiters[index].count = 0
            }
        }
    }

    private static func closeBracketHandling(
        _ units: [UInt16],
        at index: Int,
        base: Int,
        nodes: inout [MarkdownInlineNode],
        delimiters: inout [Delimiter],
        brackets: inout [Bracket]
    ) -> Int {
        guard let opener = brackets.popLast() else { return index + 1 }
        guard opener.active else { return index + 1 }
        let next = index + 1
        if next < units.count, units[next] == openParen,
           let destination = parseInlineDestination(units, openParenIndex: next) {
            let linkStart = opener.isImage ? opener.position - 1 : opener.position
            let linkEnd = destination.end
            processEmphasis(
                delimiters: &delimiters,
                from: opener.delimiterCount,
                base: base,
                nodes: &nodes,
                units: units
            )
            nodes.append(
                MarkdownInlineNode(
                    kind: .linkText,
                    range: NSRange(location: base + opener.position, length: index + 1 - opener.position),
                    openLength: 1,
                    closeLength: 1
                )
            )
            if let destinationRange = destination.destination {
                nodes.append(
                    MarkdownInlineNode(
                        kind: .linkDestination,
                        range: NSRange(location: base + destinationRange.lowerBound, length: destinationRange.count),
                        openLength: 0,
                        closeLength: 0
                    )
                )
            }
            nodes.append(
                MarkdownInlineNode(
                    kind: opener.isImage ? .image : .inlineLink,
                    range: NSRange(location: base + linkStart, length: linkEnd - linkStart),
                    openLength: 0,
                    closeLength: 0
                )
            )
            if !opener.isImage {
                for position in brackets.indices where !brackets[position].isImage {
                    brackets[position].active = false
                }
            }
            return linkEnd
        }
        if next < units.count, units[next] == openBracket,
           let labelEnd = units[(next + 1)...].firstIndex(of: closeBracket),
           !units[(next + 1)..<labelEnd].contains(openBracket) {
            processEmphasis(
                delimiters: &delimiters,
                from: opener.delimiterCount,
                base: base,
                nodes: &nodes,
                units: units
            )
            nodes.append(
                MarkdownInlineNode(
                    kind: .linkText,
                    range: NSRange(location: base + opener.position, length: index + 1 - opener.position),
                    openLength: 1,
                    closeLength: 1
                )
            )
            return labelEnd + 1
        }
        return index + 1
    }

    private static func parseInlineDestination(
        _ units: [UInt16],
        openParenIndex: Int
    ) -> (destination: Range<Int>?, end: Int)? {
        var index = openParenIndex + 1
        while index < units.count, MarkdownText.isJavaWhitespace(units[index]) { index += 1 }
        guard index < units.count else { return nil }
        if units[index] == closeParen {
            return (nil, index + 1)
        }
        let destinationStart = index
        if units[index] == lessThan {
            index += 1
            while index < units.count, units[index] != greaterThan {
                if units[index] == lessThan || units[index] == MarkdownText.lineFeed { return nil }
                if units[index] == backslash { index += 1 }
                index += 1
            }
            guard index < units.count else { return nil }
            index += 1
        } else {
            var depth = 0
            while index < units.count {
                let unit = units[index]
                if unit == backslash, index + 1 < units.count {
                    index += 2
                    continue
                }
                if MarkdownText.isJavaWhitespace(unit) || unit < 0x20 { break }
                if unit == openParen { depth += 1 }
                if unit == closeParen {
                    if depth == 0 { break }
                    depth -= 1
                }
                index += 1
            }
            if depth != 0 { return nil }
        }
        let destinationEnd = index
        while index < units.count, MarkdownText.isJavaWhitespace(units[index]) { index += 1 }
        guard index < units.count else { return nil }
        if units[index] == closeParen {
            return (destinationStart..<destinationEnd, index + 1)
        }
        let titleOpen = units[index]
        guard titleOpen == 0x22 || titleOpen == 0x27 || titleOpen == openParen, index > destinationEnd else {
            return nil
        }
        let titleClose: UInt16 = titleOpen == openParen ? closeParen : titleOpen
        index += 1
        while index < units.count, units[index] != titleClose {
            if units[index] == backslash { index += 1 }
            index += 1
        }
        guard index < units.count else { return nil }
        index += 1
        while index < units.count, MarkdownText.isJavaWhitespace(units[index]) { index += 1 }
        guard index < units.count, units[index] == closeParen else { return nil }
        return (destinationStart..<destinationEnd, index + 1)
    }

    private static func angleConstruct(_ units: [UInt16], from start: Int) -> (Int, MarkdownInlineNode.Kind)? {
        guard let close = units[(start + 1)...].firstIndex(of: greaterThan) else {
            return nil
        }
        let inner = Array(units[(start + 1)..<close])
        if inner.isEmpty { return nil }
        if inner.contains(where: { MarkdownText.isJavaWhitespace($0) }) == false {
            if isAutolinkURI(inner) || isEmailAutolink(inner) { return (close + 1, .autolink) }
        }
        if inner.starts(with: [0x21, 0x2D, 0x2D]) {
            var cursor = start + 4
            while cursor + 2 < units.count {
                if units[cursor] == 0x2D, units[cursor + 1] == 0x2D, units[cursor + 2] == greaterThan {
                    return (cursor + 3, .htmlTag)
                }
                cursor += 1
            }
            return nil
        }
        var firstIndex = 0
        if inner[0] == 0x2F { firstIndex = 1 }
        guard firstIndex < inner.count, let scalar = Unicode.Scalar(inner[firstIndex]),
              scalar.properties.isAlphabetic, scalar.isASCII else {
            return nil
        }
        return (close + 1, .htmlTag)
    }

    private static func isAutolinkURI(_ inner: [UInt16]) -> Bool {
        guard let colon = inner.firstIndex(of: 0x3A), colon >= 2, colon <= 32 else { return false }
        guard let first = Unicode.Scalar(inner[0]), first.isASCII, first.properties.isAlphabetic else { return false }
        for unit in inner[..<colon] {
            guard let scalar = Unicode.Scalar(unit), scalar.isASCII else { return false }
            guard scalar.properties.isAlphabetic || (unit >= 0x30 && unit <= 0x39) || unit == 0x2B || unit == 0x2E
                || unit == 0x2D else {
                return false
            }
        }
        return !inner[..<colon].contains(0x3C)
    }

    private static func isEmailAutolink(_ inner: [UInt16]) -> Bool {
        guard let at = inner.firstIndex(of: 0x40), at > 0, at < inner.count - 1 else { return false }
        return !inner.contains(0x3C)
    }

    private static func bareAutolinkEnd(_ units: [UInt16], from start: Int) -> Int? {
        if start > 0 {
            let previous = units[start - 1]
            let allowed = MarkdownText.isJavaWhitespace(previous) || previous == asterisk || previous == underscore
                || previous == tilde || previous == openParen
            guard allowed else { return nil }
        }
        let prefixes: [[UInt16]] = [
            Array("http://".utf16), Array("https://".utf16), Array("ftp://".utf16), Array("www.".utf16)
        ]
        guard let prefix = prefixes.first(where: { units[start...].starts(with: $0) }) else { return nil }
        var end = start + prefix.count
        guard end < units.count, !MarkdownText.isJavaWhitespace(units[end]) else { return nil }
        while end < units.count, !MarkdownText.isJavaWhitespace(units[end]), units[end] != lessThan {
            end += 1
        }
        let trailing: Set<UInt16> = [0x3F, 0x21, 0x2E, 0x2C, 0x3A, 0x2A, 0x5F, 0x7E, 0x27, 0x22, 0x3B]
        while end > start + prefix.count {
            let last = units[end - 1]
            if trailing.contains(last) {
                end -= 1
            } else if last == closeParen {
                let opens = units[start..<end].filter { $0 == openParen }.count
                let closes = units[start..<end].filter { $0 == closeParen }.count
                if closes > opens { end -= 1 } else { break }
            } else {
                break
            }
        }
        return end > start + prefix.count ? end : nil
    }
}
