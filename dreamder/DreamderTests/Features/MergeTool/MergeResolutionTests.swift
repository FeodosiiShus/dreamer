import Testing
@testable import Dreamder

@Suite
struct MergeResolutionTests {
    private func conflictedMerge() -> ThreeWayMerge {
        ThreeWayMerge(
            base: "one\ntwo\nthree\n",
            ours: "one\nleft\nthree\n",
            theirs: "one\nright\nthree\n"
        )
    }

    @Test
    func acceptLeftProducesLeftText() {
        var merge = conflictedMerge()
        for block in merge.blocks {
            merge.resolve(block.id, with: .left)
        }
        #expect(merge.resultText == "one\nleft\nthree\n")
        #expect(merge.isFullyResolved)
    }

    @Test
    func acceptRightProducesRightText() {
        var merge = conflictedMerge()
        for block in merge.blocks {
            merge.resolve(block.id, with: .right)
        }
        #expect(merge.resultText == "one\nright\nthree\n")
    }

    @Test
    func applyKeepsUnresolvedConflictAtBase() {
        let merge = conflictedMerge()
        #expect(merge.resultText == "one\ntwo\nthree\n")
        #expect(merge.isFullyResolved == false)
    }

    @Test
    func applyMixesResolvedBlocksWithAutomaticChanges() throws {
        var merge = ThreeWayMerge(
            base: "one\ntwo\nthree\nfour\n",
            ours: "one\nleft\nthree\nfour\n",
            theirs: "one\nright\nthree\nFOUR\n"
        )
        #expect(merge.resultText == "one\ntwo\nthree\nFOUR\n")
        #expect(merge.blocks.count == 2)
        let conflictID = try #require(merge.blocks.first { $0.kind == .conflict }?.id)
        merge.resolve(conflictID, with: .left)
        #expect(merge.resultText == "one\nleft\nthree\nFOUR\n")
        #expect(merge.isFullyResolved)
    }

    @Test
    func applyNonConflictingLeftKeepsOnlyLeftChanges() {
        var merge = ThreeWayMerge(
            base: "one\ntwo\nthree\n",
            ours: "one\nLEFT\nthree\n",
            theirs: "one\ntwo\nTHREE\n"
        )
        merge.applyNonConflicting(.left)
        #expect(merge.resultText == "one\nLEFT\nthree\n")

        var right = merge
        right.applyNonConflicting(.right)
        #expect(right.resultText == "one\ntwo\nTHREE\n")
    }
}
