import Foundation
import Testing
@testable import Dreamder

@Suite
struct TextDiffTests {
    @Test
    func detectsPureInsertion() throws {
        let diff = TextDiff(left: "a\nc\n", right: "a\nb\nc\n")

        #expect(diff.differenceCount == 1)
        let hunk = try #require(diff.hunks.first)
        #expect(hunk.kind == .inserted)
        #expect(hunk.leftLines.isEmpty)
        #expect(hunk.rightLines == 1..<2)
        #expect(diff.rows.map(\.kind) == [.context, .inserted, .context])
        #expect(diff.rows[1].leftLine == nil)
        #expect(diff.rows[1].rightLine == 1)
    }

    @Test
    func detectsPureDeletion() throws {
        let diff = TextDiff(left: "a\nb\nc\n", right: "a\nc\n")

        #expect(diff.differenceCount == 1)
        let hunk = try #require(diff.hunks.first)
        #expect(hunk.kind == .deleted)
        #expect(hunk.leftLines == 1..<2)
        #expect(hunk.rightLines.isEmpty)
        #expect(diff.rows.map(\.kind) == [.context, .deleted, .context])
        #expect(diff.rows[1].rightLine == nil)
    }

    @Test
    func groupsModificationAsSingleHunk() throws {
        let diff = TextDiff(left: "a\nb\nc\n", right: "a\nB\nc\n")

        #expect(diff.differenceCount == 1)
        let hunk = try #require(diff.hunks.first)
        #expect(hunk.kind == .modified)
        #expect(hunk.leftLines == 1..<2)
        #expect(hunk.rightLines == 1..<2)
        #expect(diff.rows.map(\.kind) == [.context, .modified, .context])
        #expect(diff.rows[1].leftLine == 1)
        #expect(diff.rows[1].rightLine == 1)
    }

    @Test
    func pairsUnevenModifiedBlocks() throws {
        let diff = TextDiff(left: "a\nb\nc\nd\n", right: "a\nX\nd\n")

        #expect(diff.differenceCount == 1)
        let hunk = try #require(diff.hunks.first)
        #expect(hunk.kind == .modified)
        #expect(hunk.leftLines == 1..<3)
        #expect(hunk.rightLines == 1..<2)
        #expect(diff.rows.map(\.kind) == [.context, .modified, .deleted, .context])
    }

    @Test
    func splitsDistantChangesIntoHunks() {
        let diff = TextDiff(left: "a\nb\nc\nd\ne\n", right: "a\nX\nc\nd\nY\n")

        #expect(diff.differenceCount == 2)
        #expect(diff.hunks.map(\.kind) == [.modified, .modified])
        #expect(diff.hunks[0].rows.lowerBound == 1)
        #expect(diff.hunks[1].rows.lowerBound == 4)
        #expect(diff.rows.count == 5)
    }

    @Test
    func identicalTextHasNoHunks() {
        let diff = TextDiff(left: "one\ntwo\n", right: "one\ntwo\n")

        #expect(diff.hunks.isEmpty)
        #expect(diff.differenceCount == 0)
        #expect(diff.rows.count == 2)
        #expect(diff.rows.allSatisfy { $0.kind == .context })
    }

    @Test
    func ignoresTrailingNewlineDifference() {
        #expect(TextDiff(left: "a\nb", right: "a\nb\n").hunks.isEmpty)
        #expect(TextDiff(left: "a\nb\n", right: "a\nb").hunks.isEmpty)
    }

    @Test
    func appendsNewTrailingLine() throws {
        let diff = TextDiff(left: "a\nb\n", right: "a\nb\nc\n")

        #expect(diff.differenceCount == 1)
        let hunk = try #require(diff.hunks.first)
        #expect(hunk.kind == .inserted)
        #expect(hunk.rightLines == 2..<3)
        #expect(diff.rows.last?.kind == .inserted)
        #expect(diff.rows.last?.rightLine == 2)
    }

    @Test
    func keepsTrailingEmptyLine() {
        #expect(TextDiff(left: "a\n", right: "a\n\n").differenceCount == 1)
    }

    @Test
    func detectsWhitespaceChangesByDefault() {
        let diff = TextDiff(left: "let x = 1\n", right: "let   x = 1\n")

        #expect(diff.differenceCount == 1)
    }

    @Test
    func ignoresWhitespaceWhenRequested() {
        let diff = TextDiff(
            left: "let x = 1\n",
            right: "let   x = 1\n",
            options: DiffOptions(ignoresWhitespace: true)
        )

        #expect(diff.hunks.isEmpty)
        #expect(diff.leftLines == ["let x = 1"])
        #expect(diff.rightLines == ["let   x = 1"])
    }

    @Test
    func splitsLinesWithoutTrailingNewline() {
        #expect(TextDiff.lines(in: "") == [])
        #expect(TextDiff.lines(in: "a") == ["a"])
        #expect(TextDiff.lines(in: "a\n") == ["a"])
        #expect(TextDiff.lines(in: "a\nb") == ["a", "b"])
        #expect(TextDiff.lines(in: "a\r\nb\r\n") == ["a", "b"])
        #expect(TextDiff.lines(in: "a\n\n") == ["a", ""])
    }

    @Test
    func optionsExposeIgnoreWhitespaceAsPolicy() {
        #expect(DiffOptions().policy == .default)
        #expect(DiffOptions(ignoresWhitespace: true).policy == .ignoreWhitespaces)
        #expect(DiffOptions(policy: .ignoreWhitespaces).ignoresWhitespace)
        #expect(DiffOptions(policy: .trimWhitespaces).ignoresWhitespace == false)

        var options = DiffOptions(policy: .trimWhitespaces)
        options.ignoresWhitespace = true
        #expect(options.policy == .ignoreWhitespaces)
        options.ignoresWhitespace = false
        #expect(options.policy == .default)
    }
}

@Suite
struct TextDiffEdgeCaseTests {
    @Test
    func emptySidesProduceWholeFileHunks() throws {
        let inserted = TextDiff(left: "", right: "a\nb\n")
        let insertedHunk = try #require(inserted.hunks.first)
        #expect(inserted.differenceCount == 1)
        #expect(insertedHunk.kind == .inserted)
        #expect(insertedHunk.leftLines.isEmpty)
        #expect(insertedHunk.rightLines == 0..<2)
        #expect(inserted.rows.map(\.kind) == [.inserted, .inserted])

        let deleted = TextDiff(left: "a\nb\n", right: "")
        let deletedHunk = try #require(deleted.hunks.first)
        #expect(deleted.differenceCount == 1)
        #expect(deletedHunk.kind == .deleted)
        #expect(deletedHunk.leftLines == 0..<2)
        #expect(deletedHunk.rightLines.isEmpty)
        #expect(deleted.rows.map(\.kind) == [.deleted, .deleted])

        let both = TextDiff(left: "", right: "")
        #expect(both.hunks.isEmpty)
        #expect(both.rows.isEmpty)
    }

    @Test
    func insertionAndDeletionAtTheStart() throws {
        let inserted = TextDiff(leftLines: ["b", "c"], rightLines: ["a", "b", "c"])
        let insertedHunk = try #require(inserted.hunks.first)
        #expect(inserted.differenceCount == 1)
        #expect(insertedHunk.kind == .inserted)
        #expect(insertedHunk.leftLines == 0..<0)
        #expect(insertedHunk.rightLines == 0..<1)
        #expect(inserted.rows.map(\.kind) == [.inserted, .context, .context])

        let deleted = TextDiff(leftLines: ["a", "b", "c"], rightLines: ["b", "c"])
        let deletedHunk = try #require(deleted.hunks.first)
        #expect(deleted.differenceCount == 1)
        #expect(deletedHunk.kind == .deleted)
        #expect(deletedHunk.leftLines == 0..<1)
        #expect(deletedHunk.rightLines == 0..<0)
        #expect(deleted.rows.map(\.kind) == [.deleted, .context, .context])
    }

    @Test
    func insertionAndDeletionAtTheEnd() throws {
        let inserted = TextDiff(leftLines: ["a", "b"], rightLines: ["a", "b", "c"])
        let insertedHunk = try #require(inserted.hunks.first)
        #expect(insertedHunk.kind == .inserted)
        #expect(insertedHunk.rightLines == 2..<3)
        #expect(inserted.rows.map(\.kind) == [.context, .context, .inserted])

        let deleted = TextDiff(leftLines: ["a", "b", "c"], rightLines: ["a", "b"])
        let deletedHunk = try #require(deleted.hunks.first)
        #expect(deletedHunk.kind == .deleted)
        #expect(deletedHunk.leftLines == 2..<3)
        #expect(deleted.rows.map(\.kind) == [.context, .context, .deleted])
    }

    @Test
    func trimPolicyIgnoresLeadingAndTrailingWhitespaceOnly() {
        let left = ["a", " b ", "c"]
        let right = ["a", "b", "c"]

        #expect(TextDiff(leftLines: left, rightLines: right, options: DiffOptions(policy: .default)).differenceCount == 1)
        #expect(TextDiff(leftLines: left, rightLines: right, options: DiffOptions(policy: .trimWhitespaces)).differenceCount == 0)
        #expect(TextDiff(leftLines: left, rightLines: right, options: DiffOptions(policy: .ignoreWhitespaces)).differenceCount == 0)
    }

    @Test
    func trimPolicyKeepsInnerWhitespaceChanges() {
        let left = ["x  y"]
        let right = ["x y"]

        #expect(TextDiff(leftLines: left, rightLines: right, options: DiffOptions(policy: .default)).differenceCount == 1)
        #expect(TextDiff(leftLines: left, rightLines: right, options: DiffOptions(policy: .trimWhitespaces)).differenceCount == 1)
        #expect(TextDiff(leftLines: left, rightLines: right, options: DiffOptions(policy: .ignoreWhitespaces)).differenceCount == 0)
    }

    @Test
    func whitespaceOnlyChangeKeepsLeftAndRightLinesVerbatim() {
        let diff = TextDiff(
            leftLines: ["a", "b"],
            rightLines: ["a", "  b"],
            options: DiffOptions(policy: .ignoreWhitespaces)
        )

        #expect(diff.hunks.isEmpty)
        #expect(diff.rightLines == ["a", "  b"])
        #expect(diff.rows.count == 2)
    }

    @Test(.timeLimit(.minutes(1)))
    func tenThousandLinesWithSparseEditsAreDiffedExactly() throws {
        let left = (0..<10_000).map { "line \($0) payload" }
        var right: [String] = []
        right.reserveCapacity(left.count + 1)
        for (index, line) in left.enumerated() {
            if index == 2000 { right.append("inserted") }
            if index == 5000 {
                right.append("changed")
                continue
            }
            if index == 7000 { continue }
            right.append(line)
        }

        let diff = try TextDiff.compute(leftLines: left, rightLines: right)

        #expect(diff.differenceCount == 3)
        #expect(diff.hunks.map(\.kind) == [.inserted, .modified, .deleted])
        #expect(diff.hunks[0].leftLines == 2000..<2000)
        #expect(diff.hunks[0].rightLines == 2000..<2001)
        #expect(diff.hunks[1].leftLines == 5000..<5001)
        #expect(diff.hunks[1].rightLines == 5001..<5002)
        #expect(diff.hunks[2].leftLines == 7000..<7001)
        #expect(diff.hunks[2].rightLines == 7001..<7001)
        #expect(diff.rows.count == 10_000 + 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func tenThousandIdenticalLinesProduceNoHunks() {
        let lines = (0..<10_000).map { "same \($0)" }
        let diff = TextDiff(leftLines: lines, rightLines: lines)

        #expect(diff.hunks.isEmpty)
        #expect(diff.rows.count == 10_000)
    }

    @Test
    func computeThrowsCancellationErrorForCancelledTask() async {
        let left = (0..<200).map { "left \($0)" }
        let right = (0..<200).map { "right \($0)" }
        let task = Task { () async throws -> TextDiff in
            while !Task.isCancelled { await Task.yield() }
            return try TextDiff.compute(leftLines: left, rightLines: right)
        }
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("expected CancellationError")
        } catch is CancellationError {
            return
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test
    func nonThrowingInitFallsBackToOneCoarseHunkWhenCancelled() async {
        let left = ["a", "b", "c", "d", "e"]
        let right = ["a", "X", "c", "d", "Y"]
        let task = Task { () async -> TextDiff in
            while !Task.isCancelled { await Task.yield() }
            return TextDiff(leftLines: left, rightLines: right)
        }
        task.cancel()

        let diff = await task.value
        #expect(diff.differenceCount == 1)
        #expect(diff.hunks.first?.leftLines == 1..<5)
        #expect(diff.hunks.first?.rightLines == 1..<5)
        #expect(diff.rows.count == 5)
    }
}

@Suite
struct TextDiffInnerFragmentTests {
    @Test
    func wordLevelInnerFragmentsMarkOnlyTheChangedWord() throws {
        let diff = TextDiff(left: "let x = 1\n", right: "let y = 1\n")
        let hunk = try #require(diff.hunks.first)

        let inner = try diff.innerFragments(for: hunk)

        #expect(inner.leftText == "let x = 1")
        #expect(inner.rightText == "let y = 1")
        #expect(inner.blocks.count == 1)
        #expect(inner.blocks.first?.innerFragments == [DiffFragment(4, 5, 4, 5)])
    }

    @Test
    func insertionHunkHasNoInnerFragments() throws {
        let diff = TextDiff(left: "a\nc\n", right: "a\nb\nc\n")
        let hunk = try #require(diff.hunks.first)

        let inner = try diff.innerFragments(for: hunk)

        #expect(inner.leftText.isEmpty)
        #expect(inner.rightText == "b")
        #expect(inner.blocks.count == 1)
        #expect(inner.blocks.first?.innerFragments == nil)
    }

    @Test
    func characterLevelFragmentsAreAvailable() throws {
        let diff = TextDiff(left: "abcd\n", right: "abxd\n")
        let hunk = try #require(diff.hunks.first)

        let inner = try diff.innerFragments(for: hunk, fragmentsPolicy: .chars)

        #expect(inner.blocks.first?.innerFragments == [DiffFragment(2, 3, 2, 3)])
    }
}
