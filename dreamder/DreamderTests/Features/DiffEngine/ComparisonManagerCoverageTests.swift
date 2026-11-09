import Testing
import Foundation
@testable import Dreamder

private func repeatedWords(_ word: String, _ count: Int) -> String {
    Array(repeating: word, count: count).joined(separator: " ")
}

private func ignoredRangeFragments(
    _ before: String,
    _ after: String,
    ignoredBefore: [Range<Int>],
    ignoredAfter: [Range<Int>],
    _ policy: InnerFragmentsPolicy
) throws -> [LineFragment] {
    let units1 = Array(before.utf16)
    let units2 = Array(after.utf16)
    return try ComparisonManager.compareLinesWithIgnoredRanges(
        units1,
        units2,
        LineOffsets(text: units1),
        LineOffsets(text: units2),
        ComparisonManager.collectIgnoredRanges(ignoredBefore),
        ComparisonManager.collectIgnoredRanges(ignoredAfter),
        policy
    )
}

@Suite struct ComparisonManagerMergeBlocksCoverageTests {
    @Test func conflictOfDisjointWordEditsIsResolvedIntoTheCombinedLine() throws {
        let blocks = try ComparisonManager.mergeBlocks(left: ["x b c"], base: ["a b c"], right: ["a b y"])

        let block = try #require(blocks.first)
        #expect(blocks.count == 1)
        #expect(block.range == MergeRange(0, 1, 0, 1, 0, 1))
        #expect(block.type.kind == .conflict)
        #expect(block.type.resolutionStrategy == .text)
        #expect(block.resolvedLines == ["x b y"])
    }

    @Test func resolvedMultiLineConflictIsSplitIntoLines() throws {
        let blocks = try ComparisonManager.mergeBlocks(
            left: ["x b", "c d"],
            base: ["a b", "c d"],
            right: ["a b", "c y"]
        )

        let block = try #require(blocks.first)
        #expect(blocks.count == 1)
        #expect(block.range == MergeRange(0, 2, 0, 2, 0, 2))
        #expect(block.resolvedLines == ["x b", "c y"])
    }

    @Test func conflictResolvedIntoNothingYieldsOneEmptyLine() throws {
        let blocks = try ComparisonManager.mergeBlocks(left: [""], base: ["ab"], right: ["a b"])

        let block = try #require(blocks.first)
        #expect(block.type.kind == .conflict)
        #expect(block.resolvedLines == [""])
    }

    @Test func conflictOfTheSameWordHasNoResolution() throws {
        let blocks = try ComparisonManager.mergeBlocks(left: ["b"], base: ["a"], right: ["c"])

        let block = try #require(blocks.first)
        #expect(block.type.kind == .conflict)
        #expect(block.type.canBeResolved == false)
        #expect(block.resolvedLines == nil)
    }

    @Test func oneSidedChangeIsNeverResolvedBecauseItIsNotAConflict() throws {
        let blocks = try ComparisonManager.mergeBlocks(left: ["l"], base: ["a"], right: ["a"])

        let block = try #require(blocks.first)
        #expect(block.type.kind == .modified)
        #expect(block.type.isLeftChange)
        #expect(block.type.isRightChange == false)
        #expect(block.resolvedLines == nil)
    }

    @Test func identicalSidesProduceNoBlocks() throws {
        #expect(try ComparisonManager.mergeBlocks(left: ["a b"], base: ["a b"], right: ["a b"]).isEmpty)
    }

    @Test func tryResolveConflictCombinesDisjointEditsAndRejectsOverlappingOnes() {
        #expect(ComparisonManager.tryResolveConflict(left: "x b c", base: "a b c", right: "a b y") == "x b y")
        #expect(ComparisonManager.tryResolveConflict(left: "b", base: "a", right: "c") == nil)
    }
}

@Suite struct ComparisonManagerInnerFragmentsCoverageTests {
    private static let before = "a b\nc d"
    private static let after = "a  b\nc  d"

    @Test func withoutInnerFragmentsPolicyTheLineFragmentsAreReturnedAsIs() throws {
        let fragments = try ComparisonManager.compareLinesInner(Self.before, Self.after, fragmentsPolicy: .none)

        #expect(fragments.count == 1)
        #expect(fragments.first?.innerFragments == nil)
    }

    @Test func createInnerFragmentsWithNonePolicyKeepsEveryFragment() throws {
        let units1 = Array(Self.before.utf16)
        let units2 = Array(Self.after.utf16)
        let lineFragments = try ComparisonManager.compareLines(units1, units2, .default)

        let result = try ComparisonManager.createInnerFragments(lineFragments, units1, units2, .default, .none)

        #expect(result == lineFragments)
    }

    @Test func charPolicyReportsEveryInsertedCharacter() throws {
        let fragments = try ComparisonManager.compareLinesInner(Self.before, Self.after, fragmentsPolicy: .chars)

        let fragment = try #require(fragments.first)
        #expect(fragments.count == 1)
        #expect(fragment.innerFragments == [DiffFragment(2, 2, 2, 3), DiffFragment(6, 6, 7, 8)])
    }

    @Test func wordPolicyIgnoringWhitespacesYieldsNoInnerChange() throws {
        let units1 = Array(Self.before.utf16)
        let units2 = Array(Self.after.utf16)
        let lineFragments = try ComparisonManager.compareLines(units1, units2, .default)

        let result = try ComparisonManager.createInnerFragments(lineFragments, units1, units2, .ignoreWhitespaces, .words)

        #expect(result.count == 1)
        #expect(result.first?.innerFragments?.isEmpty == true)
    }

    @Test func fragmentWhoseInnerDiffIsTooBigIsKeptWholeWithoutInnerFragments() throws {
        let before = "p\n\(repeatedWords("a", 300)) \(repeatedWords("b", 300))\nr"
        let after = "p\n\(repeatedWords("b", 300)) \(repeatedWords("a", 300))\nr"

        let exact = try ComparisonManager.compareLinesInner(before, after, fragmentsPolicy: .words)
        let limited = try SequenceDiff.$myersLimit.withValue(100) {
            try ComparisonManager.compareLinesInner(before, after, fragmentsPolicy: .words)
        }

        #expect(exact.first?.innerFragments?.count == 2)
        #expect(limited.count == 1)
        #expect(limited.first?.innerFragments == nil)
        #expect(limited.first.map { DiffRange($0.startLine1, $0.endLine1, $0.startLine2, $0.endLine2) } == DiffRange(1, 2, 1, 2))
    }

    @Test func afterThreeTooBigFragmentsTheRemainingOnesAreNotComputedAtAll() throws {
        let before = Array(repeating: "p\n\(repeatedWords("a", 300)) \(repeatedWords("b", 300))\nr\n", count: 5).joined()
        let after = Array(repeating: "p\n\(repeatedWords("b", 300)) \(repeatedWords("a", 300))\nr\n", count: 5).joined()

        let fragments = try SequenceDiff.$myersLimit.withValue(100) {
            try ComparisonManager.compareLinesInner(before, after, fragmentsPolicy: .words)
        }

        #expect(fragments.count == 5)
        #expect(fragments.allSatisfy { $0.innerFragments == nil })
    }
}

@Suite struct ComparisonManagerBlocksCoverageTests {
    private func fragments(_ before: String, _ after: String) -> (units1: DiffUnits, units2: DiffUnits, [LineFragment]) {
        let units1 = Array(before.utf16)
        let units2 = Array(after.utf16)
        let offsets1 = LineOffsets(text: units1)
        let offsets2 = LineOffsets(text: units2)
        let first = ComparisonManager.createLineFragment(0, 1, 0, 1, offsets1, offsets2)
        let second = ComparisonManager.createLineFragment(1, 2, 1, 2, offsets1, offsets2)
        return (units1, units2, [first, second])
    }

    @Test func trailingWhitespaceOnlyFragmentsAreTrimmedWhenIgnoringWhitespaces() {
        let (units1, units2, blocks) = fragments("x\ny\n", "z\n y\n")

        let trimmed = ComparisonManager.processBlocks(blocks, units1, units2, .ignoreWhitespaces, squash: false, trim: true)
        let squashed = ComparisonManager.processBlocks(blocks, units1, units2, .ignoreWhitespaces, squash: true, trim: true)

        #expect(trimmed == [blocks[0]])
        #expect(squashed == [blocks[0]])
    }

    @Test func leadingWhitespaceOnlyFragmentsAreTrimmedToo() {
        let (units1, units2, blocks) = fragments("y\nx\n", " y\nz\n")

        let trimmed = ComparisonManager.processBlocks(blocks, units1, units2, .ignoreWhitespaces, squash: false, trim: true)

        #expect(trimmed == [blocks[1]])
    }

    @Test func groupOfOnlyInsignificantFragmentsDisappears() {
        let (units1, units2, blocks) = fragments("y\ny\n", " y\n y\n")

        let trimmed = ComparisonManager.processBlocks(blocks, units1, units2, .ignoreWhitespaces, squash: false, trim: true)

        #expect(trimmed.isEmpty)
    }

    @Test func squashingMergesAdjoiningFragmentsIntoOne() throws {
        let (_, _, blocks) = fragments("x\ny\n", "z\n y\n")

        let squashed = ComparisonManager.squash(blocks)

        let merged = try #require(squashed.first)
        #expect(squashed.count == 1)
        #expect(merged.startLine1 == 0)
        #expect(merged.endLine1 == 2)
        #expect(merged.endOffset2 == 5)
    }

    @Test func squashingNothingYieldsNothing() {
        #expect(ComparisonManager.squash([]).isEmpty)
    }

    @Test func processingWithoutSquashOrTrimReturnsTheFragmentsUntouched() {
        let (units1, units2, blocks) = fragments("x\ny\n", "z\n y\n")

        #expect(ComparisonManager.processBlocks(blocks, units1, units2, .default, squash: false, trim: false) == blocks)
        #expect(ComparisonManager.processBlocks([], units1, units2, .default, squash: true, trim: true).isEmpty)
    }
}

@Suite struct ComparisonManagerIgnoredRangesCoverageTests {
    @Test func equalLinesWhoseWordsDifferBeyondTheIgnoredRangeStayDifferent() throws {
        let fragments = try ignoredRangeFragments("ba", "a", ignoredBefore: [0..<1], ignoredAfter: [], .words)

        #expect(fragments.count == 1)
        #expect(fragments.first.map { DiffRange($0.startLine1, $0.endLine1, $0.startLine2, $0.endLine2) } == DiffRange(0, 1, 0, 1))
        #expect(fragments.first?.innerFragments == nil)
    }

    @Test func withoutInnerFragmentsTheSameLineIsReported() throws {
        let fragments = try ignoredRangeFragments("ba", "a", ignoredBefore: [0..<1], ignoredAfter: [], .none)

        #expect(fragments.count == 1)
        #expect(fragments.first?.innerFragments == nil)
    }

    @Test func charDifferencesInsideTheIgnoredRangeAreDropped() throws {
        let fragments = try ignoredRangeFragments("ba", "a", ignoredBefore: [0..<1], ignoredAfter: [], .chars)

        #expect(fragments.isEmpty)
    }
}
