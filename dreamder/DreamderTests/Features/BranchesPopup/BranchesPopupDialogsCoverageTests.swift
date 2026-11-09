import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct BranchesPopupBranchNameCoverageTests {
    @Test(arguments: [
        "main",
        "feature/login-form",
        "release-1.2",
        "user/name/topic",
        "a@b",
        "ünïcode"
    ])
    func acceptsWellFormedNames(_ name: String) {
        #expect(BranchesPopupBranchName.isValid(name))
        #expect(BranchesPopupBranchName.validate(name, existingNames: []) == .valid)
    }

    @Test(arguments: [
        "",
        "@",
        "-leading-dash",
        "/leading-slash",
        "trailing-slash/",
        "trailing-dot.",
        "topic.lock",
        "a..b",
        "a@{b",
        "a//b",
        "with space",
        "tilde~",
        "caret^",
        "colon:",
        "question?",
        "star*",
        "bracket[",
        "back\\slash",
        "bell\u{07}",
        "del\u{7f}",
        "a/.hidden",
        "a./b",
        ".hidden"
    ])
    func rejectsMalformedNames(_ name: String) {
        #expect(!BranchesPopupBranchName.isValid(name))
    }

    @Test
    func validateClassifiesEmptyInvalidExistingAndValidNames() {
        let existing: Set<String> = ["main", "feature/x"]

        #expect(BranchesPopupBranchName.validate("", existingNames: existing) == .empty)
        #expect(BranchesPopupBranchName.validate(" \n\t ", existingNames: existing) == .empty)
        #expect(BranchesPopupBranchName.validate("bad name", existingNames: existing) == .invalid)
        #expect(BranchesPopupBranchName.validate("main", existingNames: existing) == .exists)
        #expect(BranchesPopupBranchName.validate("  feature/x  ", existingNames: existing) == .exists)
        #expect(BranchesPopupBranchName.validate("topic", existingNames: existing) == .valid)
    }

    @Test
    func errorMessagesDescribeEveryFailure() {
        #expect(BranchesPopupBranchName.errorMessage(for: .valid, name: "x") == nil)
        #expect(BranchesPopupBranchName.errorMessage(for: .empty, name: "") == "Branch name cannot be empty")
        #expect(BranchesPopupBranchName.errorMessage(for: .invalid, name: "a b") == "Branch name is not valid")
        #expect(BranchesPopupBranchName.errorMessage(for: .exists, name: "main") == "Branch 'main' already exists")
    }

    @Test
    func dialogResultDefaultsToCheckoutWithoutOverwriteOrUnsetUpstream() {
        let result = BranchesPopupBranchDialogResult(name: "topic")

        #expect(result.name == "topic")
        #expect(result.checkout)
        #expect(!result.overwrite)
        #expect(!result.unsetUpstream)
    }
}

@MainActor
@Suite(.uiGate)
struct BranchesPopupDialogsCoverageTests {
    @Test
    func liveDialogsAreRoutedThroughTheSuppressedModals() {
        let live = BranchesPopupDialogs.live
        let token = UUID().uuidString
        let worktreesBefore = DreamderHeadless.suppressedModals.filter { $0 == "New Worktree" }.count

        let request = BranchesPopupBranchDialogRequest(
            title: "New Branch \(token)",
            message: "Create",
            initialName: "main",
            existingNames: ["main"],
            showsCheckout: true,
            showsUnsetUpstream: true,
            confirmTitle: "Create"
        )
        #expect(live.branchDialog(request) == nil)
        #expect(!live.confirm("Confirm \(token)", "Really?", "Do it"))
        #expect(live.unmergedDelete("topic-\(token)", ["abc123 work in progress"]) == .cancel)
        #expect(live.checkoutRemoteName("origin/\(token)", "suggested") == nil)
        #expect(live.checkoutRemoteLocalCommits("local-\(token)", "origin/local", 2) == .cancel)
        #expect(live.worktreePath("/tmp/worktree-\(token)") == nil)
        live.error("Error \(token)", "Something failed")

        let modals = DreamderHeadless.suppressedModals
        #expect(modals.contains("New Branch \(token)"))
        #expect(modals.contains("Confirm \(token)"))
        #expect(modals.contains("Branch 'topic-\(token)' is not fully merged"))
        #expect(modals.contains("Checkout origin/\(token)"))
        #expect(modals.contains("Local branch 'local-\(token)' has commits that do not exist in 'origin/local'"))
        #expect(modals.filter { $0 == "New Worktree" }.count > worktreesBefore)
        #expect(modals.contains("Error \(token)"))
    }

    @Test
    func notificationsAreForwardedToTheNotificationManagerWithTheirAction() async throws {
        let title = "Deleted Branch: \(UUID().uuidString)"
        var restores = 0

        BranchesPopupNotifications.post(
            BranchesPopupNotificationRequest(
                title: title,
                description: "Branch was deleted.",
                actionTitle: "Restore",
                action: { restores += 1 }
            )
        )

        try await eventually { NotificationManager.shared.notifications.contains { $0.title == title } }
        let notification = try #require(NotificationManager.shared.notifications.first { $0.title == title })
        #expect(notification.description == "Branch was deleted.")
        #expect(notification.actionButtonTitle == "Restore")
        notification.action()
        #expect(restores == 1)
        NotificationManager.shared.dismissNotification(notification)
    }
}
