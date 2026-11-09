import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
final class GitLogCommitActionsRecorder {
    var tagAnswer: GitLogTagResult?
    var branchAnswer: BranchesPopupBranchDialogResult?
    private(set) var tagRequests: [GitLogTagRequest] = []
    private(set) var branchRequests: [BranchesPopupBranchDialogRequest] = []
    private(set) var notifications: [BranchesPopupNotificationRequest] = []
    var presented: [WorkspaceDocument] = []
    var confirmAnswer = true
    private(set) var confirmations: [[String]] = []
    var copied: [String] = []

    func seams() -> GitLogCommitSeams {
        GitLogCommitSeams(
            tagDialog: { [self] request in
                tagRequests.append(request)
                return tagAnswer
            },
            branchDialog: { [self] request in
                branchRequests.append(request)
                return branchAnswer
            },
            notify: { [self] request in notifications.append(request) },
            presentConflicts: { [self] workspace in presented.append(workspace) },
            confirmDetachedCheckout: { [self] title, message in
                confirmations.append([title, message])
                return confirmAnswer
            },
            copyRevision: { [self] text in copied.append(text) }
        )
    }
}

@MainActor
struct GitLogCommitActionsRig {
    enum Scenario {
        case history
        case conflict
    }

    let fixture: GitMergeFixture
    let workspace: WorkspaceDocument
    let manager: SourceControlManager
    let model: GitLogViewModel
    let recorder: GitLogCommitActionsRecorder

    var actions: GitLogCommitActions {
        GitLogCommitActions(workspace: workspace, manager: manager, viewModel: model, seams: recorder.seams())
    }

    static func make(in directory: URL, scenario: Scenario = .history) async throws -> GitLogCommitActionsRig {
        let fixture: GitMergeFixture
        switch scenario {
        case .history:
            fixture = try await GitMergeFixture(root: directory)
            try fixture.write("a.txt", "one\n")
            try await fixture.commit("initial")
            try await fixture.run("checkout", "-q", "-b", "feature")
            try fixture.write("f.txt", "feature\n")
            try await fixture.commit("Feature work")
            try await fixture.run("checkout", "-q", "main")
            try fixture.write("a.txt", "two\n")
            try await fixture.commit("Main work")
        case .conflict:
            fixture = try await GitMergeFixture(root: directory)
            try fixture.write("src/main.swift", "line1\nline2\nline3\n")
            try await fixture.commit("base")
            try await fixture.run("checkout", "-q", "-b", "feature")
            try fixture.write("src/main.swift", "line1\nfeature-line\nline3\n")
            try await fixture.commit("Feature work")
            try await fixture.run("checkout", "-q", "main")
            try fixture.write("src/main.swift", "line1\nmain-line\nline3\n")
            try await fixture.commit("Main work")
        }
        let workspace = try HostedViewFixture.makeWorkspace(in: directory)
        let manager = try #require(workspace.sourceControlManager)
        await manager.refreshBranches()
        await manager.refreshCurrentBranch()
        let model = GitLogViewModel()
        await model.load(manager: manager)
        return GitLogCommitActionsRig(
            fixture: fixture,
            workspace: workspace,
            manager: manager,
            model: model,
            recorder: GitLogCommitActionsRecorder()
        )
    }

    func commit(_ subject: String) throws -> GitLogCommit {
        try #require(model.commits.first { $0.subject == subject })
    }

    func head() async throws -> String {
        try await fixture.run("rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func currentBranchName() async throws -> String {
        try await fixture.run("rev-parse", "--abbrev-ref", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func close() {
        recorder.copied.removeAll()
        workspace.close()
    }
}

@MainActor
@Suite(.uiGate)
struct GitLogCommitActionsTests {
    @Test
    func copyRevisionNumberPutsTheFullHashOnThePasteboardAndSelectsTheRow() async throws {
        try await withTempDir { directory in
            let rig = try await GitLogCommitActionsRig.make(in: directory)
            defer { rig.close() }
            let target = try rig.commit("Feature work")

            await rig.actions.copyRevisionNumber(target)

            #expect(rig.recorder.copied == [target.hash])
            #expect(rig.model.selectedHash == target.hash)
        }
    }

    @Test
    func newTagCreatesAPlainTagAndReportsIt() async throws {
        try await withTempDir { directory in
            let rig = try await GitLogCommitActionsRig.make(in: directory)
            defer { rig.close() }
            let target = try rig.commit("Feature work")
            rig.recorder.tagAnswer = GitLogTagResult(name: "v1", message: "", force: false)

            await rig.actions.newTag(target)

            #expect(rig.recorder.tagRequests == [GitLogTagRequest(commit: target.shortHash)])
            #expect(try await rig.fixture.run("rev-parse", "v1^{commit}").trimmingCharacters(in: .whitespacesAndNewlines) == target.hash)
            #expect(try await rig.fixture.run("cat-file", "-t", "v1").trimmingCharacters(in: .whitespacesAndNewlines) == "commit")
            let notification = try #require(rig.recorder.notifications.first)
            #expect(notification.title == "Tag created")
            #expect(notification.description == "Created tag v1 successfully.")
            #expect(notification.actionTitle == "OK")
            notification.action()
            let reloaded = try rig.commit("Feature work")
            #expect(reloaded.refs.contains(GitLogRef(name: "v1", kind: .tag)))
        }
    }

    @Test
    func newTagWithAMessageCreatesAnAnnotatedTag() async throws {
        try await withTempDir { directory in
            let rig = try await GitLogCommitActionsRig.make(in: directory)
            defer { rig.close() }
            let target = try rig.commit("Main work")
            rig.recorder.tagAnswer = GitLogTagResult(name: "v2", message: "release", force: false)

            await rig.actions.newTag(target)

            #expect(try await rig.fixture.run("cat-file", "-t", "v2").trimmingCharacters(in: .whitespacesAndNewlines) == "tag")
        }
    }

    @Test
    func newTagReportsADuplicateAndForceMovesIt() async throws {
        try await withTempDir { directory in
            let rig = try await GitLogCommitActionsRig.make(in: directory)
            defer { rig.close() }
            let first = try rig.commit("Feature work")
            let second = try rig.commit("Main work")
            rig.recorder.tagAnswer = GitLogTagResult(name: "v1", message: "", force: false)
            await rig.actions.newTag(first)
            #expect(rig.recorder.notifications.count == 1)

            await rig.actions.newTag(second)

            let alert = try #require(rig.manager.lastAlert)
            #expect(alert.title == "Could not create tag")
            #expect(alert.message == GitClient.tagExistsMessage)
            #expect(rig.recorder.notifications.count == 1)
            #expect(try await rig.fixture.run("rev-parse", "v1").trimmingCharacters(in: .whitespacesAndNewlines) == first.hash)

            rig.recorder.tagAnswer = GitLogTagResult(name: "v1", message: "", force: true)
            await rig.actions.newTag(second)

            #expect(try await rig.fixture.run("rev-parse", "v1").trimmingCharacters(in: .whitespacesAndNewlines) == second.hash)
        }
    }

    @Test
    func newTagReportsAnInvalidName() async throws {
        try await withTempDir { directory in
            let rig = try await GitLogCommitActionsRig.make(in: directory)
            defer { rig.close() }
            rig.recorder.tagAnswer = GitLogTagResult(name: "a..b", message: "", force: false)

            await rig.actions.newTag(try rig.commit("Main work"))

            #expect(rig.manager.lastAlert?.title == "Could not create tag")
            #expect(rig.manager.lastAlert?.message == "'a..b' is not a valid tag name.")
            #expect(try await rig.fixture.run("tag").isEmpty)
        }
    }

    @Test
    func cancellingTheTagDialogDoesNothing() async throws {
        try await withTempDir { directory in
            let rig = try await GitLogCommitActionsRig.make(in: directory)
            defer { rig.close() }
            rig.recorder.tagAnswer = nil

            await rig.actions.newTag(try rig.commit("Main work"))

            #expect(rig.recorder.tagRequests.count == 1)
            #expect(rig.recorder.notifications.isEmpty)
            #expect(rig.manager.lastAlert == nil)
            #expect(try await rig.fixture.run("tag").isEmpty)
        }
    }

    @Test
    func newBranchFromACommitChecksItOut() async throws {
        try await withTempDir { directory in
            let rig = try await GitLogCommitActionsRig.make(in: directory)
            defer { rig.close() }
            let target = try rig.commit("Feature work")
            rig.recorder.branchAnswer = BranchesPopupBranchDialogResult(name: "  topic  ")

            await rig.actions.newBranch(target)

            let request = try #require(rig.recorder.branchRequests.first)
            #expect(request.title == "Create New Branch")
            #expect(request.message == "Create a new branch from '\(target.shortHash)'")
            #expect(request.confirmTitle == "Create")
            #expect(request.initialName.isEmpty)
            #expect(request.showsCheckout)
            #expect(request.showsUnsetUpstream == false)
            #expect(request.existingNames == ["main", "feature"])
            #expect(try await rig.currentBranchName() == "topic")
            #expect(try await rig.head() == target.hash)
            try await eventually { rig.manager.currentBranch?.name == "topic" }
        }
    }

    @Test
    func newBranchWithoutCheckoutKeepsTheCurrentBranch() async throws {
        try await withTempDir { directory in
            let rig = try await GitLogCommitActionsRig.make(in: directory)
            defer { rig.close() }
            let target = try rig.commit("Feature work")
            rig.recorder.branchAnswer = BranchesPopupBranchDialogResult(name: "topic", checkout: false)

            await rig.actions.newBranch(target)

            #expect(try await rig.currentBranchName() == "main")
            #expect(try await rig.fixture.run("rev-parse", "topic").trimmingCharacters(in: .whitespacesAndNewlines) == target.hash)
        }
    }

    @Test
    func newBranchOverwritesAnExistingBranchWhenAsked() async throws {
        try await withTempDir { directory in
            let rig = try await GitLogCommitActionsRig.make(in: directory)
            defer { rig.close() }
            let target = try rig.commit("Main work")
            rig.recorder.branchAnswer = BranchesPopupBranchDialogResult(name: "feature", checkout: false, overwrite: true)

            await rig.actions.newBranch(target)

            #expect(try await rig.fixture.run("rev-parse", "feature").trimmingCharacters(in: .whitespacesAndNewlines) == target.hash)
            #expect(rig.manager.lastAlert == nil)
        }
    }

    @Test
    func newBranchWithCheckoutAndOverwriteResetsAndSwitches() async throws {
        try await withTempDir { directory in
            let rig = try await GitLogCommitActionsRig.make(in: directory)
            defer { rig.close() }
            let target = try rig.commit("Main work")
            rig.recorder.branchAnswer = BranchesPopupBranchDialogResult(name: "feature", checkout: true, overwrite: true)

            await rig.actions.newBranch(target)

            #expect(try await rig.currentBranchName() == "feature")
            #expect(try await rig.head() == target.hash)
        }
    }

    @Test
    func newBranchRejectsAnExistingNameWithoutOverwriteAndAnInvalidName() async throws {
        try await withTempDir { directory in
            let rig = try await GitLogCommitActionsRig.make(in: directory)
            defer { rig.close() }
            let target = try rig.commit("Main work")
            rig.recorder.branchAnswer = BranchesPopupBranchDialogResult(name: "feature", checkout: false)

            await rig.actions.newBranch(target)

            #expect(rig.manager.lastAlert?.title == "Invalid Branch Name")
            #expect(rig.manager.lastAlert?.message == "Branch 'feature' already exists")

            rig.recorder.branchAnswer = BranchesPopupBranchDialogResult(name: "bad name", checkout: false)
            await rig.actions.newBranch(target)

            #expect(rig.manager.lastAlert?.message == "Branch name is not valid")
            #expect(try await rig.fixture.run("branch", "--format=%(refname:short)").split(separator: "\n").count == 2)
        }
    }

    @Test
    func newBranchReportsGitFailures() async throws {
        try await withTempDir { directory in
            let rig = try await GitLogCommitActionsRig.make(in: directory)
            defer { rig.close() }
            let target = try rig.commit("Feature work")
            rig.recorder.branchAnswer = BranchesPopupBranchDialogResult(name: "main", checkout: false, overwrite: true)

            await rig.actions.newBranch(target)

            #expect(rig.manager.lastAlert?.title == "Failed to create branch 'main'")
            #expect(try await rig.currentBranchName() == "main")
        }
    }

    @Test
    func cancellingTheBranchDialogDoesNothing() async throws {
        try await withTempDir { directory in
            let rig = try await GitLogCommitActionsRig.make(in: directory)
            defer { rig.close() }
            rig.recorder.branchAnswer = nil

            await rig.actions.newBranch(try rig.commit("Feature work"))

            #expect(rig.recorder.branchRequests.count == 1)
            #expect(rig.manager.lastAlert == nil)
            #expect(try await rig.currentBranchName() == "main")
        }
    }

    @Test
    func checkoutRevisionAsksForConfirmationAndDeclineSkipsGit() async throws {
        try await withTempDir { directory in
            let rig = try await GitLogCommitActionsRig.make(in: directory)
            defer { rig.close() }
            rig.recorder.confirmAnswer = false

            await rig.actions.checkoutRevision(try rig.commit("Feature work"))

            #expect(rig.recorder.confirmations == [[
                GitLogCommitActions.detachedHeadTitle,
                GitLogCommitActions.detachedHeadMessage
            ]])
            #expect(GitLogCommitActions.detachedHeadMessage.contains("detached HEAD state after checkout"))
            #expect(try await rig.currentBranchName() == "main")
        }
    }

    @Test
    func checkoutRevisionDetachesHead() async throws {
        try await withTempDir { directory in
            let rig = try await GitLogCommitActionsRig.make(in: directory)
            defer { rig.close() }
            let target = try rig.commit("Feature work")

            await rig.actions.checkoutRevision(target)

            #expect(try await rig.currentBranchName() == "HEAD")
            #expect(try await rig.head() == target.hash)
            #expect(rig.manager.lastAlert == nil)
            #expect(rig.model.selectedHash == target.hash)
        }
    }

    @Test
    func checkoutRevisionReportsLocalChangesThatWouldBeOverwritten() async throws {
        try await withTempDir { directory in
            let rig = try await GitLogCommitActionsRig.make(in: directory)
            defer { rig.close() }
            let initial = try rig.commit("initial")
            try rig.fixture.write("a.txt", "dirty\n")

            await rig.actions.checkoutRevision(initial)

            #expect(rig.manager.lastAlert?.title == "Failed to check out '\(initial.shortHash)'")
            #expect(try await rig.currentBranchName() == "main")
        }
    }

    @Test
    func checkoutBranchSwitchesToTheLocalBranchOfTheCommit() async throws {
        try await withTempDir { directory in
            let rig = try await GitLogCommitActionsRig.make(in: directory)
            defer { rig.close() }
            let target = try rig.commit("Feature work")
            #expect(rig.actions.checkoutBranchNames(for: target) == ["feature"])
            #expect(rig.actions.checkoutBranchNames(for: try rig.commit("Main work")).isEmpty)

            await rig.actions.checkoutBranch("feature", of: target)

            #expect(try await rig.currentBranchName() == "feature")
        }
    }

    @Test
    func checkoutBranchReportsFailures() async throws {
        try await withTempDir { directory in
            let rig = try await GitLogCommitActionsRig.make(in: directory)
            defer { rig.close() }

            await rig.actions.checkoutBranch("missing", of: try rig.commit("Feature work"))

            #expect(rig.manager.lastAlert?.title == "Failed to check out 'missing'")
        }
    }

    @Test
    func cherryPickAppliesTheCommitAndReportsSuccess() async throws {
        try await withTempDir { directory in
            let rig = try await GitLogCommitActionsRig.make(in: directory)
            defer { rig.close() }
            let target = try rig.commit("Feature work")

            await rig.actions.cherryPick(target)

            #expect(try rig.fixture.read("f.txt") == "feature\n")
            let notification = try #require(rig.recorder.notifications.first)
            #expect(notification.title == "Cherry-pick successful")
            #expect(notification.description == "\(target.shortHash) Feature work")
            #expect(rig.model.commits.filter { $0.subject == "Feature work" }.count == 2)
            #expect(rig.recorder.presented.isEmpty)
        }
    }

    @Test
    func cherryPickOfAnAppliedCommitReportsNothingToDo() async throws {
        try await withTempDir { directory in
            let rig = try await GitLogCommitActionsRig.make(in: directory)
            defer { rig.close() }
            let target = try rig.commit("Feature work")
            await rig.actions.cherryPick(target)
            let head = try await rig.head()

            await rig.actions.cherryPick(target)

            let notification = try #require(rig.recorder.notifications.last)
            #expect(notification.title == "Nothing to cherry-pick")
            #expect(notification.description == "All changes from \(target.shortHash) have already been applied")
            #expect(try await rig.head() == head)
        }
    }

    @Test
    func conflictingCherryPickPresentsTheMergeToolAndNotifies() async throws {
        try await withTempDir { directory in
            let rig = try await GitLogCommitActionsRig.make(in: directory, scenario: .conflict)
            defer { rig.close() }
            let target = try rig.commit("Feature work")

            await rig.actions.cherryPick(target)

            #expect(try await rig.fixture.run("rev-parse", "-q", "--verify", "CHERRY_PICK_HEAD").isEmpty == false)
            #expect(try await rig.fixture.unmergedPaths() == ["src/main.swift"])
            #expect(rig.recorder.presented.count == 1)
            #expect(rig.recorder.presented.first === rig.workspace)
            let notification = try #require(rig.recorder.notifications.first)
            #expect(notification.title == "Cherry-pick was performed with conflicts")
            #expect(notification.description.hasPrefix("\(target.shortHash) Feature work"))
            #expect(notification.description.contains("There are unresolved conflicts in the working tree."))
            #expect(notification.actionTitle == "Resolve…")
            let entries = MergeConflictsCenter.shared.entries(for: rig.manager.workspaceURL)
            #expect(entries.isEmpty == false)
            try await eventually { rig.manager.changedFiles.contains { $0.fileURL.lastPathComponent == "main.swift" } }

            notification.action()
            #expect(rig.recorder.presented.count == 2)
        }
    }

    @Test
    func cherryPickIsRefusedWhileAnotherCherryPickIsInProgress() async throws {
        try await withTempDir { directory in
            let rig = try await GitLogCommitActionsRig.make(in: directory, scenario: .conflict)
            defer { rig.close() }
            let target = try rig.commit("Feature work")
            await rig.actions.cherryPick(target)
            rig.recorder.presented.removeAll()

            await rig.actions.cherryPick(target)

            #expect(rig.manager.lastAlert?.title == "Cherry-pick failed")
            #expect(rig.manager.lastAlert?.message == "Cannot cherry-pick during cherry-pick")
            #expect(rig.recorder.presented.isEmpty)
        }
    }

    @Test
    func cherryPickOfAnUnknownCommitStillReportsTheFailureWhenThePublishedCheckFails() async throws {
        try await withTempDir { directory in
            let rig = try await GitLogCommitActionsRig.make(in: directory)
            defer { rig.close() }
            let head = try await rig.head()
            let unknown = GitLogCommit(
                hash: String(repeating: "0", count: 40),
                parents: [],
                authorName: "Nobody",
                authorEmail: "nobody@dreamder.test",
                date: Date(timeIntervalSince1970: 0),
                refs: [],
                subject: "Missing"
            )

            var outcome: GitCherryPickOutcome?
            do {
                outcome = try await rig.manager.gitLogCherryPick(unknown)
            } catch {
                outcome = nil
            }
            #expect(outcome == nil)
            await rig.actions.cherryPick(unknown)

            #expect(rig.manager.lastAlert?.title == "Cherry-pick failed")
            #expect(rig.recorder.notifications.isEmpty)
            #expect(try await rig.head() == head)
        }
    }

    @Test
    func newBranchReportsAnEmptyName() async throws {
        try await withTempDir { directory in
            let rig = try await GitLogCommitActionsRig.make(in: directory)
            defer { rig.close() }
            rig.recorder.branchAnswer = BranchesPopupBranchDialogResult(name: "   ", checkout: false)

            await rig.actions.newBranch(try rig.commit("Main work"))

            #expect(rig.manager.lastAlert?.title == "Invalid Branch Name")
            #expect(rig.manager.lastAlert?.message == "Branch name cannot be empty")
        }
    }

    @Test
    func nameRejectionAcceptsValidNamesAndOverwrittenExistingOnes() {
        #expect(GitLogCommitActions.nameRejection(.valid, name: "topic", overwrite: false) == nil)
        #expect(GitLogCommitActions.nameRejection(.valid, name: "topic", overwrite: true) == nil)
        #expect(GitLogCommitActions.nameRejection(.exists, name: "topic", overwrite: true) == nil)
        #expect(GitLogCommitActions.nameRejection(.exists, name: "topic", overwrite: false) == "Branch 'topic' already exists")
        #expect(GitLogCommitActions.nameRejection(.empty, name: "", overwrite: true) == "Branch name cannot be empty")
        #expect(GitLogCommitActions.nameRejection(.invalid, name: "a b", overwrite: true) == "Branch name is not valid")
    }

    @Test
    func liveSeamsRouteDialogsThroughTheHeadlessHost() {
        let live = GitLogCommitSeams.live(pasteboard: SystemPasteboard(board: InMemoryPasteboard()))
        let before = DreamderHeadless.suppressedModals.count
        let request = BranchesPopupBranchDialogRequest(
            title: "Live New Branch",
            message: "m",
            initialName: "",
            existingNames: [],
            showsCheckout: true,
            showsUnsetUpstream: false,
            confirmTitle: "Create"
        )

        #expect(live.tagDialog(GitLogTagRequest(commit: "livehash")) == nil)
        #expect(live.branchDialog(request) == nil)
        #expect(live.confirmDetachedCheckout("Live Detached Confirm", "m") == false)

        let added = DreamderHeadless.suppressedModals.dropFirst(before)
        #expect(added.contains("Create New Tag On livehash"))
        #expect(added.contains("Live New Branch"))
        #expect(added.contains("Live Detached Confirm"))
    }

    @Test
    func liveCopyRevisionWritesToTheInjectedPasteboard() {
        let board = InMemoryPasteboard()
        let live = GitLogCommitSeams.live(pasteboard: SystemPasteboard(board: board))

        live.copyRevision("0123abcd")

        #expect(board.plainText == "0123abcd")
    }

    @Test
    func liveNotifyForwardsToTheNotificationManagerWithItsAction() async throws {
        let title = "Live Tag \(UUID().uuidString)"
        let live = GitLogCommitSeams.live(pasteboard: SystemPasteboard(board: InMemoryPasteboard()))
        var confirmed = 0

        live.notify(BranchesPopupNotificationRequest(
            title: title,
            description: "Created tag.",
            actionTitle: "OK",
            action: { confirmed += 1 }
        ))

        try await eventually { NotificationManager.shared.notifications.contains { $0.title == title } }
        let notification = try #require(NotificationManager.shared.notifications.first { $0.title == title })
        #expect(notification.description == "Created tag.")
        notification.action()
        #expect(confirmed == 1)
        NotificationManager.shared.dismissNotification(notification)
    }

    @Test
    func livePresentConflictsOpensTheConflictsWindowOfTheWorkspace() async throws {
        try await withTempDir { directory in
            let rig = try await GitLogCommitActionsRig.make(in: directory, scenario: .conflict)
            defer { rig.close() }
            let live = GitLogCommitSeams.live(pasteboard: SystemPasteboard(board: InMemoryPasteboard()))

            live.presentConflicts(rig.workspace)
            let window = MergeToolPresenter.conflictsWindow
            let model = MergeToolPresenter.conflictsModel(for: rig.workspace)
            window?.close()

            #expect(window != nil)
            #expect(model != nil)
        }
    }

    @Test
    func environmentValueCanBeReplaced() {
        var values = EnvironmentValues()
        let recorder = GitLogCommitActionsRecorder()

        values.gitLogCommitSeams = recorder.seams()
        values.gitLogCommitSeams.copyRevision("abc")

        #expect(recorder.copied == ["abc"])
    }
}
