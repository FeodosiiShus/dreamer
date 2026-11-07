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
    static func sanitize(_ html: String) -> String {
        removingEventHandlers(removingScriptElements(html))
    }

    static func removingScriptElements(_ html: String) -> String {
        let characters = Array(html)
        var result = ""
        var index = 0
        while index < characters.count {
            guard characters[index] == "<",
                  let tag = MarkdownHTMLTag.parse(characters, at: index),
                  !tag.isClosing,
                  tag.name.lowercased() == "script" else {
                result.append(characters[index])
                index += 1
                continue
            }
            if tag.text.hasSuffix("/>") {
                index = tag.endIndex + 1
                continue
            }
            var search = tag.endIndex + 1
            var closingEnd: Int?
            while search < characters.count {
                if characters[search] == "<",
                   let closing = MarkdownHTMLTag.parse(characters, at: search),
                   closing.isClosing,
                   closing.name.lowercased() == "script" {
                    closingEnd = closing.endIndex
                    break
                }
                search += 1
            }
            index = closingEnd.map { $0 + 1 } ?? characters.count
        }
        return result
    }

    static func removingEventHandlers(_ html: String) -> String {
        let characters = Array(html)
        var result = ""
        var index = 0
        while index < characters.count {
            guard characters[index] == "<",
                  let tag = MarkdownHTMLTag.parse(characters, at: index) else {
                result.append(characters[index])
                index += 1
                continue
            }
            result += strippingEventHandlers(from: tag.text)
            index = tag.endIndex + 1
        }
        return result
    }

    static func strippingEventHandlers(from tag: String) -> String {
        let characters = Array(tag)
        var index = 1
        if index < characters.count, characters[index] == "/" {
            index += 1
        }
        guard index < characters.count, MarkdownHTMLTag.isAttributeNameStart(characters[index]) else {
            return tag
        }
        while index < characters.count, MarkdownHTMLTag.isAttributeNameCharacter(characters[index]) {
            index += 1
        }

        var result = String(characters[0..<index])
        while index < characters.count {
            let whitespaceStart = index
            while index < characters.count, characters[index].isWhitespace {
                index += 1
            }
            guard index < characters.count else {
                result += String(characters[whitespaceStart...])
                break
            }
            if characters[index] == ">" || characters[index] == "/" {
                result += String(characters[whitespaceStart...])
                break
            }

            let nameStart = index
            while index < characters.count, MarkdownHTMLTag.isAttributeNameCharacter(characters[index]) {
                index += 1
            }
            guard index > nameStart else {
                result += String(characters[whitespaceStart...])
                break
            }
            let name = String(characters[nameStart..<index]).lowercased()
            while index < characters.count, characters[index].isWhitespace {
                index += 1
            }
            if index < characters.count, characters[index] == "=" {
                index += 1
                while index < characters.count, characters[index].isWhitespace {
                    index += 1
                }
                if index < characters.count, characters[index] == "\"" || characters[index] == "'" {
                    let quote = characters[index]
                    index += 1
                    while index < characters.count, characters[index] != quote {
                        index += 1
                    }
                    if index < characters.count {
                        index += 1
                    }
                } else {
                    while index < characters.count, !characters[index].isWhitespace, characters[index] != ">" {
                        index += 1
                    }
                }
            }

            if name.hasPrefix("on") {
                continue
            }
            result += String(characters[whitespaceStart..<index])
        }
        return result
    }
}
