import Testing
import Foundation
@testable import Dreamder

@Suite struct DiffRangesCoverageTests {
    @Test func threeSideSelectsTheValueOfItsSide() {
        #expect(ThreeSide.left.select("l", "b", "r") == "l")
        #expect(ThreeSide.base.select("l", "b", "r") == "b")
        #expect(ThreeSide.right.select("l", "b", "r") == "r")
        #expect(ThreeSide.allCases == [.left, .base, .right])
    }

    @Test func diffSideSelectsAndFlips() {
        #expect(DiffSide.left.select(1, 2) == 1)
        #expect(DiffSide.right.select(1, 2) == 2)
        #expect(DiffSide.left.other == .right)
        #expect(DiffSide.right.other == .left)
        #expect(DiffSide.fromLeft(true) == .left)
        #expect(DiffSide.fromLeft(false) == .right)
    }

    @Test func mergeRangeExposesEverySide() {
        let range = MergeRange(1, 4, 2, 2, 7, 5)

        #expect(range.start(.left) == 1)
        #expect(range.start(.base) == 2)
        #expect(range.start(.right) == 7)
        #expect(range.end(.left) == 4)
        #expect(range.end(.base) == 2)
        #expect(range.end(.right) == 5)
        #expect(range.range(.left) == 1..<4)
        #expect(range.range(.base) == 2..<2)
        #expect(range.range(.right) == 7..<7)
        #expect(range.isEmpty == false)
        #expect(MergeRange(3, 3, 4, 4, 5, 5).isEmpty)
    }

    @Test func diffRangeAndFragmentReportEmptiness() {
        #expect(DiffRange(1, 1, 2, 2).isEmpty)
        #expect(DiffRange(1, 2, 2, 2).isEmpty == false)
        #expect(DiffRange(1, 4, 2, 9).length1 == 3)
        #expect(DiffRange(1, 4, 2, 9).length2 == 7)
        #expect(DiffFragment(1, 1, 2, 2).isEmpty)
        #expect(DiffFragment(1, 2, 2, 2).isEmpty == false)
        #expect(DiffFragment(1, 1, 2, 3).isEmpty == false)
    }

    @Test func bitSetReadsOutsideItsStorageAsUnset() {
        var set = DiffBitSet(count: 2)

        #expect(set[-1] == false)
        #expect(set[0] == false)
        #expect(set[5] == false)

        set[-1] = true
        set[4] = true

        #expect(set[-1] == false)
        #expect(set[4])
        #expect(set[3] == false)
    }

    @Test func bitSetRangesGrowTheStorageAndCanBeCleared() {
        var set = DiffBitSet(count: -3)

        set.set(from: -2, to: 3)
        #expect((0..<4).map { set[$0] } == [true, true, true, false])

        set.set(from: 1, to: 2, value: false)
        #expect((0..<4).map { set[$0] } == [true, false, true, false])

        set.set(from: 5, to: 5)
        set.set(from: 6, to: 4)
        #expect((0..<8).map { set[$0] } == [true, false, true, false, false, false, false, false])
    }

    @Test func changesWithoutAnyRangeAreEmpty() {
        let unchanged = DiffChanges(changes: [], length1: 3, length2: 3)
        let changed = DiffChanges(changes: [DiffRange(1, 2, 1, 2)], length1: 3, length2: 3)

        #expect(unchanged.isEmpty)
        #expect(changed.isEmpty == false)
        #expect(unchanged.unchanged == [DiffRange(0, 3, 0, 3)])
    }

    @Test func iterateAllInterleavesUnchangedGapsAndChanges() {
        let changes = DiffChanges(changes: [DiffRange(1, 2, 1, 3), DiffRange(4, 4, 5, 6)], length1: 6, length2: 8)

        let items = changes.iterateAll()

        #expect(items.map(\.range) == [
            DiffRange(0, 1, 0, 1),
            DiffRange(1, 2, 1, 3),
            DiffRange(2, 4, 3, 5),
            DiffRange(4, 4, 5, 6),
            DiffRange(4, 6, 6, 8)
        ])
        #expect(items.map(\.isUnchanged) == [true, false, true, false, true])
    }

    @Test func builtFromUnchangedRangesTheChangesAreTheirComplement() {
        let changes = DiffChanges(unchanged: [DiffRange(1, 2, 0, 1)], length1: 4, length2: 3)

        #expect(changes.changes == [DiffRange(0, 1, 0, 0), DiffRange(2, 4, 1, 3)])
    }

    @Test func builderIgnoresEmptyAndBackwardsEqualRanges() {
        var builder = DiffChangeBuilder(length1: 5, length2: 5)

        builder.markEqual(2, 2, count: 0)
        builder.markEqual(1, 1)
        builder.markEqual(0, 0)
        builder.markEqual(3, 3, end1: 2, end2: 4)

        #expect(builder.index1 == 2)
        #expect(builder.index2 == 2)
        #expect(builder.finish().changes == [DiffRange(0, 1, 0, 1), DiffRange(2, 5, 2, 5)])
    }

    @Test func builderExpandsChangesOverEqualBoundaries() {
        let first = Array("abcabc".utf8)
        let second = Array("abcxabc".utf8)
        var builder = DiffChangeBuilder(length1: first.count, length2: second.count) { first[$0] == second[$1] }

        builder.markEqual(0, 0, count: 2)
        builder.markEqual(5, 6)

        #expect(builder.finish().changes == [DiffRange(3, 3, 3, 4)])
    }

    @Test func builderDropsChangesThatExpandToNothing() {
        let first = Array("aa".utf8)
        let second = Array("aa".utf8)
        var builder = DiffChangeBuilder(length1: first.count, length2: second.count) { first[$0] == second[$1] }

        builder.markEqual(1, 1)

        #expect(builder.finish().changes.isEmpty)
    }

    @Test func mergeConflictTypeAnswersForEverySide() {
        let type = MergeConflictType(.modified, leftChange: true, rightChange: false)

        #expect(type.isChange(.left))
        #expect(type.isChange(.base))
        #expect(type.isChange(.right) == false)
        #expect(type.canBeResolved)
        #expect(MergeConflictType(.conflict, leftChange: true, rightChange: true, resolutionStrategy: nil).canBeResolved == false)
    }

    @Test func wordMergeOfIdenticalContentsIsAModificationOfBothSides() {
        let units = Array("same".utf16)

        let type = MergeRangeUtil.wordMergeType(
            range: MergeRange(0, 4, 0, 4, 0, 4),
            left: units,
            base: units,
            right: units,
            policy: .default
        )

        #expect(type.kind == .modified)
        #expect(type.isLeftChange)
        #expect(type.isRightChange)
    }

    @Test func mergeTypeCoversEveryEmptinessAndEqualityCombination() {
        func type(
            empty: Set<ThreeSide>,
            equal: Set<[ThreeSide]>,
            trueEqual: Set<[ThreeSide]>? = nil,
            resolvable: Bool = false
        ) -> MergeConflictType {
            MergeRangeUtil.mergeType(
                isEmpty: { empty.contains($0) },
                equality: { equal.contains([$0, $1]) || equal.contains([$1, $0]) },
                trueEquality: trueEqual.map { set in { set.contains([$0, $1]) || set.contains([$1, $0]) } },
                conflictResolver: { resolvable }
            )
        }

        let insertedRight = type(empty: [.left, .base], equal: [])
        #expect(insertedRight.kind == .inserted && !insertedRight.isLeftChange && insertedRight.isRightChange)

        let insertedLeft = type(empty: [.right, .base], equal: [])
        #expect(insertedLeft.kind == .inserted && insertedLeft.isLeftChange && !insertedLeft.isRightChange)

        let insertedBoth = type(empty: [.base], equal: [[.left, .right]])
        #expect(insertedBoth.kind == .inserted && insertedBoth.isLeftChange && insertedBoth.isRightChange)

        let insertedConflict = type(empty: [.base], equal: [])
        #expect(insertedConflict.kind == .conflict && !insertedConflict.canBeResolved)

        let deletedBoth = type(empty: [.left, .right], equal: [])
        #expect(deletedBoth.kind == .deleted && deletedBoth.isLeftChange && deletedBoth.isRightChange)

        let unchangedBothWithoutTruth = type(empty: [], equal: [[.base, .left], [.base, .right]])
        #expect(unchangedBothWithoutTruth.kind == .modified && unchangedBothWithoutTruth.isLeftChange && unchangedBothWithoutTruth.isRightChange)

        let unchangedBothTrueLeft = type(
            empty: [],
            equal: [[.base, .left], [.base, .right]],
            trueEqual: [[.base, .left]]
        )
        #expect(unchangedBothTrueLeft.kind == .modified && !unchangedBothTrueLeft.isLeftChange && unchangedBothTrueLeft.isRightChange)

        let unchangedLeftDeletedRight = type(empty: [.right], equal: [[.base, .left]])
        #expect(unchangedLeftDeletedRight.kind == .deleted && !unchangedLeftDeletedRight.isLeftChange && unchangedLeftDeletedRight.isRightChange)

        let unchangedLeftModifiedRight = type(empty: [], equal: [[.base, .left]])
        #expect(unchangedLeftModifiedRight.kind == .modified && !unchangedLeftModifiedRight.isLeftChange && unchangedLeftModifiedRight.isRightChange)

        let unchangedRightDeletedLeft = type(empty: [.left], equal: [[.base, .right]])
        #expect(unchangedRightDeletedLeft.kind == .deleted && unchangedRightDeletedLeft.isLeftChange && !unchangedRightDeletedLeft.isRightChange)

        let unchangedRightModifiedLeft = type(empty: [], equal: [[.base, .right]])
        #expect(unchangedRightModifiedLeft.kind == .modified && unchangedRightModifiedLeft.isLeftChange && !unchangedRightModifiedLeft.isRightChange)

        let sameChange = type(empty: [], equal: [[.left, .right]])
        #expect(sameChange.kind == .modified && sameChange.isLeftChange && sameChange.isRightChange)

        let resolvable = type(empty: [], equal: [], resolvable: true)
        #expect(resolvable.kind == .conflict && resolvable.resolutionStrategy == .text)

        let unresolvable = type(empty: [], equal: [])
        #expect(unresolvable.kind == .conflict && unresolvable.resolutionStrategy == nil)

        let emptySideBlocksResolution = type(empty: [.left], equal: [], resolvable: true)
        #expect(emptySideBlocksResolution.kind == .conflict && emptySideBlocksResolution.resolutionStrategy == nil)
    }
}
