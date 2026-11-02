import Testing
@testable import Dreamder

@Suite
struct MergeOperationTests {
    @Test
    func detectsMerge() {
        var state = MergeRepositoryState()
        state.currentBranch = "main"
        state.mergeSource = "feature"

        let context = MergeConflictContext.make(from: state)
        #expect(context.operation == .merge(source: "feature", target: "main"))
        #expect(context.summary == "Merging branch feature into branch main")
        #expect(context.yoursLabel == "main")
        #expect(context.theirsLabel == "feature")
        #expect(context.swapsSides == false)
        #expect(context.yoursHeader == "Yours (main)")
        #expect(context.theirsHeader == "Theirs (feature)")
    }

    @Test
    func detectsRebaseWithSwappedSides() {
        var state = MergeRepositoryState()
        state.currentBranch = "HEAD"
        state.hasRebaseInProgress = true
        state.rebaseBranch = "feature"
        state.rebaseOnto = "main"

        let context = MergeConflictContext.make(from: state)
        #expect(context.operation == .rebase(branch: "feature", onto: "main"))
        #expect(context.summary == "Rebasing branch feature onto main")
        #expect(context.swapsSides)
        #expect(context.yoursLabel == "feature")
        #expect(context.theirsLabel == "main")
    }

    @Test
    func detectsCherryPick() {
        var state = MergeRepositoryState()
        state.currentBranch = "main"
        state.cherryPickHash = "abc1234"

        let context = MergeConflictContext.make(from: state)
        #expect(context.operation == .cherryPick(hash: "abc1234"))
        #expect(context.summary == "Cherry-picking abc1234 into branch main")
        #expect(context.swapsSides == false)
    }

    @Test
    func detectsStashConflicts() {
        var state = MergeRepositoryState()
        state.currentBranch = "main"
        state.hasStash = true

        let context = MergeConflictContext.make(from: state)
        #expect(context.operation == .stash(branch: "main"))
        #expect(context.summary == "Conflicts during unstashing")
        #expect(context.theirsLabel == "stash")
    }

    @Test
    func fallsBackToGenericDescription() {
        var state = MergeRepositoryState()
        state.currentBranch = "main"

        let context = MergeConflictContext.make(from: state)
        #expect(context.operation == .unknown)
        #expect(context.summary == "The following files have conflicts:")
        #expect(context.yoursLabel == "main")
        #expect(context.theirsLabel == "Theirs")
    }

    @Test
    func prefersMergeOverOtherMarkers() {
        var state = MergeRepositoryState()
        state.currentBranch = "main"
        state.mergeSource = "feature"
        state.hasRebaseInProgress = true
        state.cherryPickHash = "abc1234"

        let context = MergeConflictContext.make(from: state)
        #expect(context.summary == "Merging branch feature into branch main")
    }

    @Test
    func usesShortBranchName() {
        #expect(MergeConflictRepository.shortBranchName("refs/heads/main") == "main")
        #expect(MergeConflictRepository.shortBranchName("refs/tags/v1.0") == "v1.0")
        #expect(MergeConflictRepository.shortBranchName("  feature  ") == "feature")
    }
}
