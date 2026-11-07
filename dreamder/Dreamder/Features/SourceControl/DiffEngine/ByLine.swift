import Foundation

nonisolated struct ComparisonLine: Sendable, Hashable {
    let content: DiffUnits
    let policy: ComparisonPolicy
    let contentHash: Int
    let nonSpaceChars: Int

    init(_ content: DiffUnits, policy: ComparisonPolicy) {
        self.content = content
        self.policy = policy
        self.contentHash = ComparisonUtil.hashCode(content, policy)
        var nonSpace = 0
        for unit in content where !ComparisonUtil.isSpaceEnterOrTab(unit) {
            nonSpace += 1
        }
        self.nonSpaceChars = nonSpace
    }

    func converted(to newPolicy: ComparisonPolicy) -> ComparisonLine {
        policy == newPolicy ? self : ComparisonLine(content, policy: newPolicy)
    }

    static func == (lhs: ComparisonLine, rhs: ComparisonLine) -> Bool {
        if lhs.contentHash != rhs.contentHash { return false }
        return ComparisonUtil.isEquals(lhs.content, rhs.content, lhs.policy)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(contentHash)
    }
}

nonisolated enum ByLine {
    static func compare(_ lines1: [DiffUnits], _ lines2: [DiffUnits], _ policy: ComparisonPolicy) throws -> DiffChanges {
        try Task.checkCancellation()
        return try doCompare(comparisonLines(lines1, policy), comparisonLines(lines2, policy), policy)
    }

    static func compare(
        _ lines1: [DiffUnits],
        _ lines2: [DiffUnits],
        _ lines3: [DiffUnits],
        _ policy: ComparisonPolicy
    ) throws -> [MergeRange] {
        try Task.checkCancellation()
        return try doCompare(
            comparisonLines(lines1, policy),
            comparisonLines(lines2, policy),
            comparisonLines(lines3, policy),
            policy,
            keepIgnoredChanges: false
        )
    }

    static func merge(
        _ lines1: [DiffUnits],
        _ lines2: [DiffUnits],
        _ lines3: [DiffUnits],
        _ policy: ComparisonPolicy
    ) throws -> [MergeRange] {
        try Task.checkCancellation()
        return try doCompare(
            comparisonLines(lines1, policy),
            comparisonLines(lines2, policy),
            comparisonLines(lines3, policy),
            policy,
            keepIgnoredChanges: true
        )
    }

    private static func doCompare(
        _ lines1: [ComparisonLine],
        _ lines2: [ComparisonLine],
        _ policy: ComparisonPolicy
    ) throws -> DiffChanges {
        try Task.checkCancellation()

        if policy == .ignoreWhitespaces {
            var changes = try compareSmart(lines1, lines2)
            changes = try ChunkOptimizer.optimizeLines(lines1, lines2, changes)
            return expandRanges(lines1, lines2, changes)
        }

        let iwLines1 = convertMode(lines1, .ignoreWhitespaces)
        let iwLines2 = convertMode(lines2, .ignoreWhitespaces)

        var iwChanges = try compareSmart(iwLines1, iwLines2)
        iwChanges = try ChunkOptimizer.optimizeLines(lines1, lines2, iwChanges)
        return try correctChangesSecondStep(lines1, lines2, iwChanges)
    }

    private static func doCompare(
        _ lines1: [ComparisonLine],
        _ lines2: [ComparisonLine],
        _ lines3: [ComparisonLine],
        _ policy: ComparisonPolicy,
        keepIgnoredChanges: Bool
    ) throws -> [MergeRange] {
        try Task.checkCancellation()

        let iwLines1 = convertMode(lines1, .ignoreWhitespaces)
        let iwLines2 = convertMode(lines2, .ignoreWhitespaces)
        let iwLines3 = convertMode(lines3, .ignoreWhitespaces)

        var iwChanges1 = try compareSmart(iwLines2, iwLines1)
        iwChanges1 = try ChunkOptimizer.optimizeLines(lines2, lines1, iwChanges1)
        let iterable1 = try correctChangesSecondStep(lines2, lines1, iwChanges1)

        var iwChanges2 = try compareSmart(iwLines2, iwLines3)
        iwChanges2 = try ChunkOptimizer.optimizeLines(lines2, lines3, iwChanges2)
        let iterable2 = try correctChangesSecondStep(lines2, lines3, iwChanges2)

        if keepIgnoredChanges && policy != .default {
            return try ComparisonMergeUtil.buildMerge(iterable1, iterable2) { index1, index2, index3 in
                ByLine.equalsDefaultPolicy(lines1, lines2, lines3, index1, index2, index3)
            }
        }
        return try ComparisonMergeUtil.buildSimple(iterable1, iterable2)
    }

    private static func equalsDefaultPolicy(
        _ lines1: [ComparisonLine],
        _ lines2: [ComparisonLine],
        _ lines3: [ComparisonLine],
        _ index1: Int,
        _ index2: Int,
        _ index3: Int
    ) -> Bool {
        let content1 = lines1[index1].content
        let content2 = lines2[index2].content
        let content3 = lines3[index3].content
        return content2 == content1 && content2 == content3
    }

    private static func correctChangesSecondStep(
        _ lines1: [ComparisonLine],
        _ lines2: [ComparisonLine],
        _ changes: DiffChanges
    ) throws -> DiffChanges {
        var builder = DiffChangeBuilder(length1: lines1.count, length2: lines2.count) { lines1[$0] == lines2[$1] }
        var sample: DiffUnits?
        var last1 = 0
        var last2 = 0

        func flush(_ line1: Int, _ line2: Int) {
            guard let currentSample = sample else { return }

            let start1 = max(last1, builder.index1)
            let start2 = max(last2, builder.index2)

            var subLines1: [Int] = []
            var subLines2: [Int] = []
            for i in start1..<max(start1, line1)
            where ComparisonUtil.equalsIgnoreWhitespaces(currentSample, lines1[i].content) {
                subLines1.append(i)
                last1 = i + 1
            }
            for i in start2..<max(start2, line2)
            where ComparisonUtil.equalsIgnoreWhitespaces(currentSample, lines2[i].content) {
                subLines2.append(i)
                last2 = i + 1
            }

            if !subLines1.isEmpty && !subLines2.isEmpty {
                alignExactMatching(subLines1, subLines2)
            }
            sample = nil
        }

        func alignExactMatching(_ subLines1: [Int], _ subLines2: [Int]) {
            let n = max(subLines1.count, subLines2.count)
            let skipAligning = n > 10 || subLines1.count == subLines2.count

            if skipAligning {
                let count = min(subLines1.count, subLines2.count)
                for i in 0..<count {
                    let index1 = subLines1[i]
                    let index2 = subLines2[i]
                    if lines1[index1] == lines2[index2] {
                        builder.markEqual(index1, index2)
                    }
                }
                return
            }

            if subLines1.count < subLines2.count {
                let matching = bestMatchingAlignment(subLines1, subLines2, lines1, lines2)
                for i in 0..<subLines1.count {
                    let index1 = subLines1[i]
                    let index2 = subLines2[matching[i]]
                    if lines1[index1] == lines2[index2] {
                        builder.markEqual(index1, index2)
                    }
                }
            } else {
                let matching = bestMatchingAlignment(subLines2, subLines1, lines2, lines1)
                for i in 0..<subLines2.count {
                    let index1 = subLines1[matching[i]]
                    let index2 = subLines2[i]
                    if lines1[index1] == lines2[index2] {
                        builder.markEqual(index1, index2)
                    }
                }
            }
        }

        for range in changes.unchanged {
            try Task.checkCancellation()
            let count = range.end1 - range.start1
            for i in 0..<max(count, 0) {
                let index1 = range.start1 + i
                let index2 = range.start2 + i
                let line1 = lines1[index1]
                let line2 = lines2[index2]

                let sameAsSample = sample.map { ComparisonUtil.equalsIgnoreWhitespaces($0, line1.content) } ?? false
                if !sameAsSample {
                    if line1 == line2 {
                        flush(index1, index2)
                        builder.markEqual(index1, index2)
                    } else {
                        flush(index1, index2)
                        sample = line1.content
                    }
                }
            }
        }
        flush(changes.length1, changes.length2)
        return builder.finish()
    }

    private static func bestMatchingAlignment(
        _ subLines1: [Int],
        _ subLines2: [Int],
        _ lines1: [ComparisonLine],
        _ lines2: [ComparisonLine]
    ) -> [Int] {
        let size = subLines1.count
        var combination = [Int](repeating: 0, count: size)
        var best = Array(0..<size)
        var bestWeight = 0

        func combinations(_ start: Int, _ n: Int, _ k: Int) {
            if k == size {
                var weight = 0
                for i in 0..<size {
                    if lines1[subLines1[i]] == lines2[subLines2[combination[i]]] { weight += 1 }
                }
                if weight > bestWeight {
                    bestWeight = weight
                    best = combination
                }
                return
            }
            if start > n { return }
            for i in start...n {
                combination[k] = i
                combinations(i + 1, n, k + 1)
            }
        }

        combinations(0, subLines2.count - 1, 0)
        return best
    }

    private static func compareSmart(_ lines1: [ComparisonLine], _ lines2: [ComparisonLine]) throws -> DiffChanges {
        let threshold = ComparisonUtil.unimportantLineCharCount
        if threshold == 0 { return try SequenceDiff.compare(lines1, lines2) }

        let big1 = bigLines(lines1, threshold)
        let big2 = bigLines(lines2, threshold)

        let changes = try SequenceDiff.compare(big1.lines, big2.lines)
        let strategy = SmartLineChangeCorrection(
            indexes1: big1.indexes,
            indexes2: big2.indexes,
            lines1: lines1,
            lines2: lines2
        )
        return try ChangeCorrector.build(length1: lines1.count, length2: lines2.count, changes: changes, strategy: strategy)
    }

    private static func bigLines(_ lines: [ComparisonLine], _ threshold: Int) -> (lines: [ComparisonLine], indexes: [Int]) {
        var big: [ComparisonLine] = []
        var indexes: [Int] = []
        big.reserveCapacity(lines.count)
        indexes.reserveCapacity(lines.count)
        for (index, line) in lines.enumerated() where line.nonSpaceChars > threshold {
            big.append(line)
            indexes.append(index)
        }
        return (big, indexes)
    }

    private static func expandRanges(
        _ lines1: [ComparisonLine],
        _ lines2: [ComparisonLine],
        _ iterable: DiffChanges
    ) -> DiffChanges {
        var changes: [DiffRange] = []
        for change in iterable.changes {
            let expanded = TrimUtil.expand(change.start1, change.start2, change.end1, change.end2) { lines1[$0] == lines2[$1] }
            if !expanded.isEmpty { changes.append(expanded) }
        }
        return DiffChanges(changes: changes, length1: lines1.count, length2: lines2.count)
    }

    private static func comparisonLines(_ lines: [DiffUnits], _ policy: ComparisonPolicy) -> [ComparisonLine] {
        lines.map { ComparisonLine($0, policy: policy) }
    }

    private static func convertMode(_ lines: [ComparisonLine], _ policy: ComparisonPolicy) -> [ComparisonLine] {
        lines.map { $0.converted(to: policy) }
    }
}
