import Foundation

nonisolated struct WordFirstLineBlock: Sendable, Equatable {
    let lineRange: DiffRange
    let fragments: [DiffFragment]
}

nonisolated extension LineOffsets {
    func linesRange(_ line1: Int, _ line2: Int, includeNewline: Bool) -> (start: Int, end: Int) {
        if line1 == line2 {
            let offset = line1 < lineCount ? lineStart(line1) : textLength
            return (offset, offset)
        }
        let start = lineStart(line1)
        var end = lineEnd(line2 - 1)
        if includeNewline && end < textLength { end += 1 }
        return (start, end)
    }
}

nonisolated extension ByWord {
    static func compareWordsFirst(
        _ text1: DiffUnits,
        _ text2: DiffUnits,
        _ lineOffsets1: LineOffsets,
        _ lineOffsets2: LineOffsets,
        _ policy: ComparisonPolicy
    ) throws -> [WordFirstLineBlock] {
        try Task.checkCancellation()
        let words1 = inlineChunks(text1).filter { !$0.isNewline }
        let words2 = inlineChunks(text2).filter { !$0.isNewline }

        var wordChanges = try SequenceDiff.compare(words1, words2)
        wordChanges = try ChunkOptimizer.optimizeWords(words1, words2, text1: text1, text2: text2, wordChanges)

        let delimiters = try matchAdjustmentDelimiters(text1, text2, words1, words2, wordChanges, startShift1: 0, startShift2: 0)

        var uplifter = LineUplifter(text1: text1, text2: text2, lineOffsets1: lineOffsets1, lineOffsets2: lineOffsets2, changes: delimiters)
        let lineBlocks = uplifter.build()

        let subIterables = collectLineBlockSubIterables(delimiters, lineBlocks, lineOffsets1, lineOffsets2)

        var result: [WordFirstLineBlock] = []
        for (index, lineBlock) in lineBlocks.enumerated() {
            try Task.checkCancellation()
            let subRange1 = lineOffsets1.linesRange(lineBlock.start1, lineBlock.end1, includeNewline: true)
            let subRange2 = lineOffsets2.linesRange(lineBlock.start2, lineBlock.end2, includeNewline: true)

            let subtext1 = Array(text1[subRange1.start..<subRange1.end])
            let subtext2 = Array(text2[subRange2.start..<subRange2.end])

            let corrected = matchAdjustmentWhitespaces(subtext1, subtext2, subIterables[index], policy)
            let innerFragments = convertIntoDiffFragments(corrected)
            if innerFragments.isEmpty { continue }

            if lineBlock.start1 != lineBlock.end1 && lineBlock.start2 != lineBlock.end2 {
                if lineBlock.end1 == lineOffsets1.lineCount
                    && lineBlock.end2 != lineOffsets2.lineCount
                    && subtext2.last == 10 {
                    if ComparisonUtil.isEqualTexts(subtext1, Array(subtext2.dropLast()), policy) { continue }
                }
                if lineBlock.end2 == lineOffsets2.lineCount
                    && lineBlock.end1 != lineOffsets1.lineCount
                    && subtext1.last == 10 {
                    if ComparisonUtil.isEqualTexts(Array(subtext1.dropLast()), subtext2, policy) { continue }
                }
            }

            result.append(WordFirstLineBlock(lineRange: lineBlock, fragments: innerFragments))
        }
        return result
    }

    private static func collectLineBlockSubIterables(
        _ iterable: DiffChanges,
        _ lineBlocks: [DiffRange],
        _ lineOffsets1: LineOffsets,
        _ lineOffsets2: LineOffsets
    ) -> [DiffChanges] {
        let changed = iterable.changes
        var index = 0
        var result: [DiffChanges] = []
        result.reserveCapacity(lineBlocks.count)
        for lineBlock in lineBlocks {
            let subRange1 = lineOffsets1.linesRange(lineBlock.start1, lineBlock.end1, includeNewline: true)
            let subRange2 = lineOffsets2.linesRange(lineBlock.start2, lineBlock.end2, includeNewline: true)

            while index < changed.count {
                let range = changed[index]
                if range.end1 < subRange1.start || range.end2 < subRange2.start {
                    index += 1
                    continue
                }
                break
            }

            result.append(subiterable(changed, subRange1.start, subRange1.end, subRange2.start, subRange2.end, firstIndex: index))
        }
        return result
    }
}

nonisolated struct LineUplifter {
    private let text1: DiffUnits
    private let text2: DiffUnits
    private let lineOffsets1: LineOffsets
    private let lineOffsets2: LineOffsets
    private let changes: DiffChanges
    private var lineBlocks: [DiffRange] = []
    private var blockStart1 = 0
    private var blockStart2 = 0

    init(text1: DiffUnits, text2: DiffUnits, lineOffsets1: LineOffsets, lineOffsets2: LineOffsets, changes: DiffChanges) {
        self.text1 = text1
        self.text2 = text2
        self.lineOffsets1 = lineOffsets1
        self.lineOffsets2 = lineOffsets2
        self.changes = changes
    }

    mutating func build() -> [DiffRange] {
        execute()
        return lineBlocks
    }

    private mutating func execute() {
        var lastIndex1 = -1
        var lastIndex2 = -1

        for range in changes.unchanged {
            if let pair = walkForward(lastIndex1, lastIndex2, range.start1, range.start2) {
                walkBackward(pair.first, pair.second, range.start1, range.start2)
            } else {
                walkBackward(lastIndex1, lastIndex2, range.start1, range.start2)
            }
            lastIndex1 = range.end1
            lastIndex2 = range.end2
        }

        let textEnd1 = text1.count + 1
        let textEnd2 = text2.count + 1
        if let pair = walkForward(lastIndex1, lastIndex2, textEnd1, textEnd2) {
            walkBackward(pair.first, pair.second, textEnd1, textEnd2)
        } else {
            walkBackward(lastIndex1, lastIndex2, textEnd1, textEnd2)
        }
        markNextBlock(lineOffsets1.lineCount, lineOffsets2.lineCount)
    }

    private mutating func walkForward(_ start1: Int, _ start2: Int, _ end1: Int, _ end2: Int) -> (first: Int, second: Int)? {
        guard let foundFirst1 = Self.walkSideForward(text1, start1, end1) else { return nil }
        guard let foundFirst2 = Self.walkSideForward(text2, start2, end2) else { return nil }

        var match1 = foundFirst1
        var match2 = foundFirst2
        while true {
            guard let next1 = Self.walkSideForward(text1, match1 + 1, end1),
                  let next2 = Self.walkSideForward(text2, match2 + 1, end2)
            else { break }
            match1 = next1
            match2 = next2
        }

        if match1 == end1 - 1 || match2 == end2 - 1 {
            if match1 != end1 - 1
                && Self.charAt(text1, end1 - 1) == 10
                && Self.areAllLinesEmpty(text1, match1, end1) {
                match1 = end1 - 1
            }
            if match2 != end2 - 1
                && Self.charAt(text2, end2 - 1) == 10
                && Self.areAllLinesEmpty(text2, match2, end2) {
                match2 = end2 - 1
            }
        }

        markNextBlockOffset(foundFirst1, foundFirst2)
        markNextBlockOffset(match1, match2)
        return (match1, match2)
    }

    private mutating func walkBackward(_ start1: Int, _ start2: Int, _ end1: Int, _ end2: Int) {
        guard let foundFirst1 = Self.walkSideBackward(text1, start1, end1) else { return }
        guard let foundFirst2 = Self.walkSideBackward(text2, start2, end2) else { return }

        var foundLast1 = foundFirst1
        while let next = Self.walkSideBackward(text1, start1, foundLast1) {
            foundLast1 = next
        }

        var foundLast2 = foundFirst2
        while let next = Self.walkSideBackward(text2, start2, foundLast2) {
            foundLast2 = next
        }

        markNextBlockOffset(foundLast1, foundLast2)
        markNextBlockOffset(foundFirst1, foundFirst2)
    }

    private mutating func markNextBlockOffset(_ blockEndOffset1: Int, _ blockEndOffset2: Int) {
        let blockEnd1 = Self.blockEndLine(blockEndOffset1, lineOffsets1)
        let blockEnd2 = Self.blockEndLine(blockEndOffset2, lineOffsets2)
        markNextBlock(blockEnd1, blockEnd2)
    }

    private mutating func markNextBlock(_ blockEnd1: Int, _ blockEnd2: Int) {
        if blockStart1 == blockEnd1 && blockStart2 == blockEnd2 { return }

        lineBlocks.append(DiffRange(blockStart1, blockEnd1, blockStart2, blockEnd2))
        blockStart1 = blockEnd1
        blockStart2 = blockEnd2
    }

    private static func areAllLinesEmpty(_ text: DiffUnits, _ start: Int, _ end: Int) -> Bool {
        for index in stride(from: start, to: end, by: 1) where !ComparisonUtil.isSpaceEnterOrTab(charAt(text, index)) {
            return false
        }
        return true
    }

    private static func walkSideForward(_ text: DiffUnits, _ start: Int, _ end: Int) -> Int? {
        for index in stride(from: start, to: end, by: 1) {
            let unit = charAt(text, index)
            if unit == 10 { return index }
            if !ComparisonUtil.isSpaceEnterOrTab(unit) { return nil }
        }
        return nil
    }

    private static func walkSideBackward(_ text: DiffUnits, _ start: Int, _ end: Int) -> Int? {
        for index in stride(from: end - 1, through: start, by: -1) {
            let unit = charAt(text, index)
            if unit == 10 { return index }
            if !ComparisonUtil.isSpaceEnterOrTab(unit) { return nil }
        }
        return nil
    }

    private static func charAt(_ text: DiffUnits, _ offset: Int) -> UInt16 {
        if offset == -1 || offset == text.count { return 10 }
        return text[offset]
    }

    private static func blockEndLine(_ offset: Int, _ lineOffsets: LineOffsets) -> Int {
        if offset == -1 { return 0 }
        if offset == lineOffsets.textLength { return lineOffsets.lineCount }
        return lineOffsets.lineNumber(containing: offset) + 1
    }
}
