import Foundation

nonisolated struct MarkdownTextLines: Sendable {
    nonisolated struct Line: Sendable {
        let start: Int
        let contentEnd: Int
        let end: Int
    }

    let units: [UInt16]
    let lines: [Line]
    let lineEnding: String

    init(units: [UInt16]) {
        self.units = units
        var lines: [Line] = []
        var lineEnding: String?
        var start = 0
        var index = 0
        while index < units.count {
            let unit = units[index]
            if unit == 10 {
                lines.append(Line(start: start, contentEnd: index, end: index + 1))
                lineEnding = lineEnding ?? "\n"
                start = index + 1
            } else if unit == 13 {
                if index + 1 < units.count, units[index + 1] == 10 {
                    lines.append(Line(start: start, contentEnd: index, end: index + 2))
                    lineEnding = lineEnding ?? "\r\n"
                    index += 1
                } else {
                    lines.append(Line(start: start, contentEnd: index, end: index + 1))
                    lineEnding = lineEnding ?? "\r"
                }
                start = index + 1
            }
            index += 1
        }
        lines.append(Line(start: start, contentEnd: units.count, end: units.count))
        self.lines = lines
        self.lineEnding = lineEnding ?? "\n"
    }

    init(_ text: String) {
        self.init(units: Array(text.utf16))
    }

    var count: Int {
        lines.count
    }

    func lineIndex(containing offset: Int) -> Int {
        var low = 0
        var high = lines.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if lines[middle].start <= offset {
                low = middle
            } else {
                high = middle - 1
            }
        }
        return low
    }

    func indentRunEnd(_ line: Int) -> Int {
        var index = lines[line].start
        let end = lines[line].contentEnd
        while index < end, Self.isIndentUnit(units[index]) {
            index += 1
        }
        return index
    }

    func isBlank(_ line: Int) -> Bool {
        indentRunEnd(line) == lines[line].contentEnd
    }

    func isWhitespaceOnly(_ line: Int) -> Bool {
        var index = lines[line].start
        let end = lines[line].contentEnd
        while index < end {
            if units[index] != 32, units[index] != 9 { return false }
            index += 1
        }
        return true
    }

    func expandedIndent(_ line: Int, tabWidth: Int) -> [UInt16] {
        var result: [UInt16] = []
        for index in lines[line].start..<indentRunEnd(line) {
            if units[index] == 9 {
                result.append(contentsOf: [UInt16](repeating: 32, count: tabWidth))
            } else {
                result.append(units[index])
            }
        }
        return result
    }

    func string(from start: Int, to end: Int) -> String {
        String(decoding: units[start..<end], as: UTF16.self)
    }

    static func isIndentUnit(_ unit: UInt16) -> Bool {
        unit == 32 || unit == 9 || unit == 62
    }

    static func innerSpaces(of expandedIndent: [UInt16]) -> Int {
        var count = 0
        for unit in expandedIndent.reversed() {
            if unit != 32 { break }
            count += 1
        }
        return count
    }
}

nonisolated struct MarkdownListStructure: Sendable {
    nonisolated struct Item: Sendable {
        let line: Int
        let prefix: MarkdownListItemPrefix
        let parent: Int?
        let columns: Int
        let innerIndent: Int
        let quoteCount: Int
        let contentColumn: Int
        var lastLine: Int
        var list: Int

        var normalizedMarkerLength: Int {
            prefix.markerText.utf16.count + 1
        }
    }

    nonisolated struct List: Sendable {
        var items: [Int]
        let parent: Int?
    }

    nonisolated struct Fence: Sendable {
        let openLine: Int
        var closeLine: Int?
        let startOffset: Int
        var endOffset: Int
        let indent: [UInt16]
    }

    let text: MarkdownTextLines
    let tabWidth: Int
    private(set) var items: [Item] = []
    private(set) var lists: [List] = []
    private(set) var itemAtLine: [Int?] = []
    private(set) var fences: [Fence] = []
    private(set) var fenceAtLine: [Int?] = []

    init(text: MarkdownTextLines, tabWidth: Int = 4) {
        self.text = text
        self.tabWidth = tabWidth
        var builder = Builder(text: text, tabWidth: tabWidth)
        builder.run()
        items = builder.items
        lists = builder.lists
        itemAtLine = builder.itemAtLine
        fences = builder.fences
        fenceAtLine = builder.fenceAtLine
    }

    init(_ string: String, tabWidth: Int = 4) {
        self.init(text: MarkdownTextLines(string), tabWidth: tabWidth)
    }

    func lineStart(_ line: Int) -> Int {
        text.lines[line].start
    }

    func sublists(of item: Int) -> [Int] {
        lists.indices.filter { lists[$0].parent == item }
    }

    func lastLine(ofList list: Int) -> Int {
        lists[list].items.map { items[$0].lastLine }.max() ?? items[lists[list].items[0]].line
    }

    func isEmpty(item: Int) -> Bool {
        !items[item].prefix.hasContent && items[item].lastLine == items[item].line
    }

    func fence(containingCaret caret: Int) -> Fence? {
        fences.first { $0.startOffset < caret && caret <= $0.endOffset }
    }

    func fence(coveringOffset offset: Int) -> Fence? {
        fences.first { $0.startOffset <= offset && offset < $0.endOffset }
    }

    func outermostList(of item: Int) -> Int {
        var current = item
        while let parent = items[current].parent {
            current = parent
        }
        return items[current].list
    }

    func descendantItems(after item: Int, inList list: Int) -> [Int] {
        var result: [Int] = []
        var index = item + 1
        while index < items.count, isDescendant(index, ofList: list) {
            result.append(index)
            index += 1
        }
        return result
    }

    func isDescendant(_ item: Int, ofList list: Int) -> Bool {
        var current: Int? = item
        while let index = current {
            if items[index].list == list { return true }
            current = items[index].parent
        }
        return false
    }

    func quoteInsideItem(_ item: Int, line: Int, caret: Int) -> Bool {
        let value = items[item]
        let start = text.lines[line].start
        let contentEnd = text.lines[line].contentEnd
        if line == value.line {
            var index = start + value.prefix.contentStart
            while index < contentEnd, text.units[index] == 32 || text.units[index] == 9 {
                index += 1
            }
            return index < contentEnd && text.units[index] == 62 && caret > index
        }
        var column = 0
        for index in start..<text.indentRunEnd(line) {
            if text.units[index] == 9 {
                column += tabWidth
                continue
            }
            if text.units[index] == 62, column >= value.contentColumn, caret > index {
                return true
            }
            column += 1
        }
        return false
    }

    private nonisolated struct Builder {
        let text: MarkdownTextLines
        let tabWidth: Int
        var items: [Item] = []
        var lists: [List] = []
        var itemAtLine: [Int?]
        var fences: [Fence] = []
        var fenceAtLine: [Int?]
        var stack: [Int] = []
        var afterBlank = false
        var openFence: (index: Int, marker: UInt16, length: Int)?
        var lastSibling: [Int: Int] = [:]

        init(text: MarkdownTextLines, tabWidth: Int) {
            self.text = text
            self.tabWidth = tabWidth
            itemAtLine = [Int?](repeating: nil, count: text.count)
            fenceAtLine = [Int?](repeating: nil, count: text.count)
        }

        mutating func run() {
            for line in 0..<text.count {
                process(line: line)
            }
        }

        private mutating func touchStack(line: Int) {
            for index in stack {
                items[index].lastLine = line
            }
        }

        private mutating func process(line: Int) {
            let bounds = text.lines[line]
            if let open = openFence {
                fenceAtLine[line] = open.index
                itemAtLine[line] = stack.last
                if isClosingFence(line: line, marker: open.marker, length: open.length) {
                    fences[open.index].closeLine = line
                    fences[open.index].endOffset = bounds.contentEnd
                    openFence = nil
                    touchStack(line: line)
                } else if !text.isBlank(line) {
                    touchStack(line: line)
                }
                return
            }

            let runEnd = text.indentRunEnd(line)
            if runEnd == bounds.contentEnd {
                afterBlank = true
                return
            }

            let indent = measureIndent(line: line, runEnd: runEnd)
            let parsed = MarkdownListItemPrefix.parse(units: text.units[bounds.start..<bounds.contentEnd])
            let base = stack.last.map { items[$0].contentColumn } ?? indent.quoteBase
            let candidate = (parsed != nil && indent.columns - base < 4) ? parsed : nil

            if let prefix = candidate {
                while let top = stack.last,
                      items[top].contentColumn > indent.columns || leaves(top, quoteColumns: indent.quoteColumns) {
                    stack.removeLast()
                }
                let parent = stack.last
                let index = items.count
                let sameListAsSibling = siblingList(
                    for: prefix,
                    quoteCount: indent.quoteColumns.count,
                    parent: parent,
                    line: line
                )
                let listIndex: Int
                if let existing = sameListAsSibling {
                    listIndex = existing
                    lists[existing].items.append(index)
                } else {
                    listIndex = lists.count
                    lists.append(List(items: [index], parent: parent))
                }
                items.append(Item(
                    line: line,
                    prefix: prefix,
                    parent: parent,
                    columns: indent.columns,
                    innerIndent: indent.inner,
                    quoteCount: indent.quoteColumns.count,
                    contentColumn: indent.columns + prefix.markerWidth,
                    lastLine: line,
                    list: listIndex
                ))
                lastSibling[parent ?? -1] = index
                stack.append(index)
                itemAtLine[line] = index
                afterBlank = false
                touchStack(line: line)
                openFenceIfNeeded(line: line, contentStart: bounds.start + prefix.contentStart)
                return
            }

            let startsBlock = startsNewBlock(at: runEnd, lineEnd: bounds.contentEnd)
            var strict = afterBlank
            while let top = stack.last {
                let tooShallow = items[top].contentColumn > indent.columns
                let emptyAndOpen = !items[top].prefix.hasContent && items[top].lastLine == items[top].line
                if leaves(top, quoteColumns: indent.quoteColumns)
                    || (tooShallow && (strict || startsBlock || emptyAndOpen)) {
                    if emptyAndOpen {
                        strict = true
                    }
                    stack.removeLast()
                } else {
                    break
                }
            }
            afterBlank = false
            itemAtLine[line] = stack.last
            touchStack(line: line)
            openFenceIfNeeded(line: line, contentStart: runEnd)
        }

        private func measureIndent(line: Int, runEnd: Int) -> (columns: Int, inner: Int, quoteColumns: [Int], quoteBase: Int) {
            var columns = 0
            var quoteEnd = 0
            var quoteColumns: [Int] = []
            for index in text.lines[line].start..<runEnd {
                let unit = text.units[index]
                if unit == 9 {
                    columns += tabWidth
                    continue
                }
                if unit == 62 {
                    quoteColumns.append(columns)
                    quoteEnd = columns + 1
                }
                columns += 1
            }
            return (columns, columns - quoteEnd, quoteColumns, quoteColumns.isEmpty ? 0 : quoteEnd + 1)
        }

        private func leaves(_ item: Int, quoteColumns: [Int]) -> Bool {
            let value = items[item]
            if quoteColumns.count < value.quoteCount { return true }
            if quoteColumns.count > value.quoteCount {
                return quoteColumns[value.quoteCount] < value.contentColumn
            }
            return false
        }

        private func siblingList(for prefix: MarkdownListItemPrefix, quoteCount: Int, parent: Int?, line: Int) -> Int? {
            guard let sibling = lastSibling[parent ?? -1] else { return nil }
            let previous = items[sibling]
            guard previous.quoteCount == quoteCount, previous.prefix.isSameListKind(as: prefix) else { return nil }
            var between = previous.lastLine + 1
            while between < line {
                if !text.isBlank(between) { return nil }
                between += 1
            }
            return previous.list
        }

        private func startsNewBlock(at index: Int, lineEnd: Int) -> Bool {
            guard index < lineEnd else { return false }
            let unit = text.units[index]
            if unit == 35 {
                var count = 0
                var cursor = index
                while cursor < lineEnd, text.units[cursor] == 35 {
                    count += 1
                    cursor += 1
                }
                return count <= 6 && (cursor == lineEnd || text.units[cursor] == 32 || text.units[cursor] == 9)
            }
            if fenceMarker(at: index, lineEnd: lineEnd) != nil { return true }
            if unit == 45 || unit == 42 || unit == 95 {
                var markers = 0
                for cursor in index..<lineEnd {
                    if text.units[cursor] == unit {
                        markers += 1
                    } else if text.units[cursor] != 32, text.units[cursor] != 9 {
                        return false
                    }
                }
                return markers >= 3
            }
            return false
        }

        private func fenceMarker(at index: Int, lineEnd: Int) -> (marker: UInt16, length: Int)? {
            guard index < lineEnd else { return nil }
            let marker = text.units[index]
            guard marker == 96 || marker == 126 else { return nil }
            var cursor = index
            while cursor < lineEnd, text.units[cursor] == marker {
                cursor += 1
            }
            let length = cursor - index
            guard length >= 3 else { return nil }
            if marker == 96 {
                for rest in cursor..<lineEnd where text.units[rest] == 96 {
                    return nil
                }
            }
            return (marker, length)
        }

        private func isClosingFence(line: Int, marker: UInt16, length: Int) -> Bool {
            let end = text.lines[line].contentEnd
            var cursor = text.indentRunEnd(line)
            var run = 0
            while cursor < end, text.units[cursor] == marker {
                run += 1
                cursor += 1
            }
            guard run >= length else { return false }
            while cursor < end {
                if text.units[cursor] != 32, text.units[cursor] != 9 { return false }
                cursor += 1
            }
            return true
        }

        private mutating func openFenceIfNeeded(line: Int, contentStart: Int) {
            let end = text.lines[line].contentEnd
            guard let found = fenceMarker(at: contentStart, lineEnd: end) else { return }
            let lineStart = text.lines[line].start
            let indent = text.units[lineStart..<contentStart].map { unit -> UInt16 in
                unit == 62 || unit == 9 || unit == 32 ? unit : 32
            }
            fences.append(Fence(
                openLine: line,
                closeLine: nil,
                startOffset: contentStart,
                endOffset: text.units.count,
                indent: indent
            ))
            fenceAtLine[line] = fences.count - 1
            openFence = (fences.count - 1, found.marker, found.length)
        }
    }
}
