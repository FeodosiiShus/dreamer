import Testing
import Foundation
@testable import Dreamder

private func optimizedWordRanges(_ before: String, _ after: String, unchanged: [DiffRange]) throws -> [DiffRange] {
    let units1 = Array(before.utf16)
    let units2 = Array(after.utf16)
    let words1 = ByWord.inlineChunks(units1).filter { !$0.isNewline }
    let words2 = ByWord.inlineChunks(units2).filter { !$0.isNewline }
    let changes = DiffChanges(unchanged: unchanged, length1: words1.count, length2: words2.count)
    return try ChunkOptimizer.optimizeWords(words1, words2, text1: units1, text2: units2, changes).unchanged
}

@Suite struct ChunkOptimizerCoverageTests {
    @Test func insertedWordsNotSeparatedByWhitespaceStayWhereTheyAre() throws {
        let unchanged = [DiffRange(0, 1, 0, 1), DiffRange(1, 3, 3, 5)]

        let result = try optimizedWordRanges("p.q.r", "p.q.x.q.r", unchanged: unchanged)

        #expect(result == unchanged)
    }

    @Test func insertedWordsSlideForwardToTheNearestWhitespaceBoundary() throws {
        let result = try optimizedWordRanges(
            "p.q r",
            "p.q x.q r",
            unchanged: [DiffRange(0, 1, 0, 1), DiffRange(1, 3, 3, 5)]
        )

        #expect(result == [DiffRange(0, 2, 0, 2), DiffRange(2, 3, 4, 5)])
    }

    @Test func insertedWordsSlideBackwardToTheNearestWhitespaceBoundary() throws {
        let result = try optimizedWordRanges(
            "p q.r",
            "p q.x q.r",
            unchanged: [DiffRange(0, 2, 0, 2), DiffRange(2, 3, 4, 5)]
        )

        #expect(result == [DiffRange(0, 1, 0, 1), DiffRange(1, 3, 3, 5)])
    }

    @Test func linesWithoutAnyUnimportantNeighbourKeepTheDiffChosenByTheSequenceDiff() throws {
        let ranges = try ComparisonManager.compareLineRanges(
            ["efgh", "abcd", "abcd", "efgh"],
            ["efgh", "abcd", "efgh", ""]
        )

        #expect(ranges == [DiffRange(2, 3, 2, 2), DiffRange(4, 4, 3, 4)])
    }

    @Test func aNewlineBetweenWordsCountsAsSeparatingWhitespace() throws {
        let units1 = Array("p\nq".utf16)
        let units2 = Array("p\nx\nq".utf16)
        let words1 = ByWord.inlineChunks(units1)
        let words2 = ByWord.inlineChunks(units2)
        let unchanged = [DiffRange(0, 1, 0, 1), DiffRange(1, 3, 3, 5)]
        let changes = DiffChanges(unchanged: unchanged, length1: words1.count, length2: words2.count)

        let result = try ChunkOptimizer.optimizeWords(words1, words2, text1: units1, text2: units2, changes)

        #expect(words1.map(\.isNewline) == [false, true, false])
        #expect(result.unchanged == unchanged)
    }
}
