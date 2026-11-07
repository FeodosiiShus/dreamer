import Foundation

nonisolated enum ComparisonMergeUtil {
    static func buildSimple(_ fragments1: DiffChanges, _ fragments2: DiffChanges) throws -> [MergeRange] {
        var builder = FairMergeBuilder(trueEquality: nil)
        return try builder.execute(fragments1, fragments2)
    }

    static func buildMerge(
        _ fragments1: DiffChanges,
        _ fragments2: DiffChanges,
        trueEquality: @escaping (Int, Int, Int) -> Bool
    ) throws -> [MergeRange] {
        var builder = FairMergeBuilder(trueEquality: trueEquality)
        return try builder.execute(fragments1, fragments2)
    }

    static func tryResolveConflict(left: DiffUnits, base: DiffUnits, right: DiffUnits) -> DiffUnits? {
        MergeResolveUtil.tryResolve(left: left, base: base, right: right)
    }
}

nonisolated struct FairMergeBuilder {
    private var changes: [MergeRange] = []
    private var index1 = 0
    private var index2 = 0
    private var index3 = 0
    private let trueEquality: ((Int, Int, Int) -> Bool)?

    init(trueEquality: ((Int, Int, Int) -> Bool)?) {
        self.trueEquality = trueEquality
    }

    mutating func execute(_ fragments1: DiffChanges, _ fragments2: DiffChanges) throws -> [MergeRange] {
        let unchanged1 = fragments1.unchanged
        let unchanged2 = fragments2.unchanged
        var cursor1 = 0
        var cursor2 = 0

        while cursor1 < unchanged1.count && cursor2 < unchanged2.count {
            try Task.checkCancellation()
            let side = add(unchanged1[cursor1], unchanged2[cursor2])
            if side == .left {
                cursor1 += 1
            } else {
                cursor2 += 1
            }
        }

        finish(fragments1.length2, fragments1.length1, fragments2.length2)
        return changes
    }

    private mutating func add(_ range1: DiffRange, _ range2: DiffRange) -> DiffSide {
        let start1 = range1.start1
        let end1 = range1.end1

        let start2 = range2.start1
        let end2 = range2.end1

        if end1 <= start2 { return .left }
        if end2 <= start1 { return .right }

        let startBase = max(start1, start2)
        let endBase = min(end1, end2)
        let count = endBase - startBase

        let startShift1 = startBase - start1
        let startShift2 = startBase - start2

        let startLeft = range1.start2 + startShift1
        let endLeft = startLeft + count
        let startRight = range2.start2 + startShift2
        let endRight = startRight + count

        markEqual(startLeft, startBase, startRight, endLeft, endBase, endRight)

        return DiffSide.fromLeft(end1 <= end2)
    }

    private mutating func markEqual(_ start1: Int, _ start2: Int, _ start3: Int, _ end1: Int, _ end2: Int, _ end3: Int) {
        processChange(index1, index2, index3, start1, start2, start3)
        index1 = end1
        index2 = end2
        index3 = end3
    }

    private mutating func finish(_ length1: Int, _ length2: Int, _ length3: Int) {
        processChange(index1, index2, index3, length1, length2, length3)
    }

    private mutating func processChange(_ start1: Int, _ start2: Int, _ start3: Int, _ end1: Int, _ end2: Int, _ end3: Int) {
        if let equality = trueEquality {
            let last = changes.last
            addIgnoredChanges(
                last?.end1 ?? 0,
                last?.end2 ?? 0,
                last?.end3 ?? 0,
                start1,
                start2,
                start3,
                equality
            )
        }
        addChange(start1, start2, start3, end1, end2, end3)
    }

    private mutating func addIgnoredChanges(
        _ start1: Int,
        _ start2: Int,
        _ start3: Int,
        _ end1: Int,
        _ end2: Int,
        _ end3: Int,
        _ equality: (Int, Int, Int) -> Bool
    ) {
        let count = end2 - start2
        guard count > 0, end1 - start1 == count, end3 - start3 == count else { return }

        var firstIgnoredCount = -1
        for i in 0..<count {
            let isIgnored = !equality(start1 + i, start2 + i, start3 + i)
            let previousAreIgnored = firstIgnoredCount != -1

            if isIgnored && !previousAreIgnored {
                firstIgnoredCount = i
            }
            if !isIgnored && previousAreIgnored {
                addChange(
                    start1 + firstIgnoredCount,
                    start2 + firstIgnoredCount,
                    start3 + firstIgnoredCount,
                    start1 + i,
                    start2 + i,
                    start3 + i
                )
                firstIgnoredCount = -1
            }
        }

        if firstIgnoredCount != -1 {
            addChange(
                start1 + firstIgnoredCount,
                start2 + firstIgnoredCount,
                start3 + firstIgnoredCount,
                start1 + count,
                start2 + count,
                start3 + count
            )
        }
    }

    private mutating func addChange(_ start1: Int, _ start2: Int, _ start3: Int, _ end1: Int, _ end2: Int, _ end3: Int) {
        if start1 == end1 && start2 == end2 && start3 == end3 { return }
        changes.append(MergeRange(start1, end1, start2, end2, start3, end3))
    }
}
