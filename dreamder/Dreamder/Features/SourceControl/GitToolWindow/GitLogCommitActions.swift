import AppKit
import SwiftUI

struct GitLogCommitSeams {
    var tagDialog: @MainActor (GitLogTagRequest) -> GitLogTagResult?
    var branchDialog: @MainActor (BranchesPopupBranchDialogRequest) -> BranchesPopupBranchDialogResult?
    var notify: @MainActor (BranchesPopupNotificationRequest) -> Void
    var presentConflicts: @MainActor (WorkspaceDocument) -> Void
    var confirmDetachedCheckout: @MainActor (_ title: String, _ message: String) -> Bool
    var copyRevision: @MainActor (String) -> Void

    static func live(pasteboard: any PasteboardAccess = SystemPasteboard()) -> GitLogCommitSeams {
        GitLogCommitSeams(
            tagDialog: { GitLogTagPrompt.run($0) },
            branchDialog: { BranchesPopupPrompt.branchDialog($0) },
            notify: { BranchesPopupNotifications.post($0) },
            presentConflicts: { MergeToolPresenter.showConflicts(workspace: $0) },
            confirmDetachedCheckout: { title, message in
                BranchesPopupPrompt.confirm(title: title, message: message, confirmTitle: "Checkout")
            },
            copyRevision: { text in pasteboard.replaceContents(withText: text) }
        )
    }
}

struct GitLogCommitSeamsEnvironmentKey: EnvironmentKey {
    static var defaultValue = GitLogCommitSeams.live()
}

extension EnvironmentValues {
    var gitLogCommitSeams: GitLogCommitSeams {
        get { self[GitLogCommitSeamsEnvironmentKey.self] }
        set { self[GitLogCommitSeamsEnvironmentKey.self] = newValue }
    }
}

struct GitLogCommitActions {
    let workspace: WorkspaceDocument
    let manager: SourceControlManager
    let viewModel: GitLogViewModel
    let seams: GitLogCommitSeams

    func checkoutBranchNames(for commit: GitLogCommit) -> [String] {
        let current = manager.currentBranch?.name
        return commit.refs
            .filter { $0.kind == .branch && $0.name != current }
            .map(\.name)
    }

    func copyRevisionNumber(_ commit: GitLogCommit) async {
        await viewModel.select(hash: commit.hash)
        seams.copyRevision(commit.hash)
    }

    func newTag(_ commit: GitLogCommit) async {
        await viewModel.select(hash: commit.hash)
        guard let result = seams.tagDialog(GitLogTagRequest(commit: commit.shortHash)) else { return }
        do {
            try await manager.gitLogCreateTag(
                name: result.name,
                at: commit.hash,
                message: result.message,
                force: result.force
            )
            await viewModel.load(manager: manager)
            seams.notify(Self.information(
                title: "Tag created",
                description: "Created tag \(result.name) successfully."
            ))
        } catch {
            await manager.showAlertForError(title: "Could not create tag", error: error)
        }
    }

    func newBranch(_ commit: GitLogCommit) async {
        await viewModel.select(hash: commit.hash)
        let existing = manager.gitLogLocalBranchNames()
        let request = BranchesPopupBranchDialogRequest(
            title: "Create New Branch",
            message: "Create a new branch from '\(commit.shortHash)'",
            initialName: "",
            existingNames: existing,
            showsCheckout: true,
            showsUnsetUpstream: false,
            confirmTitle: "Create"
        )
        guard let result = seams.branchDialog(request) else { return }
        let name = result.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let validation = BranchesPopupBranchName.validate(name, existingNames: existing)
        if let message = Self.nameRejection(validation, name: name, overwrite: result.overwrite) {
            await manager.showAlertForError(
                title: "Invalid Branch Name",
                error: GitClient.GitClientError.outputError(message)
            )
            return
        }
        await perform(failureTitle: "Failed to create branch '\(name)'") {
            try await manager.branchOpsCreateBranch(
                name: name,
                from: commit.hash,
                checkout: result.checkout,
                overwrite: result.overwrite
            )
        }
    }

    static func nameRejection(
        _ validation: BranchesPopupBranchNameValidation,
        name: String,
        overwrite: Bool
    ) -> String? {
        if validation == .exists, overwrite { return nil }
        return BranchesPopupBranchName.errorMessage(for: validation, name: name)
    }

    static let detachedHeadTitle = "The repository is in the detached HEAD state"
    static let detachedHeadMessage = "The Git repository is in the detached HEAD state after checkout. "
        + "You can look around, make experimental changes and commit them, but be sure to checkout a branch "
        + "not to lose your work. Otherwise you risk losing your changes."

    func checkoutRevision(_ commit: GitLogCommit) async {
        await viewModel.select(hash: commit.hash)
        guard seams.confirmDetachedCheckout(Self.detachedHeadTitle, Self.detachedHeadMessage) else { return }
        await perform(failureTitle: "Failed to check out '\(commit.shortHash)'") {
            try await manager.branchOpsCheckoutRevision(commit.hash)
        }
    }

    func checkoutBranch(_ name: String, of commit: GitLogCommit) async {
        await viewModel.select(hash: commit.hash)
        await perform(failureTitle: "Failed to check out '\(name)'") {
            try await manager.branchOpsCheckoutLocal(name)
        }
    }

    func cherryPick(_ commit: GitLogCommit) async {
        await viewModel.select(hash: commit.hash)
        let details = "\(commit.shortHash) \(commit.subject)"
        do {
            let outcome = try await manager.gitLogCherryPick(commit)
            await viewModel.load(manager: manager)
            switch outcome {
            case .success:
                seams.notify(Self.information(title: "Cherry-pick successful", description: details))
            case .empty:
                seams.notify(Self.information(
                    title: "Nothing to cherry-pick",
                    description: "All changes from \(commit.shortHash) have already been applied"
                ))
            case .conflicts:
                let target = workspace
                let presentConflicts = seams.presentConflicts
                seams.notify(BranchesPopupNotificationRequest(
                    title: "Cherry-pick was performed with conflicts",
                    description: "\(details)\nThere are unresolved conflicts in the working tree.",
                    actionTitle: "Resolve…",
                    action: { presentConflicts(target) }
                ))
                presentConflicts(target)
            }
        } catch {
            await manager.showAlertForError(title: "Cherry-pick failed", error: error)
        }
    }

    private func perform(failureTitle: String, _ operation: () async throws -> Void) async {
        do {
            try await operation()
            await viewModel.load(manager: manager)
        } catch {
            await manager.showAlertForError(title: failureTitle, error: error)
        }
    }

    static func information(title: String, description: String) -> BranchesPopupNotificationRequest {
        BranchesPopupNotificationRequest(title: title, description: description, actionTitle: "OK", action: {})
    }
}

struct GitLogCommitMenuItems: View {
    let actions: GitLogCommitActions
    let commit: GitLogCommit

    var body: some View {
        Button("Copy Revision Number") {
            Task { await actions.copyRevisionNumber(commit) }
        }
        Divider()
        Button("Cherry-Pick") {
            Task { await actions.cherryPick(commit) }
        }
        checkoutItems
        Divider()
        Button("New Branch…") {
            Task { await actions.newBranch(commit) }
        }
        Button("New Tag…") {
            Task { await actions.newTag(commit) }
        }
    }

    @ViewBuilder
    private var checkoutItems: some View {
        let branches = actions.checkoutBranchNames(for: commit)
        if branches.isEmpty {
            Button("Checkout Revision '\(commit.shortHash)'") {
                Task { await actions.checkoutRevision(commit) }
            }
        } else {
            Menu("Checkout") {
                ForEach(branches, id: \.self) { branch in
                    Button(branch) {
                        Task { await actions.checkoutBranch(branch, of: commit) }
                    }
                }
                Button("Revision '\(commit.shortHash)'") {
                    Task { await actions.checkoutRevision(commit) }
                }
            }
        }
    }
}
