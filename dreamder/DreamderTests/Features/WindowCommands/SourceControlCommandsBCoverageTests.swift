import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct SourceControlCommandsBCoverageTests {
    @MainActor
    private final class Harness {
        let manager: SourceControlManager
        let workspace: WorkspaceDocument
        let controller: DreamderWindowController
        let recorder = CommandsBSelectorRecorder()
        var conflictPresentations = 0
        var prompts: [String] = []
        var branchName: String?

        init(root: URL) {
            manager = SourceControlManager(workspaceURL: root, editorManager: EditorManager())
            workspace = WorkspaceDocument()
            workspace.sourceControlManager = manager
            controller = makeCommandsBWindowController(workspace: workspace)
        }

        func close() {
            controller.window?.close()
        }

        func menu(hasUnmergedFiles: Bool = false) -> SourceControlMenu {
            SourceControlMenu(
                windowController: controller,
                hasUnmergedFiles: hasUnmergedFiles,
                sendAction: { [recorder] in recorder.record($0) },
                presentConflicts: { [weak self] _ in self?.conflictPresentations += 1 },
                runModal: { [weak self] alert in self?.answer(alert) ?? .abort }
            )
        }

        func answer(_ alert: NSAlert) -> NSApplication.ModalResponse {
            prompts.append(alert.messageText)
            guard let branchName else { return .alertSecondButtonReturn }
            (alert.accessoryView as? NSTextField)?.stringValue = branchName
            return .alertFirstButtonReturn
        }

        func ghostChange(in root: URL) -> GitChangedFile {
            GitChangedFile(
                status: .modified,
                stagedStatus: .none,
                fileURL: root.appending(path: "ghost.txt"),
                originalFilename: nil
            )
        }
    }

    private func makeClonePair(in dir: URL) async throws -> (origin: GitMergeFixture, clone: GitMergeFixture) {
        let originRoot = dir.appending(path: "origin")
        try FileManager.default.createDirectory(at: originRoot, withIntermediateDirectories: true)
        let origin = try await GitMergeFixture(root: originRoot)
        try origin.write("a.txt", "one\n")
        try await origin.commit("initial")
        let cloneRoot = dir.appending(path: "clone")
        try await origin.run(
            "clone",
            "-q",
            originRoot.path(percentEncoded: false),
            cloneRoot.path(percentEncoded: false)
        )
        let clone = GitMergeFixture(existing: cloneRoot)
        try await clone.run("config", "user.email", "clone@dreamder.test")
        try await clone.run("config", "user.name", "Clone")
        try await clone.run("config", "commit.gpgsign", "false")
        return (origin, clone)
    }

    private func makeRepository(in dir: URL) async throws -> GitMergeFixture {
        let fixture = try await GitMergeFixture(root: dir)
        try fixture.write("a.txt", "one\n")
        try await fixture.commit("initial")
        return fixture
    }

    private func head(_ fixture: GitMergeFixture) async -> String? {
        let output = try? await fixture.run("rev-parse", "--abbrev-ref", "HEAD")
        return output?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func revision(_ fixture: GitMergeFixture, _ name: String) async -> String? {
        let output = try? await fixture.run("rev-parse", name)
        return output?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Test
    func branchesAndConflictsActionsUseTheirSeams() throws {
        try withTempDir { dir in
            let harness = Harness(root: dir)
            defer { harness.close() }
            let menu = harness.menu(hasUnmergedFiles: true)

            menu.showBranches()
            menu.resolveConflicts()

            #expect(harness.recorder.selectors == [#selector(DreamderWindowController.showGitBranches(_:))])
            #expect(harness.conflictPresentations == 1)
        }
    }

    @Test
    func resolveConflictsDoesNothingWithoutAWorkspace() {
        var presented = 0
        let menu = SourceControlMenu(
            windowController: nil,
            hasUnmergedFiles: true,
            presentConflicts: { _ in presented += 1 }
        )

        menu.resolveConflicts()

        #expect(presented == 0)
    }

    @Test
    func defaultSeamsReachTheAlertRunnerResponderChainAndMergeTool() {
        let menu = SourceControlMenu(windowController: nil, hasUnmergedFiles: false)
        let alert = NSAlert()
        alert.messageText = "SourceControlCommands default runner \(UUID().uuidString)"
        let workspace = WorkspaceDocument()

        menu.sendAction(Selector(("dreamderCommandsBNoSuchAction:")))
        let response = menu.runModal(alert)
        menu.presentConflicts(workspace)

        #expect(response == .abort)
        #expect(DreamderHeadless.suppressedModals.contains(alert.messageText))
        #expect(MergeToolPresenter.conflictsModel(for: workspace) == nil)
    }

    @Test
    func commitActionShowsTheCommitToolWindow() throws {
        try withTempDir { dir in
            let harness = Harness(root: dir)
            defer { harness.close() }
            harness.workspace.toolWindowManager.hideAll()
            #expect(harness.workspace.toolWindowManager.isVisible(.commit) == false)

            harness.menu().showCommit()

            #expect(harness.workspace.toolWindowManager.isVisible(.commit))
        }
    }

    @Test
    func sheetActionsPresentTheirSheets() throws {
        try withTempDir { dir in
            let harness = Harness(root: dir)
            defer { harness.close() }
            let menu = harness.menu()
            let manager = harness.manager

            menu.showPush()
            menu.showPull()
            menu.showFetchChanges()
            menu.addExistingRemote()

            #expect(manager.pushSheetIsPresented)
            #expect(manager.pullSheetIsPresented)
            #expect(manager.fetchSheetIsPresented)
            #expect(manager.addExistingRemoteSheetIsPresented)
        }
    }

    @Test
    func actionsWithoutAWorkspaceDoNothing() throws {
        let controller = makeCommandsBWindowController(workspace: nil)
        defer { controller.window?.close() }
        let menu = SourceControlMenu(windowController: controller, hasUnmergedFiles: false)

        menu.showCommit()
        menu.showPush()
        menu.showPull()
        menu.showFetchChanges()
        menu.addExistingRemote()
        menu.updateProject()
        menu.fetch()
        menu.newBranch()
        menu.stageAll()
        menu.unstageAll()
        menu.stash()
        menu.discardAll()

        #expect(menu.sourceControlManager == nil)
        #expect(controller.workspace == nil)
    }

    @Test
    func emptyWorkingTreeRaisesTheNoChangesAlerts() throws {
        try withTempDir { dir in
            let harness = Harness(root: dir)
            defer { harness.close() }
            let menu = harness.menu()
            let manager = harness.manager

            menu.stageAll()
            menu.unstageAll()
            menu.stash()
            menu.discardAll()

            #expect(manager.noChangesToStageAlertIsPresented)
            #expect(manager.noChangesToUnstageAlertIsPresented)
            #expect(manager.noChangesToStashAlertIsPresented)
            #expect(manager.noChangesToDiscardAlertIsPresented)
            #expect(manager.stashSheetIsPresented == false)
            #expect(manager.discardAllAlertIsPresented == false)
        }
    }

    @Test
    func changedWorkingTreeOpensTheStashAndDiscardPrompts() throws {
        try withTempDir { dir in
            let harness = Harness(root: dir)
            defer { harness.close() }
            let menu = harness.menu()
            let manager = harness.manager
            manager.changedFiles = [harness.ghostChange(in: dir)]

            menu.stash()
            menu.discardAll()

            #expect(manager.stashSheetIsPresented)
            #expect(manager.discardAllAlertIsPresented)
            #expect(manager.noChangesToStashAlertIsPresented == false)
            #expect(manager.noChangesToDiscardAlertIsPresented == false)
        }
    }

    @Test
    func failingOperationsReportAlerts() async throws {
        try await withTempDir { dir in
            let harness = Harness(root: dir)
            defer { harness.close() }
            let menu = harness.menu()
            let manager = harness.manager
            manager.changedFiles = [harness.ghostChange(in: dir)]

            menu.stageAll()
            try await eventually { manager.lastAlert?.title == "Failed To Stage Changes" }

            menu.unstageAll()
            try await eventually { manager.lastAlert?.title == "Failed To Unstage Changes" }

            menu.updateProject()
            try await eventually { manager.lastAlert?.title == "Failed to update project" }

            menu.fetch()
            try await eventually { manager.lastAlert?.title == "Failed to fetch" }

            harness.branchName = "topic"
            menu.newBranch()
            try await eventually { manager.lastAlert?.title == "Failed to create branch" }
            #expect(harness.prompts == ["New Branch"])
        }
    }

    @Test
    func stageAndUnstageAllMoveEveryChangeThroughTheIndex() async throws {
        try await withTempDir { dir in
            let fixture = try await makeRepository(in: dir)
            try fixture.write("a.txt", "two\n")
            try fixture.write("b.txt", "new\n")
            let harness = Harness(root: dir)
            defer { harness.close() }
            let menu = harness.menu()
            let manager = harness.manager
            await manager.refreshAllChangedFiles()
            #expect(manager.changedFiles.count == 2)

            menu.stageAll()
            try await eventually { (try? await fixture.stagedPaths()) == ["a.txt", "b.txt"] }
            #expect(manager.lastAlert == nil)

            menu.unstageAll()
            try await eventually { (try? await fixture.stagedPaths()) == [] }
            #expect(manager.lastAlert == nil)
        }
    }

    @Test
    func newBranchCreatesAndChecksOutTheEnteredName() async throws {
        try await withTempDir { dir in
            let fixture = try await makeRepository(in: dir)
            let harness = Harness(root: dir)
            defer { harness.close() }
            let menu = harness.menu()
            harness.branchName = "  topic  "

            menu.newBranch()

            try await eventually { await head(fixture) == "topic" }
            #expect(harness.prompts == ["New Branch"])
            try await eventually { harness.manager.currentBranch?.name == "topic" }
        }
    }

    @Test
    func newBranchIgnoresCancelledAndBlankNames() async throws {
        try await withTempDir { dir in
            let fixture = try await makeRepository(in: dir)
            let harness = Harness(root: dir)
            defer { harness.close() }
            let menu = harness.menu()

            menu.newBranch()
            harness.branchName = "   "
            menu.newBranch()
            try await Task.sleep(for: .milliseconds(150))

            #expect(harness.prompts == ["New Branch", "New Branch"])
            #expect(await head(fixture) == "main")
            #expect(harness.manager.lastAlert == nil)
        }
    }

    @Test
    func updateProjectPullsUpstreamCommits() async throws {
        try await withTempDir { dir in
            let pair = try await makeClonePair(in: dir)
            try pair.origin.write("new.txt", "from origin\n")
            try await pair.origin.commit("second")
            let harness = Harness(root: pair.clone.root)
            defer { harness.close() }

            harness.menu().updateProject()

            try await eventually { pair.clone.exists("new.txt") }
            #expect(harness.manager.lastAlert == nil)
        }
    }

    @Test
    func fetchUpdatesRemoteTrackingBranches() async throws {
        try await withTempDir { dir in
            let pair = try await makeClonePair(in: dir)
            try pair.origin.write("new.txt", "from origin\n")
            try await pair.origin.commit("second")
            let harness = Harness(root: pair.clone.root)
            defer { harness.close() }
            let originHead = await revision(pair.origin, "HEAD")
            #expect(originHead != nil)

            harness.menu().fetch()

            try await eventually { await revision(pair.clone, "origin/main") == originHead }
            #expect(pair.clone.exists("new.txt") == false)
            #expect(harness.manager.lastAlert == nil)
        }
    }

    @Test
    func menuRendersEveryStateVariant() async throws {
        try await withTempDir { dir in
            let harness = Harness(root: dir)
            defer { harness.close() }
            let detachedController = makeCommandsBWindowController(workspace: nil)
            defer { detachedController.window?.close() }

            let detached = HostedViewFixture.host(size: NSSize(width: 600, height: 800)) {
                VStack { SourceControlMenu(windowController: detachedController, hasUnmergedFiles: false) }
            }
            defer { detached.close() }
            try await detached.settle(.milliseconds(100))
            #expect(detached.renders())

            let attached = HostedViewFixture.host(size: NSSize(width: 600, height: 800)) {
                VStack { harness.menu(hasUnmergedFiles: true) }
            }
            defer { attached.close() }
            try await attached.settle(.milliseconds(100))
            #expect(attached.renders())

            #expect(HostedView.pixelsDiffer(detached.snapshot(), attached.snapshot()))
        }
    }
}
