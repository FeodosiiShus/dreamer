import Foundation
import Testing
@testable import Dreamder

@Suite
struct PartialCommitPatchBuilderTests {
    private static let modifiedHeader = "diff --git a/f.txt b/f.txt\n--- a/f.txt\n+++ b/f.txt\n"

    private func header(_ oldStart: Int, _ oldCount: Int, _ newStart: Int, _ newCount: Int) -> GitDiffParser.Hunk {
        GitDiffParser.Hunk(oldStart: oldStart, oldCount: oldCount, newStart: newStart, newCount: newCount)
    }

    private func numbered(_ range: ClosedRange<Int>, replacing replacements: [Int: String] = [:]) -> String {
        range.map { "\(replacements[$0] ?? "l\($0)")\n" }.joined()
    }

    private func patch(
        _ head: String,
        _ worktree: String,
        _ headers: [GitDiffParser.Hunk],
        select: [Int]? = nil,
        kind: PartialCommitPatchBuilder.Kind = .modified,
        mode: String = "100644",
        path: String = "f.txt"
    ) -> String? {
        let headData = Data(head.utf8)
        let worktreeData = Data(worktree.utf8)
        let hunks = PartialCommitPatchBuilder.hunks(from: headers, head: headData, worktree: worktreeData)
        let selected = select.map { Set($0.map { hunks[$0].id }) } ?? Set(hunks.map(\.id))
        return PartialCommitPatchBuilder.patch(
            path: path,
            kind: kind,
            mode: mode,
            head: headData,
            worktree: worktreeData,
            hunks: hunks,
            selected: selected
        ).map { String(decoding: $0, as: UTF8.self) }
    }

    @Test
    func aSingleHunkPatchCarriesFullHeadersAndThreeLinesOfContext() {
        let result = patch("a\nb\nc\nd\ne\n", "a\nB\nc\nd\ne\n", [header(2, 1, 2, 1)])
        #expect(result == Self.modifiedHeader + "@@ -1,5 +1,5 @@\n a\n-b\n+B\n c\n d\n e\n")
    }

    @Test
    func aOneLineFileUsesGitsShortRangeForm() {
        #expect(patch("a\n", "b\n", [header(1, 1, 1, 1)]) == Self.modifiedHeader + "@@ -1 +1 @@\n-a\n+b\n")
    }

    @Test
    func deselectingTheFirstMiddleOrLastOfThreeSeparatedHunksDropsOnlyThatHunk() {
        let head = numbered(1...20)
        let worktree = numbered(1...20, replacing: [2: "L2", 10: "L10", 19: "L19"])
        let headers = [header(2, 1, 2, 1), header(10, 1, 10, 1), header(19, 1, 19, 1)]
        let first = "@@ -1,5 +1,5 @@\n l1\n-l2\n+L2\n l3\n l4\n l5\n"
        let middle = "@@ -7,7 +7,7 @@\n l7\n l8\n l9\n-l10\n+L10\n l11\n l12\n l13\n"
        let last = "@@ -16,5 +16,5 @@\n l16\n l17\n l18\n-l19\n+L19\n l20\n"
        let cases: [(selection: [Int]?, expected: String)] = [
            (nil, first + middle + last),
            ([1, 2], middle + last),
            ([0, 2], first + last),
            ([0, 1], first + middle),
            ([0], first),
            ([1], middle),
            ([2], last)
        ]
        for testCase in cases {
            #expect(
                patch(head, worktree, headers, select: testCase.selection)
                    == Self.modifiedHeader + testCase.expected,
                "selection \(String(describing: testCase.selection))"
            )
        }
    }

    @Test
    func deselectedEarlierHunksShiftTheNewSideStartOfLaterHunks() {
        let head = numbered(1...20)
        let worktreeLines = ["l1", "l2", "x1", "x2"]
            + (3...9).map { "l\($0)" }
            + (11...18).map { "l\($0)" }
            + ["y1", "y2", "y3", "l20"]
        let worktree = worktreeLines.map { $0 + "\n" }.joined()
        let headers = [header(2, 0, 3, 2), header(10, 1, 11, 0), header(19, 1, 20, 3)]

        func inserted() -> String { "@@ -1,5 +1,7 @@\n l1\n l2\n+x1\n+x2\n l3\n l4\n l5\n" }
        func deleted(_ newStart: Int) -> String {
            "@@ -7,7 +\(newStart),6 @@\n l7\n l8\n l9\n-l10\n l11\n l12\n l13\n"
        }
        func replaced(_ newStart: Int) -> String {
            "@@ -16,5 +\(newStart),7 @@\n l16\n l17\n l18\n-l19\n+y1\n+y2\n+y3\n l20\n"
        }
        let cases: [(selection: [Int]?, expected: String)] = [
            (nil, inserted() + deleted(9) + replaced(17)),
            ([1, 2], deleted(7) + replaced(15)),
            ([0, 2], inserted() + replaced(18)),
            ([0, 1], inserted() + deleted(9)),
            ([2], replaced(16)),
            ([1], deleted(7)),
            ([0], inserted())
        ]
        for testCase in cases {
            #expect(
                patch(head, worktree, headers, select: testCase.selection)
                    == Self.modifiedHeader + testCase.expected,
                "selection \(String(describing: testCase.selection))"
            )
        }
    }

    @Test
    func closeHunksShareOneUnifiedHunkAndContextComesFromTheIndexSide() {
        let head = numbered(1...10)
        let worktree = numbered(1...10, replacing: [3: "L3", 6: "L6"])
        let headers = [header(3, 1, 3, 1), header(6, 1, 6, 1)]

        #expect(
            patch(head, worktree, headers)
                == Self.modifiedHeader
                + "@@ -1,9 +1,9 @@\n l1\n l2\n-l3\n+L3\n l4\n l5\n-l6\n+L6\n l7\n l8\n l9\n"
        )
        #expect(
            patch(head, worktree, headers, select: [0])
                == Self.modifiedHeader + "@@ -1,6 +1,6 @@\n l1\n l2\n-l3\n+L3\n l4\n l5\n l6\n"
        )
        #expect(
            patch(head, worktree, headers, select: [1])
                == Self.modifiedHeader + "@@ -3,7 +3,7 @@\n l3\n l4\n l5\n-l6\n+L6\n l7\n l8\n l9\n"
        )
    }

    @Test
    func hunksSixUnchangedLinesApartMergeAndSevenApartStaySeparate() {
        let head = numbered(1...12)
        let merged = patch(
            head,
            numbered(1...12, replacing: [2: "L2", 9: "L9"]),
            [header(2, 1, 2, 1), header(9, 1, 9, 1)]
        )
        #expect(
            merged == Self.modifiedHeader
                + "@@ -1,12 +1,12 @@\n l1\n-l2\n+L2\n l3\n l4\n l5\n l6\n l7\n l8\n-l9\n+L9\n l10\n l11\n l12\n"
        )

        let separate = patch(
            numbered(1...13),
            numbered(1...13, replacing: [2: "L2", 10: "L10"]),
            [header(2, 1, 2, 1), header(10, 1, 10, 1)]
        )
        #expect(
            separate == Self.modifiedHeader
                + "@@ -1,5 +1,5 @@\n l1\n-l2\n+L2\n l3\n l4\n l5\n"
                + "@@ -7,7 +7,7 @@\n l7\n l8\n l9\n-l10\n+L10\n l11\n l12\n l13\n"
        )
    }

    @Test
    func missingTrailingNewlinesAreMarkedOnEverySideTheyOccur() {
        #expect(
            patch("a\nb\nc", "A\nb\nc", [header(1, 1, 1, 1)])
                == Self.modifiedHeader + "@@ -1,3 +1,3 @@\n-a\n+A\n b\n c\n\\ No newline at end of file\n"
        )
        #expect(
            patch("a\nb\n", "a\nb\nc", [header(2, 0, 3, 1)])
                == Self.modifiedHeader + "@@ -1,2 +1,3 @@\n a\n b\n+c\n\\ No newline at end of file\n"
        )
        #expect(
            patch("a\nb", "a\nb\n", [header(2, 1, 2, 1)])
                == Self.modifiedHeader + "@@ -1,2 +1,2 @@\n a\n-b\n\\ No newline at end of file\n+b\n"
        )
        #expect(
            patch("a\nb\n", "a\nb", [header(2, 1, 2, 1)])
                == Self.modifiedHeader + "@@ -1,2 +1,2 @@\n a\n-b\n+b\n\\ No newline at end of file\n"
        )
    }

    @Test
    func theUnterminatedLastLineIsMarkedAsContextOnlyWhenTheHunkIsSelected() {
        let head = "a\nb\nc\nd\ne\nf\ng\nh\ni"
        let worktree = "A\nb\nc\nd\ne\nf\ng\nh\nI"
        let headers = [header(1, 1, 1, 1), header(9, 1, 9, 1)]

        #expect(
            patch(head, worktree, headers, select: [0])
                == Self.modifiedHeader + "@@ -1,4 +1,4 @@\n-a\n+A\n b\n c\n d\n"
        )
        #expect(
            patch(head, worktree, headers, select: [1])
                == Self.modifiedHeader
                + "@@ -6,4 +6,4 @@\n f\n g\n h\n-i\n\\ No newline at end of file\n+I\n\\ No newline at end of file\n"
        )
    }

    @Test
    func carriageReturnsStayPartOfEveryLine() {
        let result = patch("a\r\nb\r\nc\r\n", "a\r\nB\r\nc\r\n", [header(2, 1, 2, 1)])
        #expect(
            result.map { Data($0.utf8) }
                == Data((Self.modifiedHeader + "@@ -1,3 +1,3 @@\n a\r\n-b\r\n+B\r\n c\r\n").utf8)
        )
    }

    @Test
    func anEmptyIndexFileTakesPureInsertions() {
        #expect(patch("", "a\nb\n", [header(0, 0, 1, 2)]) == Self.modifiedHeader + "@@ -0,0 +1,2 @@\n+a\n+b\n")
    }

    @Test
    func newFilesAndDeletedFilesCarryTheirModeAndNullSide() {
        #expect(
            patch("", "x\ny\n", [header(0, 0, 1, 2)], kind: .added, path: "n.txt")
                == "diff --git a/n.txt b/n.txt\nnew file mode 100644\n--- /dev/null\n+++ b/n.txt\n@@ -0,0 +1,2 @@\n+x\n+y\n"
        )
        #expect(
            patch("x\ny\n", "", [header(1, 2, 0, 0)], kind: .deleted, mode: "100755", path: "d.txt")
                == "diff --git a/d.txt b/d.txt\ndeleted file mode 100755\n--- a/d.txt\n+++ /dev/null\n@@ -1,2 +0,0 @@\n-x\n-y\n"
        )
    }

    @Test
    func noSelectedHunkMeansNoPatch() {
        let head = "a\nb\n"
        let worktree = "A\nb\n"
        let headers = [header(1, 1, 1, 1)]
        let hunks = PartialCommitPatchBuilder.hunks(from: headers, head: Data(head.utf8), worktree: Data(worktree.utf8))

        #expect(patch(head, worktree, headers, select: []) == nil)
        #expect(patch(head, worktree, []) == nil)
        #expect(
            PartialCommitPatchBuilder.patch(
                path: "f.txt",
                head: Data(head.utf8),
                worktree: Data(worktree.utf8),
                hunks: hunks,
                selected: ["unknown"]
            ) == nil
        )
    }

    @Test
    func pathsThatNeedQuotingAreCQuotedLikeGit() {
        #expect(PartialCommitPatchBuilder.quoted("dir/a b.txt") == "dir/a b.txt")
        #expect(PartialCommitPatchBuilder.quoted("é.txt") == "é.txt")
        #expect(PartialCommitPatchBuilder.quoted("a\u{7F}") == #""a\177""#)
        let result = patch("a\n", "b\n", [header(1, 1, 1, 1)], path: "q\"\\\t\n\u{1}é")
        #expect(
            result?.hasPrefix(
                #"diff --git "a/q\"\\\t\n\001é" "b/q\"\\\t\n\001é""# + "\n"
                    + #"--- "a/q\"\\\t\n\001é""# + "\n"
                    + #"+++ "b/q\"\\\t\n\001é""# + "\n@@ -1 +1 @@\n"
            ) == true
        )
    }

    @Test
    func hunkRangeTitlesFollowGitsHeaderForm() {
        let head = Data("a\nb\nc\n".utf8)
        let worktree = Data("a\nB\nc\nx\ny\n".utf8)
        let hunks = PartialCommitPatchBuilder.hunks(
            from: [header(2, 1, 2, 1), header(3, 0, 4, 2), header(3, 1, 3, 0)],
            head: head,
            worktree: worktree
        )

        #expect(hunks.map(\.rangeTitle) == ["-2 +2", "-3,0 +4,2", "-3 +3,0"])
    }

    @Test
    func previewsShowTheFirstChangedLineTrimmedAndTruncated() {
        let long = String(repeating: "x", count: 100)
        let head = Data("keep\nold line\n\nlast\n".utf8)
        let worktree = Data("keep\n  \tindented\t\r\nnext\n\n\(long)\n".utf8)
        let hunks = PartialCommitPatchBuilder.hunks(
            from: [header(2, 1, 2, 2), header(3, 1, 4, 0), header(4, 1, 5, 1)],
            head: head,
            worktree: worktree
        )

        #expect(hunks.map(\.preview) == ["indented", "", String(repeating: "x", count: 80)])
        let deletion = PartialCommitPatchBuilder.hunks(
            from: [header(1, 1, 0, 0)],
            head: Data("  gone  \n".utf8),
            worktree: Data()
        )
        #expect(deletion.map(\.preview) == ["gone"])
    }

    @Test
    func headersThatDoNotMatchTheTextsAreDropped() {
        let hunks = PartialCommitPatchBuilder.hunks(
            from: [
                header(1, 1, 1, 1),
                header(0, 1, 1, 1),
                header(1, 0, 1, 0),
                header(5, 1, 1, 1),
                header(1, 1, 5, 1),
                header(1, 1, 1, 3),
                header(1, 1, 0, 1)
            ],
            head: Data("a\n".utf8),
            worktree: Data("b\n".utf8)
        )

        #expect(hunks.map(\.rangeTitle) == ["-1 +1"])
    }

    @Test
    func splittingTextIntoLinesTracksTheFinalNewline() {
        let empty = PartialCommitLines(Data())
        #expect(empty.lines.isEmpty)
        #expect(empty.endsWithNewline)
        #expect(empty.isUnterminated(0) == false)

        let blank = PartialCommitLines(Data("\n".utf8))
        #expect(blank.lines.map { Array($0) } == [[]])
        #expect(blank.endsWithNewline)

        let unterminated = PartialCommitLines(Data("a\nb".utf8))
        #expect(unterminated.lines.map { String(decoding: $0, as: UTF8.self) } == ["a", "b"])
        #expect(unterminated.endsWithNewline == false)
        #expect(unterminated.isUnterminated(0) == false)
        #expect(unterminated.isUnterminated(1))
    }

    @Test
    func diffParserReadsHunkHeadersOfCRLFContentWithoutLosingAny() {
        let diff = "diff --git a/f b/f\nindex 1..2 100644\n--- a/f\n+++ b/f\n"
            + "@@ -1,2 +1,2 @@\n-a\r\n+A\r\n b\r\n@@ -5 +5 @@\n-x\n+y\n"

        #expect(PartialCommitDiffParser.hunks(inDiff: diff) == [header(1, 2, 1, 2), header(5, 1, 5, 1)])
        #expect(PartialCommitDiffParser.hunks(inDiff: "").isEmpty)
    }

    @Test
    func diffParserTreatsModeRenameAndBinaryChangesAsWholeFileOnly() {
        let hunkBody = "--- a/f\n+++ b/f\n@@ -1 +1 @@\n-a\n+b\n"
        let markers = [
            "old mode 100644\nnew mode 100755\n",
            "new file mode 100644\n",
            "deleted file mode 100644\n",
            "similarity index 90%\nrename from f\nrename to g\n",
            "copy from f\ncopy to g\n",
            "dissimilarity index 10%\n",
            "Binary files a/f and b/f differ\n",
            "GIT binary patch\nliteral 0\n"
        ]
        for marker in markers {
            #expect(PartialCommitDiffParser.hunks(inDiff: "diff --git a/f b/f\n" + marker + hunkBody).isEmpty, "\(marker)")
        }
        #expect(PartialCommitDiffParser.hunks(inDiff: "diff --git a/f b/f\nBinary files a/f and b/f differ\n").isEmpty)
        #expect(PartialCommitDiffParser.hunks(inDiff: "diff --git a/f b/f\n" + hunkBody).count == 1)
        #expect(
            PartialCommitDiffParser.hunks(inDiff: "diff --git a/f b/f\n" + hunkBody + "+Binary files are fine\n").count == 1
        )
    }
}
