import Foundation

nonisolated enum MarkdownBlockLexer {
    static func scan(_ text: String) -> MarkdownDocumentScan {
        scan(units: Array(text.utf16))
    }

    static func scan(_ text: NSString) -> MarkdownDocumentScan {
        var units = [UInt16](repeating: 0, count: text.length)
        text.getCharacters(&units, range: NSRange(location: 0, length: text.length))
        return scan(units: units)
    }

    static func scan(units: [UInt16]) -> MarkdownDocumentScan {
        var scanner = BlockScanner(units: units)
        scanner.run()
        return scanner.result()
    }

    static func tokens(in text: String) -> [MarkdownToken] {
        scan(text).tokens
    }
}

private nonisolated struct BlockContainer {
    nonisolated enum Kind {
        case quote
        case listItem
    }

    let id: Int
    let kind: Kind
    let contentColumn: Int
    let markerStart: Int
}

private nonisolated struct FenceState {
    let character: UInt16
    let length: Int
    let hasLanguage: Bool
}

private nonisolated struct HTMLBlockState {
    let type: Int
    var scanner: MarkdownHTMLScanner
}

private nonisolated struct QuoteLine {
    let start: Int
    let contentEnd: Int
    let nextStart: Int
    let hasNewline: Bool
}

private nonisolated struct QuoteTracker {
    let id: Int
    var lines: [QuoteLine]
}

private nonisolated struct LineCursor {
    var position: Int
    var column: Int
}

private nonisolated struct ListItemStart {
    let markerRange: NSRange
    let checkboxRange: NSRange?
    let contentColumn: Int
    let next: LineCursor
}

private nonisolated struct TableRow {
    let pipes: [Int]
    let cells: [NSRange]
}

private nonisolated struct BlockScanner {
    private static let htmlBlockNames: Set<String> = [
        "address", "article", "aside", "base", "basefont", "blockquote", "body", "caption", "center", "col",
        "colgroup", "dd", "details", "dialog", "dir", "div", "dl", "dt", "fieldset", "figcaption", "figure",
        "footer", "form", "frame", "frameset", "h1", "h2", "h3", "h4", "h5", "h6", "head", "header", "hr", "html",
        "iframe", "legend", "li", "link", "main", "menu", "menuitem", "nav", "noframes", "ol", "optgroup", "option",
        "p", "param", "section", "source", "summary", "table", "tbody", "td", "tfoot", "th", "thead", "title", "tr",
        "track", "ul"
    ]

    private static let rawHTMLNames: Set<String> = ["script", "pre", "style", "textarea"]

    private let units: [UInt16]
    private var tokens: [MarkdownToken] = []
    private var headers: [MarkdownHeaderBlock] = []
    private var containers: [BlockContainer] = []
    private var nextContainerId = 0
    private var paragraph: [NSRange] = []
    private var fence: FenceState?
    private var html: HTMLBlockState?
    private var tableOpen = false
    private var afterIndentedCode = false
    private var quoteTracker: QuoteTracker?

    init(units: [UInt16]) {
        self.units = units
    }

    func result() -> MarkdownDocumentScan {
        MarkdownDocumentScan(tokens: tokens.sortedOuterFirst(), headers: headers)
    }

    mutating func run() {
        let count = units.count
        var lineStart = scanFrontMatter() ?? 0
        while lineStart < count {
            var lineEnd = lineStart
            while lineEnd < count, units[lineEnd] != MarkdownChar.newline {
                lineEnd += 1
            }
            let hasNewline = lineEnd < count
            let nextStart = hasNewline ? lineEnd + 1 : count
            var contentEnd = lineEnd
            if contentEnd > lineStart, units[contentEnd - 1] == MarkdownChar.carriageReturn {
                contentEnd -= 1
            }
            processLine(start: lineStart, end: contentEnd, nextStart: nextStart, hasNewline: hasNewline)
            lineStart = nextStart
        }
        closeContainers(to: 0)
        closeLeafBlocks()
        flushQuote()
    }

    private mutating func scanFrontMatter() -> Int? {
        let count = units.count
        guard count >= 3 else { return nil }
        let delimiter = units[0]
        guard delimiter == MarkdownChar.dash || delimiter == MarkdownChar.plus else { return nil }
        guard units[1] == delimiter, units[2] == delimiter else { return nil }
        var openEnd = 3
        while openEnd < count, MarkdownChar.isSpaceOrTab(units[openEnd]) {
            openEnd += 1
        }
        guard openEnd == count || MarkdownChar.isLineBreak(units[openEnd]) else { return nil }
        guard openEnd < count else { return nil }
        var lineStart = openEnd + 1
        if units[openEnd] == MarkdownChar.carriageReturn, lineStart < count, units[lineStart] == MarkdownChar.newline {
            lineStart += 1
        }
        let contentStart = lineStart
        while lineStart < count {
            var lineEnd = lineStart
            while lineEnd < count, units[lineEnd] != MarkdownChar.newline {
                lineEnd += 1
            }
            if isFrontMatterClose(from: lineStart, to: lineEnd, delimiter: delimiter) {
                tokens.append(MarkdownToken(.frontMatterDelimiter, from: 0, to: 3))
                if lineStart > contentStart {
                    var contentEnd = lineStart - 1
                    if contentEnd > contentStart, units[contentEnd - 1] == MarkdownChar.carriageReturn {
                        contentEnd -= 1
                    }
                    if contentEnd > contentStart {
                        tokens.append(MarkdownToken(.frontMatterContent, from: contentStart, to: contentEnd))
                    }
                }
                tokens.append(MarkdownToken(.frontMatterDelimiter, from: lineStart, to: lineStart + 3))
                return lineEnd < count ? lineEnd + 1 : count
            }
            lineStart = lineEnd < count ? lineEnd + 1 : count
        }
        return nil
    }

    private func isFrontMatterClose(from start: Int, to end: Int, delimiter: UInt16) -> Bool {
        guard end - start >= 3 else { return false }
        let first = units[start]
        let closing = delimiter == MarkdownChar.dash ? (first == MarkdownChar.dash || first == MarkdownChar.dot) : first == delimiter
        guard closing, units[start + 1] == first, units[start + 2] == first else { return false }
        var index = start + 3
        while index < end {
            if !MarkdownChar.isWhitespace(units[index]) { return false }
            index += 1
        }
        return true
    }

    private mutating func processLine(start: Int, end: Int, nextStart: Int, hasNewline: Bool) {
        var cursor = LineCursor(position: start, column: 0)
        let matched = matchContainers(&cursor, end: end)
        handleLine(&cursor, matched: matched, end: end)
        trackQuote(start: start, end: end, nextStart: nextStart, hasNewline: hasNewline)
    }

    private mutating func matchContainers(_ cursor: inout LineCursor, end: Int) -> Int {
        var matched = 0
        while matched < containers.count {
            let container = containers[matched]
            switch container.kind {
            case .quote:
                var probe = cursor
                var spaces = 0
                while probe.position < end, units[probe.position] == MarkdownChar.space, spaces < 3 {
                    consume(&probe)
                    spaces += 1
                }
                guard probe.position < end, units[probe.position] == MarkdownChar.greater else { return matched }
                tokens.append(MarkdownToken(.blockQuoteMarker, from: probe.position, to: probe.position + 1))
                consume(&probe)
                if probe.position < end, MarkdownChar.isSpaceOrTab(units[probe.position]) {
                    consume(&probe)
                }
                cursor = probe
            case .listItem:
                if isBlank(from: cursor.position, to: end) {
                    matched += 1
                    continue
                }
                var probe = cursor
                while probe.position < end, MarkdownChar.isSpaceOrTab(units[probe.position]),
                      probe.column < container.contentColumn {
                    consume(&probe)
                }
                guard probe.column >= container.contentColumn else { return matched }
                cursor = probe
            }
            matched += 1
        }
        return matched
    }

    private func consume(_ cursor: inout LineCursor) {
        if units[cursor.position] == MarkdownChar.tab {
            cursor.column = (cursor.column / 4 + 1) * 4
        } else {
            cursor.column += 1
        }
        cursor.position += 1
    }

    private func isBlank(from start: Int, to end: Int) -> Bool {
        var index = start
        while index < end {
            if !MarkdownChar.isSpaceOrTab(units[index]) { return false }
            index += 1
        }
        return true
    }

    private mutating func handleLine(_ cursor: inout LineCursor, matched: Int, end: Int) {
        let allMatched = matched == containers.count
        if allMatched {
            if let state = fence {
                processFenceLine(state, cursor: cursor, end: end)
                return
            }
            if processHTMLLine(cursor: cursor, end: end) {
                return
            }
        }
        if isBlank(from: cursor.position, to: end) {
            closeContainers(to: matched)
            closeLeafBlocks()
            return
        }

        var started = false
        while true {
            var probe = cursor
            while probe.position < end, MarkdownChar.isSpaceOrTab(units[probe.position]) {
                consume(&probe)
            }
            guard probe.position < end, probe.column - cursor.column < 4 else { break }
            if units[probe.position] == MarkdownChar.greater {
                if !started {
                    closeContainers(to: matched)
                }
                closeLeafBlocks()
                started = true
                tokens.append(MarkdownToken(.blockQuoteMarker, from: probe.position, to: probe.position + 1))
                let markerStart = probe.position
                consume(&probe)
                if probe.position < end, MarkdownChar.isSpaceOrTab(units[probe.position]) {
                    consume(&probe)
                }
                containers.append(
                    BlockContainer(id: nextContainerId, kind: .quote, contentColumn: probe.column, markerStart: markerStart)
                )
                nextContainerId += 1
                cursor = probe
                continue
            }
            let interruptsParagraph = !paragraph.isEmpty
                && (started || matched == containers.count || containers[matched].kind != .listItem)
            if let item = listItemStart(at: probe, end: end, paragraphOpen: interruptsParagraph) {
                if !started {
                    closeContainers(to: matched)
                }
                closeLeafBlocks()
                started = true
                tokens.append(MarkdownToken(.listMarker, item.markerRange))
                if let checkboxRange = item.checkboxRange {
                    tokens.append(MarkdownToken(.checkbox, checkboxRange))
                }
                containers.append(
                    BlockContainer(id: nextContainerId, kind: .listItem, contentColumn: item.contentColumn, markerStart: probe.position)
                )
                nextContainerId += 1
                cursor = item.next
                continue
            }
            break
        }

        var lazy = false
        if !started, matched < containers.count {
            if !paragraph.isEmpty, canContinueParagraphLazily(cursor: cursor, end: end) {
                lazy = true
            } else {
                closeContainers(to: matched)
                closeLeafBlocks()
            }
        }
        if started, isBlank(from: cursor.position, to: end) {
            return
        }
        processLeaf(cursor: cursor, end: end, lazy: lazy)
    }

    private mutating func processLeaf(cursor: LineCursor, end: Int, lazy: Bool) {
        var probe = cursor
        while probe.position < end, MarkdownChar.isSpaceOrTab(units[probe.position]) {
            consume(&probe)
        }
        let first = probe.position
        let indent = probe.column - cursor.column
        let paragraphOpen = !paragraph.isEmpty

        if lazy {
            paragraph.append(NSRange(location: first, length: end - first))
            return
        }

        if tableOpen {
            if indent < 4, !startsBlockInterruptingTable(at: first, end: end) {
                emitTableRow(from: first, to: end)
                return
            }
            tableOpen = false
        }

        if indent >= 4 {
            if !paragraphOpen {
                if !afterIndentedCode, let marker = fenceMarker(at: first, end: end) {
                    openFence(at: first, end: end, marker: marker)
                    return
                }
                var codeStart = cursor
                while codeStart.position < end, MarkdownChar.isSpaceOrTab(units[codeStart.position]),
                      codeStart.column < cursor.column + 4 {
                    consume(&codeStart)
                }
                tokens.append(MarkdownToken(.codeBlock, from: codeStart.position, to: end))
                afterIndentedCode = true
                return
            }
            paragraph.append(NSRange(location: first, length: end - first))
            return
        }
        afterIndentedCode = false

        if let marker = fenceMarker(at: first, end: end) {
            closeLeafBlocks()
            openFence(at: first, end: end, marker: marker)
            return
        }
        if processATXHeader(at: first, end: end) {
            return
        }
        if paragraphOpen, let underline = setextUnderline(at: first, end: end) {
            convertParagraphToSetext(level: underline.level, underlineStart: first, underlineEnd: underline.end)
            return
        }
        if let ruleEnd = horizontalRuleEnd(at: first, end: end) {
            closeLeafBlocks()
            tokens.append(MarkdownToken(.horizontalRule, from: first, to: ruleEnd))
            return
        }
        if let type = htmlBlockType(at: first, end: end, paragraphOpen: paragraphOpen) {
            closeLeafBlocks()
            var state = HTMLBlockState(type: type, scanner: MarkdownHTMLScanner(emitsText: true))
            state.scanner.scan(units, from: cursor.position, to: end, into: &tokens)
            html = htmlBlockEnds(type: type, from: first, to: end) ? nil : state
            return
        }
        if paragraphOpen, openTableIfDelimiterRow(at: first, end: end) {
            return
        }
        if !paragraphOpen, processLinkDefinition(at: first, end: end) {
            return
        }
        paragraph.append(NSRange(location: first, length: end - first))
    }

    private mutating func closeContainers(to count: Int) {
        guard count < containers.count else { return }
        closeLeafBlocks()
        containers.removeSubrange(count...)
    }

    private mutating func closeLeafBlocks() {
        flushParagraph()
        tableOpen = false
        html = nil
        fence = nil
    }

    private mutating func flushParagraph() {
        guard !paragraph.isEmpty else { return }
        tokens.append(contentsOf: MarkdownInlineLexer.tokens(in: units, segments: paragraph))
        paragraph.removeAll(keepingCapacity: true)
    }

    private func canContinueParagraphLazily(cursor: LineCursor, end: Int) -> Bool {
        var probe = cursor
        while probe.position < end, MarkdownChar.isSpaceOrTab(units[probe.position]) {
            consume(&probe)
        }
        if probe.column - cursor.column >= 4 { return true }
        let first = probe.position
        if fenceMarker(at: first, end: end) != nil { return false }
        if atxLevel(at: first, end: end) != nil { return false }
        if horizontalRuleEnd(at: first, end: end) != nil { return false }
        if let type = htmlBlockType(at: first, end: end, paragraphOpen: true), type <= 6 { return false }
        return true
    }

    private func startsBlockInterruptingTable(at first: Int, end: Int) -> Bool {
        if fenceMarker(at: first, end: end) != nil { return true }
        if atxLevel(at: first, end: end) != nil { return true }
        if horizontalRuleEnd(at: first, end: end) != nil { return true }
        if let type = htmlBlockType(at: first, end: end, paragraphOpen: true), type <= 6 { return true }
        return false
    }

    private mutating func trackQuote(start: Int, end: Int, nextStart: Int, hasNewline: Bool) {
        guard let outer = containers.first(where: { $0.kind == .quote }) else {
            flushQuote()
            return
        }
        if let tracker = quoteTracker, tracker.id != outer.id {
            flushQuote()
        }
        var lineStart = start
        if quoteTracker == nil {
            lineStart = outer.markerStart
            quoteTracker = QuoteTracker(id: outer.id, lines: [])
        } else {
            while lineStart < end, MarkdownChar.isSpaceOrTab(units[lineStart]) {
                lineStart += 1
            }
        }
        quoteTracker?.lines.append(QuoteLine(start: lineStart, contentEnd: end, nextStart: nextStart, hasNewline: hasNewline))
    }

    private mutating func flushQuote() {
        guard let tracker = quoteTracker else { return }
        quoteTracker = nil
        for (index, line) in tracker.lines.enumerated() {
            let isLast = index == tracker.lines.count - 1
            if isLast {
                if line.start < line.contentEnd {
                    tokens.append(MarkdownToken(.blockQuote, from: line.start, to: line.contentEnd))
                }
                if line.hasNewline {
                    tokens.append(MarkdownToken(.blockQuote, from: line.contentEnd, to: line.contentEnd + 1))
                }
            } else if line.start < line.nextStart {
                tokens.append(MarkdownToken(.blockQuote, from: line.start, to: line.nextStart))
            }
        }
    }

    private func fenceMarker(at first: Int, end: Int) -> (character: UInt16, length: Int)? {
        guard first < end else { return nil }
        let character = units[first]
        guard character == MarkdownChar.backtick || character == MarkdownChar.tilde else { return nil }
        var index = first
        while index < end, units[index] == character {
            index += 1
        }
        guard index - first >= 3 else { return nil }
        if character == MarkdownChar.backtick {
            var cursor = index
            while cursor < end {
                if units[cursor] == MarkdownChar.backtick { return nil }
                cursor += 1
            }
        }
        return (character, index - first)
    }

    private mutating func openFence(at first: Int, end: Int, marker: (character: UInt16, length: Int)) {
        let markerEnd = first + marker.length
        tokens.append(MarkdownToken(.codeFenceMarker, from: first, to: markerEnd))
        var languageStart = markerEnd
        while languageStart < end, MarkdownChar.isSpaceOrTab(units[languageStart]) {
            languageStart += 1
        }
        var languageEnd = languageStart
        while languageEnd < end, !MarkdownChar.isWhitespace(units[languageEnd]) {
            languageEnd += 1
        }
        if languageEnd > languageStart {
            tokens.append(MarkdownToken(.codeFenceLanguage, from: languageStart, to: languageEnd))
        }
        fence = FenceState(character: marker.character, length: marker.length, hasLanguage: languageEnd > languageStart)
    }

    private mutating func processFenceLine(_ state: FenceState, cursor: LineCursor, end: Int) {
        var first = cursor.position
        while first < end, MarkdownChar.isSpaceOrTab(units[first]) {
            first += 1
        }
        if first < end, units[first] == state.character {
            var runEnd = first
            while runEnd < end, units[runEnd] == state.character {
                runEnd += 1
            }
            if runEnd - first >= state.length, isBlank(from: runEnd, to: end) {
                tokens.append(MarkdownToken(.codeFenceMarker, from: first, to: runEnd))
                fence = nil
                return
            }
        }
        if cursor.position < end {
            tokens.append(MarkdownToken(.codeFenceContent(hasLanguage: state.hasLanguage), from: cursor.position, to: end))
        }
    }

    private mutating func processHTMLLine(cursor: LineCursor, end: Int) -> Bool {
        guard var state = html else { return false }
        if state.type >= 6, isBlank(from: cursor.position, to: end) {
            html = nil
            return false
        }
        state.scanner.scan(units, from: cursor.position, to: end, into: &tokens)
        html = htmlBlockEnds(type: state.type, from: cursor.position, to: end) ? nil : state
        return true
    }

    private func atxLevel(at first: Int, end: Int) -> Int? {
        guard first < end, units[first] == MarkdownChar.hash else { return nil }
        var index = first
        while index < end, units[index] == MarkdownChar.hash {
            index += 1
        }
        let level = index - first
        guard level <= 6 else { return nil }
        guard index == end || MarkdownChar.isSpaceOrTab(units[index]) else { return nil }
        return level
    }

    private mutating func processATXHeader(at first: Int, end: Int) -> Bool {
        guard let level = atxLevel(at: first, end: end) else { return false }
        closeLeafBlocks()
        let markerEnd = first + level
        tokens.append(MarkdownToken(.headerMarker, from: first, to: markerEnd))
        var lineEnd = end
        while lineEnd > markerEnd, MarkdownChar.isSpaceOrTab(units[lineEnd - 1]) {
            lineEnd -= 1
        }
        var contentStart = markerEnd
        while contentStart < lineEnd, MarkdownChar.isSpaceOrTab(units[contentStart]) {
            contentStart += 1
        }
        var contentEnd = lineEnd
        var closingStart = contentEnd
        while closingStart > contentStart, units[closingStart - 1] == MarkdownChar.hash {
            closingStart -= 1
        }
        if closingStart < contentEnd, closingStart == contentStart || MarkdownChar.isSpaceOrTab(units[closingStart - 1]) {
            tokens.append(MarkdownToken(.headerMarker, from: closingStart, to: contentEnd))
            contentEnd = closingStart
            while contentEnd > contentStart, MarkdownChar.isSpaceOrTab(units[contentEnd - 1]) {
                contentEnd -= 1
            }
        }
        let contentRange: NSRange
        if contentEnd > contentStart {
            contentRange = NSRange(location: contentStart, length: contentEnd - contentStart)
            tokens.append(MarkdownToken(.headerContent(level: level), contentRange))
            tokens.append(contentsOf: MarkdownInlineLexer.tokens(in: units, segments: [contentRange]))
        } else {
            contentRange = NSRange(location: markerEnd, length: 0)
        }
        headers.append(
            MarkdownHeaderBlock(
                level: level,
                isSetext: false,
                contentRange: contentRange,
                range: NSRange(location: first, length: lineEnd - first),
                containerPath: containers.map(\.id)
            )
        )
        return true
    }

    private func setextUnderline(at first: Int, end: Int) -> (level: Int, end: Int)? {
        guard first < end else { return nil }
        let character = units[first]
        guard character == MarkdownChar.equals || character == MarkdownChar.dash else { return nil }
        var index = first
        while index < end, units[index] == character {
            index += 1
        }
        guard isBlank(from: index, to: end) else { return nil }
        return (character == MarkdownChar.equals ? 1 : 2, index)
    }

    private mutating func convertParagraphToSetext(level: Int, underlineStart: Int, underlineEnd: Int) {
        var segments = paragraph
        paragraph.removeAll(keepingCapacity: true)
        guard var last = segments.popLast() else { return }
        var lastEnd = last.location + last.length
        while lastEnd > last.location, MarkdownChar.isSpaceOrTab(units[lastEnd - 1]) {
            lastEnd -= 1
        }
        last = NSRange(location: last.location, length: lastEnd - last.location)
        segments.append(last)
        let first = segments[0]
        let contentRange = NSRange(location: first.location, length: lastEnd - first.location)
        tokens.append(MarkdownToken(.headerContent(level: level), contentRange))
        tokens.append(contentsOf: MarkdownInlineLexer.tokens(in: units, segments: segments))
        tokens.append(MarkdownToken(.headerMarker, from: underlineStart, to: underlineEnd))
        headers.append(
            MarkdownHeaderBlock(
                level: level,
                isSetext: true,
                contentRange: contentRange,
                range: NSRange(location: first.location, length: underlineEnd - first.location),
                containerPath: containers.map(\.id)
            )
        )
    }

    private func horizontalRuleEnd(at first: Int, end: Int) -> Int? {
        guard first < end else { return nil }
        let character = units[first]
        guard character == MarkdownChar.star || character == MarkdownChar.dash || character == MarkdownChar.underscore else {
            return nil
        }
        var count = 0
        var lastEnd = first
        var index = first
        while index < end {
            let unit = units[index]
            if unit == character {
                count += 1
                lastEnd = index + 1
            } else if !MarkdownChar.isSpaceOrTab(unit) {
                return nil
            }
            index += 1
        }
        return count >= 3 ? lastEnd : nil
    }

    private func listItemStart(at probe: LineCursor, end: Int, paragraphOpen: Bool) -> ListItemStart? {
        let first = probe.position
        guard first < end else { return nil }
        let unit = units[first]
        guard unit == MarkdownChar.star || unit == MarkdownChar.plus || unit == MarkdownChar.dash
            || MarkdownChar.isASCIIDigit(unit)
        else { return nil }
        if horizontalRuleEnd(at: first, end: end) != nil { return nil }
        let line = String(decoding: units[first..<end], as: UTF16.self)
        guard let prefix = MarkdownListItemPrefix.parse(line: Substring(line)) else { return nil }
        let markerLength = prefix.markerText.utf16.count
        let markerEnd = first + markerLength
        let markerRange = NSRange(location: first, length: markerLength)
        let markerColumn = probe.column + markerLength
        var restStart = markerEnd
        var restColumn = markerColumn
        var whitespaceColumns = 0
        while restStart < end, MarkdownChar.isSpaceOrTab(units[restStart]) {
            let before = restColumn
            restColumn = units[restStart] == MarkdownChar.tab ? (restColumn / 4 + 1) * 4 : restColumn + 1
            whitespaceColumns += restColumn - before
            restStart += 1
        }
        let isEmpty = restStart >= end
        if paragraphOpen {
            if isEmpty { return nil }
            if case .ordered(let number, _) = prefix.marker, number != 1 { return nil }
        }
        if isEmpty {
            return ListItemStart(
                markerRange: markerRange,
                checkboxRange: nil,
                contentColumn: markerColumn + 1,
                next: LineCursor(position: end, column: restColumn)
            )
        }
        if whitespaceColumns >= 5 {
            return ListItemStart(
                markerRange: markerRange,
                checkboxRange: nil,
                contentColumn: markerColumn + 1,
                next: LineCursor(position: markerEnd + 1, column: markerColumn + 1)
            )
        }
        var next = LineCursor(position: restStart, column: restColumn)
        var checkboxRange: NSRange?
        if prefix.checkbox != nil, restStart + 3 <= end {
            checkboxRange = NSRange(location: restStart, length: 3)
            next.position = restStart + 3
            next.column = restColumn + 3
            if next.position < end, units[next.position] == MarkdownChar.space {
                next.position += 1
                next.column += 1
            }
        }
        return ListItemStart(
            markerRange: markerRange,
            checkboxRange: checkboxRange,
            contentColumn: markerColumn + whitespaceColumns,
            next: next
        )
    }

    private func htmlBlockType(at first: Int, end: Int, paragraphOpen: Bool) -> Int? {
        guard first + 1 < end, units[first] == MarkdownChar.less else { return nil }
        let next = units[first + 1]
        if next == MarkdownChar.exclamation {
            if hasLiteral(at: first, end: end, "<!--") { return 2 }
            if hasLiteral(at: first, end: end, "<![CDATA[") { return 5 }
            if first + 2 < end, MarkdownChar.isASCIILetter(units[first + 2]) { return 4 }
            return nil
        }
        if next == MarkdownChar.question { return 3 }
        var index = first + 1
        let closing = units[index] == MarkdownChar.slash
        if closing { index += 1 }
        let nameStart = index
        guard index < end, MarkdownChar.isASCIILetter(units[index]) else { return nil }
        while index < end, MarkdownChar.isASCIIAlphanumeric(units[index]) || units[index] == MarkdownChar.dash {
            index += 1
        }
        let name = String(decoding: units[nameStart..<index], as: UTF16.self).lowercased()
        let afterName = index < end ? units[index] : MarkdownChar.space
        let endsName = MarkdownChar.isSpaceOrTab(afterName) || afterName == MarkdownChar.greater
        if !closing, Self.rawHTMLNames.contains(name), endsName { return 1 }
        if Self.htmlBlockNames.contains(name) {
            let selfClosing = afterName == MarkdownChar.slash && index + 1 < end && units[index + 1] == MarkdownChar.greater
            if endsName || selfClosing { return 6 }
        }
        guard !paragraphOpen,
              let tagEnd = MarkdownHTMLScanner.tagEnd(in: units, from: first, to: end),
              isBlank(from: tagEnd, to: end) else { return nil }
        return 7
    }

    private func htmlBlockEnds(type: Int, from start: Int, to end: Int) -> Bool {
        switch type {
        case 1:
            return containsLiteral("</script>", from: start, to: end, caseInsensitive: true)
                || containsLiteral("</pre>", from: start, to: end, caseInsensitive: true)
                || containsLiteral("</style>", from: start, to: end, caseInsensitive: true)
                || containsLiteral("</textarea>", from: start, to: end, caseInsensitive: true)
        case 2:
            return containsLiteral("-->", from: start, to: end, caseInsensitive: false)
        case 3:
            return containsLiteral("?>", from: start, to: end, caseInsensitive: false)
        case 4:
            return containsLiteral(">", from: start, to: end, caseInsensitive: false)
        case 5:
            return containsLiteral("]]>", from: start, to: end, caseInsensitive: false)
        default:
            return false
        }
    }

    private func hasLiteral(at index: Int, end: Int, _ literal: StaticString) -> Bool {
        let length = literal.utf8CodeUnitCount
        guard index + length <= end else { return false }
        return literal.withUTF8Buffer { buffer in
            for offset in 0..<length where units[index + offset] != UInt16(buffer[offset]) {
                return false
            }
            return true
        }
    }

    private func containsLiteral(_ literal: StaticString, from start: Int, to end: Int, caseInsensitive: Bool) -> Bool {
        let length = literal.utf8CodeUnitCount
        guard end - start >= length else { return false }
        var index = start
        while index + length <= end {
            let matches = literal.withUTF8Buffer { buffer in
                for offset in 0..<length {
                    var unit = units[index + offset]
                    if caseInsensitive, unit >= 65, unit <= 90 { unit += 32 }
                    if unit != UInt16(buffer[offset]) { return false }
                }
                return true
            }
            if matches { return true }
            index += 1
        }
        return false
    }

    private func tableRow(from first: Int, to end: Int) -> TableRow {
        var upper = end
        while upper > first, MarkdownChar.isSpaceOrTab(units[upper - 1]) {
            upper -= 1
        }
        var pipes: [Int] = []
        var backslashes = 0
        var index = first
        while index < upper {
            let unit = units[index]
            if unit == MarkdownChar.backslash {
                backslashes += 1
            } else {
                if unit == MarkdownChar.pipe, backslashes % 2 == 0 {
                    pipes.append(index)
                }
                backslashes = 0
            }
            index += 1
        }
        var cells: [NSRange] = []
        var cellStart = first
        for pipe in pipes {
            cells.append(trimmedRange(from: cellStart, to: pipe))
            cellStart = pipe + 1
        }
        cells.append(trimmedRange(from: cellStart, to: upper))
        if let firstPipe = pipes.first, firstPipe == first {
            cells.removeFirst()
        }
        if let lastPipe = pipes.last, lastPipe == upper - 1, !cells.isEmpty {
            cells.removeLast()
        }
        return TableRow(pipes: pipes, cells: cells)
    }

    private func trimmedRange(from start: Int, to end: Int) -> NSRange {
        var lower = start
        var upper = end
        while lower < upper, MarkdownChar.isSpaceOrTab(units[lower]) {
            lower += 1
        }
        while upper > lower, MarkdownChar.isSpaceOrTab(units[upper - 1]) {
            upper -= 1
        }
        return NSRange(location: lower, length: upper - lower)
    }

    private func isDelimiterCell(_ cell: NSRange) -> Bool {
        var index = cell.location
        let end = cell.location + cell.length
        if index < end, units[index] == MarkdownChar.colon {
            index += 1
        }
        let dashStart = index
        while index < end, units[index] == MarkdownChar.dash {
            index += 1
        }
        guard index > dashStart else { return false }
        if index < end, units[index] == MarkdownChar.colon {
            index += 1
        }
        return index == end
    }

    private mutating func openTableIfDelimiterRow(at first: Int, end: Int) -> Bool {
        guard let header = paragraph.last else { return false }
        let headerRow = tableRow(from: header.location, to: header.location + header.length)
        guard !headerRow.pipes.isEmpty, !headerRow.cells.isEmpty else { return false }
        let delimiterRow = tableRow(from: first, to: end)
        guard !delimiterRow.pipes.isEmpty, delimiterRow.cells.count == headerRow.cells.count,
              delimiterRow.cells.allSatisfy({ isDelimiterCell($0) })
        else { return false }
        paragraph.removeLast()
        flushParagraph()
        emitTableRow(from: header.location, to: header.location + header.length)
        var delimiterEnd = end
        while delimiterEnd > first, MarkdownChar.isSpaceOrTab(units[delimiterEnd - 1]) {
            delimiterEnd -= 1
        }
        tokens.append(MarkdownToken(.tableSeparator, from: first, to: delimiterEnd))
        tableOpen = true
        return true
    }

    private mutating func emitTableRow(from first: Int, to end: Int) {
        let row = tableRow(from: first, to: end)
        for pipe in row.pipes {
            tokens.append(MarkdownToken(.tableSeparator, from: pipe, to: pipe + 1))
        }
        for cell in row.cells where cell.length > 0 {
            tokens.append(contentsOf: MarkdownInlineLexer.tokens(in: units, segments: [cell]))
        }
    }

    private mutating func processLinkDefinition(at first: Int, end: Int) -> Bool {
        guard first < end, units[first] == MarkdownChar.openBracket else { return false }
        var index = first + 1
        var labelHasContent = false
        while index < end, units[index] != MarkdownChar.closeBracket {
            if units[index] == MarkdownChar.openBracket { return false }
            if units[index] == MarkdownChar.backslash { index += 1 }
            if index < end, !MarkdownChar.isWhitespace(units[index]) { labelHasContent = true }
            index += 1
        }
        guard labelHasContent, index + 1 < end, units[index] == MarkdownChar.closeBracket,
              units[index + 1] == MarkdownChar.colon
        else { return false }
        let labelEnd = index + 1
        index += 2
        while index < end, MarkdownChar.isSpaceOrTab(units[index]) {
            index += 1
        }
        let destinationStart = index
        if index < end, units[index] == MarkdownChar.less {
            index += 1
            while index < end, units[index] != MarkdownChar.greater {
                if MarkdownChar.isWhitespace(units[index]) || units[index] == MarkdownChar.less { return false }
                index += 1
            }
            guard index < end else { return false }
            index += 1
        } else {
            while index < end, !MarkdownChar.isWhitespace(units[index]) {
                index += 1
            }
        }
        let destinationEnd = index
        guard destinationEnd > destinationStart else { return false }
        while index < end, MarkdownChar.isSpaceOrTab(units[index]) {
            index += 1
        }
        var titleRange: NSRange?
        if index < end {
            guard index > destinationEnd else { return false }
            let opening = units[index]
            let closing: UInt16
            switch opening {
            case MarkdownChar.doubleQuote: closing = MarkdownChar.doubleQuote
            case MarkdownChar.singleQuote: closing = MarkdownChar.singleQuote
            case MarkdownChar.openParen: closing = MarkdownChar.closeParen
            default: return false
            }
            var cursor = index + 1
            while cursor < end, units[cursor] != closing {
                if units[cursor] == MarkdownChar.backslash { cursor += 1 }
                cursor += 1
            }
            guard cursor < end, isBlank(from: cursor + 1, to: end) else { return false }
            titleRange = NSRange(location: index, length: cursor + 1 - index)
        }
        tokens.append(MarkdownToken(.linkLabel, from: first, to: labelEnd))
        tokens.append(MarkdownToken(.linkDestination, from: destinationStart, to: destinationEnd))
        if let titleRange {
            tokens.append(MarkdownToken(.linkTitle, titleRange))
        }
        return true
    }
}
