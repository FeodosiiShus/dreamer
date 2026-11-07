import Foundation

nonisolated struct CodePointsOffsets: Sendable {
    let codePoints: [Int]
    let offsets: [Int]

    func charOffset(_ index: Int) -> Int {
        offsets[index]
    }

    func charOffsetAfter(_ index: Int) -> Int {
        offsets[index] + TrimUtil.charCount(codePoints[index])
    }
}

nonisolated enum ByChar {
    static func compare(_ text1: DiffUnits, _ text2: DiffUnits) throws -> DiffChanges {
        try Task.checkCancellation()
        let codePoints1 = allCodePoints(text1)
        let codePoints2 = allCodePoints(text2)

        let iterable = try SequenceDiff.compare(codePoints1, codePoints2)

        var offset1 = 0
        var offset2 = 0
        var builder = DiffChangeBuilder(length1: text1.count, length2: text2.count)
        for (range, isUnchanged) in iterable.iterateAll() {
            let end1 = offset1 + countChars(codePoints1, range.start1, range.end1)
            let end2 = offset2 + countChars(codePoints2, range.start2, range.end2)
            if isUnchanged {
                builder.markEqual(offset1, offset2, end1: end1, end2: end2)
            }
            offset1 = end1
            offset2 = end2
        }
        return builder.finish()
    }

    static func compareTwoStep(_ text1: DiffUnits, _ text2: DiffUnits) throws -> DiffChanges {
        try Task.checkCancellation()
        let codePoints1 = nonSpaceCodePoints(text1)
        let codePoints2 = nonSpaceCodePoints(text2)

        let nonSpaceChanges = try SequenceDiff.compare(codePoints1.codePoints, codePoints2.codePoints)
        let strategy = DefaultCharChangeCorrection(
            codePoints1: codePoints1,
            codePoints2: codePoints2,
            text1: text1,
            text2: text2
        )
        return try ChangeCorrector.build(
            length1: text1.count,
            length2: text2.count,
            changes: nonSpaceChanges,
            strategy: strategy
        )
    }

    static func compareTrimWhitespaces(_ text1: DiffUnits, _ text2: DiffUnits) throws -> DiffChanges {
        let iterable = try compareTwoStep(text1, text2)
        return ByWord.trimSpacesCorrected(iterable, text1, text2)
    }

    static func compareIgnoreWhitespaces(_ text1: DiffUnits, _ text2: DiffUnits) throws -> DiffChanges {
        try Task.checkCancellation()
        let codePoints1 = nonSpaceCodePoints(text1)
        let codePoints2 = nonSpaceCodePoints(text2)

        let changes = try SequenceDiff.compare(codePoints1.codePoints, codePoints2.codePoints)
        return matchAdjustmentSpacesIgnoringWhitespaces(codePoints1, codePoints2, text1, text2, changes)
    }

    static func comparePunctuation(_ text1: DiffUnits, _ text2: DiffUnits) throws -> DiffChanges {
        try Task.checkCancellation()
        let chars1 = punctuationChars(text1)
        let chars2 = punctuationChars(text2)

        let changes = try SequenceDiff.compare(chars1.codePoints, chars2.codePoints)

        var builder = DiffChangeBuilder(length1: text1.count, length2: text2.count)
        for range in changes.unchanged {
            let count = range.end1 - range.start1
            for i in 0..<max(count, 0) {
                builder.markEqual(chars1.offsets[range.start1 + i], chars2.offsets[range.start2 + i])
            }
        }
        return builder.finish()
    }

    private static func matchAdjustmentSpacesIgnoringWhitespaces(
        _ codePoints1: CodePointsOffsets,
        _ codePoints2: CodePointsOffsets,
        _ text1: DiffUnits,
        _ text2: DiffUnits,
        _ changes: DiffChanges
    ) -> DiffChanges {
        var ranges: [DiffRange] = []
        for change in changes.changes {
            let startOffset1: Int
            let endOffset1: Int
            if change.start1 == change.end1 {
                endOffset1 = expandForwardIgnoring(codePoints1, codePoints2, text1, text2, change, left: true)
                startOffset1 = endOffset1
            } else {
                startOffset1 = codePoints1.charOffset(change.start1)
                endOffset1 = codePoints1.charOffsetAfter(change.end1 - 1)
            }

            let startOffset2: Int
            let endOffset2: Int
            if change.start2 == change.end2 {
                endOffset2 = expandForwardIgnoring(codePoints1, codePoints2, text1, text2, change, left: false)
                startOffset2 = endOffset2
            } else {
                startOffset2 = codePoints2.charOffset(change.start2)
                endOffset2 = codePoints2.charOffsetAfter(change.end2 - 1)
            }

            ranges.append(DiffRange(startOffset1, endOffset1, startOffset2, endOffset2))
        }
        return DiffChanges(changes: ranges, length1: text1.count, length2: text2.count)
    }

    private static func expandForwardIgnoring(
        _ codePoints1: CodePointsOffsets,
        _ codePoints2: CodePointsOffsets,
        _ text1: DiffUnits,
        _ text2: DiffUnits,
        _ change: DiffRange,
        left: Bool
    ) -> Int {
        let offset1 = change.start1 == 0 ? 0 : codePoints1.charOffsetAfter(change.start1 - 1)
        let offset2 = change.start2 == 0 ? 0 : codePoints2.charOffsetAfter(change.start2 - 1)
        let start = left ? offset1 : offset2
        return start + TrimUtil.expandWhitespacesForward(text1, text2, offset1, offset2, text1.count, text2.count)
    }

    private static func allCodePoints(_ text: DiffUnits) -> [Int] {
        var result: [Int] = []
        result.reserveCapacity(text.count)
        var offset = 0
        while offset < text.count {
            let codePoint = TrimUtil.codePointAt(text, offset)
            result.append(codePoint)
            offset += TrimUtil.charCount(codePoint)
        }
        return result
    }

    private static func nonSpaceCodePoints(_ text: DiffUnits) -> CodePointsOffsets {
        var codePoints: [Int] = []
        var offsets: [Int] = []
        codePoints.reserveCapacity(text.count)
        offsets.reserveCapacity(text.count)
        var offset = 0
        while offset < text.count {
            let codePoint = TrimUtil.codePointAt(text, offset)
            if !TrimUtil.isWhiteSpaceCodePoint(codePoint) {
                codePoints.append(codePoint)
                offsets.append(offset)
            }
            offset += TrimUtil.charCount(codePoint)
        }
        return CodePointsOffsets(codePoints: codePoints, offsets: offsets)
    }

    private static func punctuationChars(_ text: DiffUnits) -> CodePointsOffsets {
        var codePoints: [Int] = []
        var offsets: [Int] = []
        for (index, unit) in text.enumerated() where TrimUtil.isPunctuation(Int(unit)) {
            codePoints.append(Int(unit))
            offsets.append(index)
        }
        return CodePointsOffsets(codePoints: codePoints, offsets: offsets)
    }

    private static func countChars(_ codePoints: [Int], _ start: Int, _ end: Int) -> Int {
        var count = 0
        for index in start..<max(start, end) {
            count += TrimUtil.charCount(codePoints[index])
        }
        return count
    }
}
