import Foundation

nonisolated struct MarkdownSourceLine: Equatable, Sendable {
    var text: String
    var offset: Int

    var end: Int { offset + text.utf16.count }

    var contentEnd: Int {
        var length = text.utf16.count
        for unit in text.utf16.reversed() {
            guard unit == 32 || unit == 9 else { break }
            length -= 1
        }
        return offset + length
    }

    func suffix(_ remaining: String) -> MarkdownSourceLine {
        MarkdownSourceLine(text: remaining, offset: end - remaining.utf16.count)
    }

    static func split(_ markdown: String) -> [MarkdownSourceLine] {
        let units = Array(markdown.utf16)
        var lines: [MarkdownSourceLine] = []
        var lineStart = 0
        var cursor = 0
        while cursor < units.count {
            let unit = units[cursor]
            guard unit == 10 || unit == 13 else {
                cursor += 1
                continue
            }
            lines.append(line(units, from: lineStart, to: cursor))
            if unit == 13, cursor + 1 < units.count, units[cursor + 1] == 10 {
                cursor += 1
            }
            cursor += 1
            lineStart = cursor
        }
        lines.append(line(units, from: lineStart, to: units.count))
        return lines
    }

    private static func line(_ units: [UInt16], from start: Int, to end: Int) -> MarkdownSourceLine {
        MarkdownSourceLine(text: String(decoding: units[start..<end], as: UTF16.self), offset: start)
    }
}

nonisolated enum MarkdownLinkReferences {
    static func collect(_ lines: [MarkdownSourceLine]) -> [String: MarkdownLinkReference] {
        var references: [String: MarkdownLinkReference] = [:]
        var fence: (character: Character, length: Int)?
        var atBlockStart = true

        for line in lines {
            if let open = fence {
                if MarkdownBlockRenderer.isFenceClosing(line.text, character: open.character, length: open.length) {
                    fence = nil
                    atBlockStart = true
                }
                continue
            }

            let stripped = strippingContainers(line.text)
            if MarkdownBlockRenderer.isBlank(stripped) {
                atBlockStart = true
                continue
            }
            if let opening = MarkdownBlockRenderer.fenceOpening(stripped) {
                fence = (opening.character, opening.length)
                continue
            }
            if atBlockStart, let definition = parseDefinition(stripped) {
                let key = MarkdownInlineRenderer.normalizedReferenceLabel(definition.label)
                if references[key] == nil {
                    references[key] = definition.reference
                }
                continue
            }
            atBlockStart = MarkdownBlockRenderer.atxHeading(stripped) != nil
                || MarkdownBlockRenderer.isThematicBreak(stripped)
        }
        return references
    }

    static func strippingContainers(_ line: String) -> String {
        var current = Substring(line)
        while true {
            let trimmed = current.drop(while: { $0 == " " })
            if trimmed.first == ">" {
                current = trimmed.dropFirst()
                continue
            }
            if let marker = MarkdownBlockRenderer.listMarker(String(trimmed)) {
                let content = String(trimmed.dropFirst(marker.markerLength + marker.spacing))
                if content.isEmpty { return "" }
                current = Substring(content)
                continue
            }
            return String(trimmed)
        }
    }

    static func parseDefinition(_ line: String) -> (label: String, reference: MarkdownLinkReference)? {
        let characters = Array(line)
        var index = 0
        while index < characters.count, characters[index] == " " {
            index += 1
        }
        guard index <= 3, index < characters.count, characters[index] == "[" else { return nil }
        index += 1

        var label = ""
        var isClosed = false
        while index < characters.count {
            let character = characters[index]
            if character == "\\", index + 1 < characters.count {
                label.append(character)
                label.append(characters[index + 1])
                index += 2
                continue
            }
            if character == "[" { return nil }
            if character == "]" {
                isClosed = true
                index += 1
                break
            }
            label.append(character)
            index += 1
        }
        guard isClosed, index < characters.count, characters[index] == ":" else { return nil }
        guard !label.allSatisfy({ $0.isWhitespace }) else { return nil }
        index += 1
        skipBlanks(characters, &index)

        var destination = ""
        if index < characters.count, characters[index] == "<" {
            index += 1
            var isDestinationClosed = false
            while index < characters.count {
                if characters[index] == ">" {
                    isDestinationClosed = true
                    index += 1
                    break
                }
                if characters[index] == "<" { return nil }
                destination.append(characters[index])
                index += 1
            }
            guard isDestinationClosed else { return nil }
        } else {
            while index < characters.count, !characters[index].isWhitespace {
                destination.append(characters[index])
                index += 1
            }
            guard !destination.isEmpty else { return nil }
        }

        let hasSpaceBeforeTitle = index < characters.count && characters[index].isWhitespace
        skipBlanks(characters, &index)

        var title: String?
        if index < characters.count {
            guard hasSpaceBeforeTitle else { return nil }
            let opener = characters[index]
            guard opener == "\"" || opener == "'" || opener == "(" else { return nil }
            let closer: Character = opener == "(" ? ")" : opener
            index += 1
            var collected = ""
            var isTitleClosed = false
            while index < characters.count {
                let character = characters[index]
                if character == "\\", index + 1 < characters.count {
                    collected.append(character)
                    collected.append(characters[index + 1])
                    index += 2
                    continue
                }
                if character == closer {
                    isTitleClosed = true
                    index += 1
                    break
                }
                collected.append(character)
                index += 1
            }
            guard isTitleClosed else { return nil }
            skipBlanks(characters, &index)
            guard index == characters.count else { return nil }
            title = MarkdownInlineRenderer.unescapeLiteral(collected)
        }

        let reference = MarkdownLinkReference(
            destination: MarkdownInlineRenderer.unescapeLiteral(destination),
            title: title
        )
        return (label, reference)
    }

    private static func skipBlanks(_ characters: [Character], _ index: inout Int) {
        while index < characters.count, characters[index] == " " || characters[index] == "\t" {
            index += 1
        }
    }
}

nonisolated final class MarkdownRenderContext {
    let references: [String: MarkdownLinkReference]
    let includesSourcePositions: Bool
    private var headingOccurrences: [String: Int] = [:]

    init(references: [String: MarkdownLinkReference], includesSourcePositions: Bool) {
        self.references = references
        self.includesSourcePositions = includesSourcePositions
    }

    var inline: MarkdownInlineContext {
        MarkdownInlineContext(references: references)
    }

    func positionAttribute(from: Int, to: Int) -> String {
        guard includesSourcePositions else { return "" }
        return " md-src-pos=\"\(from)..\(to)\""
    }

    func headingAttributes(content: String, from: Int, to: Int) -> String {
        var attributes = ""
        if let anchor = MarkdownHeaderAnchor.rawAnchor(forHeaderContent: content) {
            let occurrence = headingOccurrences[anchor, default: 0]
            headingOccurrences[anchor] = occurrence + 1
            let identifier = occurrence == 0 ? anchor : "\(anchor)-\(occurrence)"
            attributes += " id=\"\(MarkdownInlineRenderer.escape(identifier))\""
        }
        return attributes + positionAttribute(from: from, to: to)
    }
}
