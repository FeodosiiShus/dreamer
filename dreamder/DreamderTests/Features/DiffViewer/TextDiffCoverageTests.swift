import Foundation
import Testing
@testable import Dreamder

@Suite
struct TextDiffCoverageTests {
    private static let bound = 12_000

    private static func alternatingBlocks(first: String, second: String) -> [String] {
        [String](repeating: first, count: bound) + [String](repeating: second, count: bound)
    }

    @Test(.timeLimit(.minutes(2)))
    func computeFallsBackToOneCoarseHunkWhenTheEngineGivesUp() throws {
        let left = Self.alternatingBlocks(first: "alpha line payload", second: "omega line payload")
        let right = Self.alternatingBlocks(first: "omega line payload", second: "alpha line payload")

        let diff = try TextDiff.compute(leftLines: left, rightLines: right)

        let hunk = try #require(diff.hunks.first)
        #expect(diff.differenceCount == 1)
        #expect(hunk.kind == .modified)
        #expect(hunk.leftLines == 0..<left.count)
        #expect(hunk.rightLines == 0..<right.count)
        #expect(diff.rows.count == left.count)
    }

    @Test(.timeLimit(.minutes(2)))
    func nonThrowingInitFallsBackToOneCoarseHunkWhenTheEngineGivesUp() {
        let left = Self.alternatingBlocks(first: "alpha line payload", second: "omega line payload")
        let right = Self.alternatingBlocks(first: "omega line payload", second: "alpha line payload")

        let diff = TextDiff(leftLines: left, rightLines: right)

        #expect(diff.differenceCount == 1)
        #expect(diff.hunks.first?.rows == 0..<left.count)
    }

    @Test(.timeLimit(.minutes(2)))
    func coarseFallbackKeepsTheCommonPrefixAndSuffix() throws {
        let head = "shared head line"
        let tail = "shared tail line"
        let left = [head] + Self.alternatingBlocks(first: "alpha line payload", second: "omega line payload") + [tail]
        let right = [head] + Self.alternatingBlocks(first: "omega line payload", second: "alpha line payload") + [tail]

        let diff = try TextDiff.compute(leftLines: left, rightLines: right)

        let hunk = try #require(diff.hunks.first)
        #expect(diff.differenceCount == 1)
        #expect(hunk.leftLines == 1..<(left.count - 1))
        #expect(hunk.rightLines == 1..<(right.count - 1))
        #expect(diff.rows.first?.kind == .context)
        #expect(diff.rows.last?.kind == .context)
    }
}
