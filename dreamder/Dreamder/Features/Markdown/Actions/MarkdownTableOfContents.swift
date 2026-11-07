import Foundation

nonisolated enum MarkdownTableOfContents {
    static let delimiter = "<!-- TOC -->"

    private struct OmitMarkerMatcher {
        let units: [UInt16]
        var cursor = 0

        init(_ text: String) {
            var units = Array(text.lowercased().utf16)
            while let last = units.last, MarkdownText.isJavaWhitespace(last) { units.removeLast() }
            var start = 0
            while start < units.count, MarkdownText.isJavaWhitespace(units[start]) { start += 1 }
            self.units = Array(units[start...])
        }

        mutating func literal(_ value: String) -> Bool {
            let expected = Array(value.utf16)
            guard units[cursor...].starts(with: expected) else { return false }
            cursor += expected.count
            return true
        }

        mutating func whitespace(atLeast minimum: Int) -> Bool {
            var count = 0
            while cursor < units.count, MarkdownText.isJavaWhitespace(units[cursor]) {
                cursor += 1
                count += 1
            }
            return count >= minimum
        }

        mutating func matchesWhole() -> Bool {
            guard literal("<!--"), whitespace(atLeast: 0), literal("omit"), whitespace(atLeast: 1) else { return false }
            guard literal("from") || literal("in") else { return false }
            guard whitespace(atLeast: 1), literal("toc"), whitespace(atLeast: 0), literal("-->") else { return false }
            return cursor == units.count
        }
    }

    static func isOmitMarker(_ text: String) -> Bool {
        var matcher = OmitMarkerMatcher(text)
        return matcher.matchesWhole()
    }

    static func build(text: String, indentSize: Int = 2) -> String {
        let document = MarkdownDocument(text)
        var headers: [(block: Int, content: String, raw: String)] = []
        for (index, block) in document.blocks.enumerated() where block.isHeading {
            guard let content = document.headerContent(ofBlock: index),
                  let raw = MarkdownHeaderAnchor.rawAnchor(forHeaderContent: content) else { continue }
            headers.append((index, content, raw))
        }
        let anchors = MarkdownHeaderAnchor.uniqueAnchors(forRawAnchors: headers.map(\.raw))
        var lines = [delimiter]
        for (header, anchor) in zip(headers, anchors) {
            let block = document.blocks[header.block]
            guard let level = block.headingLevel,
                  isTopLevel(document: document, block: block),
                  !isOmitted(document: document, blockIndex: header.block, content: header.content),
                  let visible = MarkdownHeaderAnchor.visibleText(forHeaderContent: header.content) else { continue }
            let indent = String(repeating: " ", count: max(level - 1, 0) * max(indentSize, 0))
            lines.append("\(indent)* [\(visible)](#\(anchor))")
        }
        lines.append(delimiter)
        return lines.joined(separator: "\n")
    }

    static func existingRanges(in text: String) -> [NSRange] {
        let document = MarkdownDocument(text)
        let delimiterBlocks = document.blocks.filter { block in
            guard block.kind == .htmlBlock, block.lines.count == 1 else { return false }
            let line = block.lines.lowerBound
            let info = document.infos[line]
            guard info.quoteDepth == 0, info.listItem == nil else { return false }
            return document.text.string(info.bodyStart..<document.text.lines[line].contentEnd) == delimiter
        }
        var ranges: [NSRange] = []
        var index = 0
        while index + 1 < delimiterBlocks.count {
            let first = delimiterBlocks[index].lines.lowerBound
            let last = delimiterBlocks[index + 1].lines.lowerBound
            let start = document.infos[first].bodyStart
            let end = document.text.lines[last].contentEnd
            ranges.append(NSRange(location: start, length: end - start))
            index += 2
        }
        return ranges
    }

    static func generate(text: String, caret: Int, indentSize: Int = 2) -> MarkdownActionResult {
        let toc = build(text: text, indentSize: indentSize)
        var buffer = MarkdownEditBuffer(text)
        let clampedCaret = min(max(caret, 0), buffer.length)
        buffer.settle(NSRange(location: clampedCaret, length: 0))
        let ranges = existingRanges(in: text)
        if ranges.isEmpty {
            buffer.insert(toc, at: clampedCaret)
        } else {
            for range in ranges.reversed() {
                buffer.replace(range.location..<(range.location + range.length), with: toc)
            }
        }
        return buffer.resultWithSettledSelections()
    }

    static func isOmitted(document: MarkdownDocument, blockIndex: Int, content: String) -> Bool {
        hasInlineMarker(content) || hasMarkerAbove(document: document, blockIndex: blockIndex)
    }

    private static func hasInlineMarker(_ content: String) -> Bool {
        let units = Array(content.utf16)
        let nodes = MarkdownInlineParser.parse(units, base: 0)
        let children = MarkdownHeaderAnchor.topLevelNodes(nodes, in: 0..<units.count)
        var run: [UInt16] = []
        var runEnd = -1
        for node in children {
            guard node.kind == .htmlTag else {
                if isOmitMarker(String(decoding: run, as: UTF16.self)) { return true }
                run = []
                continue
            }
            if node.range.location != runEnd {
                if isOmitMarker(String(decoding: run, as: UTF16.self)) { return true }
                run = []
            }
            run.append(contentsOf: units[node.range.location..<node.upperBound])
            runEnd = node.upperBound
        }
        return isOmitMarker(String(decoding: run, as: UTF16.self))
    }

    private static func hasMarkerAbove(document: MarkdownDocument, blockIndex: Int) -> Bool {
        guard blockIndex > 0 else { return false }
        let previous = document.blocks[blockIndex - 1]
        let block = document.blocks[blockIndex]
        guard previous.kind == .htmlBlock, previous.lines.upperBound == block.lines.lowerBound else { return false }
        let lastLine = document.text.lines[previous.lines.upperBound - 1]
        let start = document.infos[previous.lines.upperBound - 1].bodyStart
        return isOmitMarker(document.text.string(start..<lastLine.contentEnd))
    }

    private static func isTopLevel(document: MarkdownDocument, block: MarkdownBlock) -> Bool {
        let line = block.lines.lowerBound
        let info = document.infos[line]
        guard info.quoteDepth == 0, info.listItem == nil else { return false }
        let indent = leadingColumns(document.text, line: line)
        guard indent > 0 else { return true }
        var cursor = line - 1
        while cursor >= 0 {
            let candidate = document.infos[cursor]
            if candidate.quoteDepth == 0, let item = candidate.listItem {
                if indent >= item.contentStart { return false }
                if item.indentLength == 0 { return true }
            } else if !candidate.isBlank, candidate.quoteDepth > 0 || leadingColumns(document.text, line: cursor) == 0 {
                return true
            }
            cursor -= 1
        }
        return true
    }

    private static func leadingColumns(_ text: MarkdownText, line: Int) -> Int {
        let info = text.lines[line]
        var columns = 0
        var index = info.start
        while index < info.contentEnd, MarkdownText.isSpaceOrTab(text.units[index]) {
            columns += text.units[index] == MarkdownText.tab ? 4 : 1
            index += 1
        }
        return columns
    }
}
