import Foundation
import Testing
@testable import Dreamder

@Suite
struct PartialCommitHunkIdentityTests {
    private func header(_ oldStart: Int, _ oldCount: Int, _ newStart: Int, _ newCount: Int) -> GitDiffParser.Hunk {
        GitDiffParser.Hunk(oldStart: oldStart, oldCount: oldCount, newStart: newStart, newCount: newCount)
    }

    private func numbered(replacing replacements: [Int: String] = [:]) -> String {
        (1...20).map { "\(replacements[$0] ?? "l\($0)")\n" }.joined()
    }

    @Test
    func hunkIdentityIsTheOldSideRangeAndSurvivesEditsInsideTheHunk() throws {
        let head = numbered()
        let alone = PartialCommitPatchBuilder.hunks(
            from: [header(10, 1, 10, 1)],
            head: Data(head.utf8),
            worktree: Data(numbered(replacing: [10: "L10"]).utf8)
        )
        var shifted = (1...20).map { $0 == 10 ? "L10" : "l\($0)" }
        shifted.insert("z", at: 1)
        let afterInsertion = PartialCommitPatchBuilder.hunks(
            from: [header(10, 1, 11, 1)],
            head: Data(head.utf8),
            worktree: Data(shifted.map { $0 + "\n" }.joined().utf8)
        )
        let otherContent = PartialCommitPatchBuilder.hunks(
            from: [header(10, 1, 10, 1)],
            head: Data(head.utf8),
            worktree: Data(numbered(replacing: [10: "other"]).utf8)
        )
        let longer = PartialCommitPatchBuilder.hunks(
            from: [header(10, 1, 10, 2)],
            head: Data(head.utf8),
            worktree: Data(numbered(replacing: [10: "other\nmore"]).utf8)
        )

        #expect(alone.count == 1)
        #expect(alone.map(\.id) == ["10,1"])
        #expect(afterInsertion.map(\.id) == alone.map(\.id))
        #expect(otherContent.map(\.id) == alone.map(\.id))
        #expect(longer.map(\.id) == alone.map(\.id))
        #expect(alone != otherContent)
        #expect(alone.map(\.contentHash) != otherContent.map(\.contentHash))
        let moved = try #require(afterInsertion.first)
        #expect(moved.newStart == 11)
    }

    @Test
    func hunksShareTheOldSideWhenTheirOldRangesTouchOrOverlapAndNotWhenALineSeparatesThem() {
        func hunk(_ oldStart: Int, _ oldCount: Int) -> PartialCommitHunk {
            PartialCommitHunk(
                oldStart: oldStart,
                oldCount: oldCount,
                newStart: oldStart,
                newCount: 1,
                contentHash: 0,
                preview: ""
            )
        }
        let line5 = hunk(5, 1)
        let lines4to6 = hunk(4, 3)
        let line6 = hunk(6, 1)
        let line7 = hunk(7, 1)
        let insertionAfter5 = hunk(5, 0)
        let insertionAfter6 = hunk(6, 0)

        #expect(line5.sharesOldSide(with: line5))
        #expect(line5.sharesOldSide(with: lines4to6))
        #expect(lines4to6.sharesOldSide(with: line5))
        #expect(line5.sharesOldSide(with: insertionAfter5))
        #expect(insertionAfter5.sharesOldSide(with: line5))
        #expect(line5.sharesOldSide(with: line6))
        #expect(line5.sharesOldSide(with: line7) == false)
        #expect(line7.sharesOldSide(with: line5) == false)
        #expect(line5.sharesOldSide(with: insertionAfter6) == false)
        #expect(insertionAfter6.sharesOldSide(with: line5) == false)
    }
}
