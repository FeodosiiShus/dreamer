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

    struct Fence {
        let character: Character
        let length: Int
        let info: String
        let indent: Int
    }

    private struct TaskItem {
        let isChecked: Bool
        let line: MarkdownSourceLine
    }

    static func render(_ markdown: String, includesSourcePositions: Bool = true) -> String {
        let lines = MarkdownSourceLine.split(markdown)
        let context = MarkdownRenderContext(
            references: MarkdownLinkReferences.collect(lines),
            includesSourcePositions: includesSourcePositions
        )
        return renderBlocks(lines, context: context)
    }

    static func renderBlocks(_ lines: [MarkdownSourceLine], context: MarkdownRenderContext) -> String {
        var blocks: [String] = []
        var index = 0

        while index < lines.count {
            let source = lines[index]
            let line = source.text
            if isBlank(line) {
                index += 1
                continue
            }

            if let fence = fenceOpening(line) {
                var code: [String] = []
                let start = source.offset + fence.indent
                var end = source.contentEnd
                index += 1
                while index < lines.count {
                    end = lines[index].contentEnd
                    if isFenceClosing(lines[index].text, fence: fence) {
                        index += 1
                        break
                    }
                    code.append(lines[index].text)
                    index += 1
                }
                let position = context.positionAttribute(from: start, to: end)
                blocks.append(codeBlock(code.joined(separator: "\n"), info: fence.info, position: position))
                continue
            }

            if let heading = atxHeading(line) {
                let start = source.offset + leadingSpaces(line)
                let attributes = context.headingAttributes(content: heading.text, from: start, to: source.contentEnd)
                let content = MarkdownInlineRenderer.render(heading.text, context: context.inline)
                blocks.append("<h\(heading.level)\(attributes)>\(content)</h\(heading.level)>")
                index += 1
                continue
            }

            if isThematicBreak(line) {
                let start = source.offset + leadingSpaces(line)
                blocks.append("<hr\(context.positionAttribute(from: start, to: source.contentEnd)) />")
                index += 1
                continue
            }

            if blockQuoteContent(line) != nil {
                var quoteLines: [MarkdownSourceLine] = []
                let start = source.offset + leadingSpaces(line)
                var end = source.contentEnd
                while index < lines.count {
                    if let content = blockQuoteContent(lines[index].text) {
                        quoteLines.append(lines[index].suffix(content))
                        end = lines[index].contentEnd
                        index += 1
                    } else if isBlank(lines[index].text),
                              index + 1 < lines.count,
                              blockQuoteContent(lines[index + 1].text) != nil {
                        quoteLines.append(MarkdownSourceLine(text: "", offset: lines[index].offset))
                        index += 1
                    } else {
                        break
                    }
                }
                let position = context.positionAttribute(from: start, to: end)
                let inner = renderBlocks(quoteLines, context: context)
                let body = inner.isEmpty ? "" : "\(inner)\n"
                blocks.append("<blockquote\(position)>\n\(body)</blockquote>")
                continue
            }

            if isIndentedCode(line) {
                var code: [String] = []
                let start = source.offset
                var end = source.contentEnd
                while index < lines.count, isIndentedCode(lines[index].text) || isBlank(lines[index].text) {
                    let current = lines[index]
                    if isIndentedCode(current.text) {
                        code.append(String(strippingCodeIndent(current.text)))
                        end = current.contentEnd
                    } else {
                        code.append("")
                    }
                    index += 1
                }
                while let last = code.last, last.isEmpty {
                    code.removeLast()
                }
                let escaped = MarkdownInlineRenderer.escape(code.joined(separator: "\n"))
                let position = context.positionAttribute(from: start, to: end)
                blocks.append("<pre\(position)><code>\(escaped)\n</code></pre>")
                continue
            }

            if let kind = htmlBlockKind(line) {
                var blockLines: [String] = []
                while index < lines.count {
                    let current = lines[index].text
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

            if let table = parseTable(lines, start: index, context: context) {
                blocks.append(table.html)
                index = table.next
                continue
            }

            if let marker = listMarker(line) {
                let list = parseList(lines, start: index, firstMarker: marker, context: context)
                blocks.append(list.html)
                index = list.next
                continue
            }

            let paragraph = parseParagraph(lines, start: index, context: context)
            if !paragraph.html.isEmpty {
                blocks.append(paragraph.html)
            }
            index = paragraph.next
        }

        return blocks.joined(separator: "\n")
    }

    static func leadingSpaces(_ line: String) -> Int {
        var count = 0
        for character in line {
            guard character == " " else { break }
            count += 1
        }
        return count
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
        while index < characters.count, characters[index] == " " || characters[index] == "\t" {
            spacing += 1
            index += 1
        }
        guard spacing > 0 || index >= characters.count else { return nil }
        if spacing > 4 {
            spacing = 1
        }
        return ListMarker(ordered: ordered, number: number, indent: indent, markerLength: markerLength, spacing: spacing)
    }

    private static func parseList(
        _ lines: [MarkdownSourceLine],
        start: Int,
        firstMarker: ListMarker,
        context: MarkdownRenderContext
    ) -> ParsedBlock {
        struct Item {
            var lines: [MarkdownSourceLine]
            let start: Int
            var end: Int
        }

        var items: [Item] = []
        var listEnd = lines[start].contentEnd
        var loose = false
        var index = start

        while index < lines.count {
            guard let marker = listMarker(lines[index].text), marker.ordered == firstMarker.ordered else { break }

            let first = lines[index]
            let firstContent = itemContent(first, marker: marker)
            var item = Item(lines: [firstContent], start: first.offset + marker.indent, end: first.contentEnd)
            var hasBlankInside = false
            var pendingBlanks: [MarkdownSourceLine] = []
            var cursor = index + 1

            while cursor < lines.count {
                let current = lines[cursor]
                if isBlank(current.text) {
                    pendingBlanks.append(MarkdownSourceLine(text: "", offset: current.offset))
                    cursor += 1
                    continue
                }
                if indentation(current.text) >= marker.contentIndent {
                    if !pendingBlanks.isEmpty {
                        item.lines.append(contentsOf: pendingBlanks)
                        hasBlankInside = true
                        pendingBlanks = []
                    }
                    item.lines.append(current.suffix(droppingColumns(marker.contentIndent, from: current.text)))
                    item.end = current.contentEnd
                    cursor += 1
                    continue
                }
                if !pendingBlanks.isEmpty {
                    break
                }
                if listMarker(current.text) != nil || startsBlock(current.text) {
                    break
                }
                item.lines.append(trimmed(current))
                item.end = current.contentEnd
                cursor += 1
            }

            if hasBlankInside {
                loose = true
            }
            if !pendingBlanks.isEmpty, cursor < lines.count,
               let nextMarker = listMarker(lines[cursor].text),
               nextMarker.ordered == firstMarker.ordered {
                loose = true
            }
            items.append(item)
            listEnd = item.end
            index = cursor
        }

        let tag = firstMarker.ordered ? "ol" : "ul"
        let listStart = lines[start].offset + firstMarker.indent
        var html = "<\(tag)"
        if firstMarker.ordered, firstMarker.number != 1 {
            html += " start=\"\(firstMarker.number)\""
        }
        html += context.positionAttribute(from: listStart, to: listEnd) + ">\n"

        for item in items {
            var itemLines = item.lines
            var task: TaskItem?
            if let first = itemLines.first, let parsed = taskItem(first) {
                task = parsed
                itemLines[0] = parsed.line
            }

            var inner = renderBlocks(itemLines, context: context)
            if !loose {
                inner = unwrappingParagraphs(inner)
            }
            var itemAttributes = context.positionAttribute(from: item.start, to: item.end)
            if let task {
                inner = "<input type=\"checkbox\" disabled\(task.isChecked ? " checked" : "")> " + inner
                itemAttributes = " class=\"task-list-item\"" + itemAttributes
            }
            html += "<li\(itemAttributes)>\(inner)</li>\n"
        }

        html += "</\(tag)>"
        return ParsedBlock(html: html, next: index)
    }

    private static func parseParagraph(
        _ lines: [MarkdownSourceLine],
        start: Int,
        context: MarkdownRenderContext
    ) -> ParsedBlock {
        var index = start
        while index < lines.count, MarkdownLinkReferences.parseDefinition(lines[index].text) != nil {
            index += 1
        }
        guard index < lines.count, !isBlank(lines[index].text) else {
            return ParsedBlock(html: "", next: index)
        }

        var textLines: [MarkdownSourceLine] = []

        while index < lines.count {
            let line = lines[index]
            if isBlank(line.text) { break }
            if !textLines.isEmpty {
                if let level = setextLevel(line.text) {
                    let content = textLines.map(\.text).joined(separator: "\n").trimmingCharacters(in: .whitespaces)
                    let from = textLines[0].offset
                    let attributes = context.headingAttributes(content: content, from: from, to: line.contentEnd)
                    let inline = MarkdownInlineRenderer.render(content, context: context.inline)
                    return ParsedBlock(html: "<h\(level)\(attributes)>\(inline)</h\(level)>", next: index + 1)
                }
                if startsBlock(line.text) { break }
            }
            textLines.append(line.suffix(String(line.text.drop(while: { $0 == " " }))))
            index += 1
        }

        let content = textLines.map(\.text).joined(separator: "\n")
        let lastLine = textLines[textLines.count - 1]
        let position = context.positionAttribute(from: textLines[0].offset, to: lastLine.contentEnd)
        let inline = MarkdownInlineRenderer.render(content, context: context.inline)
        return ParsedBlock(html: "<p\(position)>\(inline)</p>", next: index)
    }

    private static func parseTable(
        _ lines: [MarkdownSourceLine],
        start: Int,
        context: MarkdownRenderContext
    ) -> ParsedBlock? {
        guard start + 1 < lines.count else { return nil }
        let headerLine = lines[start]
        guard headerLine.text.contains("|") else { return nil }
        guard let alignments = delimiterRow(lines[start + 1].text) else { return nil }
        let headerCells = splitTableRow(headerLine.text)
        guard headerCells.count == alignments.count else { return nil }

        let inlineContext = context.inline
        let headerStart = headerLine.offset + leadingSpaces(headerLine.text)
        var lastEnd = lines[start + 1].contentEnd

        let headerPosition = context.positionAttribute(from: headerStart, to: headerLine.contentEnd)
        var html = "<thead>\n<tr\(headerPosition)>\n"
        for (column, cell) in headerCells.enumerated() {
            let content = MarkdownInlineRenderer.render(cell, context: inlineContext)
            html += "<th\(alignmentAttribute(alignments[column]))>\(content)</th>\n"
        }
        html += "</tr>\n</thead>\n"

        var rows: [String] = []
        var index = start + 2
        while index < lines.count {
            let line = lines[index]
            if isBlank(line.text) || !line.text.contains("|") { break }
            let cells = splitTableRow(line.text)
            let rowStart = line.offset + leadingSpaces(line.text)
            var row = "<tr\(context.positionAttribute(from: rowStart, to: line.contentEnd))>\n"
            for column in 0..<alignments.count {
                let value = column < cells.count ? cells[column] : ""
                let content = MarkdownInlineRenderer.render(value, context: inlineContext)
                row += "<td\(alignmentAttribute(alignments[column]))>\(content)</td>\n"
            }
            row += "</tr>"
            rows.append(row)
            lastEnd = line.contentEnd
            index += 1
        }

        var table = "<table\(context.positionAttribute(from: headerStart, to: lastEnd))>\n" + html
        if !rows.isEmpty {
            table += "<tbody>\n\(rows.joined(separator: "\n"))\n</tbody>\n"
        }
        table += "</table>"
        return ParsedBlock(html: table, next: index)
    }

    static func splitTableRow(_ line: String) -> [String] {
        var characters = Array(line.trimmingCharacters(in: .whitespaces))
        if characters.first == "|" { characters.removeFirst() }
        if characters.last == "|", !endsWithEscapedPipe(characters) { characters.removeLast() }

        var cells: [String] = []
        var current = ""
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\\", index + 1 < characters.count {
                if characters[index + 1] == "|" {
                    current.append("|")
                } else {
                    current.append(character)
                    current.append(characters[index + 1])
                }
                index += 2
                continue
            }
            if character == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
                index += 1
                continue
            }
            current.append(character)
            index += 1
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private static func endsWithEscapedPipe(_ characters: [Character]) -> Bool {
        var backslashes = 0
        var index = characters.count - 2
        while index >= 0, characters[index] == "\\" {
            backslashes += 1
            index -= 1
        }
        return backslashes % 2 == 1
    }

    private static func delimiterRow(_ line: String) -> [TableAlignment]? {
        guard line.contains("-") else { return nil }
        let cells = splitTableRow(line)
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

    private static func taskItem(_ line: MarkdownSourceLine) -> TaskItem? {
        let characters = Array(line.text)
        guard characters.count >= 3, characters[0] == "[", characters[2] == "]" else { return nil }
        let mark = characters[1]
        guard mark == " " || mark == "x" || mark == "X" else { return nil }
        guard characters.count == 3 || characters[3] == " " else { return nil }
        let remainder = String(characters.dropFirst(3))
        let leading = remainder.prefix(while: { $0.isWhitespace && $0 != "\n" }).utf16.count
        let text = remainder.trimmingCharacters(in: .whitespaces)
        let remaining = MarkdownSourceLine(text: text, offset: line.offset + 3 + leading)
        return TaskItem(isChecked: mark != " ", line: remaining)
    }

    private static func unwrappingParagraphs(_ html: String) -> String {
        guard let openEnd = paragraphOpeningEnd(html) else { return html }
        var result = String(html[openEnd...])
        for block in ["<ul", "<ol", "<pre", "<blockquote", "<table", "<hr"] {
            result = result.replacingOccurrences(of: "</p>\n\(block)", with: block)
        }
        if result.hasSuffix("</p>") {
            result = String(result.dropLast(4))
        }
        return result
    }

    private static func paragraphOpeningEnd(_ html: String) -> String.Index? {
        if html.hasPrefix("<p>") {
            return html.index(html.startIndex, offsetBy: 3)
        }
        guard html.hasPrefix("<p md-src-pos=\""), let close = html.firstIndex(of: ">") else { return nil }
        return html.index(after: close)
    }

    private static func itemContent(_ line: MarkdownSourceLine, marker: ListMarker) -> MarkdownSourceLine {
        let characters = Array(line.text)
        var index = marker.indent + marker.markerLength
        while index < characters.count, characters[index] == " " || characters[index] == "\t" {
            index += 1
        }
        guard index < characters.count else { return MarkdownSourceLine(text: "", offset: line.end) }
        return line.suffix(String(characters[index...]))
    }

    private static func droppingColumns(_ columns: Int, from line: String) -> String {
        var consumed = 0
        var dropped = 0
        for character in line {
            guard consumed < columns, character == " " || character == "\t" else { break }
            consumed += character == "\t" ? 4 - consumed % 4 : 1
            dropped += 1
        }
        return String(line.dropFirst(dropped))
    }

    private static func trimmed(_ line: MarkdownSourceLine) -> MarkdownSourceLine {
        let leading = line.text.prefix(while: { $0.isWhitespace }).utf16.count
        let text = line.text.trimmingCharacters(in: .whitespaces)
        return MarkdownSourceLine(text: text, offset: line.offset + leading)
    }

    private static func setextLevel(_ line: String) -> Int? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
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
        default: return lower.contains("]]>")
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

    static func fenceOpening(_ line: String) -> Fence? {
        let characters = Array(line)
        var index = 0
        while index < characters.count, characters[index] == " " {
            index += 1
        }
        let indent = index
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
        return Fence(character: marker, length: length, info: info, indent: indent)
    }

    static func isFenceClosing(_ line: String, fence: Fence) -> Bool {
        isFenceClosing(line, character: fence.character, length: fence.length)
    }

    static func isFenceClosing(_ line: String, character: Character, length minimum: Int) -> Bool {
        let characters = Array(line)
        var index = 0
        while index < characters.count, characters[index] == " " {
            index += 1
        }
        guard index <= 3 else { return false }

        var length = 0
        while index < characters.count, characters[index] == character {
            length += 1
            index += 1
        }
        guard length >= minimum else { return false }
        guard index >= characters.count else {
            return String(characters[index...]).trimmingCharacters(in: .whitespaces).isEmpty
        }
        return true
    }

    private static func codeBlock(_ code: String, info: String, position: String) -> String {
        let language = info.split(separator: " ").first.map(String.init) ?? ""
        let escapedCode = MarkdownInlineRenderer.escape(code)
        guard !language.isEmpty else {
            return "<pre\(position)><code>\(escapedCode)\n</code></pre>"
        }
        let escapedLanguage = MarkdownInlineRenderer.escape(MarkdownInlineRenderer.unescapeLiteral(language))
        return "<pre\(position)><code class=\"language-\(escapedLanguage)\">\(escapedCode)\n</code></pre>"
    }
}
