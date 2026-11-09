import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct BranchesPopupMenuFactoryCoverageTests {
    private func item(_ title: String, in menu: NSMenu) throws -> NSMenuItem {
        try #require(menu.items.first { $0.title == title })
    }

    @Test
    func menuActionRunsItsHandlerEachTimeItIsInvoked() {
        var invocations = 0
        let action = BranchesPopupMenuAction { invocations += 1 }

        action.invoke(nil)
        action.invoke(action)

        #expect(invocations == 2)
    }

    @Test
    func localBranchMenuListsEveryActionAndRunsThem() async throws {
        try await withTempDir { directory in
            let isolated = try makeIsolatedDefaults()
            defer { removeIsolatedDefaults(isolated.defaults, suiteName: isolated.suiteName) }
            let harness = try await BranchesPopupCoverageHarness.cloned(in: directory, defaults: isolated.defaults)
            let feature = try harness.ref(.local, "feature")
            let menu = BranchesPopupMenuFactory.menu(for: feature, model: harness.model)

            #expect(BranchesPopupCoverageKeys.titles(of: menu) == [
                "Checkout",
                "New Branch from 'feature'…",
                "Checkout and Rebase onto 'main'",
                "Checkout and Update",
                "-",
                "Compare with 'main'",
                "Show Diff with Working Tree",
                "-",
                "Rebase 'main' onto 'feature'",
                "Merge 'feature' into 'main'",
                "-",
                "New Worktree from 'feature'…",
                "-",
                "Update",
                "Push…",
                "Tracked Branch 'origin/feature'",
                "-",
                "Rename…",
                "Delete"
            ])
            #expect(!menu.autoenablesItems)
            #expect(menu.items.filter { !$0.isSeparatorItem }.allSatisfy { $0.isEnabled })
            let push = try item("Push…", in: menu)
            #expect(push.keyEquivalent == "k")
            #expect(push.keyEquivalentModifierMask == [.command, .shift])
            #expect(try item("Checkout", in: menu).keyEquivalent == "")

            let tracked = try item("Tracked Branch 'origin/feature'", in: menu)
            let trackedMenu = try #require(tracked.submenu)
            #expect(tracked.action.map(NSStringFromSelector) ?? "submenuAction:" == "submenuAction:")
            #expect(BranchesPopupCoverageKeys.titles(of: trackedMenu) == [
                "Checkout",
                "New Branch from 'origin/feature'…",
                "Checkout and Rebase onto 'main'",
                "-",
                "Compare with 'main'",
                "Show Diff with Working Tree",
                "-",
                "Rebase 'main' onto 'origin/feature'",
                "Merge 'origin/feature' into 'main'",
                "-",
                "New Worktree from 'origin/feature'…",
                "-",
                "Pull into 'main' Using Rebase",
                "Pull into 'main' Using Merge",
                "-",
                "Delete"
            ])

            let diffModalsBefore = DreamderHeadless.suppressedModals.filter { $0 == "No Differences" }.count
            var dismissals = harness.dismissals

            try await harness.perform("Compare with 'main'", in: menu)
            #expect(harness.compares.map(\.branch) == ["feature"])
            #expect(harness.compares.map(\.current) == ["main"])
            #expect(harness.dismissals == dismissals + 1)
            dismissals = harness.dismissals

            try await harness.perform("Show Diff with Working Tree", in: menu)
            #expect(harness.dismissals == dismissals + 1)
            dismissals = harness.dismissals
            try await eventually {
                DreamderHeadless.suppressedModals.filter { $0 == "No Differences" }.count > diffModalsBefore
            }

            try await harness.perform("New Branch from 'feature'…", in: menu)
            #expect(harness.branchDialogTitles == ["New Branch"])

            try await harness.perform("New Worktree from 'feature'…", in: menu)
            #expect(harness.worktreeSuggestions.count == 1)
            #expect(harness.worktreeSuggestions[0].hasSuffix("clone-feature"))

            try await harness.perform("Rename…", in: menu)
            #expect(harness.branchDialogTitles == ["New Branch", "Rename Branch feature"])

            try await harness.perform("Push…", in: menu)
            #expect(harness.manager.pushSheetIsPresented)
            #expect(harness.manager.operationBranch?.name == "feature")
            #expect(harness.dismissals == dismissals + 1)
            dismissals = harness.dismissals

            try await harness.perform("Update", in: menu)
            try await harness.perform("Merge 'feature' into 'main'", in: menu)
            try await harness.perform("Rebase 'main' onto 'feature'", in: menu)

            try await harness.perform("Checkout and Update", in: menu)
            #expect(harness.dismissals == dismissals + 1)
            dismissals = harness.dismissals

            try await harness.perform("Checkout and Rebase onto 'main'", in: menu)
            #expect(harness.dismissals == dismissals + 1)
            dismissals = harness.dismissals

            try await harness.fixture.run("checkout", "-q", "main")
            await harness.manager.refreshCurrentBranch()
            try await harness.perform("Checkout", in: menu)
            #expect(harness.dismissals == dismissals + 1)
            try await eventually { harness.manager.currentBranch?.name == "feature" }
        }
    }

    @Test
    func currentBranchMenuHidesCheckoutAndDeletion() async throws {
        try await withTempDir { directory in
            let isolated = try makeIsolatedDefaults()
            defer { removeIsolatedDefaults(isolated.defaults, suiteName: isolated.suiteName) }
            let harness = try await BranchesPopupCoverageHarness.cloned(in: directory, defaults: isolated.defaults)
            let main = try harness.ref(.local, "main")

            let menu = BranchesPopupMenuFactory.menu(for: main, model: harness.model)

            #expect(BranchesPopupCoverageKeys.titles(of: menu) == [
                "New Branch from 'main'…",
                "-",
                "Show Diff with Working Tree",
                "-",
                "New Worktree from 'main'…",
                "-",
                "Update",
                "Push…",
                "Tracked Branch 'origin/main'",
                "-",
                "Rename…"
            ])
        }
    }

    @Test
    func remoteBranchMenuPullsAndDeletes() async throws {
        try await withTempDir { directory in
            let isolated = try makeIsolatedDefaults()
            defer { removeIsolatedDefaults(isolated.defaults, suiteName: isolated.suiteName) }
            let harness = try await BranchesPopupCoverageHarness.cloned(in: directory, defaults: isolated.defaults)
            let remote = try harness.ref(.remote, "origin/feature")
            let menu = BranchesPopupMenuFactory.menu(for: remote, model: harness.model)

            #expect(BranchesPopupCoverageKeys.titles(of: menu) == [
                "Checkout",
                "New Branch from 'origin/feature'…",
                "Checkout and Rebase onto 'main'",
                "-",
                "Compare with 'main'",
                "Show Diff with Working Tree",
                "-",
                "Rebase 'main' onto 'origin/feature'",
                "Merge 'origin/feature' into 'main'",
                "-",
                "New Worktree from 'origin/feature'…",
                "-",
                "Pull into 'main' Using Rebase",
                "Pull into 'main' Using Merge",
                "-",
                "Delete"
            ])

            var dismissals = harness.dismissals
            try await harness.perform("Pull into 'main' Using Rebase", in: menu)
            #expect(harness.dismissals == dismissals + 1)
            dismissals = harness.dismissals
            try await harness.perform("Pull into 'main' Using Merge", in: menu)
            #expect(harness.dismissals == dismissals + 1)

            try await harness.perform("Delete", in: menu)
            #expect(harness.confirmTitles == ["Delete Remote Branch"])
            try await harness.perform("Checkout", in: menu)
            try await eventually { harness.manager.currentBranch?.name == "feature" }
        }
    }

    @Test
    func trackedBranchSubmenuChecksOutTheRemoteTrackingBranch() async throws {
        try await withTempDir { directory in
            let isolated = try makeIsolatedDefaults()
            defer { removeIsolatedDefaults(isolated.defaults, suiteName: isolated.suiteName) }
            let harness = try await BranchesPopupCoverageHarness.cloned(in: directory, defaults: isolated.defaults)
            let feature = try harness.ref(.local, "feature")
            let menu = BranchesPopupMenuFactory.menu(for: feature, model: harness.model)
            let tracked = try item("Tracked Branch 'origin/feature'", in: menu)
            let trackedMenu = try #require(tracked.submenu)

            try await harness.perform("Checkout", in: trackedMenu)

            try await eventually { harness.manager.currentBranch?.name == "feature" }
            #expect(harness.dismissals == 1)
        }
    }

    @Test
    func tagMenuPushesToEveryRemoteAndDeletesTheTag() async throws {
        try await withTempDir { directory in
            let isolated = try makeIsolatedDefaults()
            defer { removeIsolatedDefaults(isolated.defaults, suiteName: isolated.suiteName) }
            let harness = try await BranchesPopupCoverageHarness.cloned(in: directory, defaults: isolated.defaults)
            let tag = try harness.ref(.tag, "v1")
            let menu = BranchesPopupMenuFactory.menu(for: tag, model: harness.model)

            #expect(BranchesPopupCoverageKeys.titles(of: menu) == [
                "Checkout",
                "-",
                "Show Diff with Working Tree",
                "-",
                "Merge 'v1' into 'main'",
                "-",
                "New Worktree from 'v1'…",
                "-",
                "Push Tag",
                "-",
                "Delete"
            ])
            let pushTag = try item("Push Tag", in: menu)
            #expect(pushTag.action.map(NSStringFromSelector) ?? "submenuAction:" == "submenuAction:")
            let remotesMenu = try #require(pushTag.submenu)
            #expect(BranchesPopupCoverageKeys.titles(of: remotesMenu) == ["Push to origin"])
            #expect(!remotesMenu.autoenablesItems)

            try await harness.perform("Push to origin", in: remotesMenu)
            #expect(harness.dismissals == 1)
            let origin = GitMergeFixture(existing: directory.appending(path: "origin"))
            try await eventually { ((try? await origin.run("tag")) ?? "").contains("v1") }

            try await harness.perform("Merge 'v1' into 'main'", in: menu)
            try await harness.perform("New Worktree from 'v1'…", in: menu)
            #expect(harness.worktreeSuggestions.count == 1)

            try await harness.perform("Checkout", in: menu)
            try await harness.perform("Delete", in: menu)
            try await eventually { harness.notifications.contains("Deleted Tag: v1") }
        }
    }

    @Test
    func branchWithoutUpstreamOffersNoRemoteActionsAndCanBeDeleted() async throws {
        try await withTempDir { directory in
            let isolated = try makeIsolatedDefaults()
            defer { removeIsolatedDefaults(isolated.defaults, suiteName: isolated.suiteName) }
            let harness = try await BranchesPopupCoverageHarness.cloned(in: directory, defaults: isolated.defaults)
            let obsolete = try harness.ref(.local, "obsolete")
            let menu = BranchesPopupMenuFactory.menu(for: obsolete, model: harness.model)

            #expect(BranchesPopupCoverageKeys.titles(of: menu) == [
                "Checkout",
                "New Branch from 'obsolete'…",
                "Checkout and Rebase onto 'main'",
                "-",
                "Compare with 'main'",
                "Show Diff with Working Tree",
                "-",
                "Rebase 'main' onto 'obsolete'",
                "Merge 'obsolete' into 'main'",
                "-",
                "New Worktree from 'obsolete'…",
                "-",
                "Push…",
                "-",
                "Rename…",
                "Delete"
            ])

            try await harness.perform("Delete", in: menu)

            try await eventually { harness.notifications.contains("Deleted Branch: obsolete") }
            let branches = try await harness.fixture.run("branch", "--format=%(refname:short)")
            #expect(!branches.contains("obsolete"))
        }
    }
}
