import Foundation

nonisolated enum MarkdownLinkCreation {
    private static let colon: UInt16 = 0x3A
    private static let slash: UInt16 = 0x2F
    private static let questionMark: UInt16 = 0x3F
    private static let hash: UInt16 = 0x23
    private static let backslash: UInt16 = 0x5C
    private static let openBracket: UInt16 = 0x5B
    private static let closeBracket: UInt16 = 0x5D
    private static let openParen: UInt16 = 0x28
    private static let closeParen: UInt16 = 0x29
    private static let lessThan: UInt16 = 0x3C
    private static let unicodeNextLine: UInt16 = 0x85
    private static let unicodeLineSeparator: UInt16 = 0x2028
    private static let unicodeParagraphSeparator: UInt16 = 0x2029
    private static let bareURLPrefixes: [[UInt16]] = ["http://", "https://", "ftp://", "www."].map { Array($0.utf16) }
    private static let bareURLLeadingPunctuation: Set<UInt16> = Set("*_~(".utf16)
    private static let bareURLTrailingPunctuation: Set<UInt16> = Set("?!.,:*_~'\"".utf16)
    private static let maximumDefinitionIndent = 3

    static func linkDestination(from candidate: String) -> String? {
        let trimmed = trimmedWhitespace(candidate)
        guard !trimmed.isEmpty else { return nil }
        guard !trimmed.unicodeScalars.contains(where: { $0.properties.isWhitespace }) else { return nil }
        guard hasUriShape(Array(trimmed.utf16)) else { return nil }
        return trimmed
    }

    static func createInlineLink(text: String, destination: String) -> String {
        "[\(text)](\(destination))"
    }

    static func wrapSelections(
        text: String,
        selections: [NSRange],
        clipboard: String?,
        relativePathExists: @Sendable (String) -> Bool
    ) -> MarkdownActionResult {
        let original = Array(text.utf16)
        let pastedDestination = clipboard.flatMap { clipboardDestination($0, relativePathExists: relativePathExists) }
        let clipboardUnits = pastedDestination.map { Array($0.utf16) }
        let ordered = selections.enumerated().sorted { left, right in
            left.element.location != right.element.location
                ? left.element.location < right.element.location
                : left.offset < right.offset
        }
        var updated: [UInt16] = []
        var cursor = 0
        var resulting = [NSRange](repeating: NSRange(location: 0, length: 0), count: selections.count)
        for (index, selection) in ordered {
            let start = min(max(selection.location, cursor), original.count)
            let end = min(max(selection.location + selection.length, start), original.count)
            updated.append(contentsOf: original[cursor..<start])
            let selectedUnits = Array(original[start..<end])
            let selectedText = String(decoding: selectedUnits, as: UTF16.self)
            let destination = linkDestination(from: selectedText)
            let linkText = destination == nil ? selectedText : ""
            let replacement = createInlineLink(text: linkText, destination: destination ?? "")
            let replacementStart = updated.count
            updated.append(contentsOf: Array(replacement.utf16))
            if destination == nil {
                let caret = replacementStart + selectedUnits.count + 3
                if let clipboardUnits {
                    updated.insert(contentsOf: clipboardUnits, at: caret)
                    resulting[index] = NSRange(location: caret, length: clipboardUnits.count)
                } else {
                    resulting[index] = NSRange(location: caret, length: 0)
                }
            } else {
                resulting[index] = NSRange(location: replacementStart + 1, length: 0)
            }
            cursor = end
        }
        updated.append(contentsOf: original[cursor...])
        return MarkdownActionResult(original: original, updated: updated, selections: resulting)
    }

    static func canUnwrap(text: String, selections: [NSRange]) -> Bool {
        guard !selections.isEmpty else { return false }
        let nodes = inlineNodes(MarkdownDocument(text))
        return selections.allSatisfy { enclosingLink(of: $0, in: nodes) != nil }
    }

    static func unwrap(text: String, selections: [NSRange]) -> MarkdownActionResult? {
        guard !selections.isEmpty else { return nil }
        let nodes = inlineNodes(MarkdownDocument(text))
        var links: [MarkdownInlineNode] = []
        var linkIndexBySelection: [Int] = []
        for selection in selections {
            guard let link = enclosingLink(of: selection, in: nodes) else { return nil }
            if let existing = links.firstIndex(where: { $0.range == link.range }) {
                linkIndexBySelection.append(existing)
            } else {
                links.append(link)
                linkIndexBySelection.append(links.count - 1)
            }
        }
        let original = Array(text.utf16)
        let sortedLinkIndices = links.indices.sorted { links[$0].range.location < links[$1].range.location }
        var updated: [UInt16] = []
        var cursor = 0
        var newStartByLink = [Int](repeating: 0, count: links.count)
        var textRangeByLink = [Range<Int>](repeating: 0..<0, count: links.count)
        for linkIndex in sortedLinkIndices {
            let link = links[linkIndex]
            let textRange = linkTextRange(of: link, in: nodes)
            updated.append(contentsOf: original[cursor..<link.range.location])
            newStartByLink[linkIndex] = updated.count
            updated.append(contentsOf: original[textRange])
            textRangeByLink[linkIndex] = textRange
            cursor = link.upperBound
        }
        updated.append(contentsOf: original[cursor...])
        var resulting: [NSRange] = []
        for (selectionIndex, selection) in selections.enumerated() {
            let linkIndex = linkIndexBySelection[selectionIndex]
            let link = links[linkIndex]
            let textLength = textRangeByLink[linkIndex].count
            let start = mappedOffset(
                selection.location,
                linkStart: link.range.location,
                textLength: textLength,
                newStart: newStartByLink[linkIndex]
            )
            let end = mappedOffset(
                selection.location + selection.length,
                linkStart: link.range.location,
                textLength: textLength,
                newStart: newStartByLink[linkIndex]
            )
            resulting.append(NSRange(location: start, length: end - start))
        }
        return MarkdownActionResult(original: original, updated: updated, selections: resulting)
    }

    static func pasteReplacement(text: String, selection: NSRange, pasted: String) -> String {
        let units = Array(text.utf16)
        guard selection.length > 0,
              selection.location >= 0,
              selection.location + selection.length <= units.count,
              let destination = linkDestination(from: pasted)
        else { return pasted }
        let selectedText = String(
            decoding: units[selection.location..<(selection.location + selection.length)],
            as: UTF16.self
        )
        guard !selectedText.unicodeScalars.allSatisfy({ $0.properties.isWhitespace }) else { return pasted }
        let document = MarkdownDocument(text)
        let context = PasteContext(document: document)
        let probes = [selection.location, selection.location + selection.length - 1]
        guard !probes.contains(where: { context.isIgnored($0) }) else { return pasted }
        return createInlineLink(text: selectedText, destination: destination)
    }

    private struct PasteContext {
        let document: MarkdownDocument
        let regions: [(base: Int, units: [UInt16])]
        let definitions: Set<String>

        init(document: MarkdownDocument) {
            self.document = document
            self.regions = MarkdownLinkCreation.inlineRegions(document)
            var labels: Set<String> = []
            for line in document.text.lines.indices {
                if let label = MarkdownLinkCreation.definitionLabel(document: document, line: line) {
                    labels.insert(label)
                }
            }
            self.definitions = labels
        }

        func isIgnored(_ offset: Int) -> Bool {
            if let block = document.block(containing: offset) {
                switch block.kind {
                case .fencedCode, .indentedCode, .htmlBlock, .frontMatter:
                    return true
                default:
                    break
                }
            }
            let line = document.text.lineIndex(containing: offset)
            if MarkdownLinkCreation.definitionLabel(document: document, line: line) != nil {
                return true
            }
            for region in regions where offset >= region.base && offset < region.base + region.units.count {
                if isIgnoredInline(offset, region: region) {
                    return true
                }
            }
            return false
        }

        private func isIgnoredInline(_ offset: Int, region: (base: Int, units: [UInt16])) -> Bool {
            let nodes = MarkdownInlineParser.parse(region.units, base: region.base)
            let ignoredKinds: Set<MarkdownInlineNode.Kind> = [
                .codeSpan, .linkText, .linkDestination, .inlineLink, .image, .autolink
            ]
            if nodes.contains(where: { ignoredKinds.contains($0.kind) && $0.containsChar(at: offset) }) {
                return true
            }
            let local = offset - region.base
            if MarkdownLinkCreation.bareURLRanges(region.units).contains(where: { $0.contains(local) }) {
                return true
            }
            return MarkdownLinkCreation.labelSpans(region.units).contains { span in
                span.range.contains(local) && definitions.contains(span.label)
            }
        }
    }

    private static func clipboardDestination(
        _ clipboard: String,
        relativePathExists: @Sendable (String) -> Bool
    ) -> String? {
        guard !clipboard.isEmpty else { return nil }
        if clipboard.contains("://") {
            return hasUriShape(Array(clipboard.utf16)) ? clipboard : nil
        }
        guard !clipboard.utf16.contains(0) else { return nil }
        return relativePathExists(clipboard) ? clipboard : nil
    }

    private static func hasUriShape(_ units: [UInt16]) -> Bool {
        guard !units.contains(where: isLineTerminator) else { return false }
        let delimiters: Set<UInt16> = [colon, slash, questionMark, hash]
        guard let separator = units.firstIndex(where: { delimiters.contains($0) }) else { return false }
        return units[separator] == colon && separator > 0
    }

    private static func isLineTerminator(_ unit: UInt16) -> Bool {
        MarkdownText.isNewline(unit)
            || unit == unicodeNextLine
            || unit == unicodeLineSeparator
            || unit == unicodeParagraphSeparator
    }

    private static func trimmedWhitespace(_ string: String) -> String {
        let scalars = Array(string.unicodeScalars)
        guard let first = scalars.firstIndex(where: { !$0.properties.isWhitespace }),
              let last = scalars.lastIndex(where: { !$0.properties.isWhitespace })
        else { return "" }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars[first...last])
        return String(view)
    }

    private static func inlineRegions(_ document: MarkdownDocument) -> [(base: Int, units: [UInt16])] {
        var regions: [(base: Int, units: [UInt16])] = []
        let units = document.text.units
        for index in document.blocks.indices {
            let block = document.blocks[index]
            if block.kind == .table {
                for line in block.lines {
                    let bodyStart = document.infos[line].bodyStart
                    let bodyEnd = document.text.lines[line].contentEnd
                    guard bodyStart <= bodyEnd else { continue }
                    let split = MarkdownTableRowSplitter.split(units, body: bodyStart..<bodyEnd)
                    for cell in split.cells where !cell.isEmpty {
                        regions.append((cell.lowerBound, Array(units[cell])))
                    }
                }
            } else if let region = document.inlineRegion(ofBlock: index) {
                regions.append(region)
            }
        }
        return regions
    }

    private static func inlineNodes(_ document: MarkdownDocument) -> [MarkdownInlineNode] {
        inlineRegions(document).flatMap { MarkdownInlineParser.parse($0.units, base: $0.base) }
    }

    private static func enclosingLink(of selection: NSRange, in nodes: [MarkdownInlineNode]) -> MarkdownInlineNode? {
        let selectionEnd = selection.location + selection.length
        return nodes.last { node in
            guard node.kind == .inlineLink else { return false }
            if selection.length > 0 {
                return node.containsChar(at: selection.location) && selectionEnd <= node.upperBound
            }
            return selection.location > node.range.location && selection.location < node.upperBound
        }
    }

    private static func linkTextRange(of link: MarkdownInlineNode, in nodes: [MarkdownInlineNode]) -> Range<Int> {
        guard let linkText = nodes.first(where: {
            $0.kind == .linkText && $0.range.location == link.range.location && $0.upperBound <= link.upperBound
        }) else { return link.range.location..<link.range.location }
        let content = linkText.contentRange
        return content.location..<(content.location + content.length)
    }

    private static func mappedOffset(_ offset: Int, linkStart: Int, textLength: Int, newStart: Int) -> Int {
        let clamped = max(linkStart, min(linkStart + textLength, offset - 1))
        return newStart + (clamped - linkStart)
    }

    private static func definitionLabel(document: MarkdownDocument, line: Int) -> String? {
        if let block = document.block(containing: document.text.lines[line].start) {
            switch block.kind {
            case .fencedCode, .indentedCode, .htmlBlock, .frontMatter:
                return nil
            default:
                break
            }
        }
        let units = document.text.units
        let end = document.text.lines[line].contentEnd
        var index = document.infos[line].bodyStart
        guard index <= end else { return nil }
        var indent = 0
        while index < end, indent < maximumDefinitionIndent, units[index] == MarkdownText.space {
            index += 1
            indent += 1
        }
        guard index < end, units[index] == openBracket else { return nil }
        guard let span = labelSpans(Array(units[index..<end])).first, span.range.lowerBound == 0 else { return nil }
        let colonIndex = index + span.range.upperBound + 1
        guard colonIndex < end, units[colonIndex] == colon else { return nil }
        return span.label.isEmpty ? nil : span.label
    }

    private static func labelSpans(_ units: [UInt16]) -> [(range: ClosedRange<Int>, label: String)] {
        var spans: [(range: ClosedRange<Int>, label: String)] = []
        var index = 0
        while index < units.count {
            let unit = units[index]
            if unit == backslash {
                index += 2
                continue
            }
            guard unit == openBracket else {
                index += 1
                continue
            }
            var cursor = index + 1
            var closing: Int?
            while cursor < units.count {
                if units[cursor] == backslash {
                    cursor += 2
                    continue
                }
                if units[cursor] == openBracket { break }
                if units[cursor] == closeBracket {
                    closing = cursor
                    break
                }
                cursor += 1
            }
            guard let closing else {
                index += 1
                continue
            }
            let label = normalizedLabel(units[(index + 1)..<closing])
            if !label.isEmpty {
                spans.append((index...closing, label))
            }
            index = closing + 1
        }
        return spans
    }

    private static func normalizedLabel(_ units: ArraySlice<UInt16>) -> String {
        String(decoding: units, as: UTF16.self)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased()
    }

    private static func bareURLRanges(_ units: [UInt16]) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var index = 0
        while index < units.count {
            guard isBareURLBoundary(units, at: index),
                  let prefix = bareURLPrefixes.first(where: { startsWith(units, at: index, prefix: $0) })
            else {
                index += 1
                continue
            }
            var end = index + prefix.count
            while end < units.count, !MarkdownText.isJavaWhitespace(units[end]), units[end] != lessThan {
                end += 1
            }
            end = trimmedBareURLEnd(units, start: index, end: end)
            if end > index + prefix.count {
                ranges.append(index..<end)
                index = end
            } else {
                index += 1
            }
        }
        return ranges
    }

    private static func isBareURLBoundary(_ units: [UInt16], at index: Int) -> Bool {
        guard index > 0 else { return true }
        let previous = units[index - 1]
        return MarkdownText.isJavaWhitespace(previous) || bareURLLeadingPunctuation.contains(previous)
    }

    private static func startsWith(_ units: [UInt16], at index: Int, prefix: [UInt16]) -> Bool {
        guard index + prefix.count <= units.count else { return false }
        return units[index..<(index + prefix.count)].elementsEqual(prefix)
    }

    private static func trimmedBareURLEnd(_ units: [UInt16], start: Int, end: Int) -> Int {
        var trimmedEnd = end
        while trimmedEnd > start {
            let last = units[trimmedEnd - 1]
            if bareURLTrailingPunctuation.contains(last) {
                trimmedEnd -= 1
                continue
            }
            if last == closeParen {
                let opens = units[start..<trimmedEnd].filter { $0 == openParen }.count
                let closes = units[start..<trimmedEnd].filter { $0 == closeParen }.count
                if closes > opens {
                    trimmedEnd -= 1
                    continue
                }
            }
            break
        }
        return trimmedEnd
    }
}
