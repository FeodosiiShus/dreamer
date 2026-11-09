import Testing
@testable import Dreamder

@Suite
struct ThreeWayMergeLineEndingTests {
    @Test
    func crlfFilesKeepTheirLineEndingsInTheResult() {
        let merge = ThreeWayMerge(
            base: "a\r\nb\r\nc\r\n",
            ours: "a\r\nB\r\nc\r\n",
            theirs: "a\r\nb\r\nc\r\n"
        )

        #expect(merge.lineEnding == .crlf)
        #expect(merge.resultLines == ["a", "B", "c"])
        #expect(merge.resultText == "a\r\nB\r\nc\r\n")
    }

    @Test
    func carriageReturnOnlyFilesKeepTheirLineEndingsInTheResult() {
        let merge = ThreeWayMerge(
            base: "one\rtwo\rthree\rfour\r",
            ours: "one\rTWO\rthree\rfour\r",
            theirs: "one\rtwo\rthree\rFOUR\r"
        )

        #expect(merge.lineEnding == .carriageReturn)
        #expect(merge.conflictCount == 0)
        #expect(merge.resultText == "one\rTWO\rthree\rFOUR\r")
    }

    @Test
    func lineFeedFilesStayLineFeedFiles() {
        let merge = ThreeWayMerge(base: "a\nb\n", ours: "a\nB\n", theirs: "a\nb\n")

        #expect(merge.lineEnding == .lineFeed)
        #expect(merge.resultText == "a\nB\n")
    }

    @Test
    func theOursSideDecidesTheEndingBeforeBaseAndTheirs() {
        #expect(ThreeWayMerge(base: "a\n", ours: "a\r\n", theirs: "a\r").lineEnding == .crlf)
        #expect(ThreeWayMerge(base: "a\r\n", ours: "a", theirs: "a\r").lineEnding == .crlf)
        #expect(ThreeWayMerge(base: "a", ours: "a", theirs: "a\r").lineEnding == .carriageReturn)
        #expect(ThreeWayMerge(base: "a", ours: "a", theirs: "a").lineEnding == .lineFeed)
    }

    @Test
    func resolvedConflictsAreWrittenWithTheFilesLineEnding() {
        var merge = ThreeWayMerge(
            base: "a\r\nb\r\nc\r\n",
            ours: "a\r\nL\r\nc\r\n",
            theirs: "a\r\nR\r\nc\r\n"
        )
        let conflict = merge.blocks.first { $0.kind == .conflict }

        merge.resolve(conflict?.id ?? -1, with: .right)

        #expect(conflict != nil)
        #expect(merge.resultText == "a\r\nR\r\nc\r\n")
    }

    @Test(arguments: [
        ("a\nb\n", "a\nB", "a\nb\n", "a\nB"),
        ("a\nb\n", "a\nb\n", "a\nB", "a\nB"),
        ("a\nb", "a\nB\n", "a\nb", "a\nB\n"),
        ("a\nb", "a\nb", "a\nB\n", "a\nB\n"),
        ("a\nb\n", "a\nb", "a\nB", "a\nB"),
        ("a\r\nb\r\n", "a\r\nB", "a\r\nb\r\n", "a\r\nB"),
        ("a\r\nb\r\n", "a\r\nb\r\n", "a\r\nB\r\n", "a\r\nB\r\n")
    ])
    func theFinalLineBreakFollowsTheSideThatChangedIt(base: String, ours: String, theirs: String, expected: String) {
        #expect(ThreeWayMerge(base: base, ours: ours, theirs: theirs).resultText == expected)
    }

    @Test
    func aFileThatIsOneBlankLineKeepsItsLineBreak() {
        #expect(ThreeWayMerge(base: "\n", ours: "\n", theirs: "\n").resultText == "\n")
        #expect(ThreeWayMerge(base: "\r\n", ours: "\r\n", theirs: "\r\n").resultText == "\r\n")
        #expect(ThreeWayMerge(base: "", ours: "", theirs: "").resultText.isEmpty)
    }

    @Test
    func aDeletedOnlyLineDoesNotLeaveAStrayLineBreak() {
        let merge = ThreeWayMerge(base: "a", ours: "", theirs: "a\n")

        #expect(merge.hasTrailingNewline)
        #expect(merge.resultLines.isEmpty)
        #expect(merge.resultText.isEmpty)
    }

    @Test
    func aSideWithoutAnyTextNeverRemovesTheFinalLineBreak() {
        var oursDeleted = ThreeWayMerge(base: "y\n", ours: "", theirs: "z\n")
        oursDeleted.resolve(0, with: .right)
        #expect(oursDeleted.blocks.count == 1)
        #expect(oursDeleted.resultText == "z\n")

        var theirsDeleted = ThreeWayMerge(base: "y\n", ours: "z\n", theirs: "")
        theirsDeleted.resolve(0, with: .left)
        #expect(theirsDeleted.blocks.count == 1)
        #expect(theirsDeleted.resultText == "z\n")
    }
}
