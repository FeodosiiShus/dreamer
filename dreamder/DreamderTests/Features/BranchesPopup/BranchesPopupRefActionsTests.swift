import Testing
@testable import Dreamder

@Suite
struct BranchesPopupRefActionsTests {
    private func local(_ name: String, upstream: String? = nil, current: Bool = false) -> BranchesPopupRef {
        BranchesPopupRef(
            kind: .local,
            name: name,
            shortName: name,
            upstream: upstream,
            isCurrent: current
        )
    }

    private func remote(_ shortName: String) -> BranchesPopupRef {
        let name = shortName.split(separator: "/", maxSplits: 1).map(String.init).last ?? shortName
        return BranchesPopupRef(kind: .remote, name: name, shortName: shortName, upstream: nil, isCurrent: false)
    }

    private func tag(_ name: String) -> BranchesPopupRef {
        BranchesPopupRef(kind: .tag, name: name, shortName: name, upstream: nil, isCurrent: false)
    }

    private func context(tracked: BranchesPopupRef? = nil) -> BranchesPopupRefActionContext {
        BranchesPopupRefActionContext(
            currentName: "main",
            hasRemotes: true,
            trackedBranch: tracked
        )
    }

    private func items(
        _ ref: BranchesPopupRef,
        _ context: BranchesPopupRefActionContext,
        includeTrackedBranch: Bool = true
    ) -> [String] {
        BranchesPopupRefActions.entries(
            for: ref,
            context: context,
            includeTrackedBranch: includeTrackedBranch
        ).map { entry in
            switch entry {
            case .separator:
                return "—"
            case .action(let action):
                return BranchesPopupRefActions.title(for: action, ref: ref, context: context)
            }
        }
    }

    @Test
    func currentLocalBranchMatchesIntelliJOrder() {
        let tracked = remote("origin/main")
        let ref = local("main", upstream: "origin/main", current: true)
        #expect(items(ref, context(tracked: tracked)) == [
            "New Branch from 'main'…",
            "—",
            "Show Diff with Working Tree",
            "—",
            "New Worktree from 'main'…",
            "—",
            "Update",
            "Push…",
            "Tracked Branch 'origin/main'",
            "—",
            "Rename…"
        ])
    }

    @Test
    func otherLocalBranchMatchesIntelliJOrder() {
        let tracked = remote("origin/feature")
        let ref = local("feature", upstream: "origin/feature")
        #expect(items(ref, context(tracked: tracked)) == [
            "Checkout",
            "New Branch from 'feature'…",
            "Checkout and Rebase onto 'main'",
            "Checkout and Update",
            "—",
            "Compare with 'main'",
            "Show Diff with Working Tree",
            "—",
            "Rebase 'main' onto 'feature'",
            "Merge 'feature' into 'main'",
            "—",
            "New Worktree from 'feature'…",
            "—",
            "Update",
            "Push…",
            "Tracked Branch 'origin/feature'",
            "—",
            "Rename…",
            "Delete"
        ])
    }

    @Test
    func localBranchWithoutTrackingHidesUpdateAndCheckoutAndUpdate() {
        let ref = local("feature")
        #expect(items(ref, context()) == [
            "Checkout",
            "New Branch from 'feature'…",
            "Checkout and Rebase onto 'main'",
            "—",
            "Compare with 'main'",
            "Show Diff with Working Tree",
            "—",
            "Rebase 'main' onto 'feature'",
            "Merge 'feature' into 'main'",
            "—",
            "New Worktree from 'feature'…",
            "—",
            "Push…",
            "—",
            "Rename…",
            "Delete"
        ])
    }

    @Test
    func remoteBranchMatchesIntelliJOrder() {
        let ref = remote("origin/feature")
        #expect(items(ref, context()) == [
            "Checkout",
            "New Branch from 'origin/feature'…",
            "Checkout and Rebase onto 'main'",
            "—",
            "Compare with 'main'",
            "Show Diff with Working Tree",
            "—",
            "Rebase 'main' onto 'origin/feature'",
            "Merge 'origin/feature' into 'main'",
            "—",
            "New Worktree from 'origin/feature'…",
            "—",
            "Pull into 'main' Using Rebase",
            "Pull into 'main' Using Merge",
            "—",
            "Delete"
        ])
    }

    @Test
    func tagMatchesIntelliJOrder() {
        let ref = tag("v1.0")
        #expect(items(ref, context()) == [
            "Checkout",
            "—",
            "Show Diff with Working Tree",
            "—",
            "Merge 'v1.0' into 'main'",
            "—",
            "New Worktree from 'v1.0'…",
            "—",
            "Push Tag",
            "—",
            "Delete"
        ])
    }

    @Test
    func trackedBranchSubmenuReusesTheRefActionList() {
        let tracked = remote("origin/feature")
        #expect(items(tracked, context(), includeTrackedBranch: false) == items(tracked, context()))
    }

    @Test
    func detachedHeadHidesRebaseActions() {
        let ref = local("feature")
        let detached = BranchesPopupRefActionContext(
            currentName: "HEAD",
            hasRemotes: true,
            isDetachedHead: true
        )
        let titles = items(ref, detached)
        #expect(titles.contains("Rebase 'HEAD' onto 'feature'") == false)
        #expect(titles.contains("Checkout and Rebase onto 'HEAD'") == false)
    }
}
