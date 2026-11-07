import Foundation

nonisolated enum MarkdownHeaderAnchor {
    private static let space = MarkdownText.space
    private static let ampersand: UInt16 = 0x26
    private static let semicolon: UInt16 = 0x3B
    private static let hash: UInt16 = 0x23
    private static let commentOpen = Array("<!--".utf16)
    private static let commentClose = Array("-->".utf16)
    private static let ampersandEntity = Array("&amp;".utf16)

    private static let namedEntities: [String: UInt16] = [
        "amp": 0x26, "lt": 0x3C, "gt": 0x3E, "quot": 0x22, "apos": 0x27, "nbsp": 0xA0,
        "copy": 0xA9, "reg": 0xAE, "trade": 0x2122, "hellip": 0x2026, "mdash": 0x2014, "ndash": 0x2013,
        "lsquo": 0x2018, "rsquo": 0x2019, "ldquo": 0x201C, "rdquo": 0x201D, "laquo": 0xAB, "raquo": 0xBB,
        "euro": 0x20AC, "pound": 0xA3, "yen": 0xA5, "cent": 0xA2, "sect": 0xA7, "deg": 0xB0,
        "plusmn": 0xB1, "times": 0xD7, "divide": 0xF7, "middot": 0xB7, "bull": 0x2022,
        "larr": 0x2190, "rarr": 0x2192, "uarr": 0x2191, "darr": 0x2193, "hearts": 0x2665,
    ]

    static func rawAnchor(forHeaderContent content: String) -> String? {
        let units = Array(content.utf16)
        let start = firstNonWhitespace(units)
        guard start < units.count else { return nil }
        let nodes = MarkdownInlineParser.parse(units, base: 0)
        let children = topLevelNodes(nodes, in: start..<units.count)
        var builder: [UInt16] = []
        var hasComment = false
        var index = start
        var childIndex = 0
        while index < units.count {
            if childIndex < children.count, children[childIndex].range.location == index {
                let node = children[childIndex]
                childIndex += 1
                index = node.upperBound
                switch node.kind {
                case .image:
                    break
                case .inlineLink:
                    builder.append(
                        contentsOf: linkTextPieces(units, nodes: nodes, link: node).joined(separator: [space])
                    )
                case .htmlTag where isHtmlComment(units, node: node):
                    hasComment = true
                default:
                    builder.append(contentsOf: units[node.range.location..<node.upperBound])
                }
            } else if MarkdownText.isJavaWhitespace(units[index]) {
                while index < units.count, MarkdownText.isJavaWhitespace(units[index]) { index += 1 }
                builder.append(space)
            } else {
                let stop = chunkEnd(units, from: index, children: children, childIndex: childIndex, limit: units.count)
                builder.append(contentsOf: units[index..<stop])
                index = stop
            }
        }
        if hasComment {
            while let last = builder.last, MarkdownText.isJavaWhitespace(last) { builder.removeLast() }
        }
        return normalizedAnchor(String(decoding: builder, as: UTF16.self))
    }

    static func anchor(forHeaderContent content: String) -> String? {
        rawAnchor(forHeaderContent: content)
    }

    static func uniqueAnchors(forRawAnchors raws: [String]) -> [String] {
        var occurrences: [String: Int] = [:]
        return raws.map { raw in
            let number = occurrences[raw] ?? 0
            occurrences[raw] = number + 1
            return number == 0 ? raw : "\(raw)-\(number)"
        }
    }

    static func visibleText(forHeaderContent content: String) -> String? {
        let units = Array(content.utf16)
        let start = firstNonWhitespace(units)
        guard start < units.count else { return nil }
        let nodes = MarkdownInlineParser.parse(units, base: 0)
        var builder: [UInt16] = []
        appendVisible(units, nodes: nodes, range: start..<units.count, into: &builder)
        var lower = 0
        var upper = builder.count
        while lower < upper, builder[lower] == space { lower += 1 }
        while upper > lower, builder[upper - 1] == space { upper -= 1 }
        guard lower < upper else { return nil }
        return String(decoding: builder[lower..<upper], as: UTF16.self)
    }

    static func replaceEntities(_ text: String) -> String {
        let units = Array(text.utf16)
        var result: [UInt16] = []
        var index = 0
        while index < units.count {
            if units[index] == ampersand, let entity = entity(units, at: index) {
                result.append(contentsOf: entity.replacement)
                index += entity.length
            } else {
                result.append(units[index])
                index += 1
            }
        }
        return String(decoding: result, as: UTF16.self)
    }

    private static func normalizedAnchor(_ text: String) -> String {
        var result = ""
        for scalar in replaceEntities(text).lowercased().unicodeScalars {
            if scalar == " " {
                result.unicodeScalars.append("-")
            } else if scalar.properties.isAlphabetic || (scalar.value >= 0x30 && scalar.value <= 0x39)
                || scalar == "-" || scalar == "_" {
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    private static func firstNonWhitespace(_ units: [UInt16]) -> Int {
        var index = 0
        while index < units.count, MarkdownText.isJavaWhitespace(units[index]) { index += 1 }
        return index
    }

    static func topLevelNodes(_ nodes: [MarkdownInlineNode], in range: Range<Int>) -> [MarkdownInlineNode] {
        var result: [MarkdownInlineNode] = []
        var cursor = range.lowerBound
        for node in nodes where node.range.location >= cursor && node.upperBound <= range.upperBound {
            result.append(node)
            cursor = node.upperBound
        }
        return result
    }

    private static func chunkEnd(
        _ units: [UInt16],
        from start: Int,
        children: [MarkdownInlineNode],
        childIndex: Int,
        limit: Int
    ) -> Int {
        let nextChild = childIndex < children.count ? children[childIndex].range.location : limit
        var index = start
        while index < min(nextChild, limit), !MarkdownText.isJavaWhitespace(units[index]) { index += 1 }
        return index
    }

    private static func isHtmlComment(_ units: [UInt16], node: MarkdownInlineNode) -> Bool {
        let slice = units[node.range.location..<node.upperBound]
        return slice.count >= commentOpen.count + commentClose.count
            && slice.starts(with: commentOpen)
            && slice.reversed().starts(with: commentClose.reversed())
    }

    private static func linkTextPieces(
        _ units: [UInt16],
        nodes: [MarkdownInlineNode],
        link: MarkdownInlineNode
    ) -> [[UInt16]] {
        guard let linkText = nodes.first(where: {
            $0.kind == .linkText && $0.range.location == link.range.location
        }) else {
            return []
        }
        let content = linkText.contentRange
        let range = content.location..<(content.location + content.length)
        let children = topLevelNodes(nodes, in: range)
        var pieces: [[UInt16]] = []
        var index = range.lowerBound
        var childIndex = 0
        while index < range.upperBound {
            if childIndex < children.count, children[childIndex].range.location == index {
                let node = children[childIndex]
                childIndex += 1
                index = node.upperBound
                pieces.append(node.kind == .image ? [] : Array(units[node.range.location..<node.upperBound]))
            } else if MarkdownText.isJavaWhitespace(units[index]) {
                index += 1
            } else {
                let stop = chunkEnd(
                    units,
                    from: index,
                    children: children,
                    childIndex: childIndex,
                    limit: range.upperBound
                )
                pieces.append(Array(units[index..<stop]))
                index = stop
            }
        }
        return pieces
    }

    private static func appendVisible(
        _ units: [UInt16],
        nodes: [MarkdownInlineNode],
        range: Range<Int>,
        into builder: inout [UInt16]
    ) {
        let children = topLevelNodes(nodes, in: range)
        var index = range.lowerBound
        var childIndex = 0
        while index < range.upperBound {
            guard childIndex < children.count, children[childIndex].range.location == index else {
                let nextChild = childIndex < children.count ? children[childIndex].range.location : range.upperBound
                builder.append(contentsOf: units[index..<nextChild])
                index = nextChild
                continue
            }
            let node = children[childIndex]
            childIndex += 1
            index = node.upperBound
            switch node.kind {
            case .htmlTag:
                break
            case .inlineLink:
                if let linkText = nodes.first(where: {
                    $0.kind == .linkText && $0.range.location == node.range.location
                }) {
                    let content = linkText.contentRange
                    appendVisible(
                        units,
                        nodes: nodes,
                        range: content.location..<(content.location + content.length),
                        into: &builder
                    )
                }
            case .emphasis, .strong, .strikethrough, .highlight, .linkText:
                let content = node.contentRange
                builder.append(contentsOf: units[node.range.location..<content.location])
                appendVisible(
                    units,
                    nodes: nodes,
                    range: content.location..<(content.location + content.length),
                    into: &builder
                )
                builder.append(contentsOf: units[(content.location + content.length)..<node.upperBound])
            default:
                builder.append(contentsOf: units[node.range.location..<node.upperBound])
            }
        }
    }

    private static func entity(_ units: [UInt16], at start: Int) -> (length: Int, replacement: [UInt16])? {
        var index = start + 1
        guard index < units.count else { return nil }
        let nameStart = index
        while index < units.count, isASCIIAlphanumeric(units[index]) { index += 1 }
        if index > nameStart, index < units.count, units[index] == semicolon {
            let name = String(decoding: units[nameStart..<index], as: UTF16.self)
            let length = index + 1 - start
            if let code = namedEntities[name] {
                return (length, [code])
            }
            return (length, ampersandEntity + Array(units[nameStart...index]))
        }
        guard units[nameStart] == hash else { return nil }
        index = nameStart + 1
        let isHex = index < units.count && (units[index] == 0x78 || units[index] == 0x58)
        if isHex { index += 1 }
        let digitsStart = index
        while index < units.count, isHex ? isHexDigit(units[index]) : isDecimalDigit(units[index]) { index += 1 }
        let count = index - digitsStart
        guard (1...8).contains(count), index < units.count, units[index] == semicolon else { return nil }
        let digits = String(decoding: units[digitsStart..<index], as: UTF16.self)
        guard let code = Int(digits, radix: isHex ? 16 : 10) else { return nil }
        return (index + 1 - start, [UInt16(truncatingIfNeeded: code)])
    }

    private static func isDecimalDigit(_ unit: UInt16) -> Bool {
        unit >= 0x30 && unit <= 0x39
    }

    private static func isHexDigit(_ unit: UInt16) -> Bool {
        isDecimalDigit(unit) || (unit >= 0x41 && unit <= 0x46) || (unit >= 0x61 && unit <= 0x66)
    }

    private static func isASCIIAlphanumeric(_ unit: UInt16) -> Bool {
        isDecimalDigit(unit) || (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A)
    }
}

nonisolated extension MarkdownDocument {
    func headerContent(ofBlock index: Int) -> String? {
        guard blocks[index].isHeading, let region = inlineRegion(ofBlock: index) else { return nil }
        var units = region.units
        while let last = units.last, MarkdownText.isSpaceOrTab(last) { units.removeLast() }
        return String(decoding: units, as: UTF16.self)
    }
}
