import Foundation

nonisolated struct MarkdownLineInfo: Sendable, Equatable {
    let quoteDepth: Int
    let quoteEnd: Int
    let listItem: MarkdownListItemPrefix?
    let bodyStart: Int
    let isBlank: Bool
}

nonisolated struct MarkdownBlock: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case paragraph
        case atxHeading(level: Int)
        case setextHeading(level: Int)
        case fencedCode
        case indentedCode
        case htmlBlock
        case frontMatter
        case table
        case thematicBreak
    }

    let kind: Kind
    let lines: Range<Int>

    var isHeading: Bool {
        switch kind {
        case .atxHeading, .setextHeading: true
        default: false
        }
    }

    var headingLevel: Int? {
        switch kind {
        case .atxHeading(let level), .setextHeading(let level): level
        default: nil
        }
    }

    var contentLines: Range<Int> {
        if case .setextHeading = kind {
            return lines.lowerBound..<(lines.upperBound - 1)
        }
        return lines
    }
}

nonisolated struct MarkdownTableRowSplit: Sendable, Equatable {
    let cells: [Range<Int>]
    let pipes: [Int]
    let hasLeadingPipe: Bool
    let hasTrailingPipe: Bool
    let bodyRange: Range<Int>
}

nonisolated enum MarkdownTableRowSplitter {
    static func split(_ units: [UInt16], body: Range<Int>) -> MarkdownTableRowSplit {
        var lower = body.lowerBound
        var upper = body.upperBound
        while lower < upper, MarkdownText.isSpaceOrTab(units[lower]) { lower += 1 }
        while upper > lower, MarkdownText.isSpaceOrTab(units[upper - 1]) { upper -= 1 }

        var pipes: [Int] = []
        var index = lower
        var backslashes = 0
        while index < upper {
            let unit = units[index]
            if unit == 0x5C {
                backslashes += 1
            } else {
                if unit == 0x7C, backslashes % 2 == 0 {
                    pipes.append(index)
                }
                backslashes = 0
            }
            index += 1
        }

        let hasLeading = pipes.first == lower
        let hasTrailing = pipes.last == upper - 1 && !(pipes.count == 1 && hasLeading)
        var cells: [Range<Int>] = []
        var cellStart = hasLeading ? lower + 1 : lower
        let boundaries = hasLeading ? Array(pipes.dropFirst()) : pipes
        for pipe in boundaries {
            cells.append(cellStart..<pipe)
            cellStart = pipe + 1
        }
        if !hasTrailing {
            let tail = cellStart..<max(cellStart, upper)
            if !tail.isEmpty {
                cells.append(tail)
            }
        }
        return MarkdownTableRowSplit(
            cells: cells,
            pipes: pipes,
            hasLeadingPipe: hasLeading,
            hasTrailingPipe: hasTrailing,
            bodyRange: lower..<upper
        )
    }
}

nonisolated struct MarkdownDocument: Sendable {
    let text: MarkdownText
    let infos: [MarkdownLineInfo]
    let blocks: [MarkdownBlock]
    let blockIndexByLine: [Int?]

    init(_ string: String) {
        self.init(MarkdownText(string))
    }

    init(_ text: MarkdownText) {
        self.text = text
        let infos = text.lines.indices.map { Self.makeInfo(text: text, line: $0) }
        self.infos = infos
        var scanner = Scanner(text: text, infos: infos)
        scanner.run()
        self.blocks = scanner.blocks
        var byLine = [Int?](repeating: nil, count: text.lines.count)
        for (index, block) in scanner.blocks.enumerated() {
            for line in block.lines {
                byLine[line] = index
            }
        }
        self.blockIndexByLine = byLine
    }

    func blockIndex(containing offset: Int) -> Int? {
        blockIndexByLine[text.lineIndex(containing: offset)]
    }

    func block(containing offset: Int) -> MarkdownBlock? {
        blockIndex(containing: offset).map { blocks[$0] }
    }

    func isInFencedCode(_ offset: Int) -> Bool {
        block(containing: offset)?.kind == .fencedCode
    }

    func bodyRange(line: Int) -> Range<Int> {
        infos[line].bodyStart..<text.lines[line].contentEnd
    }

    func atxContentRange(line: Int) -> Range<Int>? {
        let range = bodyRange(line: line)
        let units = text.units
        var index = range.lowerBound
        var hashes = 0
        while index < range.upperBound, units[index] == 0x23 {
            index += 1
            hashes += 1
        }
        guard hashes > 0, hashes <= 6, index == range.upperBound || MarkdownText.isSpaceOrTab(units[index]) else {
            return nil
        }
        var lower = text.skipSpacesAndTabs(from: index, to: range.upperBound)
        var upper = range.upperBound
        while upper > lower, MarkdownText.isSpaceOrTab(units[upper - 1]) { upper -= 1 }
        var closing = upper
        while closing > lower, units[closing - 1] == 0x23 { closing -= 1 }
        if closing < upper, closing == lower || MarkdownText.isSpaceOrTab(units[closing - 1]) {
            upper = closing
            while upper > lower, MarkdownText.isSpaceOrTab(units[upper - 1]) { upper -= 1 }
        }
        if lower > upper { lower = upper }
        return lower..<upper
    }

    func inlineRegion(ofBlock index: Int) -> (base: Int, units: [UInt16])? {
        let block = blocks[index]
        switch block.kind {
        case .paragraph, .setextHeading:
            let lines = block.contentLines
            return maskedRegion(lines: lines) { line in infos[line].bodyStart..<text.lines[line].contentEnd }
        case .atxHeading:
            let line = block.lines.lowerBound
            guard let content = atxContentRange(line: line) else { return nil }
            let base = text.lines[line].start
            var units = [UInt16](repeating: MarkdownText.space, count: content.upperBound - base)
            for offset in content {
                units[offset - base] = text.units[offset]
            }
            return (base, units)
        default:
            return nil
        }
    }

    private func maskedRegion(lines: Range<Int>, keep: (Int) -> Range<Int>) -> (base: Int, units: [UInt16])? {
        guard !lines.isEmpty else { return nil }
        let base = text.lines[lines.lowerBound].start
        let end = text.lines[lines.upperBound - 1].contentEnd
        var units = Array(text.units[base..<end])
        for line in lines {
            let info = text.lines[line]
            let kept = keep(line)
            var offset = info.start
            while offset < kept.lowerBound {
                units[offset - base] = MarkdownText.space
                offset += 1
            }
        }
        return (base, units)
    }

    private static func indentColumns(_ units: [UInt16], from start: Int, to end: Int) -> (columns: Int, index: Int) {
        var columns = 0
        var index = start
        while index < end {
            if units[index] == MarkdownText.space {
                columns += 1
            } else if units[index] == MarkdownText.tab {
                columns += 4 - columns % 4
            } else {
                break
            }
            index += 1
        }
        return (columns, index)
    }

    private static func makeInfo(text: MarkdownText, line lineIndex: Int) -> MarkdownLineInfo {
        let line = text.lines[lineIndex]
        let units = text.units
        var index = line.start
        var depth = 0
        while true {
            var probe = index
            var spaces = 0
            while probe < line.contentEnd, units[probe] == MarkdownText.space, spaces < 3 {
                probe += 1
                spaces += 1
            }
            guard probe < line.contentEnd, units[probe] == 0x3E else { break }
            depth += 1
            probe += 1
            if probe < line.contentEnd, units[probe] == MarkdownText.space {
                probe += 1
            }
            index = probe
        }
        let quoteEnd = index

        var listItem: MarkdownListItemPrefix?
        var bodyStart = text.skipSpacesAndTabs(from: quoteEnd, to: line.contentEnd)
        if bodyStart < line.contentEnd {
            let first = units[bodyStart]
            let couldBeMarker = first == 0x2D || first == 0x2A || first == 0x2B || (first >= 0x30 && first <= 0x39)
            if couldBeMarker, !isThematicBreak(units, from: bodyStart, to: line.contentEnd) {
                let lineString = String(decoding: units[line.start..<line.contentEnd], as: UTF16.self)
                if let parsed = MarkdownListItemPrefix.parse(line: Substring(lineString)),
                   parsed.contentStart <= line.contentEnd - line.start {
                    listItem = parsed
                    bodyStart = line.start + parsed.contentStart
                }
            }
        }
        let blank = text.isBlank(bodyStart..<line.contentEnd)
        return MarkdownLineInfo(
            quoteDepth: depth,
            quoteEnd: quoteEnd,
            listItem: listItem,
            bodyStart: bodyStart,
            isBlank: blank
        )
    }

    private static func isThematicBreak(_ units: [UInt16], from start: Int, to end: Int) -> Bool {
        var marker: UInt16?
        var count = 0
        for index in start..<end {
            let unit = units[index]
            if MarkdownText.isSpaceOrTab(unit) { continue }
            guard unit == 0x2D || unit == 0x2A || unit == 0x5F else { return false }
            if let marker, marker != unit { return false }
            marker = unit
            count += 1
        }
        return count >= 3
    }

    private static func setextLevel(text: MarkdownText, info: MarkdownLineInfo, line: Int) -> Int? {
        guard info.listItem == nil else { return nil }
        let units = text.units
        let end = text.lines[line].contentEnd
        let (columns, index) = indentColumns(units, from: info.quoteEnd, to: end)
        guard columns < 4, index < end else { return nil }
        let marker = units[index]
        guard marker == 0x3D || marker == 0x2D else { return nil }
        var cursor = index
        while cursor < end, units[cursor] == marker { cursor += 1 }
        while cursor < end, MarkdownText.isSpaceOrTab(units[cursor]) { cursor += 1 }
        guard cursor == end else { return nil }
        return marker == 0x3D ? 1 : 2
    }

    private struct Scanner {
        let text: MarkdownText
        let infos: [MarkdownLineInfo]
        var blocks: [MarkdownBlock] = []
        var listContext = false

        init(text: MarkdownText, infos: [MarkdownLineInfo]) {
            self.text = text
            self.infos = infos
        }

        private var count: Int { text.lines.count }

        mutating func run() {
            var line = 0
            while line < count {
                let info = infos[line]
                if info.isBlank {
                    line += 1
                    continue
                }
                if line == 0, let end = frontMatterEnd() {
                    blocks.append(MarkdownBlock(kind: .frontMatter, lines: 0..<(end + 1)))
                    line = end + 1
                    continue
                }
                if info.listItem != nil {
                    listContext = true
                } else if indentColumns(line) == 0 {
                    listContext = false
                }
                if let fence = fenceOpening(line) {
                    let end = fenceEnd(opening: line, fence: fence)
                    blocks.append(MarkdownBlock(kind: .fencedCode, lines: line..<end))
                    line = end
                    continue
                }
                if let end = htmlBlockEnd(line, canInterruptParagraph: false) {
                    blocks.append(MarkdownBlock(kind: .htmlBlock, lines: line..<end))
                    line = end
                    continue
                }
                if info.listItem == nil, !listContext, indentColumns(line) >= 4 {
                    let end = indentedCodeEnd(line)
                    blocks.append(MarkdownBlock(kind: .indentedCode, lines: line..<end))
                    line = end
                    continue
                }
                if Self.isThematicBreakLine(text: text, info: info, line: line) {
                    blocks.append(MarkdownBlock(kind: .thematicBreak, lines: line..<(line + 1)))
                    line += 1
                    continue
                }
                if let level = atxLevel(line) {
                    blocks.append(MarkdownBlock(kind: .atxHeading(level: level), lines: line..<(line + 1)))
                    line += 1
                    continue
                }
                if let end = tableEnd(line) {
                    blocks.append(MarkdownBlock(kind: .table, lines: line..<end))
                    line = end
                    continue
                }
                line = paragraph(from: line)
            }
        }

        private mutating func paragraph(from first: Int) -> Int {
            var line = first + 1
            while line < count {
                if let level = MarkdownDocument.setextLevel(text: text, info: infos[line], line: line),
                   infos[first].listItem == nil,
                   infos[line].quoteDepth == infos[first].quoteDepth,
                   !infos[line].isBlank {
                    blocks.append(MarkdownBlock(kind: .setextHeading(level: level), lines: first..<(line + 1)))
                    return line + 1
                }
                if interruptsParagraph(line, firstInfo: infos[first]) { break }
                line += 1
            }
            blocks.append(MarkdownBlock(kind: .paragraph, lines: first..<line))
            return line
        }

        private func interruptsParagraph(_ line: Int, firstInfo: MarkdownLineInfo) -> Bool {
            let info = infos[line]
            if info.isBlank { return true }
            if info.quoteDepth > firstInfo.quoteDepth { return true }
            if Self.isThematicBreakLine(text: text, info: info, line: line) { return true }
            if atxLevel(line) != nil { return true }
            if fenceOpening(line) != nil { return true }
            if htmlBlockEnd(line, canInterruptParagraph: true) != nil { return true }
            if let item = info.listItem, item.hasContent {
                switch item.marker {
                case .bullet:
                    return true
                case .ordered(let number, _):
                    return number == 1
                }
            }
            if tableEnd(line) != nil { return true }
            return false
        }

        private func indentColumns(_ line: Int) -> Int {
            let end = text.lines[line].contentEnd
            return MarkdownDocument.indentColumns(text.units, from: infos[line].quoteEnd, to: end).columns
        }

        private func frontMatterEnd() -> Int? {
            let first = text.lines[0]
            let units = text.units
            let line = Array(units[first.start..<first.contentEnd])
            let marker: [UInt16]
            if line == [0x2D, 0x2D, 0x2D] {
                marker = [0x2D, 0x2D, 0x2D]
            } else if line == [0x2B, 0x2B, 0x2B] {
                marker = [0x2B, 0x2B, 0x2B]
            } else {
                return nil
            }
            var index = 1
            while index < count {
                let current = text.lines[index]
                let content = Array(units[current.start..<current.contentEnd])
                if content == marker || (marker == [0x2D, 0x2D, 0x2D] && content == [0x2E, 0x2E, 0x2E]) {
                    return index
                }
                index += 1
            }
            return nil
        }

        private struct Fence {
            let marker: UInt16
            let length: Int
            let quoteDepth: Int
        }

        private func fenceBodyStart(_ line: Int) -> Int? {
            let info = infos[line]
            let end = text.lines[line].contentEnd
            if info.listItem != nil { return info.bodyStart }
            let (columns, index) = MarkdownDocument.indentColumns(text.units, from: info.quoteEnd, to: end)
            if columns >= 4, !listContext, info.quoteDepth == 0 { return nil }
            return index
        }

        private func fenceOpening(_ line: Int) -> Fence? {
            guard let start = fenceBodyStart(line) else { return nil }
            let end = text.lines[line].contentEnd
            let units = text.units
            guard start < end, units[start] == 0x60 || units[start] == 0x7E else { return nil }
            let marker = units[start]
            var index = start
            while index < end, units[index] == marker { index += 1 }
            let length = index - start
            guard length >= 3 else { return nil }
            if marker == 0x60 {
                for position in index..<end where units[position] == 0x60 { return nil }
            }
            return Fence(marker: marker, length: length, quoteDepth: infos[line].quoteDepth)
        }

        private func fenceEnd(opening: Int, fence: Fence) -> Int {
            var line = opening + 1
            let units = text.units
            while line < count {
                let info = infos[line]
                if !info.isBlank, info.quoteDepth < fence.quoteDepth { return line }
                let end = text.lines[line].contentEnd
                let start = text.skipSpacesAndTabs(from: info.quoteEnd, to: end)
                var index = start
                while index < end, units[index] == fence.marker { index += 1 }
                if index - start >= fence.length, text.isBlank(index..<end) {
                    return line + 1
                }
                line += 1
            }
            return count
        }

        private static let blockTagNames: Set<String> = [
            "address", "article", "aside", "base", "basefont", "blockquote", "body", "caption", "center", "col",
            "colgroup", "dd", "details", "dialog", "dir", "div", "dl", "dt", "fieldset", "figcaption", "figure",
            "footer", "form", "frame", "frameset", "h1", "h2", "h3", "h4", "h5", "h6", "head", "header", "hr",
            "html", "iframe", "legend", "li", "link", "main", "menu", "menuitem", "nav", "noframes", "ol",
            "optgroup", "option", "p", "param", "section", "source", "summary", "table", "tbody", "td", "tfoot",
            "th", "thead", "title", "tr", "track", "ul"
        ]

        private static let rawTagNames: Set<String> = ["pre", "script", "style", "textarea"]

        private func htmlBlockEnd(_ line: Int, canInterruptParagraph: Bool) -> Int? {
            guard let start = fenceBodyStart(line) else { return nil }
            let lineEnd = text.lines[line].contentEnd
            let units = text.units
            guard start < lineEnd, units[start] == 0x3C else { return nil }
            let body = String(decoding: units[start..<lineEnd], as: UTF16.self)
            if body.hasPrefix("<!--") {
                return terminatedEnd(from: line, startOffset: start + 4, terminator: "-->")
            }
            if body.hasPrefix("<?") {
                return terminatedEnd(from: line, startOffset: start + 2, terminator: "?>")
            }
            if body.hasPrefix("<![CDATA[") {
                return terminatedEnd(from: line, startOffset: start + 9, terminator: "]]>")
            }
            if body.hasPrefix("<!"), body.dropFirst(2).first?.isLetter == true {
                return terminatedEnd(from: line, startOffset: start + 2, terminator: ">")
            }
            var nameStart = body.index(after: body.startIndex)
            if nameStart < body.endIndex, body[nameStart] == "/" { nameStart = body.index(after: nameStart) }
            var nameEnd = nameStart
            while nameEnd < body.endIndex, body[nameEnd].isLetter || body[nameEnd].isNumber || body[nameEnd] == "-" {
                nameEnd = body.index(after: nameEnd)
            }
            let name = body[nameStart..<nameEnd].lowercased()
            guard !name.isEmpty else { return nil }
            let following = nameEnd < body.endIndex ? body[nameEnd] : nil
            let terminates = following == nil
                || following == " "
                || following == "\t"
                || following == ">"
                || following == "/"
            if Self.rawTagNames.contains(name), terminates {
                return terminatedEnd(from: line, startOffset: start, terminator: "</\(name)>", caseInsensitive: true)
            }
            if Self.blockTagNames.contains(name), terminates {
                return blankLineEnd(from: line)
            }
            if !canInterruptParagraph, Self.isCompleteTag(body) {
                return blankLineEnd(from: line)
            }
            return nil
        }

        private static func isCompleteTag(_ body: String) -> Bool {
            let trimmed = body.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("<"), trimmed.hasSuffix(">") else { return false }
            let inner = trimmed.dropFirst().dropLast()
            guard !inner.contains("<"), !inner.contains(">") else { return false }
            var name = inner
            if name.hasPrefix("/") { name = name.dropFirst() }
            guard let first = name.first, first.isLetter else { return false }
            let afterName = name.drop(while: { $0.isLetter || $0.isNumber || $0 == "-" })
            guard let next = afterName.first else { return true }
            return next == " " || next == "\t" || next == "/"
        }

        private func blankLineEnd(from line: Int) -> Int {
            var index = line + 1
            while index < count, !infos[index].isBlank { index += 1 }
            return index
        }

        private func terminatedEnd(
            from line: Int,
            startOffset: Int,
            terminator: String,
            caseInsensitive: Bool = false
        ) -> Int {
            var index = line
            var from = startOffset
            while index < count {
                let end = text.lines[index].contentEnd
                var segment = String(decoding: text.units[min(from, end)..<end], as: UTF16.self)
                var target = terminator
                if caseInsensitive {
                    segment = segment.lowercased()
                    target = terminator.lowercased()
                }
                if segment.contains(target) { return index + 1 }
                index += 1
                if index < count { from = text.lines[index].start }
            }
            return count
        }

        private func indentedCodeEnd(_ line: Int) -> Int {
            var end = line + 1
            var lastCode = line
            while end < count {
                let info = infos[end]
                if info.isBlank {
                    end += 1
                    continue
                }
                if info.listItem == nil, indentColumns(end) >= 4 {
                    lastCode = end
                    end += 1
                    continue
                }
                break
            }
            return lastCode + 1
        }

        private static func isThematicBreakLine(text: MarkdownText, info: MarkdownLineInfo, line: Int) -> Bool {
            let end = text.lines[line].contentEnd
            let (columns, index) = MarkdownDocument.indentColumns(text.units, from: info.quoteEnd, to: end)
            guard columns < 4 else { return false }
            return MarkdownDocument.isThematicBreak(text.units, from: index, to: end)
        }

        private func atxLevel(_ line: Int) -> Int? {
            let info = infos[line]
            let end = text.lines[line].contentEnd
            let start: Int
            if info.listItem != nil {
                start = info.bodyStart
            } else {
                let (columns, index) = MarkdownDocument.indentColumns(text.units, from: info.quoteEnd, to: end)
                if columns >= 4, !listContext { return nil }
                start = index
            }
            var index = start
            while index < end, text.units[index] == 0x23 { index += 1 }
            let level = index - start
            guard level >= 1, level <= 6, index == end || MarkdownText.isSpaceOrTab(text.units[index]) else {
                return nil
            }
            return level
        }

        private func tableEnd(_ line: Int) -> Int? {
            guard line + 1 < count else { return nil }
            let header = infos[line]
            let separator = infos[line + 1]
            guard !header.isBlank, !separator.isBlank, header.quoteDepth == separator.quoteDepth else { return nil }
            let headerSplit = split(line: line)
            guard headerSplit.pipes.isEmpty == false,
                isSeparatorRow(line + 1, expectedColumns: headerSplit.cells.count)
            else {
                return nil
            }
            var end = line + 2
            while end < count {
                let info = infos[end]
                if info.isBlank || info.quoteDepth != header.quoteDepth { break }
                if atxLevel(end) != nil || fenceOpening(end) != nil { break }
                if split(line: end).pipes.isEmpty { break }
                end += 1
            }
            return end
        }

        private func split(line: Int) -> MarkdownTableRowSplit {
            let info = infos[line]
            let start = text.skipSpacesAndTabs(from: info.quoteEnd, to: text.lines[line].contentEnd)
            return MarkdownTableRowSplitter.split(text.units, body: start..<text.lines[line].contentEnd)
        }

        private func isSeparatorRow(_ line: Int, expectedColumns: Int) -> Bool {
            let rowSplit = split(line: line)
            guard !rowSplit.pipes.isEmpty, rowSplit.cells.count == expectedColumns, !rowSplit.cells.isEmpty else {
                return false
            }
            for cell in rowSplit.cells {
                let range = text.trimmedRange(cell)
                guard !range.isEmpty else { return false }
                var index = range.lowerBound
                if text.units[index] == 0x3A { index += 1 }
                let dashStart = index
                while index < range.upperBound, text.units[index] == 0x2D { index += 1 }
                guard index > dashStart else { return false }
                if index < range.upperBound, text.units[index] == 0x3A { index += 1 }
                guard index == range.upperBound else { return false }
            }
            return true
        }
    }
}
