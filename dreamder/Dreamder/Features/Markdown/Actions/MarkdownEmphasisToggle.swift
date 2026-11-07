import Foundation

nonisolated enum MarkdownEmphasisStyle: Sendable {
    case asterisks
    case underscores
}

nonisolated enum MarkdownEmphasisKind: Sendable, CaseIterable {
    case bold
    case italic
    case strikethrough
    case codeSpan
}

nonisolated enum MarkdownEmphasisToggle {
    static func isEnabled(
        _ kind: MarkdownEmphasisKind,
        text: String,
        selections: [NSRange],
        style: MarkdownEmphasisStyle = .asterisks
    ) -> Bool {
        evaluation(kind, text: text, selections: selections, style: style).isEnabled
    }

    static func isSelected(
        _ kind: MarkdownEmphasisKind,
        text: String,
        selections: [NSRange],
        style: MarkdownEmphasisStyle = .asterisks
    ) -> Bool {
        evaluation(kind, text: text, selections: selections, style: style).isSelected
    }

    static func toggle(
        _ kind: MarkdownEmphasisKind,
        text: String,
        selections: [NSRange],
        style: MarkdownEmphasisStyle = .asterisks
    ) -> MarkdownActionResult? {
        let units = Array(text.utf16)
        let carets = normalizedCarets(selections, length: units.count)
        let context = MarkdownEmphasisContext(kind: kind, style: style, units: units)
        let evaluation = context.evaluate(carets)
        guard evaluation.isEnabled else { return nil }
        var session = MarkdownEmphasisSession(units: units, carets: carets)
        for index in carets.indices.reversed() {
            session.process(caret: index, kind: kind, style: style, state: !evaluation.isSelected)
        }
        return session.result
    }

    private static func evaluation(
        _ kind: MarkdownEmphasisKind,
        text: String,
        selections: [NSRange],
        style: MarkdownEmphasisStyle
    ) -> MarkdownEmphasisEvaluation {
        let units = Array(text.utf16)
        let context = MarkdownEmphasisContext(kind: kind, style: style, units: units)
        return context.evaluate(normalizedCarets(selections, length: units.count))
    }

    private static func normalizedCarets(_ selections: [NSRange], length: Int) -> [Range<Int>] {
        selections
            .map { selection in
                let lower = min(max(selection.location, 0), length)
                let upper = min(max(selection.location + selection.length, lower), length)
                return lower..<upper
            }
            .sorted { left, right in
                left.lowerBound != right.lowerBound
                    ? left.lowerBound < right.lowerBound
                    : left.upperBound < right.upperBound
            }
    }
}

fileprivate nonisolated struct MarkdownEmphasisEvaluation: Sendable {
    let isEnabled: Bool
    let isSelected: Bool
}

fileprivate nonisolated struct MarkdownEmphasisMarker: Sendable {
    var start: Int
    var end: Int

    var range: Range<Int> { start..<end }

    mutating func inserted(length: Int, at offset: Int) {
        if start == end {
            if offset < start {
                start += length
                end += length
            }
            return
        }
        if offset <= start {
            start += length
        }
        if offset < end {
            end += length
        }
    }

    mutating func deleted(_ range: Range<Int>) {
        start = Self.collapsed(start, deleting: range)
        end = Self.collapsed(end, deleting: range)
    }

    mutating func shift(by length: Int) {
        start += length
        end += length
    }

    private static func collapsed(_ position: Int, deleting range: Range<Int>) -> Int {
        if position >= range.upperBound {
            return position - range.count
        }
        if position > range.lowerBound {
            return range.lowerBound
        }
        return position
    }
}

fileprivate nonisolated struct MarkdownEmphasisRegion: Sendable {
    let blockIndex: Int
    let isTableCell: Bool
    let extent: Range<Int>
    let nodes: [MarkdownInlineNode]
    let leaves: [Range<Int>]
}

fileprivate nonisolated struct MarkdownEmphasisContext: Sendable {
    let kind: MarkdownEmphasisKind
    let style: MarkdownEmphasisStyle
    let text: MarkdownText
    let document: MarkdownDocument
    let regions: [MarkdownEmphasisRegion]

    init(kind: MarkdownEmphasisKind, style: MarkdownEmphasisStyle, units: [UInt16]) {
        let text = MarkdownText(units: units)
        let document = MarkdownDocument(text)
        var regions: [MarkdownEmphasisRegion] = []
        for (index, block) in document.blocks.enumerated() {
            switch block.kind {
            case .paragraph, .atxHeading, .setextHeading:
                guard let region = document.inlineRegion(ofBlock: index) else { continue }
                regions.append(
                    Self.makeRegion(blockIndex: index, isTableCell: false, base: region.base, units: region.units)
                )
            case .table:
                let separatorLine = block.lines.lowerBound + 1
                for line in block.lines where line != separatorLine {
                    let split = MarkdownTableRowSplitter.split(units, body: document.bodyRange(line: line))
                    for cell in split.cells where !cell.isEmpty {
                        regions.append(
                            Self.makeRegion(
                                blockIndex: index,
                                isTableCell: true,
                                base: cell.lowerBound,
                                units: Array(units[cell])
                            )
                        )
                    }
                }
            default:
                continue
            }
        }
        self.kind = kind
        self.style = style
        self.text = text
        self.document = document
        self.regions = regions
    }

    var targetNodeKind: MarkdownInlineNode.Kind {
        switch kind {
        case .bold: .strong
        case .italic: .emphasis
        case .strikethrough: .strikethrough
        case .codeSpan: .codeSpan
        }
    }

    var movesToWordBounds: Bool { kind != .codeSpan }

    func evaluate(_ carets: [Range<Int>]) -> MarkdownEmphasisEvaluation {
        guard !carets.isEmpty else {
            return MarkdownEmphasisEvaluation(isEnabled: false, isSelected: false)
        }
        if carets.contains(where: { isProhibited($0) }) {
            return MarkdownEmphasisEvaluation(isEnabled: false, isSelected: false)
        }
        let tableSelections = carets.map { tableSelection($0) }
        if tableSelections.allSatisfy({ $0 != nil }) {
            let ranges = tableSelections.flatMap { $0 ?? [] }
            let selected = !ranges.isEmpty && ranges.allSatisfy { formattingParent($0) != nil }
            return MarkdownEmphasisEvaluation(isEnabled: true, isSelected: selected)
        }
        let parents = carets.map { formattingParent($0) }
        let hasMissing = parents.contains { $0 == nil }
        let hasValid = parents.contains { $0 != nil }
        if hasMissing && hasValid {
            return MarkdownEmphasisEvaluation(isEnabled: false, isSelected: false)
        }
        return MarkdownEmphasisEvaluation(isEnabled: true, isSelected: !hasMissing)
    }

    func tableSelection(_ caret: Range<Int>) -> [Range<Int>]? {
        guard !caret.isEmpty else { return nil }
        let startOffset = min(caret.lowerBound, max(text.length - 1, 0))
        guard let blockIndex = document.blockIndex(containing: startOffset) else { return nil }
        let block = document.blocks[blockIndex]
        guard block.kind == .table else { return nil }
        let tableStart = document.bodyRange(line: block.lines.lowerBound).lowerBound
        let tableEnd = text.lines[block.lines.upperBound - 1].contentEnd
        guard caret.lowerBound >= tableStart, caret.upperBound <= tableEnd else { return nil }
        var ranges: [Range<Int>] = []
        for region in regions where region.isTableCell && region.blockIndex == blockIndex {
            var lower = max(caret.lowerBound, region.extent.lowerBound)
            var upper = min(caret.upperBound, region.extent.upperBound)
            while lower < upper, MarkdownText.isJavaWhitespace(text.units[lower]) {
                lower += 1
            }
            while lower < upper, MarkdownText.isJavaWhitespace(text.units[upper - 1]) {
                upper -= 1
            }
            if lower < upper {
                ranges.append(lower..<upper)
            }
        }
        return ranges
    }

    func formattingParent(_ range: Range<Int>) -> MarkdownInlineNode? {
        let secondOffset = range.isEmpty ? range.lowerBound : range.upperBound - 1
        guard let first = leafOffset(range.lowerBound), let second = leafOffset(secondOffset) else { return nil }
        if let direct = innermostNode(of: targetNodeKind, containing: first, second) {
            return direct
        }
        if range.isEmpty { return nil }
        guard let region = regions.first(where: { $0.extent.contains(first) && $0.extent.contains(second) }) else {
            return nil
        }
        let common = region.nodes
            .filter { $0.containsChar(at: first) && $0.containsChar(at: second) }
            .min { $0.range.length < $1.range.length }
        let content = region.leaves.filter { leaf in
            leaf.lowerBound >= range.lowerBound && leaf.upperBound <= range.upperBound
                && (common.map { Self.node($0, contains: leaf) } ?? true)
        }
        guard !content.isEmpty else { return nil }
        return region.nodes.first { node in
            node.kind == targetNodeKind
                && node.range.location < range.upperBound
                && node.upperBound > range.lowerBound
                && (common.map { Self.node($0, containsNode: node) } ?? true)
                && content.allSatisfy { Self.node(node, contains: $0) }
        }
    }

    func coversContent(_ selection: Range<Int>, of node: MarkdownInlineNode) -> Bool {
        guard let region = regions.first(where: { $0.extent.contains(node.range.location) }) else { return false }
        let content = region.leaves.filter { Self.node(node, contains: $0) }
        return !content.isEmpty
            && content.allSatisfy { $0.lowerBound >= selection.lowerBound && $0.upperBound <= selection.upperBound }
    }

    private func isProhibited(_ caret: Range<Int>) -> Bool {
        guard let first = leafOffset(caret.lowerBound),
              let second = leafOffset(caret.isEmpty ? caret.lowerBound : caret.upperBound)
        else { return false }
        let prohibitedKinds: [MarkdownInlineNode.Kind] = [.codeSpan, .linkText, .linkDestination, .autolink]
        for prohibited in prohibitedKinds where prohibited != targetNodeKind {
            if innermostNode(of: prohibited, containing: first, second) != nil {
                return true
            }
        }
        if let firstFence = fenceBlockIndex(containing: first), let secondFence = fenceBlockIndex(containing: second) {
            return firstFence == secondFence
        }
        return false
    }

    private func leafOffset(_ offset: Int) -> Int? {
        if offset < text.length { return offset }
        return offset > 0 ? offset - 1 : nil
    }

    private func innermostNode(
        of nodeKind: MarkdownInlineNode.Kind,
        containing first: Int,
        _ second: Int
    ) -> MarkdownInlineNode? {
        var best: MarkdownInlineNode?
        for region in regions {
            for node in region.nodes
            where node.kind == nodeKind && node.containsChar(at: first) && node.containsChar(at: second) {
                if let current = best, current.range.length <= node.range.length { continue }
                best = node
            }
        }
        return best
    }

    private func fenceBlockIndex(containing offset: Int) -> Int? {
        for (index, block) in document.blocks.enumerated() where block.kind == .fencedCode {
            let start = text.lines[block.lines.lowerBound].start
            let end = text.lines[block.lines.upperBound - 1].contentEnd
            if offset >= start && offset < end {
                return index
            }
        }
        return nil
    }

    private static func node(_ node: MarkdownInlineNode, contains leaf: Range<Int>) -> Bool {
        leaf.lowerBound >= node.range.location && leaf.upperBound <= node.upperBound
    }

    private static func node(_ outer: MarkdownInlineNode, containsNode inner: MarkdownInlineNode) -> Bool {
        inner.range.location >= outer.range.location && inner.upperBound <= outer.upperBound
    }

    private static func makeRegion(
        blockIndex: Int,
        isTableCell: Bool,
        base: Int,
        units: [UInt16]
    ) -> MarkdownEmphasisRegion {
        let nodes = MarkdownInlineParser.parse(units, base: base).sorted { left, right in
            left.range.location != right.range.location
                ? left.range.location < right.range.location
                : left.range.length > right.range.length
        }
        return MarkdownEmphasisRegion(
            blockIndex: blockIndex,
            isTableCell: isTableCell,
            extent: base..<(base + units.count),
            nodes: nodes,
            leaves: leaves(units: units, base: base, nodes: nodes)
        )
    }

    private static func leaves(units: [UInt16], base: Int, nodes: [MarkdownInlineNode]) -> [Range<Int>] {
        var markerOffsets = Set<Int>()
        var splitOffsets = Set<Int>()
        for node in nodes {
            splitOffsets.insert(node.range.location)
            splitOffsets.insert(node.upperBound)
            switch node.kind {
            case .emphasis, .strong, .strikethrough, .highlight:
                let openEnd = node.range.location + node.openLength
                let closeStart = node.upperBound - node.closeLength
                markerOffsets.formUnion(node.range.location..<openEnd)
                markerOffsets.formUnion(closeStart..<node.upperBound)
                splitOffsets.insert(openEnd)
                splitOffsets.insert(closeStart)
            default:
                continue
            }
        }
        let end = base + units.count
        var leaves: [Range<Int>] = []
        var index = base
        while index < end {
            if markerOffsets.contains(index) {
                index += 1
                continue
            }
            let unit = units[index - base]
            var next = index + 1
            if MarkdownText.isSpaceOrTab(unit) {
                while next < end, !markerOffsets.contains(next), !splitOffsets.contains(next),
                      MarkdownText.isSpaceOrTab(units[next - base]) {
                    next += 1
                }
            } else if MarkdownText.isLetterOrDigit(unit) {
                while next < end, !markerOffsets.contains(next), !splitOffsets.contains(next),
                      MarkdownText.isLetterOrDigit(units[next - base]) {
                    next += 1
                }
            }
            leaves.append(index..<next)
            index = next
        }
        return leaves
    }
}

fileprivate nonisolated struct MarkdownEmphasisSession: Sendable {
    private var buffer: MarkdownEditBuffer
    private var markers: [MarkdownEmphasisMarker]

    init(units: [UInt16], carets: [Range<Int>]) {
        self.buffer = MarkdownEditBuffer(units: units)
        self.markers = carets.map { MarkdownEmphasisMarker(start: $0.lowerBound, end: $0.upperBound) }
    }

    var result: MarkdownActionResult {
        buffer.result(selections: markers.map { NSRange(location: $0.start, length: $0.end - $0.start) })
    }

    mutating func process(caret index: Int, kind: MarkdownEmphasisKind, style: MarkdownEmphasisStyle, state: Bool) {
        let context = MarkdownEmphasisContext(kind: kind, style: style, units: buffer.units)
        let selection = markers[index].range
        if let tableRanges = context.tableSelection(selection) {
            let removeFormatting = !state
                || (!tableRanges.isEmpty && tableRanges.allSatisfy { context.formattingParent($0) != nil })
            for range in tableRanges.reversed() {
                if removeFormatting {
                    guard let parent = context.formattingParent(range) else { continue }
                    removeEmphasis(context: context, selection: range, parent: parent)
                } else if context.formattingParent(range) == nil {
                    addEmphasis(context: context, caret: index, range: range)
                }
            }
            return
        }
        let parent = context.formattingParent(selection)
        if let parent {
            removeEmphasis(context: context, selection: selection, parent: parent)
        } else if state {
            addEmphasis(context: context, caret: index, range: selection)
        }
    }

    private mutating func insert(_ string: String, at offset: Int) {
        buffer.insert(string, at: offset)
        let length = string.utf16.count
        for index in markers.indices {
            markers[index].inserted(length: length, at: offset)
        }
    }

    private mutating func delete(_ range: Range<Int>) {
        buffer.delete(range)
        for index in markers.indices {
            markers[index].deleted(range)
        }
    }

    private mutating func removeEmphasis(
        context: MarkdownEmphasisContext,
        selection: Range<Int>,
        parent: MarkdownInlineNode
    ) {
        let nodeStart = parent.range.location
        let nodeEnd = parent.upperBound
        let boundLength = parent.openLength
        let boundString = buffer.units[nodeStart..<(nodeStart + boundLength)]
        let bound = String(decoding: boundString, as: UTF16.self)
        let matchesContent = nodeStart + boundLength == selection.lowerBound
            && nodeEnd - boundLength == selection.upperBound
        if matchesContent || context.coversContent(selection, of: parent) {
            delete((nodeEnd - boundLength)..<nodeEnd)
            delete(nodeStart..<(nodeStart + boundLength))
            return
        }
        var from = selection.lowerBound
        var to = selection.upperBound
        if context.movesToWordBounds {
            while from - boundLength > nodeStart, MarkdownText.isJavaWhitespace(buffer.units[from - 1]) {
                from -= 1
            }
            while to + boundLength < nodeEnd, MarkdownText.isJavaWhitespace(buffer.units[to]) {
                to += 1
            }
        }
        if to + boundLength == nodeEnd {
            delete((nodeEnd - boundLength)..<nodeEnd)
        } else {
            insert(bound, at: to)
        }
        if from - boundLength == nodeStart {
            delete(nodeStart..<(nodeStart + boundLength))
        } else {
            insert(bound, at: from)
        }
    }

    private mutating func addEmphasis(context: MarkdownEmphasisContext, caret index: Int, range: Range<Int>) {
        var from = range.lowerBound
        var to = range.upperBound
        if context.movesToWordBounds {
            while from < to, MarkdownText.isJavaWhitespace(buffer.units[from]) {
                from += 1
            }
            while to > from, MarkdownText.isJavaWhitespace(buffer.units[to - 1]) {
                to -= 1
            }
            if from == to {
                from = range.lowerBound
                to = range.upperBound
            }
        }
        let bound = boundString(context: context, from: from, to: to)
        insert(bound, at: to)
        insert(bound, at: from)
        if range.isEmpty {
            markers[index].shift(by: bound.utf16.count)
        }
    }

    private func boundString(context: MarkdownEmphasisContext, from: Int, to: Int) -> String {
        let underscores = context.style == .underscores
        switch context.kind {
        case .bold:
            return underscores ? "__" : "**"
        case .italic:
            return underscores && isWord(from: from, to: to) ? "_" : "*"
        case .strikethrough:
            return "~~"
        case .codeSpan:
            var longest = 0
            var current = 0
            for index in from..<to {
                if buffer.units[index] == 0x60 {
                    current += 1
                    longest = max(longest, current)
                } else {
                    current = 0
                }
            }
            return String(repeating: "`", count: longest + 1)
        }
    }

    private func isWord(from: Int, to: Int) -> Bool {
        let units = buffer.units
        let startsWord = from == 0 || !MarkdownText.isLetterOrDigit(units[from - 1])
        let endsWord = to == units.count || !MarkdownText.isLetterOrDigit(units[to])
        return startsWord && endsWord
    }
}
