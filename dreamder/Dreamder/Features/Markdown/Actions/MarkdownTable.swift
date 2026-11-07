import Foundation

nonisolated enum MarkdownTableStyle: Sendable, CaseIterable {
    case aligned
    case compact
    case tight
}

nonisolated enum MarkdownTableAlignment: Sendable, Equatable {
    case none
    case left
    case right
    case center

    init(units: [UInt16], cell: Range<Int>) {
        let colon: UInt16 = 0x3A
        guard let first = cell.first(where: { units[$0] == colon }),
              let last = cell.last(where: { units[$0] == colon }) else {
            self = .none
            return
        }
        if first != last {
            self = .center
        } else if units[cell.lowerBound..<first].allSatisfy({ $0 == MarkdownText.space }) {
            self = .left
        } else {
            self = .right
        }
    }
}

nonisolated enum MarkdownTableCharacterWidth {
    private static let fullWidthRanges: [ClosedRange<UInt32>] = [
        0x1100...0x115F,
        0x2329...0x232A,
        0x231A...0x231B,
        0x23E9...0x23EC,
        0x23F0...0x23F0,
        0x23F3...0x23F3,
        0x25FD...0x25FE,
        0x2600...0x27BF,
        0x2B05...0x2B07,
        0x2B1B...0x2B1C,
        0x2B50...0x2B50,
        0x2B55...0x2B55,
        0x2E80...0x303E,
        0x3040...0x3247,
        0x3250...0x4DBF,
        0x4E00...0xA4C6,
        0xA960...0xA97C,
        0xAC00...0xD7A3,
        0xF900...0xFAFF,
        0xFE10...0xFE19,
        0xFE30...0xFE6B,
        0xFF01...0xFF60,
        0xFFE0...0xFFE6,
        0x1B000...0x1B122,
        0x1F0CF...0x1F0CF,
        0x1F18E...0x1F18E,
        0x1F191...0x1F19A,
        0x1F1E6...0x1F1FF,
        0x1F200...0x1F251,
        0x1F300...0x1F5FF,
        0x1F600...0x1F64F,
        0x1F680...0x1F6FF,
        0x1F7E0...0x1F7EB,
        0x1F7F0...0x1F7F0,
        0x1F900...0x1F9FF,
        0x1FA70...0x1FAFF,
        0x20000...0x3FFFD
    ]

    static func columns(of scalar: Unicode.Scalar) -> Int {
        let value = scalar.value
        if value >= 0x20, value <= 0x7E { return 1 }
        if value < 0x20 { return 0 }
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .enclosingMark, .format:
            return 0
        default:
            break
        }
        return isFullWidth(value) ? 2 : 1
    }

    static func isFullWidth(_ value: UInt32) -> Bool {
        fullWidthRanges.contains { $0.contains(value) }
    }

    static func displayWidth(of string: String, startColumn: Int, tabSize: Int) -> Int {
        var width = 0
        let size = max(tabSize, 1)
        for character in string {
            guard let scalar = character.unicodeScalars.first else { continue }
            if scalar.value == 9 {
                width += size - (startColumn + width) % size
            } else {
                width += columns(of: scalar)
            }
        }
        return width
    }
}

nonisolated struct MarkdownTableLayout: Sendable {
    struct Row: Sendable {
        let line: Int
        let lineStart: Int
        let prefixLength: Int
        let split: MarkdownTableRowSplit

        var bodyStart: Int { lineStart + prefixLength }
        var end: Int { split.bodyRange.upperBound }
        var cells: [Range<Int>] { split.cells }
    }

    let lines: Range<Int>
    let rows: [Row]

    init?(text: MarkdownText, lines: Range<Int>, prefixLengths: [Int]) {
        guard lines.count >= 2, prefixLengths.count == lines.count, lines.upperBound <= text.lines.count else {
            return nil
        }
        var rows: [Row] = []
        for (position, line) in lines.enumerated() {
            let textLine = text.lines[line]
            let bodyStart = textLine.start + prefixLengths[position]
            guard bodyStart <= textLine.contentEnd else { return nil }
            let split = MarkdownTableRowSplitter.split(text.units, body: bodyStart..<textLine.contentEnd)
            rows.append(Row(line: line, lineStart: textLine.start, prefixLength: prefixLengths[position], split: split))
        }
        self.lines = lines
        self.rows = rows
    }

    init?(document: MarkdownDocument, block: MarkdownBlock) {
        let prefixLengths = Self.prefixLengths(document: document, lines: block.lines)
        self.init(text: document.text, lines: block.lines, prefixLengths: prefixLengths)
    }

    static func prefixLengths(document: MarkdownDocument, lines: Range<Int>) -> [Int] {
        lines.map { line in
            let textLine = document.text.lines[line]
            let bodyStart = document.text.skipSpacesAndTabs(
                from: document.infos[line].quoteEnd,
                to: textLine.contentEnd
            )
            return bodyStart - textLine.start
        }
    }

    static func find(in document: MarkdownDocument, containing offset: Int) -> MarkdownTableLayout? {
        guard let block = document.block(containing: offset), block.kind == .table else { return nil }
        return MarkdownTableLayout(document: document, block: block)
    }

    var header: Row { rows[0] }
    var separator: Row { rows[1] }

    var hasBorders: Bool {
        rows.allSatisfy { $0.split.hasLeadingPipe && $0.split.hasTrailingPipe }
    }

    func rowPosition(ofLine line: Int) -> Int? {
        lines.contains(line) ? line - lines.lowerBound : nil
    }

    func cellIndex(containing offset: Int, row: Row) -> Int? {
        row.cells.firstIndex { $0.lowerBound <= offset && offset <= $0.upperBound }
    }

    func isInsideListItem(document: MarkdownDocument) -> Bool {
        let first = lines.lowerBound
        let quoteEnd = document.infos[first].quoteEnd
        let tableDepth = document.infos[first].quoteDepth
        let tableIndent = rows[0].bodyStart - quoteEnd
        guard tableIndent > 0 else { return false }
        var line = first - 1
        while line >= 0 {
            let info = document.infos[line]
            if info.isBlank {
                line -= 1
                continue
            }
            if info.quoteDepth != tableDepth { return false }
            if info.listItem != nil {
                return info.bodyStart - info.quoteEnd <= tableIndent
            }
            let textLine = document.text.lines[line]
            let bodyStart = document.text.skipSpacesAndTabs(from: info.quoteEnd, to: textLine.contentEnd)
            if bodyStart == info.quoteEnd { return false }
            line -= 1
        }
        return false
    }

    func emptyRow(style: MarkdownTableStyle, units: [UInt16]) -> String {
        let columns = header.cells.count
        switch style {
        case .compact:
            return MarkdownTable.emptyRow(columns: columns, fill: " ", width: 1)
        case .tight:
            return MarkdownTable.emptyRow(columns: columns, fill: " ", width: 0)
        case .aligned:
            var result = "|"
            for cell in header.cells {
                let content = String(decoding: units[cell], as: UTF16.self)
                let width = MarkdownTable.displayWidth(of: content, startColumn: 0, tabSize: 4)
                result += String(repeating: " ", count: max(width, 0)) + "|"
            }
            return result
        }
    }
}

nonisolated enum MarkdownTable {
    static func displayWidth(of string: String, startColumn: Int = 0, tabSize: Int = 4) -> Int {
        MarkdownTableCharacterWidth.displayWidth(of: string, startColumn: startColumn, tabSize: tabSize)
    }

    static func displayWidth(units: some Sequence<UInt16>, startColumn: Int = 0, tabSize: Int = 4) -> Int {
        displayWidth(of: String(decoding: Array(units), as: UTF16.self), startColumn: startColumn, tabSize: tabSize)
    }

    static func emptyRow(columns: Int, fill: String, width: Int) -> String {
        var result = ""
        for _ in 0..<max(columns, 0) {
            result += "|" + String(repeating: fill, count: max(width, 0))
        }
        return result + "|"
    }

    static func buildEmptyTable(
        contentRows: Int,
        columns: Int,
        cellWidth: Int = 3,
        style: MarkdownTableStyle = .aligned
    ) -> String {
        let contentWidth: Int
        switch style {
        case .aligned: contentWidth = cellWidth
        case .compact: contentWidth = 1
        case .tight: contentWidth = 0
        }
        var result = emptyRow(columns: columns, fill: " ", width: contentWidth) + "\n"
        switch style {
        case .aligned:
            result += emptyRow(columns: columns, fill: "-", width: cellWidth)
        case .compact, .tight:
            let separatorCell = style == .compact ? " --- " : "---"
            for _ in 0..<max(columns, 0) {
                result += "|" + separatorCell
            }
            result += "|"
        }
        result += "\n"
        for _ in 0..<max(contentRows, 0) {
            result += emptyRow(columns: columns, fill: " ", width: contentWidth) + "\n"
        }
        return result
    }

    static func insertEmptyTable(
        text: String,
        caret: Int,
        contentRows: Int,
        columns: Int,
        style: MarkdownTableStyle = .aligned
    ) -> MarkdownActionResult {
        let document = MarkdownText(text)
        let offset = min(max(caret, 0), document.length)
        let line = document.lineIndex(containing: offset)
        let insertNewLine = line != 0 && !document.isBlankLine(line - 1)
        let prefix = blockQuotePrefix(document, line: line)
        var tableText = buildEmptyTable(contentRows: contentRows, columns: columns, cellWidth: 3, style: style)
        if !prefix.isEmpty {
            tableText = tableText.replacingOccurrences(of: "\n", with: "\n" + prefix)
            if tableText.hasSuffix(prefix) {
                tableText.removeLast(prefix.count)
            }
        }
        let leading = insertNewLine ? "\n" + prefix : ""
        var buffer = MarkdownEditBuffer(text)
        buffer.insert(leading + tableText, at: offset)
        let firstCell = offset + leading.utf16.count + 1
        return buffer.result(selections: [NSRange(location: firstCell, length: 0)])
    }

    static func format(
        text: String,
        selections: [NSRange],
        style: MarkdownTableStyle = .aligned,
        tabSize: Int = 4,
        trimToMaxContent: Bool = true
    ) -> MarkdownActionResult? {
        MarkdownTableFormatter(style: style, tabSize: tabSize, trimToMaxContent: trimToMaxContent, preventExpand: false)
            .format(text: text, selections: selections, onlyTablesTouchedBySelections: !selections.isEmpty)
    }

    static func formatAllTables(
        text: String,
        style: MarkdownTableStyle = .aligned,
        tabSize: Int = 4
    ) -> MarkdownActionResult? {
        MarkdownTableFormatter(style: style, tabSize: tabSize, trimToMaxContent: true, preventExpand: false)
            .format(text: text, selections: [], onlyTablesTouchedBySelections: false)
    }

    static func columnAlignments(text: String, tableContaining offset: Int) -> [MarkdownTableAlignment]? {
        let document = MarkdownDocument(text)
        guard let layout = MarkdownTableLayout.find(in: document, containing: offset) else { return nil }
        let units = document.text.units
        return layout.separator.cells.map { MarkdownTableAlignment(units: units, cell: $0) }
    }

    static func isProbablyInsideCell(_ text: MarkdownText, caret: Int) -> Bool {
        guard caret > 0, caret <= text.length else { return false }
        let line = text.lines[text.lineIndex(containing: caret)]
        let pipe: UInt16 = 0x7C
        let leftBar = caret > line.start && text.units[line.start..<min(caret, line.contentEnd)].contains(pipe)
        guard leftBar, caret < line.contentEnd else { return false }
        return text.units[caret..<line.contentEnd].contains(pipe)
    }

    static func isInsideTable(text: String, caret: Int) -> Bool {
        let document = MarkdownDocument(text)
        return cellContext(document: document, caret: caret) != nil
    }

    static func cellContext(
        document: MarkdownDocument,
        caret: Int
    ) -> (layout: MarkdownTableLayout, rowPosition: Int, cell: Int)? {
        guard isProbablyInsideCell(document.text, caret: caret),
              let layout = MarkdownTableLayout.find(in: document, containing: caret),
              let position = layout.rowPosition(ofLine: document.text.lineIndex(containing: caret)),
              position != 1,
              let cell = layout.cellIndex(containing: caret, row: layout.rows[position]) else {
            return nil
        }
        return (layout, position, cell)
    }

    private static func blockQuotePrefix(_ text: MarkdownText, line: Int) -> String {
        let textLine = text.lines[line]
        var index = textLine.start
        var hasQuote = false
        while index < textLine.contentEnd {
            let unit = text.units[index]
            if unit == 0x3E {
                hasQuote = true
            } else if !MarkdownText.isSpaceOrTab(unit) {
                break
            }
            index += 1
        }
        guard hasQuote else { return "" }
        return text.string(textLine.start..<index)
    }
}
