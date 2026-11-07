import Foundation

nonisolated enum MergeConflictResolutionStrategy: Sendable, Hashable {
    case `default`
    case text
}

nonisolated struct MergeConflictType: Sendable, Hashable {
    enum Kind: Sendable, Hashable {
        case inserted
        case deleted
        case modified
        case conflict
    }

    let kind: Kind
    let isLeftChange: Bool
    let isRightChange: Bool
    let resolutionStrategy: MergeConflictResolutionStrategy?

    init(
        _ kind: Kind,
        leftChange: Bool,
        rightChange: Bool,
        resolutionStrategy: MergeConflictResolutionStrategy? = .default
    ) {
        self.kind = kind
        self.isLeftChange = leftChange
        self.isRightChange = rightChange
        self.resolutionStrategy = resolutionStrategy
    }

    var canBeResolved: Bool { resolutionStrategy != nil }

    func isChange(_ side: ThreeSide) -> Bool {
        switch side {
        case .left: return isLeftChange
        case .base: return true
        case .right: return isRightChange
        }
    }
}

nonisolated enum MergeRangeUtil {
    static func mergeType(
        isEmpty: (ThreeSide) -> Bool,
        equality: (ThreeSide, ThreeSide) -> Bool,
        trueEquality: ((ThreeSide, ThreeSide) -> Bool)?,
        conflictResolver: () -> Bool
    ) -> MergeConflictType {
        let isLeftEmpty = isEmpty(.left)
        let isBaseEmpty = isEmpty(.base)
        let isRightEmpty = isEmpty(.right)

        if isBaseEmpty {
            if isLeftEmpty {
                return MergeConflictType(.inserted, leftChange: false, rightChange: true)
            } else if isRightEmpty {
                return MergeConflictType(.inserted, leftChange: true, rightChange: false)
            } else {
                if equality(.left, .right) {
                    return MergeConflictType(.inserted, leftChange: true, rightChange: true)
                }
                return MergeConflictType(.conflict, leftChange: true, rightChange: true, resolutionStrategy: nil)
            }
        }

        if isLeftEmpty && isRightEmpty {
            return MergeConflictType(.deleted, leftChange: true, rightChange: true)
        }

        let unchangedLeft = equality(.base, .left)
        let unchangedRight = equality(.base, .right)

        if unchangedLeft && unchangedRight {
            let trueUnchangedLeft = trueEquality?(.base, .left) ?? false
            let trueUnchangedRight = trueEquality?(.base, .right) ?? false
            return MergeConflictType(.modified, leftChange: !trueUnchangedLeft, rightChange: !trueUnchangedRight)
        }

        if unchangedLeft {
            return MergeConflictType(isRightEmpty ? .deleted : .modified, leftChange: false, rightChange: true)
        }
        if unchangedRight {
            return MergeConflictType(isLeftEmpty ? .deleted : .modified, leftChange: true, rightChange: false)
        }

        if equality(.left, .right) {
            return MergeConflictType(.modified, leftChange: true, rightChange: true)
        }

        let canBeResolved = !isLeftEmpty && !isRightEmpty && conflictResolver()
        return MergeConflictType(
            .conflict,
            leftChange: true,
            rightChange: true,
            resolutionStrategy: canBeResolved ? .text : nil
        )
    }

    static func lineMergeType(
        range: MergeRange,
        left: [DiffUnits],
        base: [DiffUnits],
        right: [DiffUnits],
        policy: ComparisonPolicy
    ) -> MergeConflictType {
        mergeType(
            isEmpty: { side in range.start(side) == range.end(side) },
            equality: { side1, side2 in
                lineContentsEqual(range, left, base, right, policy, side1, side2)
            },
            trueEquality: { side1, side2 in
                MergeRangeUtil.lineContentsEqual(range, left, base, right, .default, side1, side2)
            },
            conflictResolver: {
                canResolveLineConflict(range, left, base, right)
            }
        )
    }

    static func wordMergeType(
        range: MergeRange,
        left: DiffUnits,
        base: DiffUnits,
        right: DiffUnits,
        policy: ComparisonPolicy
    ) -> MergeConflictType {
        mergeType(
            isEmpty: { side in range.start(side) == range.end(side) },
            equality: { side1, side2 in
                wordContentsEqual(range, left, base, right, policy, side1, side2)
            },
            trueEquality: nil,
            conflictResolver: { false }
        )
    }

    static func wordContentsEqual(
        _ range: MergeRange,
        _ left: DiffUnits,
        _ base: DiffUnits,
        _ right: DiffUnits,
        _ policy: ComparisonPolicy,
        _ side1: ThreeSide,
        _ side2: ThreeSide
    ) -> Bool {
        let texts = [left, base, right]
        let text1 = texts[index(of: side1)]
        let text2 = texts[index(of: side2)]
        let content1 = Array(text1[range.range(side1)])
        let content2 = Array(text2[range.range(side2)])
        return ComparisonUtil.isEqualTexts(content1, content2, policy)
    }

    private static func lineContentsEqual(
        _ range: MergeRange,
        _ left: [DiffUnits],
        _ base: [DiffUnits],
        _ right: [DiffUnits],
        _ policy: ComparisonPolicy,
        _ side1: ThreeSide,
        _ side2: ThreeSide
    ) -> Bool {
        let sides = [left, base, right]
        let lines1 = sides[index(of: side1)]
        let lines2 = sides[index(of: side2)]
        let range1 = range.range(side1)
        let range2 = range.range(side2)
        if range1.count != range2.count { return false }
        for offset in 0..<range1.count {
            if !ComparisonUtil.isEqualTexts(lines1[range1.lowerBound + offset], lines2[range2.lowerBound + offset], policy) {
                return false
            }
        }
        return true
    }

    private static func canResolveLineConflict(
        _ range: MergeRange,
        _ left: [DiffUnits],
        _ base: [DiffUnits],
        _ right: [DiffUnits]
    ) -> Bool {
        let leftText = joinedLines(left, range.range(.left))
        let baseText = joinedLines(base, range.range(.base))
        let rightText = joinedLines(right, range.range(.right))
        return MergeResolveUtil.tryResolve(left: leftText, base: baseText, right: rightText) != nil
    }

    static func joinedLines(_ lines: [DiffUnits], _ range: Range<Int>) -> DiffUnits {
        var result: DiffUnits = []
        for index in range {
            if index > range.lowerBound { result.append(10) }
            result.append(contentsOf: lines[index])
        }
        return result
    }

    private static func index(of side: ThreeSide) -> Int {
        switch side {
        case .left: return 0
        case .base: return 1
        case .right: return 2
        }
    }
}
