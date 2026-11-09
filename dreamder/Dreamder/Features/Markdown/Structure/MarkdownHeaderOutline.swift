import Foundation

nonisolated struct MarkdownHeaderNode: Equatable, Sendable {
    let level: Int
    let title: String
    let range: NSRange
    let line: Int
    var children: [MarkdownHeaderNode]
}

nonisolated struct MarkdownHeaderEntry: Equatable, Sendable {
    let level: Int
    let title: String
    let range: NSRange
    let line: Int
    let depth: Int
}

nonisolated enum MarkdownHeaderOutline {
    static let invalidHeaderPrefix = "Invalid header: "

    static func nodes(in text: String) -> [MarkdownHeaderNode] {
        build(units: Array(text.utf16))
    }

    static func entries(in text: String) -> [MarkdownHeaderEntry] {
        var result: [MarkdownHeaderEntry] = []
        func append(_ nodes: [MarkdownHeaderNode], depth: Int) {
            for node in nodes {
                result.append(
                    MarkdownHeaderEntry(level: node.level, title: node.title, range: node.range, line: node.line, depth: depth)
                )
                append(node.children, depth: depth + 1)
            }
        }
        append(nodes(in: text), depth: 0)
        return result
    }

    private static func build(units: [UInt16]) -> [MarkdownHeaderNode] {
        let scan = MarkdownBlockLexer.scan(units: units)
        guard !scan.headers.isEmpty else { return [] }
        let root = OutlineScope(id: -1)
        for (index, header) in scan.headers.enumerated() {
            var scope = root
            for id in header.containerPath {
                if case .container(let last)? = scope.items.last, last.id == id {
                    scope = last
                } else {
                    let created = OutlineScope(id: id)
                    scope.items.append(.container(created))
                    scope = created
                }
            }
            scope.items.append(.header(index))
        }
        let context = OutlineContext(
            headers: scan.headers,
            titles: scan.headers.map { title(for: $0, units: units) },
            lineStarts: lineStarts(in: units)
        )
        return process(ArraySlice(root.items), restriction: nil, context: context)
    }

    private static func process(
        _ items: ArraySlice<OutlineItem>,
        restriction: Int?,
        context: OutlineContext
    ) -> [MarkdownHeaderNode] {
        var result: [MarkdownHeaderNode] = []
        var maxLevel: Int?
        for index in items.indices {
            switch items[index] {
            case .container(let scope):
                if maxLevel == nil {
                    result.append(contentsOf: process(ArraySlice(scope.items), restriction: nil, context: context))
                }
            case .header(let headerIndex):
                let header = context.headers[headerIndex]
                if let restriction, header.level <= restriction {
                    return result
                }
                if let maxLevel, header.level > maxLevel {
                    continue
                }
                maxLevel = header.level
                let children = process(items[(index + 1)...], restriction: header.level, context: context)
                result.append(
                    MarkdownHeaderNode(
                        level: header.level,
                        title: context.titles[headerIndex],
                        range: header.range,
                        line: context.line(at: header.range.location),
                        children: children
                    )
                )
            }
        }
        return result
    }

    private static func lineStarts(in units: [UInt16]) -> [Int] {
        var starts = [0]
        for (index, unit) in units.enumerated() where unit == MarkdownChar.newline {
            starts.append(index + 1)
        }
        return starts
    }

    private static func title(for header: MarkdownHeaderBlock, units: [UInt16]) -> String {
        let content = header.contentRange
        if content.length > 0 {
            let tokens = MarkdownInlineLexer.tokens(in: units, segments: [content])
            var visible = visibleText(units: units, range: content, tokens: tokens)
            visible = visible.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ")
            let trimmed = visible.trimmingCharacters(in: CharacterSet(charactersIn: " "))
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        let source = String(decoding: units[header.range.location..<(header.range.location + header.range.length)], as: UTF16.self)
        return invalidHeaderPrefix + source
    }

    private static func visibleText(units: [UInt16], range: NSRange, tokens: [MarkdownToken]) -> String {
        var result: [UInt16] = []
        var cursor = range.location
        let end = range.location + range.length
        for token in tokens {
            if token.range.location >= end { break }
            guard token.range.location >= cursor else { continue }
            let tokenEnd = token.range.location + token.range.length
            switch token.kind {
            case .inlineHtml:
                result.append(contentsOf: units[cursor..<token.range.location])
                cursor = tokenEnd
            case .inlineLink:
                result.append(contentsOf: units[cursor..<token.range.location])
                if let linkText = tokens.first(where: { $0.kind == .linkText && contains(token.range, $0.range) }) {
                    let inner = NSRange(location: linkText.range.location + 1, length: max(0, linkText.range.length - 2))
                    let nested = visibleText(units: units, range: inner, tokens: tokens)
                    result.append(contentsOf: Array(nested.utf16))
                }
                cursor = tokenEnd
            case .image:
                result.append(contentsOf: units[cursor..<token.range.location])
                if let linkText = tokens.first(where: { $0.kind == .linkText && contains(token.range, $0.range) }) {
                    let lower = linkText.range.location + 1
                    let upper = linkText.range.location + linkText.range.length - 1
                    if lower < upper {
                        result.append(contentsOf: units[lower..<upper])
                    }
                } else if let label = tokens.first(where: { $0.kind == .linkLabel && contains(token.range, $0.range) }) {
                    let lower = label.range.location + 1
                    let upper = label.range.location + label.range.length - 1
                    if lower < upper {
                        result.append(contentsOf: units[lower..<upper])
                    }
                }
                cursor = tokenEnd
            default:
                continue
            }
        }
        if cursor < end {
            result.append(contentsOf: units[cursor..<end])
        }
        return String(decoding: result, as: UTF16.self)
    }

    private static func contains(_ outer: NSRange, _ inner: NSRange) -> Bool {
        inner.location >= outer.location && inner.location + inner.length <= outer.location + outer.length
    }
}

private nonisolated enum OutlineItem {
    case header(Int)
    case container(OutlineScope)
}

private nonisolated final class OutlineScope {
    let id: Int
    var items: [OutlineItem] = []

    init(id: Int) {
        self.id = id
    }
}

private nonisolated struct OutlineContext {
    let headers: [MarkdownHeaderBlock]
    let titles: [String]
    let lineStarts: [Int]

    func line(at offset: Int) -> Int {
        var low = 0
        var high = lineStarts.count
        while low < high {
            let middle = (low + high) / 2
            if lineStarts[middle] <= offset {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }
}
