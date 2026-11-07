import Foundation

nonisolated extension ComparisonManager {
    static func compareLines(
        boundary: DiffRange,
        _ text1: DiffUnits,
        _ text2: DiffUnits,
        _ offsets1: LineOffsets,
        _ offsets2: LineOffsets,
        _ policy: ComparisonPolicy
    ) throws -> [LineFragment] {
        let lines1 = offsets1.lineContents(in: text1, lines: boundary.start1..<boundary.end1)
        let lines2 = offsets2.lineContents(in: text2, lines: boundary.start2..<boundary.end2)
        let iterable = try ByLine.compare(lines1, lines2, policy)
        return convertIntoLineFragments(boundary: boundary, offsets1, offsets2, iterable)
    }

    static func compareLinesInner(
        boundary: DiffRange,
        _ text1: DiffUnits,
        _ text2: DiffUnits,
        _ offsets1: LineOffsets,
        _ offsets2: LineOffsets,
        _ policy: ComparisonPolicy,
        _ fragmentsPolicy: InnerFragmentsPolicy
    ) throws -> [LineFragment] {
        let lineFragments = try compareLines(boundary: boundary, text1, text2, offsets1, offsets2, policy)
        guard fragmentsPolicy != .none else { return lineFragments }
        return try createInnerFragments(lineFragments, text1, text2, policy, fragmentsPolicy)
    }

    static func compareLinesWordFirst(
        _ text1: DiffUnits,
        _ text2: DiffUnits,
        _ offsets1: LineOffsets,
        _ offsets2: LineOffsets,
        _ policy: ComparisonPolicy
    ) throws -> [LineFragment] {
        let blocks = try ByWord.compareWordsFirst(text1, text2, offsets1, offsets2, policy)
        return blocks.map { block in
            let range = block.lineRange
            let fragment = createLineFragment(range.start1, range.end1, range.start2, range.end2, offsets1, offsets2)
            return LineFragment(fragment, innerFragments: block.fragments)
        }
    }

    static func convertIntoLineFragments(
        boundary: DiffRange,
        _ offsets1: LineOffsets,
        _ offsets2: LineOffsets,
        _ changes: DiffChanges
    ) -> [LineFragment] {
        changes.changes.map { range in
            createLineFragment(
                range.start1 + boundary.start1,
                range.end1 + boundary.start1,
                range.start2 + boundary.start2,
                range.end2 + boundary.start2,
                offsets1,
                offsets2
            )
        }
    }

    static func collectIgnoredRanges(_ ranges: [Range<Int>]) -> DiffBitSet {
        var set = DiffBitSet()
        for range in ranges {
            set.set(from: range.lowerBound, to: range.upperBound)
        }
        return set
    }

    static func compareLinesWithIgnoredRanges(
        _ text1: DiffUnits,
        _ text2: DiffUnits,
        _ offsets1: LineOffsets,
        _ offsets2: LineOffsets,
        _ ignored1: DiffBitSet,
        _ ignored2: DiffBitSet,
        _ fragmentsPolicy: InnerFragmentsPolicy
    ) throws -> [LineFragment] {
        let boundary = DiffRange(0, offsets1.lineCount, 0, offsets2.lineCount)
        return try compareLinesWithIgnoredRanges(
            boundary: boundary,
            text1,
            text2,
            offsets1,
            offsets2,
            ignored1,
            ignored2,
            fragmentsPolicy
        )
    }

    static func compareLinesWithIgnoredRanges(
        boundary: DiffRange,
        _ text1: DiffUnits,
        _ text2: DiffUnits,
        _ offsets1: LineOffsets,
        _ offsets2: LineOffsets,
        _ ignored1: DiffBitSet,
        _ ignored2: DiffBitSet,
        _ fragmentsPolicy: InnerFragmentsPolicy
    ) throws -> [LineFragment] {
        let lineTexts1 = notIgnoredLineContents(boundary.start1, boundary.end1, text1, offsets1, ignored1)
        let lineTexts2 = notIgnoredLineContents(boundary.start2, boundary.end2, text2, offsets2, ignored2)

        let iterable = try ByLine.compare(lineTexts1, lineTexts2, .default)

        let corrected = correctIgnoredRangesSecondStep(boundary, iterable, text1, text2, offsets1, offsets2, ignored1, ignored2)
        let trimmed = trimIgnoredLines(boundary, corrected, text1, text2, offsets1, offsets2, ignored1, ignored2)

        var lineFragments = convertIntoLineFragments(boundary: boundary, offsets1, offsets2, trimmed)
        if fragmentsPolicy != .none {
            lineFragments = try createInnerFragments(lineFragments, text1, text2, .default, fragmentsPolicy)
        }
        return lineFragments.compactMap { trimIgnoredInnerFragments($0, ignored1, ignored2) }
    }

    private static func notIgnoredLineContents(
        _ start: Int,
        _ end: Int,
        _ text: DiffUnits,
        _ offsets: LineOffsets,
        _ ignored: DiffBitSet
    ) -> [DiffUnits] {
        var lines: [DiffUnits] = []
        lines.reserveCapacity(max(end - start, 0))
        for line in start..<max(start, end) {
            var content: DiffUnits = []
            for offset in offsets.lineStart(line)..<offsets.lineEnd(line) where !ignored[offset] {
                content.append(text[offset])
            }
            lines.append(content)
        }
        return lines
    }

    private static func correctIgnoredRangesSecondStep(
        _ boundary: DiffRange,
        _ iterable: DiffChanges,
        _ text1: DiffUnits,
        _ text2: DiffUnits,
        _ offsets1: LineOffsets,
        _ offsets2: LineOffsets,
        _ ignored1: DiffBitSet,
        _ ignored2: DiffBitSet
    ) -> DiffChanges {
        var builder = DiffChangeBuilder(length1: iterable.length1, length2: iterable.length2)
        for range in iterable.unchanged {
            for offset in 0..<(range.end1 - range.start1) {
                let index1 = range.start1 + offset
                let index2 = range.start2 + offset
                if areIgnoredEqualLines(
                    boundary.start1 + index1,
                    boundary.start2 + index2,
                    text1,
                    text2,
                    offsets1,
                    offsets2,
                    ignored1,
                    ignored2
                ) {
                    builder.markEqual(index1, index2)
                }
            }
        }
        return builder.finish()
    }

    private static func trimIgnoredLines(
        _ boundary: DiffRange,
        _ iterable: DiffChanges,
        _ text1: DiffUnits,
        _ text2: DiffUnits,
        _ offsets1: LineOffsets,
        _ offsets2: LineOffsets,
        _ ignored1: DiffBitSet,
        _ ignored2: DiffBitSet
    ) -> DiffChanges {
        var changedRanges: [DiffRange] = []
        for change in iterable.changes {
            let trimmed = TrimUtil.trimExpand(
                change.start1,
                change.start2,
                change.end1,
                change.end2,
                equals: { index1, index2 in
                    areIgnoredEqualLines(
                        boundary.start1 + index1,
                        boundary.start2 + index2,
                        text1,
                        text2,
                        offsets1,
                        offsets2,
                        ignored1,
                        ignored2
                    )
                },
                ignored1: { index in isIgnoredLine(boundary.start1 + index, offsets1, ignored1) },
                ignored2: { index in isIgnoredLine(boundary.start2 + index, offsets2, ignored2) }
            )
            if !trimmed.isEmpty { changedRanges.append(trimmed) }
        }
        return DiffChanges(changes: changedRanges, length1: iterable.length1, length2: iterable.length2)
    }

    private static func trimIgnoredInnerFragments(
        _ fragment: LineFragment,
        _ ignored1: DiffBitSet,
        _ ignored2: DiffBitSet
    ) -> LineFragment? {
        guard let innerFragments = fragment.innerFragments else { return fragment }

        let newInner = innerFragments.compactMap { inner -> DiffFragment? in
            let range1 = trimIgnoredRange(inner.startOffset1, inner.endOffset1, ignored1, fragment.startOffset1)
            let range2 = trimIgnoredRange(inner.startOffset2, inner.endOffset2, ignored2, fragment.startOffset2)
            if range1.start == range1.end && range2.start == range2.end { return nil }
            return DiffFragment(range1.start, range1.end, range2.start, range2.end)
        }

        if newInner.isEmpty { return nil }
        return LineFragment(fragment, innerFragments: newInner)
    }

    private static func isIgnoredLine(_ index: Int, _ offsets: LineOffsets, _ ignored: DiffBitSet) -> Bool {
        isIgnoredRange(ignored, offsets.lineStart(index), offsets.lineEnd(index, includeNewline: true))
    }

    private static func areIgnoredEqualLines(
        _ index1: Int,
        _ index2: Int,
        _ text1: DiffUnits,
        _ text2: DiffUnits,
        _ offsets1: LineOffsets,
        _ offsets2: LineOffsets,
        _ ignored1: DiffBitSet,
        _ ignored2: DiffBitSet
    ) -> Bool {
        let start1 = offsets1.lineStart(index1)
        let end1 = offsets1.lineEnd(index1, includeNewline: true)
        let start2 = offsets2.lineStart(index2)
        let end2 = offsets2.lineEnd(index2, includeNewline: true)
        let range = TrimUtil.trimExpand(
            start1,
            start2,
            end1,
            end2,
            equals: { text1[$0] == text2[$1] },
            ignored1: { ignored1[$0] },
            ignored2: { ignored2[$0] }
        )
        if !range.isEmpty { return false }

        let words1 = nonIgnoredWords(index1, text1, offsets1, ignored1)
        let words2 = nonIgnoredWords(index2, text2, offsets2, ignored2)
        if words1.count != words2.count { return false }

        for (word1, word2) in zip(words1, words2) where !ComparisonUtil.isEqualTexts(word1.content, word2.content, .default) {
            return false
        }
        return true
    }

    private static func nonIgnoredWords(
        _ index: Int,
        _ text: DiffUnits,
        _ offsets: LineOffsets,
        _ ignored: DiffBitSet
    ) -> [InlineChunk] {
        let offset = offsets.lineStart(index)
        let content = Array(text[offset..<offsets.lineEnd(index, includeNewline: true)])
        return ByWord.inlineChunks(content).filter { chunk in
            !chunk.isNewline && !isIgnoredRange(ignored, offset + chunk.offset1, offset + chunk.offset2)
        }
    }

    private static func trimIgnoredRange(
        _ start: Int,
        _ end: Int,
        _ ignored: DiffBitSet,
        _ offset: Int
    ) -> (start: Int, end: Int) {
        let trimmed = TrimUtil.trim(offset + start, offset + end, ignored: { ignored[$0] })
        return (trimmed.start - offset, trimmed.end - offset)
    }

    private static func isIgnoredRange(_ ignored: DiffBitSet, _ start: Int, _ end: Int) -> Bool {
        for index in stride(from: start, to: end, by: 1) where !ignored[index] {
            return false
        }
        return true
    }
}
