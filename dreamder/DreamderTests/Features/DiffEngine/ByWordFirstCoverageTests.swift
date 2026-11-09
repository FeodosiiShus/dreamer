import Testing
import Foundation
@testable import Dreamder

struct WordFirstExpectedBlock: Sendable, Equatable {
    let lines: DiffRange
    let inner: [DiffFragment]?

    init(_ lines: DiffRange, _ inner: [DiffFragment]? = nil) {
        self.lines = lines
        self.inner = inner
    }
}

struct WordFirstCase: Sendable, CustomTestStringConvertible {
    let before: String
    let after: String
    let policy: ComparisonPolicy
    let expected: [WordFirstExpectedBlock]

    init(_ before: String, _ after: String, _ policy: ComparisonPolicy, _ expected: [WordFirstExpectedBlock]) {
        self.before = before
        self.after = after
        self.policy = policy
        self.expected = expected
    }

    var testDescription: String { "\(before.debugDescription) vs \(after.debugDescription) [\(policy)]" }
}

private func wordFirstBlocks(_ before: String, _ after: String, _ policy: ComparisonPolicy) throws -> [WordFirstExpectedBlock] {
    let units1 = Array(DiffEngineTestSupport.source(before).utf16)
    let units2 = Array(DiffEngineTestSupport.source(after).utf16)
    let fragments = try ComparisonManager.compareLinesWordFirst(
        units1,
        units2,
        LineOffsets(text: units1),
        LineOffsets(text: units2),
        policy
    )
    return fragments.map {
        WordFirstExpectedBlock(DiffRange($0.startLine1, $0.endLine1, $0.startLine2, $0.endLine2), $0.innerFragments)
    }
}

private func block(_ range: DiffRange, _ inner: DiffFragment? = nil) -> WordFirstExpectedBlock {
    WordFirstExpectedBlock(range, inner.map { [$0] })
}

private let allPolicies: [ComparisonPolicy] = [.default, .trimWhitespaces, .ignoreWhitespaces]

@Suite struct ByWordFirstCoverageTests {
    @Test(arguments: [
        WordFirstCase("a a", "a a", .default, []),
        WordFirstCase("a a", "a a", .trimWhitespaces, []),
        WordFirstCase("a a", "a a", .ignoreWhitespaces, []),
        WordFirstCase("a", "a a", .default, [block(DiffRange(0, 1, 0, 1), DiffFragment(1, 1, 1, 3))]),
        WordFirstCase("a", "a a", .trimWhitespaces, [block(DiffRange(0, 1, 0, 1), DiffFragment(1, 1, 1, 3))]),
        WordFirstCase("a", "a a", .ignoreWhitespaces, [block(DiffRange(0, 1, 0, 1), DiffFragment(1, 1, 2, 3))]),
        WordFirstCase("a a", "a", .default, [block(DiffRange(0, 1, 0, 1), DiffFragment(1, 3, 1, 1))]),
        WordFirstCase("a a", "a", .trimWhitespaces, [block(DiffRange(0, 1, 0, 1), DiffFragment(1, 3, 1, 1))]),
        WordFirstCase("a a", "a", .ignoreWhitespaces, [block(DiffRange(0, 1, 0, 1), DiffFragment(2, 3, 1, 1))]),
        WordFirstCase("a", "b a", .default, [block(DiffRange(0, 1, 0, 1), DiffFragment(0, 0, 0, 2))]),
        WordFirstCase("a", "b a", .trimWhitespaces, [block(DiffRange(0, 1, 0, 1), DiffFragment(0, 0, 0, 2))]),
        WordFirstCase("a", "b a", .ignoreWhitespaces, [block(DiffRange(0, 1, 0, 1), DiffFragment(0, 0, 0, 1))])
    ])
    func singleLineChangesCarryTheirInnerFragments(_ testCase: WordFirstCase) throws {
        #expect(try wordFirstBlocks(testCase.before, testCase.after, testCase.policy) == testCase.expected)
    }

    @Test(arguments: [
        WordFirstCase("_", "", .default, [block(DiffRange(0, 2, 0, 1))]),
        WordFirstCase("_", "", .trimWhitespaces, []),
        WordFirstCase("_", "", .ignoreWhitespaces, []),
        WordFirstCase("", "_", .default, [block(DiffRange(0, 1, 0, 2))]),
        WordFirstCase("", "_", .trimWhitespaces, []),
        WordFirstCase("", "_", .ignoreWhitespaces, []),
        WordFirstCase("", "a ", .default, [block(DiffRange(0, 0, 0, 1))]),
        WordFirstCase("", "a ", .trimWhitespaces, [block(DiffRange(0, 0, 0, 1), DiffFragment(0, 0, 0, 1))]),
        WordFirstCase("", "a ", .ignoreWhitespaces, [block(DiffRange(0, 0, 0, 1), DiffFragment(0, 0, 0, 1))]),
        WordFirstCase("", " _a", .default, [block(DiffRange(0, 1, 0, 1)), block(DiffRange(1, 1, 1, 2))]),
        WordFirstCase("", " _a", .trimWhitespaces, [block(DiffRange(1, 1, 1, 2))]),
        WordFirstCase("", " _a", .ignoreWhitespaces, [block(DiffRange(1, 1, 1, 2))])
    ])
    func blankLinesAndTrailingWhitespaceMoveTheBlockBoundaries(_ testCase: WordFirstCase) throws {
        #expect(try wordFirstBlocks(testCase.before, testCase.after, testCase.policy) == testCase.expected)
    }

    @Test(arguments: allPolicies)
    func aTrailingNewlineAloneIsNotABlock(_ policy: ComparisonPolicy) throws {
        #expect(try wordFirstBlocks("a_", "a", policy).isEmpty)
        #expect(try wordFirstBlocks("a", "a_", policy).isEmpty)
    }

    @Test func aTrailingNewlineIsNotAddedToABlockWhoseOtherSideIsDifferent() throws {
        #expect(try wordFirstBlocks("a_", "b", .default) == [block(DiffRange(0, 1, 0, 1))])
        #expect(
            try wordFirstBlocks("a_", "b", .trimWhitespaces) == [block(DiffRange(0, 1, 0, 1), DiffFragment(0, 1, 0, 1))]
        )
    }

    @Test func linesRangeOfAnEmptyRangePointsAtTheLineStartOrTheTextEnd() {
        let units = Array("ab\ncd".utf16)
        let offsets = LineOffsets(text: units)

        #expect(offsets.linesRange(1, 1, includeNewline: true) == (3, 3))
        #expect(offsets.linesRange(2, 2, includeNewline: true) == (5, 5))
    }

    @Test func linesRangeIncludesTheTrailingNewlineOnlyWhenAsked() {
        let units = Array("ab\ncd\n".utf16)
        let offsets = LineOffsets(text: units)

        #expect(offsets.linesRange(0, 1, includeNewline: true) == (0, 3))
        #expect(offsets.linesRange(0, 1, includeNewline: false) == (0, 2))
        #expect(offsets.linesRange(1, 3, includeNewline: true) == (3, 6))
    }
}
