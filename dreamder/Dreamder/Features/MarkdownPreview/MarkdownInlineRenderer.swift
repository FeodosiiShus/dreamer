import Foundation

nonisolated enum MarkdownInlineRenderer {
    static func render(_ text: String) -> String {
        var scanner = MarkdownInlineScanner(text)
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
}

private nonisolated struct MarkdownInlineScanner {
    private static let lineBreakMarker: Character = "\u{E000}"
    private static let escapableCharacters: Set<Character> = Set("!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~")

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
    }

    private let characters: [Character]
    private var index = 0
    private var tokens: [Token] = []
    private var pendingText = ""

    init(_ text: String) {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "  \n", with: String(Self.lineBreakMarker))
            .replacingOccurrences(of: "\\\n", with: String(Self.lineBreakMarker))
        characters = Array(normalized)
    }

    mutating func render() -> String {
        while index < characters.count {
            let start = index
            scan()
            if index == start {
                pendingText.append(characters[index])
                index += 1
            }
        }
        flushText()
        processEmphasis()
        return emit()
    }

    private mutating func scan() {
        let character = characters[index]
        switch character {
        case "\\":
            if index + 1 < characters.count, Self.escapableCharacters.contains(characters[index + 1]) {
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
            if let tag = MarkdownHTMLTag.parse(characters, at: index) {
                appendRaw(MarkdownHTMLSanitizer.sanitize(tag.text))
                index = tag.endIndex + 1
            } else {
                pendingText.append("<")
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

    private mutating func scanLink(isImage: Bool) -> Bool {
        let labelStart = index + (isImage ? 2 : 1)
        guard let closingBracket = closingBracketIndex(from: labelStart) else { return false }

        var cursor = closingBracket + 1
        guard cursor < characters.count, characters[cursor] == "(" else { return false }
        cursor += 1
        skipSpaces(&cursor)

        var destination = ""
        if cursor < characters.count, characters[cursor] == "<" {
            cursor += 1
            while cursor < characters.count, characters[cursor] != ">" {
                destination.append(characters[cursor])
                cursor += 1
            }
            guard cursor < characters.count else { return false }
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
            guard cursor < characters.count else { return false }
            cursor += 1
            title = collected
            skipSpaces(&cursor)
        }

        guard cursor < characters.count, characters[cursor] == ")" else { return false }
        cursor += 1

        let label = String(characters[labelStart..<closingBracket])
        let titleHTML = title.map { " title=\"\(MarkdownInlineRenderer.escape($0))\"" } ?? ""
        if isImage {
            appendRaw("<img src=\"\(MarkdownInlineRenderer.escape(destination))\" alt=\"\(MarkdownInlineRenderer.escape(label))\"\(titleHTML) />")
        } else {
            let labelHTML = MarkdownInlineRenderer.render(label)
            appendRaw("<a href=\"\(MarkdownInlineRenderer.escape(destination))\"\(titleHTML)>\(labelHTML)</a>")
        }
        index = cursor
        return true
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
                      !Self.violatesRuleOfThree(opener: currentOpener, closer: currentCloser) else {
                    openerPosition -= 1
                    continue
                }

                var opener = currentOpener
                var closer = currentCloser
                let use = (opener.count >= 2 && closer.count >= 2) ? 2 : 1
                let tag = use == 2 ? "strong" : "em"
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
                if delimiter.openTags.isEmpty {
                    html += delimiter.closeTags.joined()
                    html += leftover
                } else if delimiter.closeTags.isEmpty {
                    html += leftover
                    html += delimiter.openTags.joined()
                } else {
                    html += leftover
                    html += delimiter.openTags.joined()
                    html += delimiter.closeTags.joined()
                }
            }
        }
        return html
    }
}
