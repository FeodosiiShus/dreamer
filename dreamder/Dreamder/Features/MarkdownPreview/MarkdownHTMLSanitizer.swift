import Foundation

nonisolated enum MarkdownHTMLTag {
    struct ParsedTag {
        let text: String
        let name: String
        let isClosing: Bool
        let endIndex: Int
    }

    static func parse(_ characters: [Character], at start: Int) -> ParsedTag? {
        guard start < characters.count, characters[start] == "<" else { return nil }
        var index = start + 1
        guard index < characters.count else { return nil }

        if characters[index] == "!" {
            let rest = String(characters[index...]).lowercased()
            if rest.hasPrefix("!--") {
                return delimited(characters, contentStart: index + 3, opening: start, terminator: ["-", "-", ">"], name: "#comment")
            }
            if rest.hasPrefix("![cdata[") {
                return delimited(characters, contentStart: index + 8, opening: start, terminator: ["]", "]", ">"], name: "#cdata")
            }
            guard index + 1 < characters.count, characters[index + 1].isASCII, characters[index + 1].isLetter else {
                return nil
            }
            return delimited(characters, contentStart: index + 2, opening: start, terminator: [">"], name: "#declaration")
        }

        if characters[index] == "?" {
            return delimited(characters, contentStart: index + 1, opening: start, terminator: ["?", ">"], name: "#instruction")
        }

        var isClosing = false
        if characters[index] == "/" {
            isClosing = true
            index += 1
        }
        guard index < characters.count, characters[index].isASCII, characters[index].isLetter else { return nil }

        let nameStart = index
        while index < characters.count, characters[index].isASCII,
              characters[index].isLetter || characters[index].isNumber || characters[index] == "-" {
            index += 1
        }
        let name = String(characters[nameStart..<index])

        if isClosing {
            while index < characters.count, characters[index].isWhitespace { index += 1 }
            guard index < characters.count, characters[index] == ">" else { return nil }
            return ParsedTag(text: String(characters[start...index]), name: name, isClosing: true, endIndex: index)
        }

        while index < characters.count {
            var sawWhitespace = false
            while index < characters.count, characters[index].isWhitespace {
                sawWhitespace = true
                index += 1
            }
            guard index < characters.count else { return nil }
            if characters[index] == ">" {
                return ParsedTag(text: String(characters[start...index]), name: name, isClosing: false, endIndex: index)
            }
            if characters[index] == "/" {
                guard index + 1 < characters.count, characters[index + 1] == ">" else { return nil }
                return ParsedTag(text: String(characters[start...index + 1]), name: name, isClosing: false, endIndex: index + 1)
            }
            guard sawWhitespace, isAttributeNameStart(characters[index]) else { return nil }
            index += 1
            while index < characters.count, isAttributeNameCharacter(characters[index]) {
                index += 1
            }
            var lookahead = index
            while lookahead < characters.count, characters[lookahead].isWhitespace {
                lookahead += 1
            }
            guard lookahead < characters.count, characters[lookahead] == "=" else { continue }
            index = lookahead + 1
            while index < characters.count, characters[index].isWhitespace {
                index += 1
            }
            guard index < characters.count else { return nil }
            if characters[index] == "\"" || characters[index] == "'" {
                let quote = characters[index]
                index += 1
                while index < characters.count, characters[index] != quote {
                    index += 1
                }
                guard index < characters.count else { return nil }
                index += 1
            } else {
                let valueStart = index
                while index < characters.count, !characters[index].isWhitespace,
                      !"\"'=<>`".contains(characters[index]) {
                    index += 1
                }
                guard index > valueStart else { return nil }
            }
        }
        return nil
    }

    static func isAttributeNameStart(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character == "_" || character == ":")
    }

    static func isAttributeNameCharacter(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber ||
            character == "_" || character == "." || character == ":" || character == "-")
    }

    private static func delimited(
        _ characters: [Character],
        contentStart: Int,
        opening: Int,
        terminator: [Character],
        name: String
    ) -> ParsedTag? {
        var index = contentStart
        while index + terminator.count <= characters.count {
            if Array(characters[index..<(index + terminator.count)]) == terminator {
                let end = index + terminator.count - 1
                return ParsedTag(text: String(characters[opening...end]), name: name, isClosing: false, endIndex: end)
            }
            index += 1
        }
        return nil
    }
}

nonisolated enum MarkdownHTMLSanitizer {
    static let allowedElements: Set<String> = [
        "a", "abbr", "article", "aside", "b", "bdo", "blockquote", "br", "caption", "center", "cite", "code", "col",
        "colgroup", "dd", "del", "details", "dfn", "div", "dl", "dt", "em", "figcaption", "figure", "footer",
        "h1", "h2", "h3", "h4", "h5", "h6", "header", "hr", "i", "img", "input", "ins", "kbd", "li", "main", "mark",
        "nav", "ol", "p", "pre", "q", "rp", "rt", "ruby", "s", "samp", "section", "small", "span", "strike",
        "strong", "sub", "summary", "sup", "table", "tbody", "td", "tfoot", "th", "thead", "time", "tr", "tt", "u",
        "ul", "var", "wbr"
    ]

    static let contentDroppedElements: Set<String> = ["script", "style"]

    static let userIdentifierPrefix = "user-content-"

    static let globalAttributes: Set<String> = [
        "id", "class", "title", "lang", "dir", "align", "valign", "width", "height", "role"
    ]

    static let elementAttributes: [String: Set<String>] = [
        "a": ["href"],
        "img": ["src", "alt"],
        "td": ["colspan", "rowspan", "scope", "headers", "abbr", "nowrap"],
        "th": ["colspan", "rowspan", "scope", "headers", "abbr", "nowrap"],
        "table": ["border", "cellpadding", "cellspacing", "summary"],
        "col": ["span"],
        "colgroup": ["span"],
        "ol": ["start", "reversed", "type"],
        "li": ["value"],
        "input": ["type", "checked", "disabled"],
        "details": ["open"],
        "time": ["datetime"],
        "ins": ["datetime"],
        "del": ["datetime"]
    ]

    static let linkSchemes: Set<String> = ["http", "https", "mailto"]
    static let imageSchemes: Set<String> = ["http", "https"]

    private struct Attribute {
        let name: String
        let value: String
        let separator: String
        let text: String

        var namespacedText: String {
            separator + "id=\"" + MarkdownHTMLSanitizer.userIdentifierPrefix
                + value.replacingOccurrences(of: "\"", with: "&quot;") + "\""
        }
    }

    static func sanitize(_ html: String) -> String {
        let characters = Array(html)
        var result = ""
        var index = 0
        while index < characters.count {
            let character = characters[index]
            guard character == "<" else {
                result.append(character)
                index += 1
                continue
            }
            guard let tag = MarkdownHTMLTag.parse(characters, at: index) else {
                result += startsMarkup(characters, after: index) ? "&lt;" : "<"
                index += 1
                continue
            }
            let element = tag.name.lowercased()
            if tag.name.hasPrefix("#") {
                result += specialMarkup(tag)
            } else if contentDroppedElements.contains(element) {
                index = tag.isClosing ? tag.endIndex : endOfDroppedElement(characters, opening: tag, element: element)
            } else if allowedElements.contains(element) {
                result += tag.isClosing ? tag.text : sanitizedStartTag(tag, element: element)
            }
            index = max(index, tag.endIndex) + 1
        }
        return result
    }

    private static func startsMarkup(_ characters: [Character], after index: Int) -> Bool {
        guard index + 1 < characters.count else { return false }
        let next = characters[index + 1]
        return (next.isASCII && next.isLetter) || next == "/" || next == "!" || next == "?"
    }

    private static func endOfDroppedElement(
        _ characters: [Character],
        opening: MarkdownHTMLTag.ParsedTag,
        element: String
    ) -> Int {
        if opening.text.hasSuffix("/>") {
            return opening.endIndex
        }
        var search = opening.endIndex + 1
        while search < characters.count {
            if characters[search] == "<",
               let closing = MarkdownHTMLTag.parse(characters, at: search),
               closing.isClosing,
               closing.name.lowercased() == element {
                return closing.endIndex
            }
            search += 1
        }
        return characters.count
    }

    private static func specialMarkup(_ tag: MarkdownHTMLTag.ParsedTag) -> String {
        let text = Array(tag.text)
        switch tag.name {
        case "#comment":
            let body = String(text.dropFirst(4).dropLast(3))
            let isSafe = !body.hasPrefix(">") && !body.hasPrefix("->") && !body.contains("--!>")
            return isSafe ? tag.text : ""
        case "#declaration":
            return tag.text
        default:
            return text.dropLast().contains(">") ? "" : tag.text
        }
    }

    private static func sanitizedStartTag(_ tag: MarkdownHTMLTag.ParsedTag, element: String) -> String {
        let characters = Array(tag.text)
        var index = 1 + tag.name.count
        var kept = String(characters[0..<index])
        var isCheckbox = false
        var tail = ""
        while index < characters.count {
            let whitespaceStart = index
            index = skipWhitespace(in: characters, from: index)
            guard index < characters.count, characters[index] != ">", characters[index] != "/" else {
                tail = String(characters[whitespaceStart...])
                break
            }
            let nameStart = index
            index += 1
            while index < characters.count, MarkdownHTMLTag.isAttributeNameCharacter(characters[index]) {
                index += 1
            }
            let name = String(characters[nameStart..<index]).lowercased()
            let value = attributeValue(in: characters, index: &index)
            let attribute = Attribute(
                name: name,
                value: value,
                separator: String(characters[whitespaceStart..<nameStart]),
                text: String(characters[whitespaceStart..<index])
            )
            guard isAllowed(attribute, on: element) else { continue }
            if name == "type", value.lowercased() == "checkbox" {
                isCheckbox = true
            }
            kept += name == "id" ? attribute.namespacedText : attribute.text
        }
        if element == "input", !isCheckbox {
            return ""
        }
        return kept + tail
    }

    private static func skipWhitespace(in characters: [Character], from start: Int) -> Int {
        var index = start
        while index < characters.count, characters[index].isWhitespace {
            index += 1
        }
        return index
    }

    private static func attributeValue(in characters: [Character], index: inout Int) -> String {
        let lookahead = skipWhitespace(in: characters, from: index)
        guard lookahead < characters.count, characters[lookahead] == "=" else { return "" }
        index = skipWhitespace(in: characters, from: lookahead + 1)
        if index < characters.count, characters[index] == "\"" || characters[index] == "'" {
            let quote = characters[index]
            index += 1
            let valueStart = index
            while index < characters.count, characters[index] != quote {
                index += 1
            }
            let value = String(characters[valueStart..<index])
            index = min(index + 1, characters.count)
            return value
        }
        let valueStart = index
        while index < characters.count, !characters[index].isWhitespace, characters[index] != ">" {
            index += 1
        }
        return String(characters[valueStart..<index])
    }

    private static func isAllowed(_ attribute: Attribute, on element: String) -> Bool {
        if attribute.name.hasPrefix("aria-") {
            return true
        }
        guard globalAttributes.contains(attribute.name) || elementAttributes[element]?.contains(attribute.name) == true
        else { return false }
        switch (element, attribute.name) {
        case ("a", "href"):
            return isSafeURL(attribute.value, schemes: linkSchemes, allowsInlineImages: false)
        case ("img", "src"):
            return isSafeURL(attribute.value, schemes: imageSchemes, allowsInlineImages: true)
        default:
            return true
        }
    }

    static func isSafeURL(_ value: String, schemes: Set<String>, allowsInlineImages: Bool) -> Bool {
        let compact = String(
            decodingEntities(value).unicodeScalars
                .filter { $0.value > 0x20 && $0.value != 0x7F }
                .map(Character.init)
        )
        let prefix = compact.prefix { !"/?#".contains($0) }
        guard !prefix.contains("&") else { return false }
        guard let colon = prefix.firstIndex(of: ":") else { return true }
        let scheme = prefix[..<colon].lowercased()
        if schemes.contains(scheme) {
            return true
        }
        return allowsInlineImages && scheme == "data" && compact.lowercased().hasPrefix("data:image/")
    }

    private static func decodingEntities(_ value: String) -> String {
        let characters = Array(value)
        var result = ""
        var index = 0
        while index < characters.count {
            if characters[index] == "&", let entity = MarkdownHTMLEntities.decode(characters, at: index) {
                result += entity.text
                index = entity.end
            } else {
                result.append(characters[index])
                index += 1
            }
        }
        return result
    }
}
