import Testing
@testable import Dreamder

@Suite
struct CompletionTriggerSyncTests {
    @Test
    func requestEqualToAppliedIsUnchanged() {
        var sync = CompletionTriggerSync()

        let step = sync.request([], hasController: true)

        #expect(step == .unchanged)
        #expect(sync.applied.isEmpty)
        #expect(!sync.isApplyPending)
    }

    @Test
    func withoutControllerTheRequestIsAdoptedImmediately() {
        var sync = CompletionTriggerSync()

        let step = sync.request([".", "("], hasController: false)

        #expect(step == .adopted)
        #expect(sync.applied == [".", "("])
        #expect(!sync.isApplyPending)
    }

    @Test
    func withControllerTheChangeIsDeferredAndAppliedStaysUntilCommit() {
        var sync = CompletionTriggerSync(applied: ["."])

        let step = sync.request([".", "("], hasController: true)

        #expect(step == .applyLater)
        #expect(sync.applied == ["."])
        #expect(sync.desired == [".", "("])
        #expect(sync.isApplyPending)
    }

    @Test
    func repeatedRequestsWhilePendingScheduleOnlyOnce() {
        var sync = CompletionTriggerSync()
        let first = sync.request(["."], hasController: true)
        let second = sync.request(["."], hasController: true)
        let third = sync.request([".", "<"], hasController: true)

        #expect(first == .applyLater)
        #expect(second == .unchanged)
        #expect(third == .unchanged)
        #expect(sync.commit() == [".", "<"])
    }

    @Test
    func commitAppliesLatestDesiredAndClearsPending() {
        var sync = CompletionTriggerSync()
        _ = sync.request(["/"], hasController: true)

        let committed = sync.commit()
        let following = sync.request(["/"], hasController: true)

        #expect(committed == ["/"])
        #expect(sync.applied == ["/"])
        #expect(!sync.isApplyPending)
        #expect(following == .unchanged)
    }

    @Test
    func requestAfterCommitWithNewValueSchedulesAgain() {
        var sync = CompletionTriggerSync()
        _ = sync.request(["/"], hasController: true)
        _ = sync.commit()

        let step = sync.request([], hasController: true)

        #expect(step == .applyLater)
        #expect(sync.applied == ["/"])
    }

    @Test
    func revertingToAppliedBeforeCommitLeavesAppliedUnchanged() {
        var sync = CompletionTriggerSync()
        _ = sync.request(["."], hasController: true)
        let revert = sync.request([], hasController: true)

        #expect(revert == .unchanged)
        #expect(sync.commit().isEmpty)
    }

    @Test
    func losingTheControllerWhilePendingAdoptsTheLatestRequest() {
        var sync = CompletionTriggerSync()
        _ = sync.request(["."], hasController: true)

        let step = sync.request(["("], hasController: false)

        #expect(step == .adopted)
        #expect(sync.applied == ["("])
    }
}
