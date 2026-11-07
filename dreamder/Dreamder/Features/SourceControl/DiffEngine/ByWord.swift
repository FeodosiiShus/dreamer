import Foundation

nonisolated struct InlineChunk: Sendable, Hashable {
    let offset1: Int
    let offset2: Int
    let isNewline: Bool
    let wordHash: Int
    let content: ArraySlice<UInt16>

    static func word(_ text: DiffUnits, _ start: Int, _ end: Int, hash: Int) -> InlineChunk {
        InlineChunk(offset1: start, offset2: end, isNewline: false, wordHash: hash, content: text[start..<end])
    }

    static func newline(_ offset: Int) -> InlineChunk {
        InlineChunk(offset1: offset, offset2: offset + 1, isNewline: true, wordHash: 0, content: [])
    }

    static func == (lhs: InlineChunk, rhs: InlineChunk) -> Bool {
        if lhs.isNewline != rhs.isNewline { return false }
        if lhs.isNewline { return true }
        return lhs.wordHash == rhs.wordHash && lhs.content == rhs.content
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(isNewline)
        if !isNewline { hasher.combine(wordHash) }
    }
}

nonisolated struct WordLineBlock: Sendable, Equatable {
    let fragments: [DiffFragment]
    let offsets: DiffRange
    let newlines1: Int
    let newlines2: Int
}

nonisolated enum ByWord {
    static func compare(_ text1: DiffUnits, _ text2: DiffUnits, _ policy: ComparisonPolicy) throws -> [DiffFragment] {
        try Task.checkCancellation()
        let words1 = inlineChunks(text1)
        let words2 = inlineChunks(text2)

        var wordChanges = try SequenceDiff.compare(words1, words2)
        wordChanges = try ChunkOptimizer.optimizeWords(words1, words2, text1: text1, text2: text2, wordChanges)

        let delimiters = try matchAdjustmentDelimiters(text1, text2, words1, words2, wordChanges, startShift1: 0, startShift2: 0)
        let corrected = matchAdjustmentWhitespaces(text1, text2, delimiters, policy)
        return convertIntoDiffFragments(corrected)
    }

    static func compare(
        _ text1: DiffUnits,
        _ text2: DiffUnits,
        _ text3: DiffUnits,
        _ policy: ComparisonPolicy
    ) throws -> [MergeRange] {
        try Task.checkCancellation()
        let words1 = inlineChunks(text1)
        let words2 = inlineChunks(text2)
        let words3 = inlineChunks(text3)

        var wordChanges1 = try SequenceDiff.compare(words2, words1)
        wordChanges1 = try ChunkOptimizer.optimizeWords(words2, words1, text1: text2, text2: text1, wordChanges1)
        let iterable1 = try matchAdjustmentDelimiters(text2, text1, words2, words1, wordChanges1, startShift1: 0, startShift2: 0)

        var wordChanges2 = try SequenceDiff.compare(words2, words3)
        wordChanges2 = try ChunkOptimizer.optimizeWords(words2, words3, text1: text2, text2: text3, wordChanges2)
        let iterable2 = try matchAdjustmentDelimiters(text2, text3, words2, words3, wordChanges2, startShift1: 0, startShift2: 0)

        let wordConflicts = try ComparisonMergeUtil.buildSimple(iterable1, iterable2)
        return matchAdjustmentWhitespaces(text1, text2, text3, wordConflicts, policy)
    }

    static func compareAndSplit(_ text1: DiffUnits, _ text2: DiffUnits, _ policy: ComparisonPolicy) throws -> [WordLineBlock] {
        try Task.checkCancellation()
        let words1 = inlineChunks(text1)
        let words2 = inlineChunks(text2)

        var wordChanges = try SequenceDiff.compare(words1, words2)
        wordChanges = try ChunkOptimizer.optimizeWords(words1, words2, text1: text1, text2: text2, wordChanges)

        var splitter = LineFragmentSplitter(text1: text1, text2: text2, words1: words1, words2: words2, iterable: wordChanges)
        let wordBlocks = try splitter.run()

        let subIterables = collectWordBlockSubIterables(wordChanges, wordBlocks)

        var lineBlocks: [WordLineBlock] = []
        lineBlocks.reserveCapacity(wordBlocks.count)
        for (index, block) in wordBlocks.enumerated() {
            try Task.checkCancellation()
            let offsets = block.offsets
            let words = block.words

            let subtext1 = Array(text1[offsets.start1..<offsets.end1])
            let subtext2 = Array(text2[offsets.start2..<offsets.end2])
            let subwords1 = Array(words1[words.start1..<words.end1])
            let subwords2 = Array(words2[words.start2..<words.end2])

            let delimiters = try matchAdjustmentDelimiters(
                subtext1,
                subtext2,
                subwords1,
                subwords2,
                subIterables[index],
                startShift1: offsets.start1,
                startShift2: offsets.start2
            )
            let corrected = matchAdjustmentWhitespaces(subtext1, subtext2, delimiters, policy)
            let fragments = convertIntoDiffFragments(corrected)

            lineBlocks.append(WordLineBlock(
                fragments: fragments,
                offsets: offsets,
                newlines1: countNewlines(subwords1),
                newlines2: countNewlines(subwords2)
            ))
        }
        return lineBlocks
    }

    static func convertIntoDiffFragments(_ changes: DiffChanges) -> [DiffFragment] {
        changes.changes.map { DiffFragment($0.start1, $0.end1, $0.start2, $0.end2) }
    }

    static func inlineChunks(_ text: DiffUnits) -> [InlineChunk] {
        var chunks: [InlineChunk] = []
        let length = text.count
        var offset = 0
        var wordStart = -1
        var wordHash: Int32 = 0

        while offset < length {
            let codePoint = TrimUtil.codePointAt(text, offset)
            let charCount = TrimUtil.charCount(codePoint)

            let isAlpha = TrimUtil.isAlpha(codePoint)
            let isWordPart = isAlpha && !TrimUtil.isContinuousScript(codePoint)

            if isWordPart {
                if wordStart == -1 {
                    wordStart = offset
                    wordHash = 0
                }
                wordHash = wordHash &* 31 &+ Int32(truncatingIfNeeded: codePoint)
            } else {
                if wordStart != -1 {
                    chunks.append(InlineChunk.word(text, wordStart, offset, hash: Int(wordHash)))
                    wordStart = -1
                }
                if isAlpha {
                    chunks.append(InlineChunk.word(text, offset, offset + charCount, hash: codePoint))
                } else if codePoint == 10 {
                    chunks.append(InlineChunk.newline(offset))
                }
            }
            offset += charCount
        }

        if wordStart != -1 {
            chunks.append(InlineChunk.word(text, wordStart, length, hash: Int(wordHash)))
        }
        return chunks
    }

    private static func countNewlines(_ words: [InlineChunk]) -> Int {
        var count = 0
        for word in words where word.isNewline {
            count += 1
        }
        return count
    }

    private static func collectWordBlockSubIterables(_ wordChanges: DiffChanges, _ wordBlocks: [WordBlock]) -> [DiffChanges] {
        let changed = wordChanges.changes
        var index = 0
        var result: [DiffChanges] = []
        result.reserveCapacity(wordBlocks.count)
        for block in wordBlocks {
            let words = block.words
            while index < changed.count {
                let range = changed[index]
                if range.end1 < words.start1 || range.end2 < words.start2 {
                    index += 1
                    continue
                }
                break
            }
            result.append(subiterable(changed, words.start1, words.end1, words.start2, words.end2, firstIndex: index))
        }
        return result
    }

    static func subiterable(
        _ changed: [DiffRange],
        _ start1: Int,
        _ end1: Int,
        _ start2: Int,
        _ end2: Int,
        firstIndex: Int
    ) -> DiffChanges {
        var ranges: [DiffRange] = []
        var index = firstIndex
        while index < changed.count {
            let range = changed[index]
            index += 1
            if range.end1 < start1 || range.end2 < start2 { continue }
            if range.start1 > end1 || range.start2 > end2 { break }
            let clipped = DiffRange(
                max(start1, range.start1) - start1,
                min(end1, range.end1) - start1,
                max(start2, range.start2) - start2,
                min(end2, range.end2) - start2
            )
            if clipped.isEmpty { continue }
            ranges.append(clipped)
        }
        return DiffChanges(changes: ranges, length1: end1 - start1, length2: end2 - start2)
    }

    static func matchAdjustmentDelimiters(
        _ text1: DiffUnits,
        _ text2: DiffUnits,
        _ words1: [InlineChunk],
        _ words2: [InlineChunk],
        _ changes: DiffChanges,
        startShift1: Int,
        startShift2: Int
    ) throws -> DiffChanges {
        var matcher = AdjustmentPunctuationMatcher(
            text1: text1,
            text2: text2,
            words1: words1,
            words2: words2,
            startShift1: startShift1,
            startShift2: startShift2,
            changes: changes
        )
        return try matcher.build()
    }

    static func matchAdjustmentWhitespaces(
        _ text1: DiffUnits,
        _ text2: DiffUnits,
        _ iterable: DiffChanges,
        _ policy: ComparisonPolicy
    ) -> DiffChanges {
        switch policy {
        case .default:
            return defaultCorrected(iterable, text1, text2)
        case .trimWhitespaces:
            return trimSpacesCorrected(defaultCorrected(iterable, text1, text2), text1, text2)
        case .ignoreWhitespaces:
            return ignoreSpacesCorrected(iterable, text1, text2)
        }
    }

    private static func matchAdjustmentWhitespaces(
        _ text1: DiffUnits,
        _ text2: DiffUnits,
        _ text3: DiffUnits,
        _ conflicts: [MergeRange],
        _ policy: ComparisonPolicy
    ) -> [MergeRange] {
        switch policy {
        case .default:
            return mergeDefaultCorrected(conflicts, text1, text2, text3)
        case .trimWhitespaces:
            return mergeTrimSpacesCorrected(mergeDefaultCorrected(conflicts, text1, text2, text3), text1, text2, text3)
        case .ignoreWhitespaces:
            return mergeIgnoreSpacesCorrected(conflicts, text1, text2, text3)
        }
    }

    static func defaultCorrected(_ iterable: DiffChanges, _ text1: DiffUnits, _ text2: DiffUnits) -> DiffChanges {
        var changes: [DiffRange] = []
        for range in iterable.changes {
            let endCut = TrimUtil.expandWhitespacesBackward(
                text1, text2, range.start1, range.start2, range.end1, range.end2
            )
            let startCut = TrimUtil.expandWhitespacesForward(
                text1, text2, range.start1, range.start2, range.end1 - endCut, range.end2 - endCut
            )
            let expanded = DiffRange(
                range.start1 + startCut,
                range.end1 - endCut,
                range.start2 + startCut,
                range.end2 - endCut
            )
            if !expanded.isEmpty { changes.append(expanded) }
        }
        return DiffChanges(changes: changes, length1: text1.count, length2: text2.count)
    }

    static func ignoreSpacesCorrected(_ iterable: DiffChanges, _ text1: DiffUnits, _ text2: DiffUnits) -> DiffChanges {
        var changes: [DiffRange] = []
        for range in iterable.changes {
            let expanded = TrimUtil.expandWhitespaces(text1, text2, range)
            let trimmed = TrimUtil.trim(text1, text2, expanded)
            if !trimmed.isEmpty && !TrimUtil.isEqualsIgnoreWhitespaces(text1, text2, trimmed) {
                changes.append(trimmed)
            }
        }
        return DiffChanges(changes: changes, length1: text1.count, length2: text2.count)
    }

    static func trimSpacesCorrected(_ iterable: DiffChanges, _ text1: DiffUnits, _ text2: DiffUnits) -> DiffChanges {
        var changes: [DiffRange] = []
        for range in iterable.changes {
            var start1 = range.start1
            var start2 = range.start2
            var end1 = range.end1
            var end2 = range.end2

            if isLeadingTrailingSpace(text1, start1) {
                start1 = TrimUtil.trimStart(text1, start1, end1)
            }
            if isLeadingTrailingSpace(text1, end1 - 1) {
                end1 = TrimUtil.trimEnd(text1, start1, end1)
            }
            if isLeadingTrailingSpace(text2, start2) {
                start2 = TrimUtil.trimStart(text2, start2, end2)
            }
            if isLeadingTrailingSpace(text2, end2 - 1) {
                end2 = TrimUtil.trimEnd(text2, start2, end2)
            }

            let trimmed = DiffRange(start1, end1, start2, end2)
            if !trimmed.isEmpty && !TrimUtil.isEquals(text1, text2, trimmed) {
                changes.append(trimmed)
            }
        }
        return DiffChanges(changes: changes, length1: text1.count, length2: text2.count)
    }

    private static func mergeDefaultCorrected(
        _ iterable: [MergeRange],
        _ text1: DiffUnits,
        _ text2: DiffUnits,
        _ text3: DiffUnits
    ) -> [MergeRange] {
        var changes: [MergeRange] = []
        for range in iterable {
            let endCut = TrimUtil.expandWhitespacesBackward(text1, text2, text3, range)
            let startCut = TrimUtil.expandWhitespacesForward(text1, text2, text3, range, endShift: endCut)
            let expanded = MergeRange(
                range.start1 + startCut,
                range.end1 - endCut,
                range.start2 + startCut,
                range.end2 - endCut,
                range.start3 + startCut,
                range.end3 - endCut
            )
            if !expanded.isEmpty { changes.append(expanded) }
        }
        return changes
    }

    private static func mergeIgnoreSpacesCorrected(
        _ iterable: [MergeRange],
        _ text1: DiffUnits,
        _ text2: DiffUnits,
        _ text3: DiffUnits
    ) -> [MergeRange] {
        var changes: [MergeRange] = []
        for range in iterable {
            let expanded = TrimUtil.expandWhitespaces(text1, text2, text3, range)
            let trimmed = TrimUtil.trim(text1, text2, text3, expanded)
            if !trimmed.isEmpty && !TrimUtil.isEqualsIgnoreWhitespaces(text1, text2, text3, trimmed) {
                changes.append(trimmed)
            }
        }
        return changes
    }

    private static func mergeTrimSpacesCorrected(
        _ iterable: [MergeRange],
        _ text1: DiffUnits,
        _ text2: DiffUnits,
        _ text3: DiffUnits
    ) -> [MergeRange] {
        var changes: [MergeRange] = []
        for range in iterable {
            var start1 = range.start1
            var start2 = range.start2
            var start3 = range.start3
            var end1 = range.end1
            var end2 = range.end2
            var end3 = range.end3

            if isLeadingTrailingSpace(text1, start1) {
                start1 = TrimUtil.trimStart(text1, start1, end1)
            }
            if isLeadingTrailingSpace(text1, end1 - 1) {
                end1 = TrimUtil.trimEnd(text1, start1, end1)
            }
            if isLeadingTrailingSpace(text2, start2) {
                start2 = TrimUtil.trimStart(text2, start2, end2)
            }
            if isLeadingTrailingSpace(text2, end2 - 1) {
                end2 = TrimUtil.trimEnd(text2, start2, end2)
            }
            if isLeadingTrailingSpace(text3, start3) {
                start3 = TrimUtil.trimStart(text3, start3, end3)
            }
            if isLeadingTrailingSpace(text3, end3 - 1) {
                end3 = TrimUtil.trimEnd(text3, start3, end3)
            }

            let trimmed = MergeRange(start1, end1, start2, end2, start3, end3)
            if !trimmed.isEmpty && !TrimUtil.isEquals(text1, text2, text3, trimmed) {
                changes.append(trimmed)
            }
        }
        return changes
    }

    private static func isLeadingTrailingSpace(_ text: DiffUnits, _ start: Int) -> Bool {
        isLeadingSpace(text, start) || isTrailingSpace(text, start)
    }

    private static func isLeadingSpace(_ text: DiffUnits, _ start: Int) -> Bool {
        if start < 0 || start >= text.count { return false }
        if !ComparisonUtil.isSpaceEnterOrTab(text[start]) { return false }
        var cursor = start - 1
        while cursor >= 0 {
            let unit = text[cursor]
            if unit == 10 { return true }
            if !ComparisonUtil.isSpaceEnterOrTab(unit) { return false }
            cursor -= 1
        }
        return true
    }

    private static func isTrailingSpace(_ text: DiffUnits, _ end: Int) -> Bool {
        if end < 0 || end >= text.count { return false }
        if !ComparisonUtil.isSpaceEnterOrTab(text[end]) { return false }
        var cursor = end
        while cursor < text.count {
            let unit = text[cursor]
            if unit == 10 { return true }
            if !ComparisonUtil.isSpaceEnterOrTab(unit) { return false }
            cursor += 1
        }
        return true
    }
}

nonisolated struct WordBlock: Sendable {
    let words: DiffRange
    let offsets: DiffRange
}

nonisolated struct LineFragmentSplitter {
    private struct PendingChunk {
        let block: WordBlock
        let hasEqualWords: Bool
        let hasWordsInside: Bool
        let isEqualIgnoreWhitespaces: Bool
    }

    private let text1: DiffUnits
    private let text2: DiffUnits
    private let words1: [InlineChunk]
    private let words2: [InlineChunk]
    private let iterable: DiffChanges
    private var result: [WordBlock] = []
    private var last1 = -1
    private var last2 = -1
    private var pendingChunk: PendingChunk?

    init(text1: DiffUnits, text2: DiffUnits, words1: [InlineChunk], words2: [InlineChunk], iterable: DiffChanges) {
        self.text1 = text1
        self.text2 = text2
        self.words1 = words1
        self.words2 = words2
        self.iterable = iterable
    }

    mutating func run() throws -> [WordBlock] {
        var hasEqualWords = false
        for range in iterable.unchanged {
            try Task.checkCancellation()
            let count = range.end1 - range.start1
            for i in 0..<max(count, 0) {
                let index1 = range.start1 + i
                let index2 = range.start2 + i

                if words1[index1].isNewline && words2[index2].isNewline {
                    addLineChunk(index1, index2, hasEqualWords)
                    hasEqualWords = false
                } else {
                    if isFirstInLine(words1, index1) && isFirstInLine(words2, index2) {
                        addLineChunk(index1 - 1, index2 - 1, hasEqualWords)
                        hasEqualWords = false
                    }
                    hasEqualWords = true
                }
            }
        }
        addLineChunk(words1.count, words2.count, hasEqualWords)

        if let pending = pendingChunk {
            result.append(pending.block)
        }
        return result
    }

    private mutating func addLineChunk(_ end1: Int, _ end2: Int, _ hasEqualWords: Bool) {
        if last1 > end1 || last2 > end2 { return }

        let chunk = createChunk(last1, last2, end1, end2, hasEqualWords)
        if chunk.block.offsets.isEmpty { return }

        if let pending = pendingChunk {
            if shouldMergeChunks(pending, chunk) {
                pendingChunk = mergeChunks(pending, chunk)
            } else {
                result.append(pending.block)
                pendingChunk = chunk
            }
        } else {
            pendingChunk = chunk
        }

        last1 = end1
        last2 = end2
    }

    private func createChunk(_ start1: Int, _ start2: Int, _ end1: Int, _ end2: Int, _ hasEqualWords: Bool) -> PendingChunk {
        let startOffset1 = offset(words1, text1, start1)
        let startOffset2 = offset(words2, text2, start2)
        let endOffset1 = offset(words1, text1, end1)
        let endOffset2 = offset(words2, text2, end2)

        let wordStart1 = max(0, start1 + 1)
        let wordStart2 = max(0, start2 + 1)
        let wordEnd1 = min(end1 + 1, words1.count)
        let wordEnd2 = min(end2 + 1, words2.count)

        let block = WordBlock(
            words: DiffRange(wordStart1, wordEnd1, wordStart2, wordEnd2),
            offsets: DiffRange(startOffset1, endOffset1, startOffset2, endOffset2)
        )
        return PendingChunk(
            block: block,
            hasEqualWords: hasEqualWords,
            hasWordsInside: hasWordsInside(block),
            isEqualIgnoreWhitespaces: isEqualsIgnoringWhitespace(block)
        )
    }

    private func isEqualsIgnoringWhitespace(_ block: WordBlock) -> Bool {
        guard block.offsets.start1 <= block.offsets.end1, block.offsets.start2 <= block.offsets.end2 else { return false }
        let sequence1 = Array(text1[block.offsets.start1..<block.offsets.end1])
        let sequence2 = Array(text2[block.offsets.start2..<block.offsets.end2])
        return ComparisonUtil.equalsIgnoreWhitespaces(sequence1, sequence2)
    }

    private func hasWordsInside(_ block: WordBlock) -> Bool {
        for i in block.words.start1..<max(block.words.start1, block.words.end1) where !words1[i].isNewline {
            return true
        }
        for i in block.words.start2..<max(block.words.start2, block.words.end2) where !words2[i].isNewline {
            return true
        }
        return false
    }

    private func shouldMergeChunks(_ chunk1: PendingChunk, _ chunk2: PendingChunk) -> Bool {
        if !chunk1.hasEqualWords && !chunk2.hasEqualWords { return true }
        if chunk1.isEqualIgnoreWhitespaces && chunk2.isEqualIgnoreWhitespaces { return true }
        if !chunk1.hasWordsInside || !chunk2.hasWordsInside { return true }
        return false
    }

    private func mergeChunks(_ chunk1: PendingChunk, _ chunk2: PendingChunk) -> PendingChunk {
        let block1 = chunk1.block
        let block2 = chunk2.block
        let block = WordBlock(
            words: DiffRange(block1.words.start1, block2.words.end1, block1.words.start2, block2.words.end2),
            offsets: DiffRange(block1.offsets.start1, block2.offsets.end1, block1.offsets.start2, block2.offsets.end2)
        )
        return PendingChunk(
            block: block,
            hasEqualWords: chunk1.hasEqualWords || chunk2.hasEqualWords,
            hasWordsInside: chunk1.hasWordsInside || chunk2.hasWordsInside,
            isEqualIgnoreWhitespaces: chunk1.isEqualIgnoreWhitespaces && chunk2.isEqualIgnoreWhitespaces
        )
    }

    private func offset(_ words: [InlineChunk], _ text: DiffUnits, _ index: Int) -> Int {
        if index == -1 { return 0 }
        if index >= words.count { return text.count }
        return words[index].offset2
    }

    private func isFirstInLine(_ words: [InlineChunk], _ index: Int) -> Bool {
        if index == 0 { return true }
        return words[index - 1].isNewline
    }
}

nonisolated struct AdjustmentPunctuationMatcher {
    private let text1: DiffUnits
    private let text2: DiffUnits
    private let words1: [InlineChunk]
    private let words2: [InlineChunk]
    private let startShift1: Int
    private let startShift2: Int
    private let changes: DiffChanges
    private let length1: Int
    private let length2: Int
    private var builder: DiffChangeBuilder
    private var lastStart1 = 0
    private var lastStart2 = 0
    private var lastEnd1 = 0
    private var lastEnd2 = 0

    init(
        text1: DiffUnits,
        text2: DiffUnits,
        words1: [InlineChunk],
        words2: [InlineChunk],
        startShift1: Int,
        startShift2: Int,
        changes: DiffChanges
    ) {
        self.text1 = text1
        self.text2 = text2
        self.words1 = words1
        self.words2 = words2
        self.startShift1 = startShift1
        self.startShift2 = startShift2
        self.changes = changes
        self.length1 = text1.count
        self.length2 = text2.count
        self.builder = DiffChangeBuilder(length1: text1.count, length2: text2.count)
    }

    mutating func build() throws -> DiffChanges {
        try execute()
        return builder.finish()
    }

    private mutating func execute() throws {
        clearLastRange()
        matchForward(-1, -1)

        for change in changes.unchanged {
            try Task.checkCancellation()
            let count = change.end1 - change.start1
            for i in 0..<max(count, 0) {
                let index1 = change.start1 + i
                let index2 = change.start2 + i

                let start1 = startOffset1(index1)
                let start2 = startOffset2(index2)
                let end1 = endOffset1(index1)
                let end2 = endOffset2(index2)

                try matchBackward(index1, index2)
                builder.markEqual(start1, start2, end1: end1, end2: end2)
                matchForward(index1, index2)
            }
        }
        try matchBackward(words1.count, words2.count)
    }

    private mutating func clearLastRange() {
        lastStart1 = -1
        lastStart2 = -1
        lastEnd1 = -1
        lastEnd2 = -1
    }

    private mutating func matchBackward(_ index1: Int, _ index2: Int) throws {
        let start1 = index1 == 0 ? 0 : endOffset1(index1 - 1)
        let start2 = index2 == 0 ? 0 : endOffset2(index2 - 1)
        let end1 = index1 == words1.count ? length1 : startOffset1(index1)
        let end2 = index2 == words2.count ? length2 : startOffset2(index2)

        try matchBackward(start1, start2, end1, end2)
        clearLastRange()
    }

    private mutating func matchForward(_ index1: Int, _ index2: Int) {
        let start1 = index1 == -1 ? 0 : endOffset1(index1)
        let start2 = index2 == -1 ? 0 : endOffset2(index2)
        let end1 = index1 + 1 == words1.count ? length1 : startOffset1(index1 + 1)
        let end2 = index2 + 1 == words2.count ? length2 : startOffset2(index2 + 1)

        lastStart1 = start1
        lastStart2 = start2
        lastEnd1 = end1
        lastEnd2 = end2
    }

    private mutating func matchBackward(_ start1: Int, _ start2: Int, _ end1: Int, _ end2: Int) throws {
        if lastStart1 == start1 && lastStart2 == start2 {
            try matchRange(start1, start2, end1, end2)
            return
        }
        if lastStart1 < start1 && lastStart2 < start2 {
            try matchRange(lastStart1, lastStart2, lastEnd1, lastEnd2)
            try matchRange(start1, start2, end1, end2)
            return
        }
        try matchComplexRange(lastStart1, lastStart2, lastEnd1, lastEnd2, start1, start2, end1, end2)
    }

    private mutating func matchRange(_ start1: Int, _ start2: Int, _ end1: Int, _ end2: Int) throws {
        if start1 == end1 && start2 == end2 { return }
        guard start1 <= end1, start2 <= end2 else { return }

        let sequence1 = Array(text1[start1..<end1])
        let sequence2 = Array(text2[start2..<end2])
        let punctuation = try ByChar.comparePunctuation(sequence1, sequence2)

        for change in punctuation.unchanged {
            builder.markEqual(start1 + change.start1, start2 + change.start2, end1: start1 + change.end1, end2: start2 + change.end2)
        }
    }

    private mutating func matchComplexRange(
        _ start11: Int,
        _ start12: Int,
        _ end11: Int,
        _ end12: Int,
        _ start21: Int,
        _ start22: Int,
        _ end21: Int,
        _ end22: Int
    ) throws {
        if start11 == start21 && end11 == end21 {
            try matchComplexRangeLeft(start11, end11, start12, end12, start22, end22)
        } else if start12 == start22 && end12 == end22 {
            try matchComplexRangeRight(start12, end12, start11, end11, start21, end21)
        }
    }

    private mutating func matchComplexRangeLeft(
        _ start1: Int,
        _ end1: Int,
        _ start12: Int,
        _ end12: Int,
        _ start22: Int,
        _ end22: Int
    ) throws {
        guard start1 <= end1, start12 <= end12, start22 <= end22 else { return }
        let sequence1 = Array(text1[start1..<end1])
        let sequence21 = Array(text2[start12..<end12])
        let sequence22 = Array(text2[start22..<end22])

        let changes = try Self.comparePunctuation2Side(sequence1, sequence21, sequence22)

        for change in changes.first.unchanged {
            builder.markEqual(start1 + change.start1, start12 + change.start2, end1: start1 + change.end1, end2: start12 + change.end2)
        }
        for change in changes.second.unchanged {
            builder.markEqual(start1 + change.start1, start22 + change.start2, end1: start1 + change.end1, end2: start22 + change.end2)
        }
    }

    private mutating func matchComplexRangeRight(
        _ start2: Int,
        _ end2: Int,
        _ start11: Int,
        _ end11: Int,
        _ start21: Int,
        _ end21: Int
    ) throws {
        guard start2 <= end2, start11 <= end11, start21 <= end21 else { return }
        let sequence11 = Array(text1[start11..<end11])
        let sequence12 = Array(text1[start21..<end21])
        let sequence2 = Array(text2[start2..<end2])

        let changes = try Self.comparePunctuation2Side(sequence2, sequence11, sequence12)

        for change in changes.first.unchanged {
            builder.markEqual(start11 + change.start2, start2 + change.start1, end1: start11 + change.end2, end2: start2 + change.end1)
        }
        for change in changes.second.unchanged {
            builder.markEqual(start21 + change.start2, start2 + change.start1, end1: start21 + change.end2, end2: start2 + change.end1)
        }
    }

    private static func comparePunctuation2Side(
        _ text1: DiffUnits,
        _ text21: DiffUnits,
        _ text22: DiffUnits
    ) throws -> (first: DiffChanges, second: DiffChanges) {
        let text2 = text21 + text22
        let changes = try ByChar.comparePunctuation(text1, text2)

        let offset = text21.count
        var ranges1: [DiffRange] = []
        var ranges2: [DiffRange] = []
        for change in changes.unchanged {
            if change.end2 <= offset {
                ranges1.append(DiffRange(change.start1, change.end1, change.start2, change.end2))
            } else if change.start2 >= offset {
                ranges2.append(DiffRange(change.start1, change.end1, change.start2 - offset, change.end2 - offset))
            } else {
                let length2 = offset - change.start2
                ranges1.append(DiffRange(change.start1, change.start1 + length2, change.start2, offset))
                ranges2.append(DiffRange(change.start1 + length2, change.end1, 0, change.end2 - offset))
            }
        }

        let iterable1 = DiffChanges(unchanged: ranges1, length1: text1.count, length2: text21.count)
        let iterable2 = DiffChanges(unchanged: ranges2, length1: text1.count, length2: text22.count)
        return (iterable1, iterable2)
    }

    private func startOffset1(_ index: Int) -> Int { words1[index].offset1 - startShift1 }
    private func startOffset2(_ index: Int) -> Int { words2[index].offset1 - startShift2 }
    private func endOffset1(_ index: Int) -> Int { words1[index].offset2 - startShift1 }
    private func endOffset2(_ index: Int) -> Int { words2[index].offset2 - startShift2 }
}
