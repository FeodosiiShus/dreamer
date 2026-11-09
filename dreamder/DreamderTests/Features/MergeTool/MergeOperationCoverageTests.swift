import Testing
@testable import Dreamder

@Suite
struct MergeOperationCoverageTests {
    @Test
    func emptyCurrentBranchIsDescribedAsHead() {
        var state = MergeRepositoryState()
        state.mergeSource = "feature"

        let context = MergeConflictContext.make(from: state)

        #expect(context.operation == .merge(source: "feature", target: "HEAD"))
        #expect(context.summary == "Merging branch feature into branch HEAD")
        #expect(context.yoursLabel == "HEAD")
    }

    @Test
    func emptyMergeSourceFallsThroughToTheNextOperation() {
        var state = MergeRepositoryState()
        state.currentBranch = "main"
        state.mergeSource = ""
        state.hasStash = true

        #expect(MergeConflictContext.make(from: state).operation == .stash(branch: "main"))
    }

    @Test
    func rebaseWithoutNamesFallsBackToTheCurrentBranchAndHead() {
        var state = MergeRepositoryState()
        state.currentBranch = "topic"
        state.hasRebaseInProgress = true

        let context = MergeConflictContext.make(from: state)

        #expect(context.operation == .rebase(branch: "topic", onto: "HEAD"))
        #expect(context.summary == "Rebasing branch topic onto HEAD")
        #expect(context.swapsSides)
    }

    @Test
    func rebaseWithEmptyNamesFallsBackLikeMissingNames() {
        var state = MergeRepositoryState()
        state.currentBranch = "topic"
        state.hasRebaseInProgress = true
        state.rebaseBranch = ""
        state.rebaseOnto = ""

        #expect(MergeConflictContext.make(from: state).operation == .rebase(branch: "topic", onto: "HEAD"))
    }

    @Test
    func rebaseBranchAloneIsEnoughToDetectARebase() {
        var state = MergeRepositoryState()
        state.currentBranch = "HEAD"
        state.rebaseBranch = "feature"

        let context = MergeConflictContext.make(from: state)

        #expect(context.operation == .rebase(branch: "feature", onto: "HEAD"))
        #expect(context.yoursHeader == "Yours (feature)")
        #expect(context.theirsHeader == "Theirs (HEAD)")
    }

    @Test
    func emptyCherryPickHashFallsThroughToUnknown() {
        var state = MergeRepositoryState()
        state.currentBranch = "main"
        state.cherryPickHash = ""

        #expect(MergeConflictContext.make(from: state).operation == .unknown)
    }

    @Test
    func onlyRebasesSwapSides() {
        var merge = MergeRepositoryState()
        merge.mergeSource = "feature"
        var cherryPick = MergeRepositoryState()
        cherryPick.cherryPickHash = "abc1234"
        var stash = MergeRepositoryState()
        stash.hasStash = true

        #expect(MergeConflictContext.make(from: merge).swapsSides == false)
        #expect(MergeConflictContext.make(from: cherryPick).swapsSides == false)
        #expect(MergeConflictContext.make(from: stash).swapsSides == false)
        #expect(MergeConflictContext.make(from: MergeRepositoryState()).swapsSides == false)
    }
}
