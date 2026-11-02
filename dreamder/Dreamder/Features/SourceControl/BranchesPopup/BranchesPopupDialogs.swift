import Foundation

struct BranchesPopupBranchDialogRequest {
    let title: String
    let message: String
    let initialName: String
    let existingNames: Set<String>
    let showsCheckout: Bool
    let showsUnsetUpstream: Bool
    let confirmTitle: String
}

struct BranchesPopupBranchDialogResult {
    var name: String
    var checkout: Bool = true
    var overwrite: Bool = false
    var unsetUpstream: Bool = false
}

enum BranchesPopupLocalCommitsDecision {
    case cancel
    case rebase
    case drop
}

enum BranchesPopupDeleteBranchDecision {
    case cancel
    case force
}

enum BranchesPopupBranchNameValidation: Equatable {
    case valid
    case empty
    case invalid
    case exists
}

enum BranchesPopupBranchName {
    static func validate(_ name: String, existingNames: Set<String>) -> BranchesPopupBranchNameValidation {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        guard isValid(trimmed) else { return .invalid }
        guard !existingNames.contains(trimmed) else { return .exists }
        return .valid
    }

    static func isValid(_ name: String) -> Bool {
        guard !name.isEmpty, name != "@" else { return false }
        guard !name.hasPrefix("-"), !name.hasPrefix("/"), !name.hasSuffix("/") else { return false }
        guard !name.hasSuffix("."), !name.hasSuffix(".lock") else { return false }
        guard !name.contains(".."), !name.contains("@{"), !name.contains("//") else { return false }
        let forbidden = CharacterSet(charactersIn: " ~^:?*[\\")
        if name.unicodeScalars.contains(where: { forbidden.contains($0) }) { return false }
        if name.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7f }) { return false }
        for component in name.split(separator: "/", omittingEmptySubsequences: false) {
            if component.isEmpty || component.hasPrefix(".") || component.hasSuffix(".") {
                return false
            }
        }
        return true
    }

    static func errorMessage(for validation: BranchesPopupBranchNameValidation, name: String) -> String? {
        switch validation {
        case .valid:
            return nil
        case .empty:
            return "Branch name cannot be empty"
        case .invalid:
            return "Branch name is not valid"
        case .exists:
            return "Branch '\(name)' already exists"
        }
    }
}

struct BranchesPopupDialogs {
    var branchDialog: (BranchesPopupBranchDialogRequest) -> BranchesPopupBranchDialogResult?
    var confirm: (_ title: String, _ message: String, _ confirmTitle: String) -> Bool
    var unmergedDelete: (_ name: String, _ commits: [String]) -> BranchesPopupDeleteBranchDecision
    var checkoutRemoteName: (_ remote: String, _ suggested: String) -> String?
    var checkoutRemoteLocalCommits: (
        _ local: String,
        _ remote: String,
        _ count: Int
    ) -> BranchesPopupLocalCommitsDecision
    var worktreePath: (_ suggested: String) -> String?
    var error: (_ title: String, _ message: String) -> Void

    static let live = BranchesPopupDialogs(
        branchDialog: { BranchesPopupPrompt.branchDialog($0) },
        confirm: { title, message, confirmTitle in
            BranchesPopupPrompt.confirm(title: title, message: message, confirmTitle: confirmTitle)
        },
        unmergedDelete: { name, commits in
            BranchesPopupPrompt.unmergedDelete(name: name, commits: commits)
        },
        checkoutRemoteName: { remote, suggested in
            BranchesPopupPrompt.name(
                title: "Checkout \(remote)",
                message: "Enter a name for the new local branch:",
                placeholder: "Branch name",
                initialValue: suggested
            )
        },
        checkoutRemoteLocalCommits: { local, remote, count in
            BranchesPopupPrompt.localCommitsDecision(local: local, remote: remote, count: count)
        },
        worktreePath: { suggested in
            BranchesPopupPrompt.name(
                title: "New Worktree",
                message: "Enter the path for the new worktree:",
                placeholder: "Worktree path",
                initialValue: suggested
            )
        },
        error: { title, message in
            BranchesPopupPrompt.error(title: title, message: message)
        }
    )
}

struct BranchesPopupNotificationRequest {
    let title: String
    let description: String
    let actionTitle: String
    let action: () -> Void
}

enum BranchesPopupNotifications {
    static func post(_ request: BranchesPopupNotificationRequest) {
        NotificationManager.shared.post(
            iconSymbol: "arrow.triangle.branch",
            title: request.title,
            description: request.description,
            actionButtonTitle: request.actionTitle,
            action: request.action
        )
    }
}
