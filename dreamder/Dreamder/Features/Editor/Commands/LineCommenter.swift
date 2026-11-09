import Foundation

nonisolated enum LineCommenter {
    enum Outcome: Equatable, Sendable {
        case edit(EditorCommandResult)
        case unsupported(String)
        case unchanged
    }

    static let unsupportedMessage = "Comments are not supported for this file type"

    static func toggle(in text: NSString, selections: [NSRange], language: CommentLanguage) -> Outcome {
        guard let base = LineCommentStyle(language: language) else {
            return .unsupported(unsupportedMessage)
        }
        guard text.length > 0 else { return .unchanged }
        var engine = LineCommentEngine(text: text, selections: selections, base: base)
        engine.run()
        return engine.outcome
    }
}

nonisolated private struct LineCommentStyle {
    enum Kind {
        case line(prefix: String)
        case block(prefix: String, suffix: String)
    }

    let kind: Kind
    let language: CommentLanguage

    init?(language: CommentLanguage) {
        if let prefix = language.linePrefix {
            kind = .line(prefix: prefix)
        } else if let prefix = language.blockPrefix, let suffix = language.blockSuffix {
            kind = .block(prefix: prefix, suffix: suffix)
        } else {
            return nil
        }
        self.language = language
    }

    init(markupOf language: CommentLanguage) {
        kind = .block(prefix: CommentLanguage.jsxMarkupPrefix, suffix: CommentLanguage.jsxMarkupSuffix)
        self.language = language.jsxMarkup
    }

    var leadingPrefix: String {
        switch kind {
        case .line(let prefix), .block(let prefix, _):
            prefix
        }
    }
}

nonisolated private enum CaretUpdate {
    case putAtCommentStart
    case shiftDown
    case restoreSelection
}

nonisolated private struct CommentedSpan {
    let start: Int
    let end: Int
}

nonisolated private struct LineBlock {
    var startLine: Int
    var endLine: Int
    var carets: [Int]
    var caretUpdate: CaretUpdate?
    var styles: [LineCommentStyle] = []
    var spans: [CommentedSpan?] = []
    var commentWithIndent = false

    var isSingleLine: Bool { startLine == endLine }
}

nonisolated private struct LineCommentEngine {
    var buffer: CommentTextBuffer
    let lines: EditorLineIndex
    let selections: [NSRange]
    let base: LineCommentStyle
    let markupScanner: JsxMarkupScanner?
    let carets: [Int]
    var blocks: [LineBlock] = []

    init(text: NSString, selections: [NSRange], base: LineCommentStyle) {
        let units = CommentTextBuffer.units(of: text)
        var buffer = CommentTextBuffer(units: units)
        carets = selections.map {
            buffer.addMarker(start: $0.location, end: $0.location + $0.length, greedy: $0.length == 0)
        }
        self.buffer = buffer
        self.lines = EditorLineIndex(text)
        self.selections = selections
        self.base = base
        markupScanner = base.language.isJsx ? JsxMarkupScanner(units: units) : nil
    }

    var outcome: LineCommenter.Outcome {
        let edits = buffer.edits()
        guard !edits.isEmpty else { return .unchanged }
        let resulting = carets.indices.map { index -> NSRange in
            let range = buffer.markerRange(carets[index])
            return NSRange(location: range.lowerBound, length: selections[index].length == 0 ? 0 : range.count)
        }
        return .edit(EditorCommandResult(edits: edits, selections: resulting))
    }

    mutating func run() {
        collectBlocks()
        let allLinesCommented = classifyBlocks()
        let moveCarets = !blocks.contains { $0.carets.count > 1 && !$0.isSingleLine }
        for index in blocks.indices.reversed() {
            let block = blocks[index]
            if !allLinesCommented {
                if block.commentWithIndent {
                    commentWithIndent(block)
                } else {
                    commentAtFirstColumn(block)
                }
            } else {
                uncomment(block)
            }
            if moveCarets, let update = block.caretUpdate {
                apply(update, to: block)
            }
        }
    }

    private func isLineEmpty(_ line: Int) -> Bool {
        buffer.isBlank(lines.lines[line].start..<lines.lines[line].contentEnd)
    }

    private mutating func collectBlocks() {
        for (index, selection) in selections.enumerated() {
            let hasSelection = selection.length > 0
            let startOffset = selection.location
            let endOffset = selection.location + selection.length
            let startLine = lines.lineIndex(containing: startOffset)
            var endLine = lines.lineIndex(containing: endOffset)
            if endLine > startLine && lines.lines[endLine].start == endOffset {
                endLine -= 1
            }
            let update: CaretUpdate?
            if !hasSelection {
                update = isLineEmpty(startLine) ? .putAtCommentStart : .shiftDown
            } else if selectsWholeLines(startOffset: startOffset, endOffset: endOffset) {
                update = .restoreSelection
            } else {
                update = nil
            }
            if var last = blocks.last, startLine <= last.endLine + 1 {
                last.carets.append(carets[index])
                last.endLine = max(last.endLine, endLine)
                last.caretUpdate = update
                blocks[blocks.count - 1] = last
            } else {
                blocks.append(LineBlock(startLine: startLine, endLine: endLine, carets: [carets[index]], caretUpdate: update))
            }
        }
    }

    private func selectsWholeLines(startOffset: Int, endOffset: Int) -> Bool {
        let first = lines.line(containing: startOffset)
        let last = lines.line(containing: endOffset - 1)
        return startOffset == first.start && last.hasTerminator && endOffset == last.end
    }

    private func lineStyle(_ line: Int) -> LineCommentStyle {
        guard let markupScanner else { return base }
        let firstText = buffer.shiftForward(lines.lines[line].start, skipping: CommentTextBuffer.spaceAndTab)
        return markupScanner.isMarkup(at: firstText) ? LineCommentStyle(markupOf: base.language) : base
    }

    private mutating func classifyBlocks() -> Bool {
        var allLinesCommented = true
        var hasCommentedNonEmptyLine = false
        for index in blocks.indices {
            var block = blocks[index]
            block.commentWithIndent = !lineStyle(block.startLine).language.lineCommentAtFirstColumn
            for line in block.startLine...block.endLine {
                let style = lineStyle(line)
                let span = commentedSpan(of: line, style: style, isMultiline: !block.isSingleLine)
                block.styles.append(style)
                block.spans.append(span)
                let lineEmpty = isLineEmpty(line)
                if span != nil && !lineEmpty { hasCommentedNonEmptyLine = true }
                if allLinesCommented && span == nil && (block.isSingleLine || !lineEmpty) {
                    allLinesCommented = false
                }
            }
            if allLinesCommented && !block.isSingleLine && !hasCommentedNonEmptyLine {
                allLinesCommented = false
            }
            blocks[index] = block
        }
        return allLinesCommented
    }

    private func commentedSpan(of line: Int, style: LineCommentStyle, isMultiline: Bool) -> CommentedSpan? {
        let lineStart = buffer.shiftForward(lines.lines[line].start, skipping: CommentTextBuffer.spaceAndTab)
        switch style.kind {
        case .line(let prefix):
            let trimmed = Self.trimmingTrailingWhitespace(prefix)
            return buffer.matches(trimmed, at: lineStart) ? CommentedSpan(start: lineStart, end: -1) : nil
        case .block(let prefix, let suffix):
            let length = buffer.length
            var lineEnd = lines.lines[line].contentEnd
            if lineEnd == length {
                let shifted = buffer.shiftBackward(length - 1, skipping: CommentTextBuffer.spaceAndTab)
                if shifted < length - 1 { lineEnd = shifted }
            } else {
                lineEnd = buffer.shiftBackward(lineEnd, skipping: CommentTextBuffer.spaceAndTab)
            }
            let blankInsideBlock = lineStart == lineEnd && isMultiline
            let wrapped = buffer.matches(prefix, at: lineStart)
                && buffer.matches(suffix, at: lineEnd - suffix.utf16.count)
            return blankInsideBlock || wrapped ? CommentedSpan(start: lineStart, end: lineEnd) : nil
        }
    }

    private static func trimmingTrailingWhitespace(_ string: String) -> String {
        var result = string
        while let last = result.last, last.isWhitespace { result.removeLast() }
        return result
    }

    private mutating func commentAtFirstColumn(_ block: LineBlock) {
        for line in (block.startLine...block.endLine).reversed() {
            commentLine(block, line: line, offset: lines.lines[line].start)
        }
    }

    private mutating func commentWithIndent(_ block: LineBlock) {
        let indent = minimumIndent(of: block)
        let indentWidth = CommentTextBuffer.indentWidth(of: indent.utf16)
        for line in (block.startLine...block.endLine).reversed() {
            let lineStart = lines.lines[line].start
            var offset = lineStart
            var consumed = 0
            while consumed < indentWidth {
                guard let value = buffer.unit(at: offset), value == 0x20 || value == 0x09 else {
                    buffer.replace(lineStart..<offset, with: indent)
                    offset = lineStart + indent.utf16.count
                    break
                }
                consumed = value == 0x09 ? (consumed / 4 + 1) * 4 : consumed + 1
                offset += 1
            }
            commentLine(block, line: line, offset: offset)
        }
    }

    private func minimumIndent(of block: LineBlock) -> String {
        let blockIndent = buffer.minIndent(
            firstLineStart: lines.lines[block.startLine].start,
            lastLineStart: lines.lines[block.endLine].start
        )
        guard block.startLine > 0, let previous = commentIndent(ofLine: block.startLine - 1) else {
            return blockIndent ?? ""
        }
        guard let blockIndent,
              CommentTextBuffer.indentWidth(of: blockIndent.utf16) <= CommentTextBuffer.indentWidth(of: previous.utf16)
        else { return previous }
        return blockIndent
    }

    private func commentIndent(ofLine line: Int) -> String? {
        let lineStart = lines.lines[line].start
        let commentStart = buffer.shiftForward(lineStart, skipping: CommentTextBuffer.spaceAndTab)
        let prefix = lineStyle(line).leadingPrefix
        guard buffer.matches(prefix, at: commentStart) else { return nil }
        return buffer.string(in: lineStart..<commentStart)
    }

    private mutating func commentLine(_ block: LineBlock, line: Int, offset: Int) {
        let style = block.styles[line - block.startLine]
        let marker = buffer.addMarker(start: offset, end: buffer.lineEnd(from: offset), greedy: true)
        let skipsEscaping = insertComment(block, line: line, offset: offset, style: style)
        if !skipsEscaping {
            buffer.processEscaping(style.language, marker: marker, escape: true)
        }
        buffer.releaseMarker(marker)
    }

    private mutating func insertComment(_ block: LineBlock, line: Int, offset: Int, style: LineCommentStyle) -> Bool {
        switch style.kind {
        case .line(var prefix):
            let shifted = buffer.shiftForward(offset, skipping: CommentTextBuffer.spaceAndTab)
            if style.language.lineCommentAddsSpace, let next = buffer.unit(at: shifted),
               block.caretUpdate == .putAtCommentStart || !CommentTextBuffer.isLineBreak(next)
            {
                prefix += " "
            }
            buffer.insert(prefix, at: offset)
            return false
        case .block(let prefix, let suffix):
            return insertBlockComment(block, line: line, offset: offset, prefix: prefix, suffix: suffix, style: style)
        }
    }

    private mutating func insertBlockComment(
        _ block: LineBlock,
        line: Int,
        offset: Int,
        prefix: String,
        suffix: String,
        style: LineCommentStyle
    ) -> Bool {
        let addsSpace = style.language.blockCommentAddsSpace
        let newPrefix = addsSpace ? prefix + " " : prefix
        let newSuffix = addsSpace ? " " + suffix : suffix
        var endOffset = buffer.lineEnd(from: offset)
        if endOffset == offset && !block.isSingleLine { return true }
        let length = buffer.length
        if endOffset == length {
            let shifted = buffer.shiftBackward(length - 1, skipping: CommentTextBuffer.spaceAndTab) + 1
            if shifted < length { endOffset = shifted }
        } else {
            endOffset = buffer.shiftBackward(endOffset, skipping: CommentTextBuffer.spaceAndTab)
        }
        if endOffset < offset || (offset == length - 1 && line != lines.count - 1) { return true }
        let prefixUnits = Array(prefix.utf16)
        let suffixUnits = Array(suffix.utf16)
        let text = Array(buffer.units[offset..<endOffset])
        var prefixes: [Int] = []
        var suffixes: [Int] = []
        var position = 0
        while position < text.count {
            let nearestPrefix = CommentTextBuffer.index(of: prefixUnits, in: text, from: position)
            let nearestSuffix = CommentTextBuffer.index(of: suffixUnits, in: text, from: position)
            if min(nearestPrefix, nearestSuffix) == text.count { break }
            if nearestPrefix < nearestSuffix {
                prefixes.append(nearestPrefix)
                position = nearestPrefix + prefixUnits.count
            } else {
                suffixes.append(nearestSuffix)
                position = nearestSuffix + suffixUnits.count
            }
        }
        let commentedPrefix = style.language.commentedBlockPrefix
        let commentedSuffix = style.language.commentedBlockSuffix
        let lastSuffixClosesLine = commentedSuffix == nil
            && (suffixes.last.map { offset + $0 + suffixUnits.count >= endOffset } ?? false)
        if !lastSuffixClosesLine {
            buffer.insert(newSuffix, at: endOffset)
        }
        var prefixIndex = prefixes.count - 1
        var suffixIndex = suffixes.count - 1
        while prefixIndex >= 0 || suffixIndex >= 0 {
            if suffixIndex == -1 || (prefixIndex != -1 && prefixes[prefixIndex] > suffixes[suffixIndex]) {
                let nested = offset + prefixes[prefixIndex]
                prefixIndex -= 1
                if let commentedPrefix {
                    buffer.replace(nested..<nested + prefixUnits.count, with: commentedPrefix)
                } else if nested != offset {
                    buffer.insert(newSuffix, at: nested)
                }
            } else {
                let nested = offset + suffixes[suffixIndex]
                suffixIndex -= 1
                if let commentedSuffix {
                    buffer.replace(nested..<nested + suffixUnits.count, with: commentedSuffix)
                } else if nested + suffixUnits.count < endOffset {
                    buffer.insert(newPrefix, at: nested + suffixUnits.count)
                }
            }
        }
        let firstPrefixOpensLine = commentedPrefix == nil && prefixes.first == 0
        if !firstPrefixOpensLine {
            buffer.insert(newPrefix, at: offset)
        }
        return false
    }

    private mutating func uncomment(_ block: LineBlock) {
        for line in (block.startLine...block.endLine).reversed() {
            guard let span = block.spans[line - block.startLine], span.start != span.end else { continue }
            let style = block.styles[line - block.startLine]
            switch style.kind {
            case .line(let prefix):
                uncommentLinePrefix(line: line, start: span.start, prefix: prefix, style: style)
            case .block(let prefix, let suffix):
                uncommentBlockLine(span: span, prefix: prefix, suffix: suffix, style: style)
            }
        }
    }

    private mutating func uncommentLinePrefix(line: Int, start: Int, prefix: String, style: LineCommentStyle) {
        let spaced = style.language.lineCommentAddsSpace ? prefix + " " : prefix
        let trimmed = spaced.trimmingCharacters(in: .whitespaces)
        let removed = buffer.matches(spaced, at: start) ? spaced.utf16.count : trimmed.utf16.count
        buffer.delete(start..<start + removed)
        let lineStart = lines.lines[line].start
        let lineEnd = buffer.lineEnd(from: lineStart)
        if buffer.isBlank(lineStart..<lineEnd) {
            buffer.delete(lineStart..<lineEnd)
        }
    }

    private mutating func uncommentBlockLine(
        span: CommentedSpan,
        prefix: String,
        suffix: String,
        style: LineCommentStyle
    ) {
        let prefixUnits = Array(prefix.utf16)
        let suffixUnits = Array(suffix.utf16)
        let text = Array(buffer.units[span.start..<span.end])
        var prefixes: [Int] = []
        var suffixes: [Int] = []
        var position = 0
        while position < text.count {
            let prefixPosition = CommentTextBuffer.index(of: prefixUnits, in: text, from: position)
            if prefixPosition == text.count { break }
            prefixes.append(prefixPosition)
            position = prefixPosition + prefixUnits.count
            var suffixPosition = CommentTextBuffer.index(of: suffixUnits, in: text, from: position)
            if suffixPosition == text.count { suffixPosition = text.count - suffixUnits.count }
            suffixes.append(suffixPosition)
            position = suffixPosition + suffixUnits.count
        }
        let marker = buffer.addMarker(start: span.start, end: span.end)
        for index in prefixes.indices.reversed() {
            uncommentRange(
                start: span.start + prefixes[index],
                end: min(span.start + suffixes[index] + suffixUnits.count, span.end),
                prefixLength: prefixUnits.count,
                suffix: suffix,
                style: style
            )
        }
        buffer.processEscaping(style.language, marker: marker, escape: false)
        buffer.releaseMarker(marker)
    }

    private mutating func uncommentRange(
        start: Int,
        end: Int,
        prefixLength: Int,
        suffix: String,
        style: LineCommentStyle
    ) {
        let removesSpace = style.language.blockCommentAddsSpace
        let suffixLength = suffix.utf16.count
        var rangeEnd = end
        if rangeEnd >= suffixLength && buffer.matches(suffix, at: rangeEnd - suffixLength) {
            var from = rangeEnd - suffixLength
            if removesSpace && buffer.unit(at: from - 1) == 0x20 { from -= 1 }
            buffer.delete(from..<rangeEnd)
            rangeEnd = from
        }
        if style.language.commentedBlockPrefix != nil && style.language.commentedBlockSuffix != nil {
            buffer.commentNestedComments(in: start..<rangeEnd, language: style.language)
        }
        var to = min(start + prefixLength, rangeEnd)
        if removesSpace && to < rangeEnd && buffer.unit(at: to) == 0x20 { to += 1 }
        buffer.delete(start..<to)
    }

    private mutating func apply(_ update: CaretUpdate, to block: LineBlock) {
        switch update {
        case .putAtCommentStart:
            let style = block.styles[0]
            var offset = buffer.shiftForward(lines.lines[block.startLine].start, skipping: CommentTextBuffer.spaceAndTab)
            offset += style.leadingPrefix.utf16.count
            offset = buffer.shiftForward(offset, skipping: CommentTextBuffer.spaceAndTab)
            if style.language.blockCommentAddsSpace,
               let suffix = style.language.blockSuffix,
               buffer.matches(suffix, at: offset),
               buffer.unit(at: offset - 1) == 0x20
            {
                offset -= 1
            }
            offset = min(offset, buffer.length)
            for caret in block.carets {
                buffer.moveMarker(caret, to: offset..<offset)
            }
        case .shiftDown:
            for caret in block.carets {
                let offset = buffer.markerRange(caret).lowerBound
                let lineEnd = buffer.lineEnd(from: offset)
                guard lineEnd < buffer.length else { continue }
                let crlf = buffer.units[lineEnd] == 0x0D && buffer.unit(at: lineEnd + 1) == 0x0A
                let nextStart = lineEnd + (crlf ? 2 : 1)
                let column = offset - buffer.lineStart(containing: offset)
                let target = min(nextStart + column, buffer.lineEnd(from: nextStart))
                buffer.moveMarker(caret, to: target..<target)
            }
        case .restoreSelection:
            for caret in block.carets {
                let range = buffer.markerRange(caret)
                buffer.moveMarker(caret, to: buffer.lineStart(containing: range.lowerBound)..<range.upperBound)
            }
        }
    }
}
