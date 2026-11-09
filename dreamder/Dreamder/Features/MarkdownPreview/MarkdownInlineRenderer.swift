import Foundation

nonisolated struct MarkdownLinkReference: Equatable, Sendable {
    let destination: String
    let title: String?
}

nonisolated struct MarkdownInlineContext: Sendable {
    static let empty = MarkdownInlineContext()

    var references: [String: MarkdownLinkReference] = [:]
    var allowsLinks = true
}

nonisolated enum MarkdownInlineRenderer {
    fileprivate static let escapableCharacters: Set<Character> = Set("!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~")

    static func render(_ text: String, context: MarkdownInlineContext = .empty) -> String {
        var scanner = MarkdownInlineScanner(text, context: context)
        return scanner.render()
    }

    static func escape(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            default: result.append(character)
            }
        }
        return result
    }

    static func unescapeLiteral(_ text: String) -> String {
        guard text.contains("\\") || text.contains("&") else { return text }
        let characters = Array(text)
        var result = ""
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\\", index + 1 < characters.count, escapableCharacters.contains(characters[index + 1]) {
                result.append(characters[index + 1])
                index += 2
            } else if character == "&", let entity = MarkdownHTMLEntities.decode(characters, at: index) {
                result += entity.text
                index = entity.end
            } else {
                result.append(character)
                index += 1
            }
        }
        return result
    }

    static func normalizedReferenceLabel(_ label: String) -> String {
        label
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased()
    }

    static func plainText(fromHTML html: String) -> String {
        var result = ""
        var insideTag = false
        for character in html {
            if character == "<" {
                insideTag = true
            } else if character == ">", insideTag {
                insideTag = false
            } else if !insideTag {
                result.append(character)
            }
        }
        return result
    }
}

private nonisolated struct MarkdownInlineScanner {
    private static let lineBreakMarker: Character = "\u{E000}"
    private static let bareLinkPrefixes = ["https://", "http://", "www."]
    private static let bareLinkLeadingBoundaries: Set<Character> = ["*", "_", "~", "("]
    private static let bareLinkTrailingPunctuation: Set<Character> = ["?", "!", ".", ",", ":", "*", "_", "~", "'", "\""]
    private static let emailLocalCharacters: Set<Character> = Set("!#$%&'*+/=?^_`{|}~.-")

    private enum Token {
        case text(String)
        case delimiter(Delimiter)
    }

    private struct Delimiter {
        let character: Character
        var count: Int
        let canOpen: Bool
        let canClose: Bool
        var isActive = true
        var openTags: [String] = []
        var closeTags: [String] = []

        var isPair: Bool { character == "~" || character == "=" }
    }

    private struct InlineTail {
        let destination: String
        let title: String?
        let end: Int
    }

    private let characters: [Character]
    private let context: MarkdownInlineContext
    private var index = 0
    private var tokens: [Token] = []
    private var pendingText = ""

    init(_ text: String, context: MarkdownInlineContext) {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "  \n", with: String(Self.lineBreakMarker))
            .replacingOccurrences(of: "\\\n", with: String(Self.lineBreakMarker))
        characters = Array(normalized)
        self.context = context
    }

    mutating func render() -> String {
        while index < characters.count {
            scan()
        }
        flushText()
        processEmphasis()
        return emit()
    }

    private mutating func scan() {
        let character = characters[index]
        switch character {
        case "\\":
            if index + 1 < characters.count, MarkdownInlineRenderer.escapableCharacters.contains(characters[index + 1]) {
                pendingText.append(characters[index + 1])
                index += 2
            } else {
                pendingText.append(character)
                index += 1
            }
        case "`":
            scanCodeSpan()
        case "*", "_":
            scanDelimiter(character)
        case "~", "=":
            scanPairDelimiter(character)
        case "&":
            if let entity = MarkdownHTMLEntities.decode(characters, at: index) {
                pendingText += entity.text
                index = entity.end
            } else {
                pendingText.append("&")
                index += 1
            }
        case "!":
            let startsImage = index + 1 < characters.count && characters[index + 1] == "["
            if !startsImage || !scanLink(isImage: true) {
                pendingText.append("!")
                index += 1
            }
        case "[":
            if !scanLink(isImage: false) {
                pendingText.append("[")
                index += 1
            }
        case "<":
            if let autolink = angleAutolink(at: index) {
                appendRaw(autolink.html)
                index = autolink.end
            } else if let tag = MarkdownHTMLTag.parse(characters, at: index) {
                appendRaw(MarkdownHTMLSanitizer.sanitize(tag.text))
                index = tag.endIndex + 1
            } else {
                pendingText.append("<")
                index += 1
            }
        case "h", "H", "w", "W":
            if !scanBareAutolink() {
                pendingText.append(character)
                index += 1
            }
        case Self.lineBreakMarker:
            appendRaw("<br />\n")
            index += 1
        default:
            pendingText.append(character)
            index += 1
        }
    }

    private mutating func scanCodeSpan() {
        let start = index
        var runLength = 0
        while index < characters.count, characters[index] == "`" {
            runLength += 1
            index += 1
        }

        var search = index
        while search < characters.count {
            guard characters[search] == "`" else {
                search += 1
                continue
            }
            var closerLength = 0
            var closerEnd = search
            while closerEnd < characters.count, characters[closerEnd] == "`" {
                closerLength += 1
                closerEnd += 1
            }
            if closerLength == runLength {
                var content = String(characters[index..<search]).replacingOccurrences(of: "\n", with: " ")
                if content.count >= 2, content.hasPrefix(" "), content.hasSuffix(" "),
                   content.contains(where: { $0 != " " }) {
                    content = String(content.dropFirst().dropLast())
                }
                appendRaw("<code>\(MarkdownInlineRenderer.escape(content))</code>")
                index = closerEnd
                return
            }
            search = closerEnd
        }

        pendingText += String(characters[start..<index])
    }

    private mutating func scanDelimiter(_ character: Character) {
        let previous = index > 0 ? characters[index - 1] : nil
        var count = 0
        while index < characters.count, characters[index] == character {
            count += 1
            index += 1
        }
        let next = index < characters.count ? characters[index] : nil

        let previousIsWhitespace = previous?.isWhitespace ?? true
        let nextIsWhitespace = next?.isWhitespace ?? true

        var canOpen = !nextIsWhitespace
        var canClose = !previousIsWhitespace
        if character == "_" {
            let previousIsWord = (previous?.isLetter ?? false) || (previous?.isNumber ?? false)
            let nextIsWord = (next?.isLetter ?? false) || (next?.isNumber ?? false)
            canOpen = canOpen && !previousIsWord
            canClose = canClose && !nextIsWord
        }

        flushText()
        tokens.append(.delimiter(Delimiter(character: character, count: count, canOpen: canOpen, canClose: canClose)))
    }

    private mutating func scanPairDelimiter(_ character: Character) {
        let previous = index > 0 ? characters[index - 1] : nil
        var count = 0
        while index < characters.count, characters[index] == character {
            count += 1
            index += 1
        }
        guard count == 2 else {
            pendingText += String(repeating: String(character), count: count)
            return
        }
        let next = index < characters.count ? characters[index] : nil
        let canOpen = !(next?.isWhitespace ?? true)
        let canClose = !(previous?.isWhitespace ?? true)

        flushText()
        tokens.append(.delimiter(Delimiter(character: character, count: 2, canOpen: canOpen, canClose: canClose)))
    }

    private mutating func scanLink(isImage: Bool) -> Bool {
        if !isImage, !context.allowsLinks { return false }
        let labelStart = index + (isImage ? 2 : 1)
        guard let closingBracket = closingBracketIndex(from: labelStart) else { return false }
        let label = String(characters[labelStart..<closingBracket])
        let afterLabel = closingBracket + 1

        if afterLabel < characters.count, characters[afterLabel] == "(",
           let tail = parseInlineTail(from: afterLabel + 1) {
            emitLink(label: label, destination: tail.destination, title: tail.title, isImage: isImage)
            index = tail.end
            return true
        }

        if afterLabel < characters.count, characters[afterLabel] == "[" {
            guard let referenceClose = closingBracketIndex(from: afterLabel + 1) else { return false }
            let referenceLabel = String(characters[(afterLabel + 1)..<referenceClose])
            let key = referenceLabel.allSatisfy({ $0.isWhitespace }) ? label : referenceLabel
            guard let reference = context.references[MarkdownInlineRenderer.normalizedReferenceLabel(key)] else {
                return false
            }
            emitLink(label: label, destination: reference.destination, title: reference.title, isImage: isImage)
            index = referenceClose + 1
            return true
        }

        guard let reference = context.references[MarkdownInlineRenderer.normalizedReferenceLabel(label)] else {
            return false
        }
        emitLink(label: label, destination: reference.destination, title: reference.title, isImage: isImage)
        index = afterLabel
        return true
    }

    private func parseInlineTail(from start: Int) -> InlineTail? {
        var cursor = start
        skipSpaces(&cursor)

        var destination = ""
        if cursor < characters.count, characters[cursor] == "<" {
            cursor += 1
            while cursor < characters.count, characters[cursor] != ">" {
                destination.append(characters[cursor])
                cursor += 1
            }
            guard cursor < characters.count else { return nil }
            cursor += 1
        } else {
            var depth = 0
            while cursor < characters.count, !characters[cursor].isWhitespace {
                if characters[cursor] == "(" {
                    depth += 1
                } else if characters[cursor] == ")" {
                    if depth == 0 { break }
                    depth -= 1
                }
                destination.append(characters[cursor])
                cursor += 1
            }
        }

        skipSpaces(&cursor)

        var title: String?
        if cursor < characters.count, "\"'(".contains(characters[cursor]) {
            let opener = characters[cursor]
            let closer: Character = opener == "(" ? ")" : opener
            cursor += 1
            var collected = ""
            while cursor < characters.count, characters[cursor] != closer {
                collected.append(characters[cursor])
                cursor += 1
            }
            guard cursor < characters.count else { return nil }
            cursor += 1
            title = collected
            skipSpaces(&cursor)
        }

        guard cursor < characters.count, characters[cursor] == ")" else { return nil }
        return InlineTail(
            destination: MarkdownInlineRenderer.unescapeLiteral(destination),
            title: title.map(MarkdownInlineRenderer.unescapeLiteral),
            end: cursor + 1
        )
    }

    private mutating func emitLink(label: String, destination: String, title: String?, isImage: Bool) {
        let titleHTML = title.map { " title=\"\(MarkdownInlineRenderer.escape($0))\"" } ?? ""
        let labelContext = MarkdownInlineContext(references: context.references, allowsLinks: false)
        let labelHTML = MarkdownInlineRenderer.render(label, context: labelContext)
        if isImage {
            let alt = MarkdownInlineRenderer.plainText(fromHTML: labelHTML)
            appendRaw("<img src=\"\(MarkdownInlineRenderer.escape(destination))\" alt=\"\(alt)\"\(titleHTML) />")
        } else {
            appendRaw("<a href=\"\(MarkdownInlineRenderer.escape(destination))\"\(titleHTML)>\(labelHTML)</a>")
        }
    }

    private func angleAutolink(at start: Int) -> (html: String, end: Int)? {
        guard context.allowsLinks else { return nil }
        var cursor = start + 1
        var content = ""
        while cursor < characters.count, characters[cursor] != ">" {
            let character = characters[cursor]
            if character == "<" || character.isWhitespace || character == Self.lineBreakMarker { return nil }
            content.append(character)
            cursor += 1
        }
        guard cursor < characters.count, !content.isEmpty else { return nil }

        let escaped = MarkdownInlineRenderer.escape(content)
        if Self.isURIAutolink(content) {
            return ("<a href=\"\(escaped)\">\(escaped)</a>", cursor + 1)
        }
        if Self.isEmailAutolink(content) {
            return ("<a href=\"mailto:\(escaped)\">\(escaped)</a>", cursor + 1)
        }
        return nil
    }

    private static func isURIAutolink(_ content: String) -> Bool {
        guard let colon = content.firstIndex(of: ":") else { return false }
        let scheme = content[content.startIndex..<colon]
        guard (2...32).contains(scheme.count), let first = scheme.first, first.isASCII, first.isLetter else {
            return false
        }
        return scheme.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "+" || $0 == "." || $0 == "-") }
    }

    private static func isEmailAutolink(_ content: String) -> Bool {
        let parts = content.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return false }
        let localIsValid = parts[0].allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || emailLocalCharacters.contains($0))
        }
        guard localIsValid else { return false }
        let labels = parts[1].split(separator: ".", omittingEmptySubsequences: false)
        return labels.allSatisfy { label in
            guard let first = label.first, let last = label.last, label.count <= 63 else { return false }
            let edgesAreAlphanumeric = [first, last].allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
            return edgesAreAlphanumeric && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }
    }

    private mutating func scanBareAutolink() -> Bool {
        guard context.allowsLinks else { return false }
        if index > 0 {
            let previous = characters[index - 1]
            let isBoundary = previous.isWhitespace
                || previous == Self.lineBreakMarker
                || Self.bareLinkLeadingBoundaries.contains(previous)
            guard isBoundary else { return false }
        }
        guard let prefix = Self.bareLinkPrefixes.first(where: { hasPrefix($0, at: index) }) else { return false }

        var end = index
        while end < characters.count {
            let character = characters[end]
            if character.isWhitespace || character == "<" || character == Self.lineBreakMarker { break }
            end += 1
        }
        var candidate = Array(characters[index..<end])
        Self.trimTrailingPunctuation(&candidate)
        guard candidate.count > prefix.count, Self.hasValidDomain(candidate, prefixLength: prefix.count) else {
            return false
        }

        let text = String(candidate)
        let escaped = MarkdownInlineRenderer.escape(text)
        let destination = prefix == "www." ? "http://" + escaped : escaped
        appendRaw("<a href=\"\(destination)\">\(escaped)</a>")
        index += candidate.count
        return true
    }

    private func hasPrefix(_ prefix: String, at start: Int) -> Bool {
        var cursor = start
        for expected in prefix {
            guard cursor < characters.count, characters[cursor].lowercased() == String(expected) else { return false }
            cursor += 1
        }
        return true
    }

    private static func trimTrailingPunctuation(_ candidate: inout [Character]) {
        while let last = candidate.last {
            if bareLinkTrailingPunctuation.contains(last) {
                candidate.removeLast()
                continue
            }
            if last == ")" {
                let opens = candidate.filter { $0 == "(" }.count
                let closes = candidate.filter { $0 == ")" }.count
                if closes > opens {
                    candidate.removeLast()
                    continue
                }
            }
            if last == ";", let ampersand = candidate.lastIndex(of: "&"),
               ampersand < candidate.count - 2,
               candidate[(ampersand + 1)..<(candidate.count - 1)].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) {
                candidate.removeSubrange(ampersand...)
                continue
            }
            break
        }
    }

    private static func hasValidDomain(_ candidate: [Character], prefixLength: Int) -> Bool {
        let domainStart = prefixLength == 4 ? 0 : prefixLength
        var domainEnd = domainStart
        while domainEnd < candidate.count, !"/?#:".contains(candidate[domainEnd]) {
            domainEnd += 1
        }
        let domain = candidate[domainStart..<domainEnd]
        guard domain.count > (prefixLength == 4 ? 4 : 0) else { return false }
        let segments = domain.split(separator: ".", omittingEmptySubsequences: false)
        return segments.allSatisfy { segment in
            !segment.isEmpty && segment.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
        }
    }

    private func closingBracketIndex(from start: Int) -> Int? {
        var depth = 0
        var cursor = start
        while cursor < characters.count {
            if characters[cursor] == "\\" {
                cursor += 2
                continue
            }
            if characters[cursor] == "[" {
                depth += 1
            } else if characters[cursor] == "]" {
                if depth == 0 { return cursor }
                depth -= 1
            }
            cursor += 1
        }
        return nil
    }

    private func skipSpaces(_ cursor: inout Int) {
        while cursor < characters.count, characters[cursor] == " " {
            cursor += 1
        }
    }

    private mutating func flushText() {
        guard !pendingText.isEmpty else { return }
        tokens.append(.text(MarkdownInlineRenderer.escape(pendingText)))
        pendingText = ""
    }

    private mutating func appendRaw(_ html: String) {
        flushText()
        tokens.append(.text(html))
    }

    private mutating func processEmphasis() {
        var delimiterIndices: [Int] = []
        for (offset, token) in tokens.enumerated() {
            if case .delimiter = token {
                delimiterIndices.append(offset)
            }
        }

        var closerPosition = 0
        while closerPosition < delimiterIndices.count {
            let closerTokenIndex = delimiterIndices[closerPosition]
            guard case .delimiter(let currentCloser) = tokens[closerTokenIndex],
                  currentCloser.canClose,
                  currentCloser.isActive,
                  currentCloser.count > 0 else {
                closerPosition += 1
                continue
            }

            var openerPosition = closerPosition - 1
            var matched = false
            while openerPosition >= 0 {
                let openerTokenIndex = delimiterIndices[openerPosition]
                guard case .delimiter(let currentOpener) = tokens[openerTokenIndex],
                      currentOpener.character == currentCloser.character,
                      currentOpener.canOpen,
                      currentOpener.isActive,
                      currentOpener.count > 0,
                      currentCloser.isPair || !Self.violatesRuleOfThree(opener: currentOpener, closer: currentCloser)
                else {
                    openerPosition -= 1
                    continue
                }

                var opener = currentOpener
                var closer = currentCloser
                let use = (currentCloser.isPair || (opener.count >= 2 && closer.count >= 2)) ? 2 : 1
                let tag = Self.tagName(for: currentCloser.character, use: use)
                opener.count -= use
                closer.count -= use
                opener.openTags.insert("<\(tag)>", at: 0)
                closer.closeTags.append("</\(tag)>")

                for droppedPosition in stride(from: openerPosition + 1, to: closerPosition, by: 1) {
                    let droppedIndex = delimiterIndices[droppedPosition]
                    if case .delimiter(var dropped) = tokens[droppedIndex] {
                        dropped.isActive = false
                        tokens[droppedIndex] = .delimiter(dropped)
                    }
                }

                tokens[openerTokenIndex] = .delimiter(opener)
                tokens[closerTokenIndex] = .delimiter(closer)
                matched = true
                break
            }

            guard matched else {
                closerPosition += 1
                continue
            }
            if case .delimiter(let updatedCloser) = tokens[closerTokenIndex], updatedCloser.count == 0 {
                closerPosition += 1
            }
        }
    }

    private static func tagName(for character: Character, use: Int) -> String {
        switch character {
        case "~": return "del"
        case "=": return "mark"
        default: return use == 2 ? "strong" : "em"
        }
    }

    private static func violatesRuleOfThree(opener: Delimiter, closer: Delimiter) -> Bool {
        guard opener.canClose || closer.canOpen else { return false }
        guard (opener.count + closer.count) % 3 == 0 else { return false }
        return !(opener.count % 3 == 0 && closer.count % 3 == 0)
    }

    private func emit() -> String {
        var html = ""
        for token in tokens {
            switch token {
            case .text(let text):
                html += text
            case .delimiter(let delimiter):
                let leftover = delimiter.count > 0
                    ? String(repeating: String(delimiter.character), count: delimiter.count)
                    : ""
                html += delimiter.closeTags.joined()
                html += leftover
                html += delimiter.openTags.joined()
            }
        }
        return html
    }
}
