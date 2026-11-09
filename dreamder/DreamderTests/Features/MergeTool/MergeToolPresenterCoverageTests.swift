import AppKit
import Foundation
import Testing
@testable import Dreamder

extension MergeAutomationTests {
    private static let presenterConfigPath = "app/config.txt"

    private func presenterWorkspace(_ root: URL) -> WorkspaceDocument {
        let document = WorkspaceDocument()
        document.sourceControlManager = SourceControlManager(workspaceURL: root, editorManager: EditorManager())
        return document
    }

    private func presenterWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        return window
    }

    private func presenterController(window: NSWindow, workspace: WorkspaceDocument) -> DreamderWindowController {
        let controller = DreamderWindowController(window: window, workspace: nil)
        controller.workspace = workspace
        return controller
    }

    @Test
    func showingWindowsForAWorkspaceWithoutSourceControlDoesNothing() {
        let conflictsKey = MergeToolPresenter.lastConflictsKey
        let revisionsKey = MergeToolPresenter.lastRevisionsKey

        MergeToolPresenter.showConflicts(workspace: WorkspaceDocument())
        MergeToolPresenter.showMergeRevisions(workspace: WorkspaceDocument(), path: "a.txt")

        #expect(MergeToolPresenter.lastConflictsKey == conflictsKey)
        #expect(MergeToolPresenter.lastRevisionsKey == revisionsKey)
        #expect(MergeToolPresenter.conflictsModel(for: WorkspaceDocument()) == nil)
    }

    @Test
    func showingMergeRevisionsWithoutAPathDoesNothing() {
        let workspace = presenterWorkspace(URL(filePath: "/Users/dreamder-test/presenter"))
        let revisionsKey = MergeToolPresenter.lastRevisionsKey

        MergeToolPresenter.showMergeRevisions(workspace: workspace, path: "")

        #expect(MergeToolPresenter.lastRevisionsKey == revisionsKey)
    }

    @Test
    func showingTheConflictsDialogTwiceReusesItsWindow() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.mergeConflict(in: dir)
            let workspace = presenterWorkspace(dir)

            MergeToolPresenter.showConflicts(workspace: workspace)
            let window = try #require(MergeToolPresenter.conflictsWindow)
            let model = try #require(MergeToolPresenter.conflictsModel(for: workspace))
            defer { window.close() }

            MergeToolPresenter.showConflicts(workspace: workspace)

            #expect(MergeToolPresenter.conflictsWindow === window)
            #expect(MergeToolPresenter.conflictsModel(for: workspace) === model)
            #expect(MergeToolPresenter.lastConflictsKey == MergeConflictsCenter.workspaceKey(dir))
            try await eventually { model.entries.count == 2 }
        }
    }

    @Test
    func showingMergeRevisionsAgainReloadsOnlyAnUneditedResult() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.mergeConflict(in: dir)
            let workspace = presenterWorkspace(dir)

            MergeToolPresenter.showMergeRevisions(workspace: workspace, path: Self.presenterConfigPath)
            let window = try #require(MergeToolPresenter.revisionsWindow)
            let model = try #require(MergeToolPresenter.revisionsModel)
            defer { window.close() }
            try await eventually { model.isLoading == false && model.merge != nil }
            let firstRevision = model.contentRevision

            MergeToolPresenter.showMergeRevisions(workspace: workspace, path: Self.presenterConfigPath)

            #expect(MergeToolPresenter.revisionsWindow === window)
            #expect(MergeToolPresenter.lastRevisionsPath == Self.presenterConfigPath)
            try await eventually { model.contentRevision > firstRevision }
            let reloadedRevision = model.contentRevision

            model.userEditedResult("draft\n")
            MergeToolPresenter.showMergeRevisions(workspace: workspace, path: Self.presenterConfigPath)
            try await Task.sleep(for: .milliseconds(300))

            #expect(model.contentRevision == reloadedRevision)
            #expect(model.isResultEdited)
            #expect(model.resultText == "draft\n")
        }
    }

    @Test
    func closingTheMergeRevisionsWindowRefreshesTheConflictList() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.mergeConflict(in: dir)
            let workspace = presenterWorkspace(dir)

            MergeToolPresenter.showMergeRevisions(workspace: workspace, path: Self.presenterConfigPath)
            let window = try #require(MergeToolPresenter.revisionsWindow)
            #expect(MergeConflictsCenter.shared.state(for: dir) == nil)

            window.close()

            try await eventually { MergeConflictsCenter.shared.state(for: dir) != nil }
            #expect(
                MergeConflictsCenter.shared.entries(for: dir).map(\.path) == [Self.presenterConfigPath, "docs/notes.txt"]
            )
        }
    }

    @Test
    func activeWorkspaceFollowsKeyThenMainThenOrderedWindows() {
        let first = WorkspaceDocument()
        let second = WorkspaceDocument()
        let third = WorkspaceDocument()
        let firstWindow = presenterWindow()
        let secondWindow = presenterWindow()
        let thirdWindow = presenterWindow()
        let plainWindow = presenterWindow()
        let controllers = [
            presenterController(window: firstWindow, workspace: first),
            presenterController(window: secondWindow, workspace: second),
            presenterController(window: thirdWindow, workspace: third)
        ]

        withExtendedLifetime(controllers) {
            let key = MergeToolPresenter.activeWorkspace(
                keyWindow: firstWindow,
                mainWindow: secondWindow,
                orderedWindows: [thirdWindow]
            )
            let main = MergeToolPresenter.activeWorkspace(
                keyWindow: plainWindow,
                mainWindow: secondWindow,
                orderedWindows: [thirdWindow]
            )
            let ordered = MergeToolPresenter.activeWorkspace(
                keyWindow: nil,
                mainWindow: plainWindow,
                orderedWindows: [plainWindow, thirdWindow]
            )
            let unplaced = MergeToolPresenter.activeWorkspace(
                keyWindow: nil,
                mainWindow: nil,
                orderedWindows: [plainWindow]
            )
            let empty = MergeToolPresenter.activeWorkspace(keyWindow: nil, mainWindow: nil, orderedWindows: [])

            #expect(key === first)
            #expect(main === second)
            #expect(ordered === third)
            #expect(unplaced == nil)
            #expect(empty == nil)
        }
    }

    @Test
    func showingConflictsForTheActiveWorkspaceUsesTheResolvedWorkspace() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.mergeConflict(in: dir)
            let workspace = presenterWorkspace(dir)
            let conflictsKey = MergeToolPresenter.lastConflictsKey

            MergeToolPresenter.showConflictsForActiveWorkspace(resolve: { nil })
            #expect(MergeToolPresenter.lastConflictsKey == conflictsKey)

            MergeToolPresenter.showConflictsForActiveWorkspace(resolve: { workspace })
            let window = try #require(MergeToolPresenter.conflictsWindow)
            defer { window.close() }
            #expect(MergeToolPresenter.conflictsModel(for: workspace) != nil)
            #expect(MergeToolPresenter.lastConflictsKey == MergeConflictsCenter.workspaceKey(dir))
        }
    }

    @Test
    func showingConflictsForTheActiveWorkspaceWithoutArgumentsResolvesThroughTheWindows() {
        if let active = MergeToolPresenter.activeWorkspace(), active.sourceControlManager != nil {
            return
        }
        let conflictsKey = MergeToolPresenter.lastConflictsKey

        MergeToolPresenter.showConflictsForActiveWorkspace()

        #expect(MergeToolPresenter.lastConflictsKey == conflictsKey)
    }

    @Test
    func centerOpensTheConflictsDialogWhenConflictsAppearInAMonitoredWorkspace() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture(root: dir)
            try fixture.write("f.txt", "one\ntwo\nthree\n")
            try await fixture.commit("base")
            try await fixture.run("checkout", "-q", "-b", "feature")
            try fixture.write("f.txt", "one\nfeature\nthree\n")
            try await fixture.commit("feature")
            try await fixture.run("checkout", "-q", "main")
            try fixture.write("f.txt", "one\nmain\nthree\n")
            try await fixture.commit("main")

            let workspace = presenterWorkspace(dir)
            let manager = try #require(workspace.sourceControlManager)
            NSDocumentController.shared.addDocument(workspace)
            defer {
                for _ in 0..<8 {
                    guard let window = MergeToolPresenter.conflictsWindow else { break }
                    window.close()
                }
                NSDocumentController.shared.removeDocument(workspace)
            }
            let center = MergeConflictsCenter()

            center.monitor(manager)
            center.monitor(manager)
            try await eventually { center.state(for: dir) != nil }
            #expect(center.hasConflicts(rootURL: dir) == false)
            #expect(MergeToolPresenter.conflictsModel(for: workspace) == nil)

            _ = try await fixture.runIgnoringFailure("merge", "feature")
            manager.changedFiles = [
                GitChangedFile(
                    status: .unmerged,
                    stagedStatus: .unmerged,
                    fileURL: dir.appending(path: "f.txt"),
                    originalFilename: nil
                )
            ]

            try await eventually { center.hasConflicts(rootURL: dir) }
            try await eventually { MergeToolPresenter.conflictsModel(for: workspace) != nil }
            #expect(center.entries(for: dir).map(\.path) == ["f.txt"])
        }
    }

    @Test
    func installForwardsNotificationsToTheCommandQueue() async throws {
        let center = NotificationCenter()
        MergeAutomation.install(center: center)

        center.post(name: MergeAutomation.notification, object: "target:/tmp/dreamder-installed")
        try await eventually { MergeAutomation.targetPath == "/tmp/dreamder-installed" }

        center.post(name: MergeAutomation.notification, object: nil)
        center.post(name: MergeAutomation.notification, object: "target:")
        try await eventually { MergeAutomation.targetPath.isEmpty }

        MergeAutomation.install()
    }

    @Test
    func workspaceLookupFallsBackToTheKeyWindowAndThenToTheFirstDocument() {
        let keyWorkspace = WorkspaceDocument()
        let keyWindow = presenterWindow()
        let keyController = presenterController(window: keyWindow, workspace: keyWorkspace)
        let plainWindow = presenterWindow()
        let emptyWindow = presenterWindow()
        let emptyController = DreamderWindowController(window: emptyWindow, workspace: nil)

        withExtendedLifetime((keyController, emptyController)) {
            let expectedFirst = NSDocumentController.shared.documents.compactMap { $0 as? WorkspaceDocument }.first

            #expect(MergeAutomation.workspace(for: "/Users/dreamder-test/no-such-workspace", keyWindow: keyWindow) === keyWorkspace)
            #expect(MergeAutomation.workspace(for: "", keyWindow: keyWindow) === keyWorkspace)
            #expect(MergeAutomation.workspace(for: "", keyWindow: plainWindow) === expectedFirst)
            #expect(MergeAutomation.workspace(for: "", keyWindow: emptyWindow) === expectedFirst)
            #expect(MergeAutomation.workspace(for: "", keyWindow: nil) === expectedFirst)
        }
    }
}
