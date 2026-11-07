import Foundation

nonisolated enum ChunkOptimizer {
    static func optimizeLines(
        _ lines1: [ComparisonLine],
        _ lines2: [ComparisonLine],
        _ changes: DiffChanges
    ) throws -> DiffChanges {
        try optimize(
            length1: lines1.count,
            length2: lines2.count,
            changes: changes,
            equals: { lines1[$0] == lines2[$1] },
            shift: { touchSide, equalForward, equalBackward, range1, range2 in
                lineShift(lines1, lines2, touchSide, equalForward, equalBackward, range1, range2)
            }
        )
    }

    static func optimizeWords(
        _ words1: [InlineChunk],
        _ words2: [InlineChunk],
        text1: DiffUnits,
        text2: DiffUnits,
        _ changes: DiffChanges
    ) throws -> DiffChanges {
        try optimize(
            length1: words1.count,
            length2: words2.count,
            changes: changes,
            equals: { words1[$0] == words2[$1] },
            shift: { touchSide, equalForward, equalBackward, range1, range2 in
                wordShift(words1, words2, text1, text2, touchSide, equalForward, equalBackward, range1, range2)
            }
        )
    }

    private static func optimize(
        length1: Int,
        length2: Int,
        changes: DiffChanges,
        equals: (Int, Int) -> Bool,
        shift: (DiffSide, Int, Int, DiffRange, DiffRange) -> Int
    ) throws -> DiffChanges {
        var ranges: [DiffRange] = []
        ranges.reserveCapacity(changes.unchanged.count)
        for range in changes.unchanged {
            try Task.checkCancellation()
            ranges.append(range)
            processLastRanges(&ranges, equals: equals, shift: shift)
        }
        return DiffChanges(unchanged: ranges, length1: length1, length2: length2)
    }

    private static func processLastRanges(
        _ ranges: inout [DiffRange],
        equals: (Int, Int) -> Bool,
        shift: (DiffSide, Int, Int, DiffRange, DiffRange) -> Int
    ) {
        while ranges.count >= 2 {
            let range1 = ranges[ranges.count - 2]
            let range2 = ranges[ranges.count - 1]
            if range1.end1 != range2.start1 && range1.end2 != range2.start2 { return }

            let count1 = range1.end1 - range1.start1
            let count2 = range2.end1 - range2.start1

            let equalForward = TrimUtil.expandForward(
                range1.end1, range1.end2, range1.end1 + count2, range1.end2 + count2, equals
            )
            let equalBackward = TrimUtil.expandBackward(
                range2.start1 - count1, range2.start2 - count1, range2.start1, range2.start2, equals
            )

            if equalForward == 0 && equalBackward == 0 { return }

            if equalForward == count2 {
                ranges.removeLast(2)
                ranges.append(DiffRange(range1.start1, range1.end1 + count2, range1.start2, range1.end2 + count2))
                continue
            }

            if equalBackward == count1 {
                ranges.removeLast(2)
                ranges.append(DiffRange(range2.start1 - count1, range2.end1, range2.start2 - count1, range2.end2))
                continue
            }

            let touchSide = DiffSide.fromLeft(range1.end1 == range2.start1)
            let amount = shift(touchSide, equalForward, equalBackward, range1, range2)
            if amount != 0 {
                ranges.removeLast(2)
                ranges.append(DiffRange(range1.start1, range1.end1 + amount, range1.start2, range1.end2 + amount))
                ranges.append(DiffRange(range2.start1 + amount, range2.end1, range2.start2 + amount, range2.end2))
            }
            return
        }
    }

    private static func lineShift(
        _ lines1: [ComparisonLine],
        _ lines2: [ComparisonLine],
        _ touchSide: DiffSide,
        _ equalForward: Int,
        _ equalBackward: Int,
        _ range1: DiffRange,
        _ range2: DiffRange
    ) -> Int {
        let threshold = ComparisonUtil.unimportantLineCharCount
        for limit in [0, threshold] {
            if let amount = unchangedBoundaryShift(
                lines1, lines2, touchSide, equalForward, equalBackward, range2, limit
            ) {
                return amount
            }
            if let amount = changedBoundaryShift(
                lines1, lines2, touchSide, equalForward, equalBackward, range1, range2, limit
            ) {
                return amount
            }
        }
        return 0
    }

    private static func unchangedBoundaryShift(
        _ lines1: [ComparisonLine],
        _ lines2: [ComparisonLine],
        _ touchSide: DiffSide,
        _ equalForward: Int,
        _ equalBackward: Int,
        _ range2: DiffRange,
        _ threshold: Int
    ) -> Int? {
        let touchLines = touchSide.select(lines1, lines2)
        let touchStart = touchSide.select(range2.start1, range2.start2)
        let shiftForward = findNextUnimportantLine(touchLines, touchStart, equalForward + 1, threshold)
        let shiftBackward = findPrevUnimportantLine(touchLines, touchStart - 1, equalBackward + 1, threshold)
        return combinedShift(shiftForward, shiftBackward)
    }

    private static func changedBoundaryShift(
        _ lines1: [ComparisonLine],
        _ lines2: [ComparisonLine],
        _ touchSide: DiffSide,
        _ equalForward: Int,
        _ equalBackward: Int,
        _ range1: DiffRange,
        _ range2: DiffRange,
        _ threshold: Int
    ) -> Int? {
        let nonTouchSide = touchSide.other
        let nonTouchLines = nonTouchSide.select(lines1, lines2)
        let changeStart = nonTouchSide.select(range1.end1, range1.end2)
        let changeEnd = nonTouchSide.select(range2.start1, range2.start2)
        let shiftForward = findNextUnimportantLine(nonTouchLines, changeStart, equalForward + 1, threshold)
        let shiftBackward = findPrevUnimportantLine(nonTouchLines, changeEnd - 1, equalBackward + 1, threshold)
        return combinedShift(shiftForward, shiftBackward)
    }

    private static func findNextUnimportantLine(_ lines: [ComparisonLine], _ offset: Int, _ count: Int, _ threshold: Int) -> Int {
        for i in 0..<max(count, 0) {
            let index = offset + i
            guard index >= 0 && index < lines.count else { return -1 }
            if lines[index].nonSpaceChars <= threshold { return i }
        }
        return -1
    }

    private static func findPrevUnimportantLine(_ lines: [ComparisonLine], _ offset: Int, _ count: Int, _ threshold: Int) -> Int {
        for i in 0..<max(count, 0) {
            let index = offset - i
            guard index >= 0 && index < lines.count else { return -1 }
            if lines[index].nonSpaceChars <= threshold { return i }
        }
        return -1
    }

    private static func combinedShift(_ shiftForward: Int, _ shiftBackward: Int) -> Int? {
        if shiftForward == -1 && shiftBackward == -1 { return nil }
        if shiftForward == 0 || shiftBackward == 0 { return 0 }
        return shiftForward != -1 ? shiftForward : -shiftBackward
    }

    private static func wordShift(
        _ words1: [InlineChunk],
        _ words2: [InlineChunk],
        _ text1: DiffUnits,
        _ text2: DiffUnits,
        _ touchSide: DiffSide,
        _ equalForward: Int,
        _ equalBackward: Int,
        _ range1: DiffRange,
        _ range2: DiffRange
    ) -> Int {
        let touchWords = touchSide.select(words1, words2)
        let touchText = touchSide.select(text1, text2)
        let touchStart = touchSide.select(range2.start1, range2.start2)
        guard touchStart >= 1 && touchStart < touchWords.count else { return 0 }

        if isSeparatedWithWhitespace(touchText, touchWords[touchStart - 1], touchWords[touchStart]) { return 0 }

        let leftShift = findSequenceEdgeShift(touchText, touchWords, touchStart, equalForward, leftToRight: true)
        if leftShift > 0 { return leftShift }

        let rightShift = findSequenceEdgeShift(touchText, touchWords, touchStart - 1, equalBackward, leftToRight: false)
        if rightShift > 0 { return -rightShift }

        return 0
    }

    private static func findSequenceEdgeShift(
        _ text: DiffUnits,
        _ words: [InlineChunk],
        _ offset: Int,
        _ count: Int,
        leftToRight: Bool
    ) -> Int {
        for i in 0..<max(count, 0) {
            let index1 = leftToRight ? offset + i : offset - i - 1
            let index2 = leftToRight ? offset + i + 1 : offset - i
            guard index1 >= 0 && index2 >= 0 && index1 < words.count && index2 < words.count else { return -1 }
            if isSeparatedWithWhitespace(text, words[index1], words[index2]) { return i + 1 }
        }
        return -1
    }

    private static func isSeparatedWithWhitespace(_ text: DiffUnits, _ word1: InlineChunk, _ word2: InlineChunk) -> Bool {
        if word1.isNewline || word2.isNewline { return true }
        let offset1 = word1.offset2
        let offset2 = min(word2.offset1, text.count)
        var index = max(offset1, 0)
        while index < offset2 {
            if ComparisonUtil.isSpaceEnterOrTab(text[index]) { return true }
            index += 1
        }
        return false
    }
}
