import Foundation

nonisolated struct CommentTextBuffer {
    private struct Marker {
        var start: Int
        var end: Int
        var greedy: Bool
        var isActive: Bool
    }

    private struct DirtySpan {
        var start: Int
        var length: Int
        var originalLength: Int
    }

    static let spaceAndTab: Set<UInt16> = [0x20, 0x09]
    static let spaceTabAndNewline: Set<UInt16> = [0x20, 0x09, 0x0A]

    private let originalUnits: [UInt16]
    private(set) var units: [UInt16]
    private var markers: [Marker] = []
    private var dirtySpans: [DirtySpan] = []

    init(units: [UInt16]) {
        originalUnits = units
        self.units = units
    }

    static func units(of text: NSString) -> [UInt16] {
        var result = [UInt16](repeating: 0, count: text.length)
        text.getCharacters(&result, range: NSRange(location: 0, length: text.length))
        return result
    }

    static func isLineBreak(_ unit: UInt16) -> Bool {
        unit == 0x0A || unit == 0x0D
    }

    var length: Int { units.count }

    func unit(at offset: Int) -> UInt16? {
        units.indices.contains(offset) ? units[offset] : nil
    }

    func matches(_ string: String, at offset: Int) -> Bool {
        CommentTextBuffer.matches(Array(string.utf16), in: units, at: offset)
    }

    static func matches(_ needle: [UInt16], in haystack: [UInt16], at offset: Int) -> Bool {
        guard offset >= 0, offset + needle.count <= haystack.count else { return false }
        return haystack[offset..<offset + needle.count].elementsEqual(needle)
    }

    static func index(of needle: [UInt16], in haystack: [UInt16], from position: Int) -> Int {
        var offset = max(position, 0)
        while offset + needle.count <= haystack.count {
            if matches(needle, in: haystack, at: offset) { return offset }
            offset += 1
        }
        return haystack.count
    }

    func shiftForward(_ offset: Int, skipping skipped: Set<UInt16>) -> Int {
        var cursor = offset
        while cursor < units.count, skipped.contains(units[cursor]) { cursor += 1 }
        return cursor
    }

    func shiftBackward(_ offset: Int, skipping skipped: Set<UInt16>) -> Int {
        if offset >= units.count { return offset }
        var cursor = offset
        while cursor >= 0, skipped.contains(units[cursor]) { cursor -= 1 }
        return cursor
    }

    func lineStart(containing offset: Int) -> Int {
        var cursor = offset
        while cursor > 0, !CommentTextBuffer.isLineBreak(units[cursor - 1]) { cursor -= 1 }
        return cursor
    }

    func lineEnd(from offset: Int) -> Int {
        var cursor = offset
        while cursor < units.count, !CommentTextBuffer.isLineBreak(units[cursor]) { cursor += 1 }
        return cursor
    }

    func isBlank(_ range: Range<Int>) -> Bool {
        units[range].allSatisfy { $0 == 0x20 || $0 == 0x09 || CommentTextBuffer.isLineBreak($0) }
    }

    func string(in range: Range<Int>) -> String {
        String(decoding: units[range], as: UTF16.self)
    }

    static func indentWidth<Units: Sequence>(of units: Units) -> Int where Units.Element == UInt16 {
        units.reduce(0) { $1 == 0x09 ? ($0 / 4 + 1) * 4 : $0 + 1 }
    }

    func minIndent(firstLineStart: Int, lastLineStart: Int) -> String? {
        if let found = minIndentInLines(from: firstLineStart, through: lastLineStart) { return found }
        guard firstLineStart == lastLineStart else { return nil }
        let end = lineEnd(from: firstLineStart)
        let crlf = units[end] == 0x0D && unit(at: end + 1) == 0x0A
        let next = end + (crlf ? 2 : 1)
        return minIndent(firstLineStart: next, lastLineStart: next)
    }

    private func minIndentInLines(from first: Int, through last: Int) -> String? {
        var best: Range<Int>?
        var bestWidth = 0
        var lineStart = first
        while true {
            let textStart = shiftForward(lineStart, skipping: CommentTextBuffer.spaceAndTab)
            let isEmptyLine = textStart < units.count && CommentTextBuffer.isLineBreak(units[textStart])
            if !isEmptyLine {
                let indent = lineStart..<textStart
                let width = CommentTextBuffer.indentWidth(of: units[indent])
                if best == nil || width < bestWidth {
                    best = indent
                    bestWidth = width
                }
            }
            let end = lineEnd(from: lineStart)
            guard lineStart < last, end < units.count else { break }
            let crlf = units[end] == 0x0D && unit(at: end + 1) == 0x0A
            lineStart = end + (crlf ? 2 : 1)
        }
        return best.map { string(in: $0) }
    }

    mutating func addMarker(start: Int, end: Int, greedy: Bool = false) -> Int {
        markers.append(Marker(start: start, end: end, greedy: greedy, isActive: true))
        return markers.count - 1
    }

    func markerRange(_ identifier: Int) -> Range<Int> {
        markers[identifier].start..<markers[identifier].end
    }

    mutating func moveMarker(_ identifier: Int, to range: Range<Int>) {
        markers[identifier].start = range.lowerBound
        markers[identifier].end = range.upperBound
    }

    mutating func releaseMarker(_ identifier: Int) {
        markers[identifier].isActive = false
    }

    mutating func insert(_ string: String, at offset: Int) {
        replace(offset..<offset, with: string)
    }

    mutating func delete(_ range: Range<Int>) {
        replace(range, with: "")
    }

    mutating func replace(_ range: Range<Int>, with string: String) {
        let replacement = Array(string.utf16)
        units.replaceSubrange(range, with: replacement)
        for index in markers.indices where markers[index].isActive {
            let marker = markers[index]
            let start = CommentTextBuffer.mapped(
                marker.start, in: range, newLength: replacement.count, isStart: true, greedy: marker.greedy
            )
            let end = CommentTextBuffer.mapped(
                marker.end, in: range, newLength: replacement.count, isStart: false, greedy: marker.greedy
            )
            markers[index].start = start
            markers[index].end = max(start, end)
        }
        recordChange(range: range, newLength: replacement.count)
    }

    private static func mapped(
        _ position: Int,
        in range: Range<Int>,
        newLength: Int,
        isStart: Bool,
        greedy: Bool
    ) -> Int {
        if range.isEmpty {
            if position < range.lowerBound { return position }
            if position > range.lowerBound { return position + newLength }
            let shifts = isStart ? !greedy : greedy
            return shifts ? position + newLength : position
        }
        if position <= range.lowerBound { return position }
        if position >= range.upperBound { return position + newLength - range.count }
        return isStart ? range.lowerBound : range.lowerBound + newLength
    }

    private mutating func recordChange(range: Range<Int>, newLength: Int) {
        let delta = newLength - range.count
        var before: [DirtySpan] = []
        var after: [DirtySpan] = []
        var unionStart = range.lowerBound
        var unionEnd = range.upperBound
        var mergedLength = 0
        var mergedOriginalLength = 0
        for span in dirtySpans {
            let spanEnd = span.start + span.length
            if spanEnd < range.lowerBound {
                before.append(span)
            } else if span.start > range.upperBound {
                after.append(
                    DirtySpan(start: span.start + delta, length: span.length, originalLength: span.originalLength)
                )
            } else {
                unionStart = min(unionStart, span.start)
                unionEnd = max(unionEnd, spanEnd)
                mergedLength += span.length
                mergedOriginalLength += span.originalLength
            }
        }
        let unionLength = unionEnd - unionStart
        let merged = DirtySpan(
            start: unionStart,
            length: unionLength + delta,
            originalLength: unionLength - mergedLength + mergedOriginalLength
        )
        dirtySpans = before + [merged] + after
    }

    func edits() -> [EditorTextEdit] {
        var shift = 0
        var result: [EditorTextEdit] = []
        for span in dirtySpans {
            let originalStart = span.start - shift
            shift += span.length - span.originalLength
            let oldUnits = originalUnits[originalStart..<originalStart + span.originalLength]
            let newUnits = units[span.start..<span.start + span.length]
            if oldUnits.elementsEqual(newUnits) { continue }
            result.append(
                EditorTextEdit(
                    range: NSRange(location: originalStart, length: span.originalLength),
                    replacement: String(decoding: newUnits, as: UTF16.self)
                )
            )
        }
        return result
    }

    mutating func escapeXmlComment(in identifier: Int) {
        let prefix = "<!--"
        let suffix = "-->"
        let prefixLength = prefix.utf16.count
        let suffixLength = suffix.utf16.count
        let prefixStart = shiftForward(markerRange(identifier).lowerBound, skipping: CommentTextBuffer.spaceTabAndNewline)
        var start = prefixStart
        if matches(prefix, at: prefixStart) { start += prefixLength }
        var end = markerRange(identifier).upperBound
        if matches(suffix, at: end - suffixLength) { end -= suffixLength }
        if start >= end { return }
        var cursor = end - 2
        while cursor >= start {
            if matches("--", at: cursor), !matches(suffix, at: cursor), !matches(prefix, at: cursor - 2) {
                replace(cursor..<cursor + 2, with: "&#45;&#45;")
            }
            cursor -= 1
        }
        if matches(">", at: start) { replace(start..<start + 1, with: "&gt;") }
        if matches(prefix + "-", at: prefixStart) { insert(" ", at: start) }
        let currentEnd = markerRange(identifier).upperBound
        if matches("-" + suffix, at: currentEnd - suffixLength - 1) { insert(" ", at: currentEnd - suffixLength) }
    }

    mutating func unescapeXmlComment(in identifier: Int) {
        let escapedDashes = "&#45;&#45;"
        let range = markerRange(identifier)
        var cursor = range.upperBound
        while cursor >= range.lowerBound {
            if matches(escapedDashes, at: cursor) { replace(cursor..<cursor + escapedDashes.utf16.count, with: "--") }
            cursor -= 1
        }
        if matches("&gt;", at: range.lowerBound) { replace(range.lowerBound..<range.lowerBound + 4, with: ">") }
    }

    mutating func processEscaping(_ language: CommentLanguage, marker identifier: Int, escape: Bool) {
        guard language.escapesXmlDashes else { return }
        if escape {
            escapeXmlComment(in: identifier)
        } else {
            unescapeXmlComment(in: identifier)
        }
    }

    mutating func commentNestedComments(in range: Range<Int>, language: CommentLanguage) {
        guard let commentedPrefixText = language.commentedBlockPrefix,
              let commentedSuffixText = language.commentedBlockSuffix,
              let commentPrefix = language.blockPrefix,
              let commentSuffix = language.blockSuffix else { return }
        let commentedPrefix = Array(commentedPrefixText.utf16)
        let commentedSuffix = Array(commentedSuffixText.utf16)
        let offset = range.lowerBound
        let text = Array(units[range])
        var toReplace: [Int] = []
        var prefixes: [Int] = []
        var nearestSuffix = CommentTextBuffer.index(of: commentedSuffix, in: text, from: 0)
        var nearestPrefix = CommentTextBuffer.index(of: commentedPrefix, in: text, from: 0)
        var level = 0
        var lastSuffix = -1
        var position = min(nearestPrefix, nearestSuffix)
        while position < text.count {
            if position == nearestPrefix {
                if level <= 0 {
                    if lastSuffix != -1 { toReplace.append(lastSuffix) }
                    level = 1
                    lastSuffix = -1
                    toReplace.append(position)
                    prefixes.append(position)
                } else {
                    level += 1
                }
                nearestPrefix = CommentTextBuffer.index(of: commentedPrefix, in: text, from: nearestPrefix + 1)
            } else {
                lastSuffix = position
                level -= 1
                nearestSuffix = CommentTextBuffer.index(of: commentedSuffix, in: text, from: nearestSuffix + 1)
            }
            position = min(nearestPrefix, nearestSuffix)
        }
        if lastSuffix != -1 { toReplace.append(lastSuffix) }
        var prefixIndex = prefixes.count - 1
        for replacedPosition in toReplace.reversed() {
            if prefixIndex >= 0, replacedPosition == prefixes[prefixIndex] {
                prefixIndex -= 1
                let start = offset + replacedPosition
                replace(start..<start + commentedPrefix.count, with: commentPrefix)
            } else {
                let start = offset + replacedPosition
                replace(start..<start + commentedSuffix.count, with: commentSuffix)
            }
        }
    }
}

nonisolated struct CommentRegion: Equatable, Sendable {
    let range: Range<Int>
    let isLine: Bool
}

nonisolated enum CommentRegionScanner {
    static func regions(in units: [UInt16], language: CommentLanguage) -> [CommentRegion] {
        let linePrefix = Array((language.linePrefix ?? "").utf16)
        let blockPrefix = Array((language.blockPrefix ?? "").utf16)
        let blockSuffix = Array((language.blockSuffix ?? "").utf16)
        var regions: [CommentRegion] = []
        var offset = 0
        while offset < units.count {
            if !linePrefix.isEmpty, CommentTextBuffer.matches(linePrefix, in: units, at: offset) {
                var end = offset
                while end < units.count, !CommentTextBuffer.isLineBreak(units[end]) { end += 1 }
                regions.append(CommentRegion(range: offset..<end, isLine: true))
                offset = end
            } else if !blockPrefix.isEmpty, CommentTextBuffer.matches(blockPrefix, in: units, at: offset) {
                let found = CommentTextBuffer.index(of: blockSuffix, in: units, from: offset + blockPrefix.count)
                let end = min(found + blockSuffix.count, units.count)
                regions.append(CommentRegion(range: offset..<end, isLine: false))
                offset = end
            } else if language.hasStringLiterals, [0x22, 0x27, 0x60].contains(units[offset]) {
                offset = stringEnd(in: units, from: offset)
            } else {
                offset += 1
            }
        }
        return regions
    }

    private static func stringEnd(in units: [UInt16], from offset: Int) -> Int {
        let quote = units[offset]
        let tripleQuote: [UInt16] = [0x22, 0x22, 0x22]
        if CommentTextBuffer.matches(tripleQuote, in: units, at: offset) {
            return min(CommentTextBuffer.index(of: tripleQuote, in: units, from: offset + 3) + 3, units.count)
        }
        var cursor = offset + 1
        while cursor < units.count {
            let value = units[cursor]
            if value == 0x5C {
                cursor += 2
            } else if value == quote {
                return cursor + 1
            } else if quote != 0x60, CommentTextBuffer.isLineBreak(value) {
                return cursor
            } else {
                cursor += 1
            }
        }
        return units.count
    }
}

nonisolated private struct BlockCommentStyle {
    let language: CommentLanguage
    let prefix: String
    let suffix: String

    var prefixLength: Int { prefix.utf16.count }
    var trimmedPrefix: String { prefix.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedSuffix: String { suffix.trimmingCharacters(in: .whitespacesAndNewlines) }
}

nonisolated enum BlockCommenter {
    static let unsupportedMessage = "Block comments are not supported for this file type"

    static func toggle(in text: NSString, selections: [NSRange], language: CommentLanguage) -> LineCommenter.Outcome {
        guard let prefix = language.blockPrefix, let suffix = language.blockSuffix else {
            return .unsupported(unsupportedMessage)
        }
        var engine = BlockCommentEngine(
            units: CommentTextBuffer.units(of: text),
            selections: selections,
            base: BlockCommentStyle(language: language, prefix: prefix, suffix: suffix)
        )
        engine.run()
        return engine.outcome
    }
}

nonisolated private struct BlockCommentEngine {
    static let intersectsMessage = "Block comment intersects an existing comment"
    static let wrappingSuffixMessage = "Selection contains a block comment suffix outside of a comment"

    var buffer: CommentTextBuffer
    let base: BlockCommentStyle
    let jsxScanner: JsxMarkupScanner?
    let carets: [Int]
    var warning: String?

    init(units: [UInt16], selections: [NSRange], base: BlockCommentStyle) {
        var buffer = CommentTextBuffer(units: units)
        carets = selections.map { buffer.addMarker(start: $0.location, end: $0.location + $0.length) }
        self.buffer = buffer
        self.base = base
        jsxScanner = base.language.isJsx ? JsxMarkupScanner(units: units) : nil
    }

    var outcome: LineCommenter.Outcome {
        let edits = buffer.edits()
        guard !edits.isEmpty else {
            if let warning { return .unsupported(warning) }
            return .unchanged
        }
        let selections = carets.map { identifier -> NSRange in
            let range = buffer.markerRange(identifier)
            return NSRange(location: range.lowerBound, length: range.count)
        }
        return .edit(EditorCommandResult(edits: edits, selections: selections))
    }

    mutating func run() {
        for caret in carets.reversed() {
            process(caret: caret)
        }
    }

    private func commentStyle(at offset: Int) -> BlockCommentStyle {
        guard let jsxScanner, jsxScanner.isMarkup(at: offset) else { return base }
        let markup = base.language.jsxMarkup
        return BlockCommentStyle(
            language: markup,
            prefix: CommentLanguage.jsxMarkupPrefix,
            suffix: CommentLanguage.jsxMarkupSuffix
        )
    }

    private mutating func process(caret: Int) {
        let selection = buffer.markerRange(caret)
        let style = commentStyle(at: selection.lowerBound)
        guard let commented = findCommentedRange(selection: selection, style: style) else {
            if selection.isEmpty {
                insertEmptyComment(caret: caret, at: selection.lowerBound, style: style)
            } else {
                commentRange(caret: caret, range: selection, style: style)
            }
            return
        }
        uncommentRange(caret: caret, range: commented, style: style)
    }

    private mutating func insertEmptyComment(caret: Int, at offset: Int, style: BlockCommentStyle) {
        let addsSpace = style.language.blockCommentAddsSpace
        let caretOffset = offset + (addsSpace ? style.prefixLength + 1 : style.prefixLength)
        let comment = addsSpace ? style.prefix + "  " + style.suffix : style.prefix + style.suffix
        buffer.insert(comment, at: offset)
        buffer.moveMarker(caret, to: caretOffset..<caretOffset)
    }

    private func findCommentedRange(selection: Range<Int>, style: BlockCommentStyle) -> Range<Int>? {
        let regions = CommentRegionScanner.regions(in: buffer.units, language: style.language)
        guard selectionHoldsOnlyComments(selection, regions: regions) else { return nil }
        if !selection.isEmpty, let range = selectedComment(selection, style: style) { return range }
        return commentAtCaret(selection, regions: regions, style: style)
    }

    private func selectionHoldsOnlyComments(_ selection: Range<Int>, regions: [CommentRegion]) -> Bool {
        guard selection.count > 1 else { return true }
        var regionIndex = 0
        for offset in selection.lowerBound..<selection.upperBound - 1 {
            while regionIndex < regions.count, regions[regionIndex].range.upperBound <= offset { regionIndex += 1 }
            let insideComment = regionIndex < regions.count && regions[regionIndex].range.lowerBound <= offset
            let value = buffer.units[offset]
            let isBlank = value == 0x20 || value == 0x09 || CommentTextBuffer.isLineBreak(value)
            if !insideComment && !isBlank { return false }
        }
        return true
    }

    private func selectedComment(_ selection: Range<Int>, style: BlockCommentStyle) -> Range<Int>? {
        let prefix = style.trimmedPrefix
        let suffix = style.trimmedSuffix
        let start = buffer.shiftForward(selection.lowerBound, skipping: CommentTextBuffer.spaceTabAndNewline)
        let end = buffer.shiftBackward(selection.upperBound - 1, skipping: CommentTextBuffer.spaceTabAndNewline) + 1
        guard end - start >= prefix.utf16.count + suffix.utf16.count,
              buffer.matches(prefix, at: start),
              buffer.matches(suffix, at: end - suffix.utf16.count)
        else { return nil }
        return start..<end
    }

    private func commentAtCaret(
        _ selection: Range<Int>,
        regions: [CommentRegion],
        style: BlockCommentStyle
    ) -> Range<Int>? {
        var offset = selection.upperBound - 1
        if offset <= selection.lowerBound { offset += 1 }
        guard let comment = regions.first(where: { $0.range.contains(offset) }) else { return nil }
        if !selection.isEmpty, !(selection.lowerBound <= comment.range.lowerBound && comment.range.upperBound <= selection.upperBound) {
            return nil
        }
        guard buffer.matches(style.trimmedPrefix, at: comment.range.lowerBound),
              buffer.matches(style.trimmedSuffix, at: comment.range.upperBound - style.trimmedSuffix.utf16.count)
        else { return nil }
        return comment.range
    }

    private func breaksExistingComment(_ offset: Int, includingAfterLineComment: Bool, style: BlockCommentStyle) -> Bool {
        guard style.language.detectsCommentTokens, offset != 0 else { return false }
        let regions = CommentRegionScanner.regions(in: buffer.units, language: style.language)
        guard let token = regions.first(where: { $0.range.contains(offset - 1) }) else { return false }
        return token.range.upperBound > offset
            || (includingAfterLineComment && token.range.upperBound == offset && token.isLine)
    }

    private mutating func commentRange(caret: Int, range: Range<Int>, style: BlockCommentStyle) {
        let startOffset = range.lowerBound
        let endOffset = range.upperBound
        if breaksExistingComment(startOffset, includingAfterLineComment: true, style: style)
            || breaksExistingComment(endOffset, includingAfterLineComment: false, style: style)
        {
            warning = warning ?? Self.intersectsMessage
            return
        }
        let startsLine = startOffset == 0 || buffer.unit(at: startOffset - 1).map(CommentTextBuffer.isLineBreak) == true
        let endsLine = endOffset == buffer.length
            || (endOffset > 0 && buffer.unit(at: endOffset - 1).map(CommentTextBuffer.isLineBreak) == true)
        var nestingPrefix = style.prefix
        var nestingSuffix = style.suffix
        if startsLine && endsLine {
            var space = ""
            if !style.language.blockCommentAtFirstColumn {
                let firstLineStart = buffer.lineStart(containing: startOffset)
                let lastLineStart = buffer.lineStart(containing: endOffset - 1)
                space = buffer.minIndent(firstLineStart: firstLineStart, lastLineStart: lastLineStart) ?? ""
            }
            nestingPrefix = space + style.prefix + "\n"
            nestingSuffix = space + nestingSuffix + "\n"
        } else if style.language.blockCommentAddsSpace {
            nestingPrefix += " "
            nestingSuffix = " " + nestingSuffix
        }
        guard let inserted = insertNestedComments(
            start: startOffset,
            end: endOffset,
            commentPrefix: nestingPrefix,
            commentSuffix: nestingSuffix,
            style: style
        ) else { return }
        buffer.moveMarker(caret, to: inserted)
    }

    private func blockRegion(containing offset: Int, in regions: [CommentRegion]) -> CommentRegion? {
        regions.first { !$0.isLine && $0.range.contains(offset) }
    }

    private mutating func insertNestedComments(
        start: Int,
        end: Int,
        commentPrefix: String,
        commentSuffix: String,
        style: BlockCommentStyle
    ) -> Range<Int>? {
        let normalizedPrefix = commentPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSuffix = commentSuffix.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPrefixLength = normalizedPrefix.utf16.count
        let normalizedSuffixLength = normalizedSuffix.utf16.count
        let commentedPrefix = style.language.commentedBlockPrefix
        let commentedSuffix = style.language.commentedBlockSuffix
        let detects = style.language.detectsCommentTokens
        let regions = detects ? CommentRegionScanner.regions(in: buffer.units, language: style.language) : []
        var prefixes: [Int] = []
        var suffixes: [Int] = []
        var offset = start
        while offset < end {
            defer { offset += 1 }
            if buffer.matches(normalizedPrefix, at: offset) {
                if commentedPrefix == nil && detects {
                    guard let region = blockRegion(containing: offset, in: regions), region.range.lowerBound == offset
                    else { continue }
                }
                prefixes.append(offset)
            } else if buffer.matches(normalizedSuffix, at: offset) {
                if commentedSuffix == nil && detects && blockRegion(containing: offset, in: regions) == nil {
                    warning = warning ?? Self.wrappingSuffixMessage
                    return nil
                }
                suffixes.append(offset)
            }
        }
        var shift = 0
        let suffixAlreadyClosesRange = commentedSuffix == nil
            && (suffixes.last.map { $0 + commentSuffix.utf16.count == end } ?? false)
        if !suffixAlreadyClosesRange {
            buffer.insert(commentSuffix, at: end)
            shift += commentSuffix.utf16.count
        }
        var prefixIndex = prefixes.count - 1
        var suffixIndex = suffixes.count - 1
        let selection = start..<end
        while prefixIndex >= 0 || suffixIndex >= 0 {
            if suffixIndex < 0 || (prefixIndex >= 0 && prefixes[prefixIndex] > suffixes[suffixIndex]) {
                shift += commentBound(
                    at: prefixes[prefixIndex],
                    commented: commentedPrefix,
                    skipLength: normalizedPrefixLength,
                    toInsert: commentSuffix,
                    skipsBrace: false,
                    selection: selection
                )
                prefixIndex -= 1
            } else {
                shift += commentBound(
                    at: suffixes[suffixIndex],
                    commented: commentedSuffix,
                    skipLength: normalizedSuffixLength,
                    toInsert: commentPrefix,
                    skipsBrace: true,
                    selection: selection
                )
                suffixIndex -= 1
            }
        }
        let prefixAlreadyOpensRange = commentedPrefix == nil && prefixes.first == start
        if !prefixAlreadyOpensRange {
            buffer.insert(commentPrefix, at: start)
            shift += commentPrefix.utf16.count
        }
        let marker = buffer.addMarker(start: start, end: end + shift)
        buffer.processEscaping(style.language, marker: marker, escape: true)
        let result = buffer.markerRange(marker)
        buffer.releaseMarker(marker)
        return result
    }

    private mutating func commentBound(
        at offset: Int,
        commented: String?,
        skipLength: Int,
        toInsert: String,
        skipsBrace: Bool,
        selection: Range<Int>
    ) -> Int {
        let insertionOffset = offset + (skipsBrace ? skipLength : 0)
        guard let commented else {
            if offset == selection.lowerBound || insertionOffset == selection.upperBound { return 0 }
            buffer.insert(toInsert, at: insertionOffset)
            return toInsert.utf16.count
        }
        buffer.replace(offset..<offset + skipLength, with: commented)
        return commented.utf16.count - skipLength
    }

    private mutating func uncommentRange(caret: Int, range: Range<Int>, style: BlockCommentStyle) {
        let prefix = Array(style.trimmedPrefix.utf16)
        let suffix = Array(style.trimmedSuffix.utf16)
        let text = Array(buffer.units[range])
        var blocks: [(prefix: Range<Int>, suffix: Range<Int>)] = []
        var position = 0
        while true {
            let start = CommentTextBuffer.index(of: prefix, in: text, from: position)
            if start == text.count { break }
            let suffixStart = CommentTextBuffer.index(of: suffix, in: text, from: start + prefix.count)
            if suffixStart == text.count { break }
            let end = suffixStart + suffix.count
            position = end
            blocks.append(
                commentBlock(
                    range: start + range.lowerBound..<end + range.lowerBound,
                    prefixLength: prefix.count,
                    suffixLength: suffix.count,
                    style: style
                )
            )
        }
        let marker = buffer.addMarker(start: range.lowerBound, end: range.upperBound)
        for block in blocks.reversed() {
            buffer.delete(block.prefix)
            let shift = block.prefix.count
            buffer.delete(block.suffix.lowerBound - shift..<block.suffix.upperBound - shift)
            if style.language.commentedBlockPrefix != nil {
                buffer.commentNestedComments(
                    in: block.prefix.upperBound - shift..<block.suffix.lowerBound - shift,
                    language: style.language
                )
            }
        }
        buffer.processEscaping(style.language, marker: marker, escape: false)
        buffer.releaseMarker(marker)
    }

    private func expandedRange(_ range: Range<Int>) -> Range<Int> {
        let before = buffer.shiftBackward(range.lowerBound - 1, skipping: CommentTextBuffer.spaceAndTab)
        let startsLine = before < 0 || CommentTextBuffer.isLineBreak(buffer.units[before])
        guard startsLine else { return range }
        let after = buffer.shiftForward(range.upperBound, skipping: CommentTextBuffer.spaceAndTab)
        let endsLine = after == buffer.length || CommentTextBuffer.isLineBreak(buffer.units[after])
        guard endsLine else { return range }
        var upper = range.upperBound
        if after < buffer.length {
            upper = after + 1
            if buffer.units[after] == 0x0D, buffer.unit(at: after + 1) == 0x0A { upper += 1 }
        }
        return before + 1..<upper
    }

    private func commentBlock(
        range: Range<Int>,
        prefixLength: Int,
        suffixLength: Int,
        style: BlockCommentStyle
    ) -> (prefix: Range<Int>, suffix: Range<Int>) {
        let addsSpace = style.language.blockCommentAddsSpace
        let initialPrefix = range.lowerBound..<range.lowerBound + prefixLength
        var prefix = expandedRange(initialPrefix)
        if addsSpace, initialPrefix == prefix, buffer.unit(at: prefix.upperBound) == 0x20 {
            prefix = prefix.lowerBound..<prefix.upperBound + 1
        }
        let initialSuffix = range.upperBound - suffixLength..<range.upperBound
        var suffix = expandedRange(initialSuffix)
        let spaceIndex = suffix.lowerBound - 1
        if addsSpace, initialSuffix == suffix, prefix.upperBound <= spaceIndex, buffer.unit(at: spaceIndex) == 0x20 {
            suffix = spaceIndex..<suffix.upperBound
        }
        return (prefix, suffix)
    }
}
