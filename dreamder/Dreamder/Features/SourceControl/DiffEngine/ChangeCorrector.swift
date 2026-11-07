import Foundation

nonisolated protocol ChangeCorrectionStrategy {
    func matchGap(_ builder: inout DiffChangeBuilder, _ start1: Int, _ end1: Int, _ start2: Int, _ end2: Int) throws
    func originalRange1(_ index: Int) -> (start: Int, end: Int)
    func originalRange2(_ index: Int) -> (start: Int, end: Int)
}

nonisolated enum ChangeCorrector {
    static func build(
        length1: Int,
        length2: Int,
        changes: DiffChanges,
        strategy: some ChangeCorrectionStrategy
    ) throws -> DiffChanges {
        var builder = DiffChangeBuilder(length1: length1, length2: length2)
        var last1 = 0
        var last2 = 0

        for change in changes.unchanged {
            try Task.checkCancellation()
            let count = change.end1 - change.start1
            for i in 0..<max(count, 0) {
                let range1 = strategy.originalRange1(change.start1 + i)
                let range2 = strategy.originalRange2(change.start2 + i)

                try strategy.matchGap(&builder, last1, range1.start, last2, range2.start)
                builder.markEqual(range1.start, range2.start, end1: range1.end, end2: range2.end)

                last1 = range1.end
                last2 = range2.end
            }
        }
        try strategy.matchGap(&builder, last1, length1, last2, length2)
        return builder.finish()
    }
}

nonisolated struct SmartLineChangeCorrection: ChangeCorrectionStrategy {
    let indexes1: [Int]
    let indexes2: [Int]
    let lines1: [ComparisonLine]
    let lines2: [ComparisonLine]

    func matchGap(_ builder: inout DiffChangeBuilder, _ start1: Int, _ end1: Int, _ start2: Int, _ end2: Int) throws {
        let expanded = TrimUtil.expand(start1, start2, end1, end2) { lines1[$0] == lines2[$1] }

        let inner1 = Array(lines1[expanded.start1..<max(expanded.start1, expanded.end1)])
        let inner2 = Array(lines2[expanded.start2..<max(expanded.start2, expanded.end2)])
        let innerChanges = try SequenceDiff.compare(inner1, inner2)

        builder.markEqual(start1, start2, end1: expanded.start1, end2: expanded.start2)

        for chunk in innerChanges.unchanged {
            builder.markEqual(
                expanded.start1 + chunk.start1,
                expanded.start2 + chunk.start2,
                count: chunk.end1 - chunk.start1
            )
        }

        builder.markEqual(expanded.end1, expanded.end2, end1: end1, end2: end2)
    }

    func originalRange1(_ index: Int) -> (start: Int, end: Int) {
        let offset = indexes1[index]
        return (offset, offset + 1)
    }

    func originalRange2(_ index: Int) -> (start: Int, end: Int) {
        let offset = indexes2[index]
        return (offset, offset + 1)
    }
}

nonisolated struct DefaultCharChangeCorrection: ChangeCorrectionStrategy {
    let codePoints1: CodePointsOffsets
    let codePoints2: CodePointsOffsets
    let text1: DiffUnits
    let text2: DiffUnits

    func matchGap(_ builder: inout DiffChangeBuilder, _ start1: Int, _ end1: Int, _ start2: Int, _ end2: Int) throws {
        let inner1 = Array(text1[start1..<max(start1, end1)])
        let inner2 = Array(text2[start2..<max(start2, end2)])
        let innerChanges = try ByChar.compare(inner1, inner2)

        for chunk in innerChanges.unchanged {
            builder.markEqual(start1 + chunk.start1, start2 + chunk.start2, count: chunk.end1 - chunk.start1)
        }
    }

    func originalRange1(_ index: Int) -> (start: Int, end: Int) {
        (codePoints1.charOffset(index), codePoints1.charOffsetAfter(index))
    }

    func originalRange2(_ index: Int) -> (start: Int, end: Int) {
        (codePoints2.charOffset(index), codePoints2.charOffsetAfter(index))
    }
}
