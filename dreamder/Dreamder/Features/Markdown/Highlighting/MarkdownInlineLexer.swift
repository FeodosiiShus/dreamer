import Foundation

nonisolated enum MarkdownInlineLexer {
    static func tokens(in text: String) -> [MarkdownToken] {
        let units = Array(text.utf16)
        return tokens(in: units, segments: [NSRange(location: 0, length: units.count)])
    }

    static func tokens(in text: NSString, range: NSRange) -> [MarkdownToken] {
        var units = [UInt16](repeating: 0, count: text.length)
        text.getCharacters(&units, range: NSRange(location: 0, length: text.length))
        return tokens(in: units, segments: [range])
    }

    static func tokens(in units: [UInt16], segments: [NSRange]) -> [MarkdownToken] {
        var state = InlineLexerState(units: units, segments: segments)
        state.run()
        return state.finish()
    }
}

private nonisolated struct InlineDelimiter {
    let character: UInt16
    let originalCount: Int
    var low: Int
    var high: Int
    var canOpen: Bool
    var canClose: Bool

    var isEmpty: Bool { high <= low }

    mutating func kill() {
        canOpen = false
        canClose = false
        high = low
    }
}

private nonisolated struct InlineBracket {
    let index: Int
    let isImage: Bool
    let delimiterBottom: Int
    var active: Bool
}

private nonisolated struct InlineLinkTail {
    let end: Int
    let destination: Range<Int>?
    let title: Range<Int>?
}

private nonisolated struct InlineLexerState {
    private let text: [UInt16]
    private let origin: [Int]
    private let breaks: [Int]
    private var emitted: [MarkdownToken] = []
    private var delimiters: [InlineDelimiter] = []
    private var brackets: [InlineBracket] = []
    private var backtickRuns: [Int: [Int]] = [:]

    init(units: [UInt16], segments: [NSRange]) {
        var text: [UInt16] = []
        var origin: [Int] = []
        var breaks: [Int] = []
        for (index, segment) in segments.enumerated() {
            if index > 0 {
                breaks.append(text.count)
                text.append(MarkdownChar.newline)
                origin.append(segments[index - 1].location + segments[index - 1].length)
            }
            guard segment.length > 0 else { continue }
            text.append(contentsOf: units[segment.location..<(segment.location + segment.length)])
            for offset in 0..<segment.length {
                origin.append(segment.location + offset)
            }
        }
        self.text = text
        self.origin = origin
        self.breaks = breaks
        collectBacktickRuns()
    }

    private mutating func collectBacktickRuns() {
        var index = 0
        while index < text.count {
            guard text[index] == MarkdownChar.backtick else {
                index += 1
                continue
            }
            var end = index
            while end < text.count, text[end] == MarkdownChar.backtick {
                end += 1
            }
            backtickRuns[end - index, default: []].append(index)
            index = end
        }
    }

    func finish() -> [MarkdownToken] {
        emitted.sortedOuterFirst()
    }

    mutating func run() {
        let count = text.count
        var index = 0
        while index < count {
            switch text[index] {
            case MarkdownChar.backslash:
                index = scanBackslash(at: index)
            case MarkdownChar.backtick:
                index = scanBacktick(at: index)
            case MarkdownChar.star, MarkdownChar.underscore, MarkdownChar.tilde, MarkdownChar.equals:
                index = scanDelimiterRun(at: index)
            case MarkdownChar.openBracket:
                brackets.append(InlineBracket(index: index, isImage: false, delimiterBottom: delimiters.count, active: true))
                index += 1
            case MarkdownChar.exclamation:
                if index + 1 < count, text[index + 1] == MarkdownChar.openBracket {
                    brackets.append(
                        InlineBracket(index: index, isImage: true, delimiterBottom: delimiters.count, active: true)
                    )
                    index += 2
                } else {
                    index += 1
                }
            case MarkdownChar.closeBracket:
                index = scanCloseBracket(at: index)
            case MarkdownChar.less:
                index = scanLess(at: index)
            case MarkdownChar.space:
                index = scanSpaces(at: index)
            case MarkdownChar.lowerH, MarkdownChar.upperH, MarkdownChar.lowerW, MarkdownChar.upperW,
                 MarkdownChar.lowerF, MarkdownChar.upperF:
                index = scanBareURL(at: index)
            default:
                index += 1
            }
        }
        processEmphasis(bottom: 0)
    }

    private mutating func emit(_ kind: MarkdownTokenKind, _ start: Int, _ end: Int) {
        guard start < end else { return }
        var pieceStart = start
        var breakIndex = lowerBound(of: start)
        while breakIndex < breaks.count, breaks[breakIndex] < end {
            let separator = breaks[breakIndex]
            appendPiece(kind, pieceStart, separator)
            pieceStart = separator + 1
            breakIndex += 1
        }
        appendPiece(kind, pieceStart, end)
    }

    private mutating func appendPiece(_ kind: MarkdownTokenKind, _ start: Int, _ end: Int) {
        guard start < end else { return }
        let location = origin[start]
        let upper = origin[end - 1] + 1
        emitted.append(MarkdownToken(kind, from: location, to: upper))
    }

    private func lowerBound(of value: Int) -> Int {
        var low = 0
        var high = breaks.count
        while low < high {
            let middle = (low + high) / 2
            if breaks[middle] < value {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }

    private mutating func scanBackslash(at index: Int) -> Int {
        guard index + 1 < text.count else { return index + 1 }
        let next = text[index + 1]
        if next == MarkdownChar.newline {
            emit(.hardBreak, index, index + 1)
            return index + 1
        }
        if MarkdownChar.isASCIIPunctuation(next) {
            emit(.escape, index, index + 2)
            return index + 2
        }
        return index + 1
    }

    private mutating func scanSpaces(at index: Int) -> Int {
        var end = index
        while end < text.count, text[end] == MarkdownChar.space {
            end += 1
        }
        if end - index >= 2, end < text.count, text[end] == MarkdownChar.newline {
            emit(.hardBreak, index, end)
        }
        return end
    }

    private mutating func scanBacktick(at index: Int) -> Int {
        var end = index
        while end < text.count, text[end] == MarkdownChar.backtick {
            end += 1
        }
        let length = end - index
        guard let starts = backtickRuns[length] else { return end }
        var low = 0
        var high = starts.count
        while low < high {
            let middle = (low + high) / 2
            if starts[middle] < end {
                low = middle + 1
            } else {
                high = middle
            }
        }
        guard low < starts.count else { return end }
        let closeStart = starts[low]
        emit(.codeSpan, index, closeStart + length)
        emit(.codeSpanMarker, index, end)
        emit(.codeSpanMarker, closeStart, closeStart + length)
        return closeStart + length
    }

    private mutating func scanDelimiterRun(at index: Int) -> Int {
        let character = text[index]
        var end = index
        while end < text.count, text[end] == character {
            end += 1
        }
        let length = end - index
        let isPair = character == MarkdownChar.tilde || character == MarkdownChar.equals
        if isPair, length != 2 { return end }
        let previous = index > 0 ? text[index - 1] : MarkdownChar.space
        let next = end < text.count ? text[end] : MarkdownChar.space
        let nextIsWhitespace = MarkdownChar.isWhitespace(next)
        let nextIsPunctuation = MarkdownChar.isPunctuation(next)
        let previousIsWhitespace = MarkdownChar.isWhitespace(previous)
        let previousIsPunctuation = MarkdownChar.isPunctuation(previous)
        let leftFlanking = !nextIsWhitespace && (!nextIsPunctuation || previousIsWhitespace || previousIsPunctuation)
        let rightFlanking = !previousIsWhitespace
            && (!previousIsPunctuation || nextIsWhitespace || nextIsPunctuation)
        let canOpen: Bool
        let canClose: Bool
        if character == MarkdownChar.underscore {
            canOpen = leftFlanking && (!rightFlanking || previousIsPunctuation)
            canClose = rightFlanking && (!leftFlanking || nextIsPunctuation)
        } else {
            canOpen = leftFlanking
            canClose = rightFlanking
        }
        if canOpen || canClose {
            delimiters.append(
                InlineDelimiter(
                    character: character,
                    originalCount: length,
                    low: index,
                    high: end,
                    canOpen: canOpen,
                    canClose: canClose
                )
            )
        }
        return end
    }

    private mutating func processEmphasis(bottom: Int) {
        var openerFloors: [Int: Int] = [:]
        var closerIndex = bottom
        while closerIndex < delimiters.count {
            let closer = delimiters[closerIndex]
            guard closer.canClose, !closer.isEmpty else {
                closerIndex += 1
                continue
            }
            let isPair = closer.character == MarkdownChar.tilde || closer.character == MarkdownChar.equals
            let key = Int(closer.character) * 8 + (closer.canOpen ? 4 : 0) + (closer.originalCount % 3)
            let floor = max(bottom, openerFloors[key] ?? bottom)
            var openerIndex = closerIndex - 1
            var found = -1
            while openerIndex >= floor {
                let opener = delimiters[openerIndex]
                if opener.character == closer.character, opener.canOpen, !opener.isEmpty {
                    let oddMatch = (opener.canClose || closer.canOpen)
                        && (opener.originalCount + closer.originalCount) % 3 == 0
                        && !(opener.originalCount % 3 == 0 && closer.originalCount % 3 == 0)
                    if isPair || !oddMatch {
                        found = openerIndex
                        break
                    }
                }
                openerIndex -= 1
            }
            if found >= 0 {
                closerIndex = pair(openerIndex: found, closerIndex: closerIndex)
            } else {
                openerFloors[key] = closerIndex
                if !closer.canOpen {
                    delimiters[closerIndex].kill()
                }
                closerIndex += 1
            }
        }
        if bottom < delimiters.count {
            delimiters.removeSubrange(bottom...)
        }
    }

    private mutating func pair(openerIndex: Int, closerIndex: Int) -> Int {
        var opener = delimiters[openerIndex]
        var closer = delimiters[closerIndex]
        let isPair = closer.character == MarkdownChar.tilde || closer.character == MarkdownChar.equals
        let used = isPair ? 2 : ((opener.high - opener.low >= 2 && closer.high - closer.low >= 2) ? 2 : 1)
        let openStart = opener.high - used
        let closeEnd = closer.low + used
        switch closer.character {
        case MarkdownChar.tilde:
            emit(.strikethrough, openStart, closeEnd)
        case MarkdownChar.equals:
            emit(.highlight, openStart, closeEnd)
        default:
            emit(used == 2 ? .bold : .italic, openStart, closeEnd)
            emit(used == 2 ? .boldMarker : .italicMarker, openStart, openStart + used)
            emit(used == 2 ? .boldMarker : .italicMarker, closeEnd - used, closeEnd)
        }
        opener.high -= used
        closer.low += used
        delimiters[openerIndex] = opener
        delimiters[closerIndex] = closer
        if openerIndex + 1 < closerIndex {
            for index in (openerIndex + 1)..<closerIndex {
                delimiters[index].kill()
            }
        }
        if opener.isEmpty {
            delimiters[openerIndex].kill()
        }
        if closer.isEmpty {
            delimiters[closerIndex].kill()
            return closerIndex + 1
        }
        return closerIndex
    }

    private mutating func scanCloseBracket(at index: Int) -> Int {
        guard let opener = brackets.popLast(), opener.active else { return index + 1 }
        let linkStart = opener.isImage ? opener.index + 1 : opener.index
        let outerStart = opener.index
        let count = text.count

        if index + 1 < count, text[index + 1] == MarkdownChar.openParen, let tail = parseInlineLinkTail(from: index + 1) {
            processEmphasis(bottom: opener.delimiterBottom)
            if opener.isImage {
                emit(.image, outerStart, tail.end)
            }
            emit(.inlineLink, linkStart, tail.end)
            emit(.linkText, linkStart, index + 1)
            if let destination = tail.destination {
                emit(.linkDestination, destination.lowerBound, destination.upperBound)
            }
            if let title = tail.title {
                emit(.linkTitle, title.lowerBound, title.upperBound)
            }
            finishLink(isImage: opener.isImage)
            return tail.end
        }

        if index + 1 < count, text[index + 1] == MarkdownChar.openBracket, let labelEnd = labelEnd(from: index + 1) {
            processEmphasis(bottom: opener.delimiterBottom)
            if opener.isImage {
                emit(.image, outerStart, labelEnd + 1)
            }
            emit(.linkText, linkStart, index + 1)
            emit(.linkLabel, index + 1, labelEnd + 1)
            finishLink(isImage: opener.isImage)
            return labelEnd + 1
        }

        let contentStart = opener.index + (opener.isImage ? 2 : 1)
        guard hasVisibleContent(from: contentStart, to: index) else { return index + 1 }
        processEmphasis(bottom: opener.delimiterBottom)
        if opener.isImage {
            emit(.image, outerStart, index + 1)
        }
        emit(.linkLabel, linkStart, index + 1)
        finishLink(isImage: opener.isImage)
        return index + 1
    }

    private mutating func finishLink(isImage: Bool) {
        guard !isImage else { return }
        for index in brackets.indices where !brackets[index].isImage {
            brackets[index].active = false
        }
    }

    private func hasVisibleContent(from start: Int, to end: Int) -> Bool {
        var index = start
        while index < end {
            if !MarkdownChar.isWhitespace(text[index]) { return true }
            index += 1
        }
        return false
    }

    private func labelEnd(from start: Int) -> Int? {
        var index = start + 1
        while index < text.count {
            switch text[index] {
            case MarkdownChar.backslash:
                index += 2
                continue
            case MarkdownChar.openBracket:
                return nil
            case MarkdownChar.closeBracket:
                return index
            default:
                index += 1
            }
        }
        return nil
    }

    private func parseInlineLinkTail(from start: Int) -> InlineLinkTail? {
        let count = text.count
        var index = start + 1
        index = skipWhitespace(from: index)
        var destination: Range<Int>?
        if index < count, text[index] == MarkdownChar.less {
            var cursor = index + 1
            while cursor < count {
                let unit = text[cursor]
                if unit == MarkdownChar.backslash {
                    cursor += 2
                    continue
                }
                if unit == MarkdownChar.newline || unit == MarkdownChar.less { return nil }
                if unit == MarkdownChar.greater { break }
                cursor += 1
            }
            guard cursor < count, text[cursor] == MarkdownChar.greater else { return nil }
            destination = index..<(cursor + 1)
            index = cursor + 1
        } else {
            var depth = 0
            var cursor = index
            while cursor < count {
                let unit = text[cursor]
                if unit == MarkdownChar.backslash, cursor + 1 < count, MarkdownChar.isASCIIPunctuation(text[cursor + 1]) {
                    cursor += 2
                    continue
                }
                if MarkdownChar.isWhitespace(unit) || unit < 32 { break }
                if unit == MarkdownChar.openParen {
                    depth += 1
                } else if unit == MarkdownChar.closeParen {
                    if depth == 0 { break }
                    depth -= 1
                }
                cursor += 1
            }
            guard depth == 0 else { return nil }
            if cursor > index {
                destination = index..<cursor
            }
            index = cursor
        }
        let afterDestination = index
        index = skipWhitespace(from: index)
        var title: Range<Int>?
        if index > afterDestination, index < count {
            let opening = text[index]
            let closing: UInt16?
            switch opening {
            case MarkdownChar.doubleQuote: closing = MarkdownChar.doubleQuote
            case MarkdownChar.singleQuote: closing = MarkdownChar.singleQuote
            case MarkdownChar.openParen: closing = MarkdownChar.closeParen
            default: closing = nil
            }
            if let closing {
                var cursor = index + 1
                while cursor < count {
                    let unit = text[cursor]
                    if unit == MarkdownChar.backslash {
                        cursor += 2
                        continue
                    }
                    if unit == closing { break }
                    if opening == MarkdownChar.openParen, unit == MarkdownChar.openParen { return nil }
                    cursor += 1
                }
                guard cursor < count, text[cursor] == closing else { return nil }
                title = index..<(cursor + 1)
                index = skipWhitespace(from: cursor + 1)
            }
        }
        guard index < count, text[index] == MarkdownChar.closeParen else { return nil }
        return InlineLinkTail(end: index + 1, destination: destination, title: title)
    }

    private func skipWhitespace(from start: Int) -> Int {
        var index = start
        while index < text.count, MarkdownChar.isWhitespace(text[index]) {
            index += 1
        }
        return index
    }

    private mutating func scanLess(at index: Int) -> Int {
        if let close = autolinkEnd(from: index) {
            emit(.autolink, index + 1, close)
            return close + 1
        }
        if let end = inlineHTMLEnd(from: index) {
            emit(.inlineHtml, index, end)
            var scanner = MarkdownHTMLScanner(emitsText: false)
            var tokens: [MarkdownToken] = []
            scanner.scan(text, from: index, to: end, into: &tokens)
            for token in tokens {
                emit(token.kind, token.range.location, token.range.location + token.range.length)
            }
            return end
        }
        return index + 1
    }

    private func autolinkEnd(from start: Int) -> Int? {
        let count = text.count
        let index = start + 1
        guard index < count, MarkdownChar.isASCIILetter(text[index]) else { return nil }
        var cursor = index
        while cursor < count, cursor - index < 32,
              MarkdownChar.isASCIIAlphanumeric(text[cursor]) || text[cursor] == MarkdownChar.plus
                || text[cursor] == MarkdownChar.dot || text[cursor] == MarkdownChar.dash {
            cursor += 1
        }
        if cursor < count, text[cursor] == MarkdownChar.colon, cursor - index >= 2 {
            var end = cursor + 1
            while end < count {
                let unit = text[end]
                if unit == MarkdownChar.greater { return end }
                if unit == MarkdownChar.less || MarkdownChar.isWhitespace(unit) || unit < 32 { return nil }
                end += 1
            }
            return nil
        }
        cursor = start + 1
        let localStart = cursor
        while cursor < count, MarkdownChar.isASCIIAlphanumeric(text[cursor]) || Self.emailPunctuation.contains(text[cursor]) {
            cursor += 1
        }
        guard cursor > localStart, cursor < count, text[cursor] == MarkdownChar.at else { return nil }
        cursor += 1
        let domainStart = cursor
        while cursor < count,
              MarkdownChar.isASCIIAlphanumeric(text[cursor]) || text[cursor] == MarkdownChar.dash
                || text[cursor] == MarkdownChar.dot {
            cursor += 1
        }
        guard cursor > domainStart, cursor < count, text[cursor] == MarkdownChar.greater else { return nil }
        return cursor
    }

    private static let emailPunctuation: Set<UInt16> = Set(".!#$%&'*+/=?^_`{|}~-".utf16)

    private func inlineHTMLEnd(from start: Int) -> Int? {
        let count = text.count
        guard start + 1 < count else { return nil }
        let next = text[start + 1]
        if next == MarkdownChar.exclamation {
            if hasLiteral(at: start, "<!--") {
                return find("-->", from: start + 4).map { $0 + 3 }
            }
            if hasLiteral(at: start, "<![CDATA[") {
                return find("]]>", from: start + 9).map { $0 + 3 }
            }
            if start + 2 < count, MarkdownChar.isASCIILetter(text[start + 2]), text[start + 2] < 97 {
                return find(">", from: start + 2).map { $0 + 1 }
            }
            return nil
        }
        if next == MarkdownChar.question {
            return find("?>", from: start + 2).map { $0 + 2 }
        }
        return MarkdownHTMLScanner.tagEnd(in: text, from: start, to: count)
    }

    private func hasLiteral(at index: Int, _ literal: StaticString) -> Bool {
        let length = literal.utf8CodeUnitCount
        guard index + length <= text.count else { return false }
        return literal.withUTF8Buffer { buffer in
            for offset in 0..<length where text[index + offset] != UInt16(buffer[offset]) {
                return false
            }
            return true
        }
    }

    private func find(_ literal: StaticString, from start: Int) -> Int? {
        var index = start
        while index < text.count {
            if hasLiteral(at: index, literal) { return index }
            index += 1
        }
        return nil
    }

    private mutating func scanBareURL(at index: Int) -> Int {
        if index > 0 {
            let previous = text[index - 1]
            let allowed = MarkdownChar.isWhitespace(previous) || previous == MarkdownChar.star
                || previous == MarkdownChar.underscore || previous == MarkdownChar.tilde
                || previous == MarkdownChar.openParen
            if !allowed { return index + 1 }
        }
        let prefixLength = bareURLPrefixLength(at: index)
        guard prefixLength > 0 else { return index + 1 }
        var end = index + prefixLength
        let bodyStart = end
        while end < text.count {
            let unit = text[end]
            if MarkdownChar.isWhitespace(unit) || unit == MarkdownChar.less || unit < 32 { break }
            if unit == MarkdownChar.closeBracket, !brackets.isEmpty { break }
            end += 1
        }
        end = trimURLTail(from: bodyStart, to: end)
        guard end > bodyStart else { return index + 1 }
        emit(.autolink, index, end)
        return end
    }

    private func bareURLPrefixLength(at index: Int) -> Int {
        let candidates: [(StaticString, Bool)] = [("http://", false), ("https://", false), ("ftp://", false), ("www.", true)]
        for (prefix, needsAlphanumericAfter) in candidates {
            let length = prefix.utf8CodeUnitCount
            guard index + length <= text.count else { continue }
            let matches = prefix.withUTF8Buffer { buffer in
                for offset in 0..<length {
                    var unit = text[index + offset]
                    if unit >= 65, unit <= 90 { unit += 32 }
                    if unit != UInt16(buffer[offset]) { return false }
                }
                return true
            }
            guard matches else { continue }
            if needsAlphanumericAfter {
                guard index + length < text.count, MarkdownChar.isASCIIAlphanumeric(text[index + length]) else { continue }
            }
            return length
        }
        return 0
    }

    private func trimURLTail(from start: Int, to end: Int) -> Int {
        var upper = end
        while upper > start {
            let unit = text[upper - 1]
            switch unit {
            case MarkdownChar.question, MarkdownChar.exclamation, MarkdownChar.dot, MarkdownChar.comma,
                 MarkdownChar.colon, MarkdownChar.star, MarkdownChar.underscore, MarkdownChar.tilde,
                 MarkdownChar.singleQuote, MarkdownChar.doubleQuote, MarkdownChar.semicolon:
                upper -= 1
            case MarkdownChar.closeParen:
                var opening = 0
                var closing = 0
                for index in start..<upper {
                    if text[index] == MarkdownChar.openParen { opening += 1 }
                    if text[index] == MarkdownChar.closeParen { closing += 1 }
                }
                if closing > opening {
                    upper -= 1
                } else {
                    return upper
                }
            default:
                return upper
            }
        }
        return upper
    }
}
