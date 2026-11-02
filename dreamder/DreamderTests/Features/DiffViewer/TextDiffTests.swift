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
}
