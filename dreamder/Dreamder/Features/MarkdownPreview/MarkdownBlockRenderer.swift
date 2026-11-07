import Foundation

nonisolated enum MarkdownBlockRenderer {
    enum TableAlignment {
        case none
        case left
        case center
        case right
    }

    struct ParsedBlock {
        let html: String
        let next: Int
    }

    struct ListMarker {
        let ordered: Bool
        let number: Int
        let indent: Int
        let markerLength: Int
        let spacing: Int

        var contentIndent: Int { indent + markerLength + spacing }
    }

    private struct Fence {
        let character: Character
        let length: Int
        let info: String
    }

    static func render(_ markdown: String) -> String {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return renderBlocks(normalized.components(separatedBy: "\n"))
    }

    static func renderBlocks(_ lines: [String]) -> String {
        var blocks: [String] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            if isBlank(line) {
                index += 1
                continue
            }

            if let fence = fenceOpening(line) {
                var code: [String] = []
                index += 1
                while index < lines.count, !isFenceClosing(lines[index], fence: fence) {
                    code.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                blocks.append(codeBlock(code.joined(separator: "\n"), info: fence.info))
                continue
            }

            if let heading = atxHeading(line) {
                blocks.append("<h\(heading.level)>\(MarkdownInlineRenderer.render(heading.text))</h\(heading.level)>")
                index += 1
                continue
            }

            if isThematicBreak(line) {
                blocks.append("<hr />")
                index += 1
                continue
            }

            if blockQuoteContent(line) != nil {
                var quoteLines: [String] = []
                while index < lines.count {
                    if let content = blockQuoteContent(lines[index]) {
                        quoteLines.append(content)
                        index += 1
                    } else if isBlank(lines[index]),
                              index + 1 < lines.count,
                              blockQuoteContent(lines[index + 1]) != nil {
                        quoteLines.append("")
                        index += 1
                    } else {
                        break
                    }
                }
                blocks.append("<blockquote>\n\(renderBlocks(quoteLines))\n</blockquote>")
                continue
            }

            if isIndentedCode(line) {
                var code: [String] = []
                while index < lines.count, isIndentedCode(lines[index]) || isBlank(lines[index]) {
                    code.append(isIndentedCode(lines[index]) ? String(strippingCodeIndent(lines[index])) : "")
                    index += 1
                }
                while let last = code.last, last.isEmpty {
                    code.removeLast()
                }
                blocks.append("<pre><code>\(MarkdownInlineRenderer.escape(code.joined(separator: "\n")))\n</code></pre>")
                continue
            }

            if let kind = htmlBlockKind(line) {
                var blockLines: [String] = []
                while index < lines.count {
                    let current = lines[index]
                    if kind >= 6, isBlank(current) {
                        break
                    }
                    blockLines.append(current)
                    index += 1
                    if kind < 6, htmlBlockEnds(kind: kind, line: current) {
                        break
                    }
                }
                let html = MarkdownHTMLSanitizer.sanitize(blockLines.joined(separator: "\n"))
                if !html.isEmpty {
                    blocks.append(html)
                }
                continue
            }

            if let table = parseTable(lines, start: index) {
                blocks.append(table.html)
                index = table.next
                continue
            }

            if listMarker(line) != nil {
                let list = parseList(lines, start: index)
                blocks.append(list.html)
                index = list.next
                continue
            }

            let paragraph = parseParagraph(lines, start: index)
            blocks.append(paragraph.html)
            index = paragraph.next
        }

        return blocks.joined(separator: "\n")
    }

    static func atxHeading(_ line: String) -> (level: Int, text: String)? {
        let characters = Array(line)
        var index = 0
        while index < characters.count, characters[index] == " " {
            index += 1
        }
        guard index <= 3, index < characters.count else { return nil }

        var level = 0
        while index < characters.count, characters[index] == "#" {
            level += 1
            index += 1
        }
        guard (1...6).contains(level) else { return nil }
        guard index >= characters.count || characters[index] == " " || characters[index] == "\t" else { return nil }

        var content = String(characters[index...]).trimmingCharacters(in: .whitespaces)
        var trailingHashes = 0
        while let last = content.last, last == "#" {
            content.removeLast()
            trailingHashes += 1
        }
        if trailingHashes > 0 {
            if content.isEmpty {
                content = ""
            } else if let last = content.last, last == " " || last == "\t" {
                content = content.trimmingCharacters(in: .whitespaces)
            } else {
                content += String(repeating: "#", count: trailingHashes)
            }
        }
        return (level, content)
    }

    static func isThematicBreak(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let marker = trimmed.first, marker == "*" || marker == "-" || marker == "_" else { return false }
        var count = 0
        for character in trimmed {
            if character == marker {
                count += 1
            } else if character != " " && character != "\t" {
                return false
            }
        }
        return count >= 3
    }

    static func listMarker(_ line: String) -> ListMarker? {
        guard !isThematicBreak(line) else { return nil }
        let characters = Array(line)
        var index = 0
        while index < characters.count, characters[index] == " " {
            index += 1
        }
        let indent = index
        guard indent <= 3, index < characters.count else { return nil }

        let markerStart = index
        var ordered = false
        var number = 0

        if characters[index].isNumber {
            var digits = 0
            while index < characters.count, characters[index].isNumber, digits < 9 {
                number = number * 10 + (Int(String(characters[index])) ?? 0)
                index += 1
                digits += 1
            }
            guard index < characters.count, characters[index] == "." || characters[index] == ")" else { return nil }
            index += 1
            ordered = true
        } else if characters[index] == "-" || characters[index] == "+" || characters[index] == "*" {
            index += 1
        } else {
            return nil
        }

        let markerLength = index - markerStart
        var spacing = 0
        while index < characters.count, characters[index] == " " {
            spacing += 1
            index += 1
        }
        guard spacing > 0 || index >= characters.count else { return nil }
        if spacing > 4 {
            spacing = 1
        }
        return ListMarker(ordered: ordered, number: number, indent: indent, markerLength: markerLength, spacing: spacing)
    }

    private static func parseList(_ lines: [String], start: Int) -> ParsedBlock {
        guard let firstMarker = listMarker(lines[start]) else {
            return ParsedBlock(html: MarkdownInlineRenderer.render(lines[start]), next: start + 1)
        }

        var items: [[String]] = []
        var loose = false
        var index = start

        while index < lines.count {
            guard let marker = listMarker(lines[index]), marker.ordered == firstMarker.ordered else { break }

            var itemLines: [String] = [itemContent(lines[index], marker: marker)]
            var hasBlankInside = false
            var pendingBlanks = 0
            var cursor = index + 1

            while cursor < lines.count {
                let line = lines[cursor]
                if isBlank(line) {
                    pendingBlanks += 1
                    cursor += 1
                    continue
                }
                if indentation(line) >= marker.contentIndent {
                    if pendingBlanks > 0 {
                        itemLines.append(contentsOf: Array(repeating: "", count: pendingBlanks))
                        hasBlankInside = true
                        pendingBlanks = 0
                    }
                    itemLines.append(String(line.dropFirst(marker.contentIndent)))
                    cursor += 1
                    continue
                }
                if pendingBlanks > 0 {
                    break
                }
                if listMarker(line) != nil || startsBlock(line) {
                    break
                }
                itemLines.append(line.trimmingCharacters(in: .whitespaces))
                cursor += 1
            }

            if hasBlankInside {
                loose = true
            }
            if pendingBlanks > 0, cursor < lines.count,
               let nextMarker = listMarker(lines[cursor]),
               nextMarker.ordered == firstMarker.ordered {
                loose = true
            }
            items.append(itemLines)
            index = cursor
        }

        let tag = firstMarker.ordered ? "ol" : "ul"
        var html = "<\(tag)"
        if firstMarker.ordered, firstMarker.number != 1 {
            html += " start=\"\(firstMarker.number)\""
        }
        html += ">\n"

        for itemLines in items {
            var lines = itemLines
            var task: (checked: Bool, remaining: String)?
            if let first = lines.first, let parsed = taskMarker(first) {
                task = parsed
                lines[0] = parsed.remaining
            }

            var inner = renderBlocks(lines)
            if !loose {
                inner = unwrappingParagraphs(inner)
            }
            if let task {
                inner = "<input type=\"checkbox\" disabled\(task.checked ? " checked" : "")> " + inner
            }
            html += "<li>\(inner)</li>\n"
        }

        html += "</\(tag)>"
        return ParsedBlock(html: html, next: index)
    }

    private static func parseParagraph(_ lines: [String], start: Int) -> ParsedBlock {
        var textLines: [String] = []
        var index = start

        while index < lines.count {
            let line = lines[index]
            if isBlank(line) { break }
            if !textLines.isEmpty {
                if let level = setextLevel(line) {
                    let content = textLines.joined(separator: "\n").trimmingCharacters(in: .whitespaces)
                    return ParsedBlock(
                        html: "<h\(level)>\(MarkdownInlineRenderer.render(content))</h\(level)>",
                        next: index + 1
                    )
                }
                if startsBlock(line) { break }
            }
            textLines.append(String(line.drop(while: { $0 == " " })))
            index += 1
        }

        let content = textLines.joined(separator: "\n")
        return ParsedBlock(html: "<p>\(MarkdownInlineRenderer.render(content))</p>", next: index)
    }

    private static func parseTable(_ lines: [String], start: Int) -> ParsedBlock? {
        guard start + 1 < lines.count else { return nil }
        let headerLine = lines[start]
        guard headerLine.contains("|") else { return nil }
        guard let alignments = delimiterRow(lines[start + 1]) else { return nil }
        let headerCells = splitTableRow(headerLine)
        guard headerCells.count == alignments.count else { return nil }

        var html = "<table>\n<thead>\n<tr>\n"
        for (column, cell) in headerCells.enumerated() {
            html += "<th\(alignmentAttribute(alignments[column]))>\(MarkdownInlineRenderer.render(cell))</th>\n"
        }
        html += "</tr>\n</thead>\n"

        var rows: [String] = []
        var index = start + 2
        while index < lines.count {
            let line = lines[index]
            if isBlank(line) || !line.contains("|") { break }
            let cells = splitTableRow(line)
            var row = "<tr>\n"
            for column in 0..<alignments.count {
                let value = column < cells.count ? cells[column] : ""
                row += "<td\(alignmentAttribute(alignments[column]))>\(MarkdownInlineRenderer.render(value))</td>\n"
            }
            row += "</tr>"
            rows.append(row)
            index += 1
        }

        if !rows.isEmpty {
            html += "<tbody>\n\(rows.joined(separator: "\n"))\n</tbody>\n"
        }
        html += "</table>"
        return ParsedBlock(html: html, next: index)
    }

    static func splitTableRow(_ line: String) -> [String] {
        var characters = Array(line.trimmingCharacters(in: .whitespaces))
        if characters.first == "|" { characters.removeFirst() }
        if characters.last == "|" { characters.removeLast() }

        var cells: [String] = []
        var current = ""
        var escaped = false
        for character in characters {
            if escaped {
                current.append(character)
                escaped = false
                continue
            }
            if character == "\\" {
                current.append(character)
                escaped = true
                continue
            }
            if character == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
                continue
            }
            current.append(character)
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private static func delimiterRow(_ line: String) -> [TableAlignment]? {
        guard line.contains("-") else { return nil }
        let cells = splitTableRow(line)
        guard !cells.isEmpty else { return nil }

        var alignments: [TableAlignment] = []
        for cell in cells {
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            let startsWithColon = trimmed.hasPrefix(":")
            let endsWithColon = trimmed.count > 1 && trimmed.hasSuffix(":")
            let core = trimmed.dropFirst(startsWithColon ? 1 : 0).dropLast(endsWithColon ? 1 : 0)
            guard !core.isEmpty, core.allSatisfy({ $0 == "-" }) else { return nil }
            switch (startsWithColon, endsWithColon) {
            case (true, true): alignments.append(.center)
            case (true, false): alignments.append(.left)
            case (false, true): alignments.append(.right)
            case (false, false): alignments.append(.none)
            }
        }
        return alignments
    }

    private static func alignmentAttribute(_ alignment: TableAlignment) -> String {
        switch alignment {
        case .none: return ""
        case .left: return " style=\"text-align: left\""
        case .center: return " style=\"text-align: center\""
        case .right: return " style=\"text-align: right\""
        }
    }

    private static func taskMarker(_ line: String) -> (checked: Bool, remaining: String)? {
        let characters = Array(line)
        guard characters.count >= 3, characters[0] == "[", characters[2] == "]" else { return nil }
        let mark = characters[1]
        guard mark == " " || mark == "x" || mark == "X" else { return nil }
        guard characters.count == 3 || characters[3] == " " else { return nil }
        return (mark != " ", String(characters.dropFirst(3)).trimmingCharacters(in: .whitespaces))
    }

    private static func unwrappingParagraphs(_ html: String) -> String {
        guard html.hasPrefix("<p>") else { return html }
        var result = String(html.dropFirst(3))
        for block in ["<ul", "<ol", "<pre", "<blockquote", "<table", "<hr"] {
            result = result.replacingOccurrences(of: "</p>\n\(block)", with: block)
        }
        if result.hasSuffix("</p>") {
            result = String(result.dropLast(4))
        }
        return result
    }

    private static func itemContent(_ line: String, marker: ListMarker) -> String {
        let characters = Array(line)
        var index = marker.indent + marker.markerLength
        while index < characters.count, characters[index] == " " {
            index += 1
        }
        guard index < characters.count else { return "" }
        return String(characters[index...])
    }

    private static func setextLevel(_ line: String) -> Int? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.allSatisfy({ $0 == "=" }) { return 1 }
        if trimmed.allSatisfy({ $0 == "-" }) { return 2 }
        return nil
    }

    static func startsBlock(_ line: String) -> Bool {
        if fenceOpening(line) != nil { return true }
        if atxHeading(line) != nil { return true }
        if isThematicBreak(line) { return true }
        if blockQuoteContent(line) != nil { return true }
        if listMarker(line) != nil { return true }
        if isIndentedCode(line) { return true }
        if let kind = htmlBlockKind(line), kind != 7 { return true }
        return false
    }

    static let htmlBlockTagNames: Set<String> = [
        "address", "article", "aside", "base", "basefont", "blockquote", "body", "caption", "center",
        "col", "colgroup", "dd", "details", "dialog", "dir", "div", "dl", "dt", "fieldset", "figcaption",
        "figure", "footer", "form", "frame", "frameset", "h1", "h2", "h3", "h4", "h5", "h6", "head",
        "header", "hr", "html", "iframe", "img", "legend", "li", "link", "main", "menu", "menuitem",
        "nav", "noframes", "ol", "optgroup", "option", "p", "param", "section", "source", "summary",
        "table", "tbody", "td", "tfoot", "th", "thead", "title", "tr", "track", "ul"
    ]

    static func htmlBlockKind(_ line: String) -> Int? {
        let characters = Array(line)
        var index = 0
        while index < characters.count, index < 4, characters[index] == " " {
            index += 1
        }
        guard index <= 3, index < characters.count, characters[index] == "<" else { return nil }

        let lower = String(characters[index...]).lowercased()
        if lower.hasPrefix("<!--") { return 2 }
        if lower.hasPrefix("<?") { return 3 }
        if lower.hasPrefix("<![cdata[") { return 5 }
        if lower.hasPrefix("<!") {
            guard index + 2 < characters.count else { return nil }
            let first = characters[index + 2]
            return first.isASCII && first.isLetter ? 4 : nil
        }

        for name in ["script", "pre", "style", "textarea"] where lower.hasPrefix("<" + name) {
            let remainder = lower.dropFirst(name.count + 1)
            if remainder.isEmpty || remainder.first == ">" || remainder.first?.isWhitespace == true {
                return 1
            }
        }

        guard let tag = MarkdownHTMLTag.parse(characters, at: index) else { return nil }
        if htmlBlockTagNames.contains(tag.name.lowercased()) { return 6 }
        if onlyWhitespaceRemains(characters, after: tag.endIndex + 1) { return 7 }
        return nil
    }

    private static func htmlBlockEnds(kind: Int, line: String) -> Bool {
        let lower = line.lowercased()
        switch kind {
        case 1:
            return lower.contains("</script>") || lower.contains("</pre>")
                || lower.contains("</style>") || lower.contains("</textarea>")
        case 2: return lower.contains("-->")
        case 3: return lower.contains("?>")
        case 4: return lower.contains(">")
        case 5: return lower.contains("]]>")
        default: return false
        }
    }

    private static func onlyWhitespaceRemains(_ characters: [Character], after index: Int) -> Bool {
        var cursor = index
        while cursor < characters.count {
            if !characters[cursor].isWhitespace { return false }
            cursor += 1
        }
        return true
    }

    static func blockQuoteContent(_ line: String) -> String? {
        let characters = Array(line)
        var index = 0
        while index < characters.count, index < 4, characters[index] == " " {
            index += 1
        }
        guard index < characters.count, characters[index] == ">" else { return nil }
        index += 1
        if index < characters.count, characters[index] == " " {
            index += 1
        }
        guard index < characters.count else { return "" }
        return String(characters[index...])
    }

    static func indentation(_ line: String) -> Int {
        var count = 0
        for character in line {
            if character == " " {
                count += 1
            } else if character == "\t" {
                count += 4
            } else {
                break
            }
        }
        return count
    }

    static func isIndentedCode(_ line: String) -> Bool {
        line.hasPrefix("    ") || line.hasPrefix("\t")
    }

    private static func strippingCodeIndent(_ line: String) -> Substring {
        if line.hasPrefix("\t") {
            return line.dropFirst()
        }
        return line.dropFirst(4)
    }

    static func isBlank(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func fenceOpening(_ line: String) -> Fence? {
        let characters = Array(line)
        var index = 0
        while index < characters.count, characters[index] == " " {
            index += 1
        }
        guard index <= 3, index < characters.count else { return nil }
        let marker = characters[index]
        guard marker == "`" || marker == "~" else { return nil }

        var length = 0
        while index < characters.count, characters[index] == marker {
            length += 1
            index += 1
        }
        guard length >= 3 else { return nil }

        let info = String(characters[index...]).trimmingCharacters(in: .whitespaces)
        if marker == "`", info.contains("`") { return nil }
        return Fence(character: marker, length: length, info: info)
    }

    private static func isFenceClosing(_ line: String, fence: Fence) -> Bool {
        let characters = Array(line)
        var index = 0
        while index < characters.count, characters[index] == " " {
            index += 1
        }
        guard index <= 3 else { return false }

        var length = 0
        while index < characters.count, characters[index] == fence.character {
            length += 1
            index += 1
        }
        guard length >= fence.length else { return false }
        guard index >= characters.count else {
            return String(characters[index...]).trimmingCharacters(in: .whitespaces).isEmpty
        }
        return true
    }

    private static func codeBlock(_ code: String, info: String) -> String {
        let language = info.split(separator: " ").first.map(String.init) ?? ""
        let escapedCode = MarkdownInlineRenderer.escape(code)
        guard !language.isEmpty else {
            return "<pre><code>\(escapedCode)\n</code></pre>"
        }
        return "<pre><code class=\"language-\(MarkdownInlineRenderer.escape(language))\">\(escapedCode)\n</code></pre>"
    }
}
