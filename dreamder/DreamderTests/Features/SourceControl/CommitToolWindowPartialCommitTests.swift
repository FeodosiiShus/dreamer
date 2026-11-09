import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct CommitToolWindowPartialCommitTests {
    private func numbered(replacing replacements: [Int: String] = [:]) -> String {
        (1...20).map { "\(replacements[$0] ?? "l\($0)")\n" }.joined()
    }

    private func makeRepo(_ directory: URL) async throws -> (GitMergeFixture, SourceControlManager) {
        let fixture = try await GitMergeFixture(root: directory)
        try fixture.write("a.txt", numbered())
        try fixture.write("b.txt", "b\n")
        try await fixture.commit("initial")
        return (fixture, SourceControlManager(workspaceURL: directory, editorManager: EditorManager()))
    }

    private func file(_ name: String, in manager: SourceControlManager) throws -> GitChangedFile {
        try #require(manager.changedFiles.first { $0.fileURL.lastPathComponent == name })
    }

    private func changedNames(_ manager: SourceControlManager) -> [String] {
        manager.changedFiles.map(\.fileURL.lastPathComponent).sorted()
    }

    private func hunkCount(_ fixture: GitMergeFixture, _ arguments: String...) async throws -> Int {
        let output = try await fixture.runAllowingFailure(arguments)
        return PartialCommitDiffParser.hunks(inDiff: output).count
    }

    private func expandedModel(
        _ manager: SourceControlManager,
        file name: String = "a.txt"
    ) async throws -> (CommitToolWindowViewModel, GitChangedFile) {
        let model = CommitToolWindowViewModel()
        let changed = try file(name, in: manager)
        await model.toggleExpansion(of: changed, using: manager)
        return (model, changed)
    }

    @Test
    func supportsHunksOnlyForPlainModifiedTrackedFiles() {
        func status(_ worktree: GitStatus, _ staged: GitStatus) -> Bool {
            CommitToolWindowViewModel.supportsHunks(
                GitChangedFile(
                    status: worktree,
                    stagedStatus: staged,
                    fileURL: URL(fileURLWithPath: "/tmp/repo/f.txt"),
                    originalFilename: nil
                )
            )
        }

        #expect(status(.modified, .none))
        #expect(status(.none, .modified))
        #expect(status(.modified, .modified))
        #expect(status(.none, .none) == false)
        #expect(status(.modified, .added) == false)
        #expect(status(.deleted, .none) == false)
        #expect(status(.none, .deleted) == false)
        #expect(status(.modified, .renamed) == false)
        #expect(status(.untracked, .none) == false)
        #expect(status(.unmerged, .none) == false)
        #expect(status(.fileTypeChange, .none) == false)
    }

    @Test
    func expandingAFileLoadsItsHunksAndCollapsingKeepsThem() async throws {
        try await withTempDir { directory in
            let (fixture, manager) = try await makeRepo(directory)
            try fixture.write("a.txt", numbered(replacing: [2: "L2", 10: "L10", 19: "L19"]))
            await manager.refreshAllChangedFiles()
            let (model, changed) = try await expandedModel(manager)

            #expect(model.canExpand(changed))
            #expect(model.isExpanded(changed))
            let hunks = model.hunks(for: changed)
            #expect(hunks.map(\.rangeTitle) == ["-2 +2", "-10 +10", "-19 +19"])
            #expect(hunks.map(\.preview) == ["L2", "L10", "L19"])
            #expect(model.isPartiallyIncluded(changed) == false)
            #expect(hunks.allSatisfy { model.isHunkIncluded($0, in: changed) })

            await model.toggleExpansion(of: changed, using: manager)
            #expect(model.isExpanded(changed) == false)
            #expect(model.hunks(for: changed).count == 3)
            #expect(model.canExpand(changed))
        }
    }

    @Test
    func binaryAndModeChangedFilesAreWholeFileOnly() async throws {
        try await withTempDir { directory in
            let (fixture, manager) = try await makeRepo(directory)
            try Data([0, 1, 2, 3, 0, 255]).write(to: directory.appending(path: "bin.dat"))
            try await fixture.commit("binary")
            try Data([0, 9, 2, 3, 0, 255]).write(to: directory.appending(path: "bin.dat"))
            try fixture.write("a.txt", numbered(replacing: [2: "L2"]))
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: directory.appending(path: "a.txt").path(percentEncoded: false)
            )
            await manager.refreshAllChangedFiles()

            let (model, binary) = try await expandedModel(manager, file: "bin.dat")
            #expect(model.hunks(for: binary).isEmpty)
            #expect(model.canExpand(binary) == false)
            #expect(model.isExpanded(binary) == false)

            let (_, modeChanged) = try await expandedModel(manager)
            #expect(try await manager.gitClient.commitToolWindowHunks(path: "a.txt").isEmpty)
            #expect(CommitToolWindowViewModel.supportsHunks(modeChanged))
        }
    }

    @Test
    func hunkCheckboxesDriveTheTriStateFileSelection() async throws {
        try await withTempDir { directory in
            let (fixture, manager) = try await makeRepo(directory)
            try fixture.write("a.txt", numbered(replacing: [2: "L2", 10: "L10", 19: "L19"]))
            await manager.refreshAllChangedFiles()
            let (model, changed) = try await expandedModel(manager)
            let hunks = model.hunks(for: changed)

            model.setHunkIncluded(false, hunks[0], in: changed)
            #expect(model.isPartiallyIncluded(changed))
            #expect(model.isIncluded(changed))
            #expect(model.isHunkIncluded(hunks[0], in: changed) == false)
            #expect(model.isHunkIncluded(hunks[1], in: changed))

            model.setHunkIncluded(false, hunks[1], in: changed)
            model.setHunkIncluded(false, hunks[2], in: changed)
            #expect(model.isIncluded(changed) == false)
            #expect(model.isPartiallyIncluded(changed) == false)
            #expect(model.excludedIDs.contains(changed.id))
            #expect(hunks.allSatisfy { model.isHunkIncluded($0, in: changed) == false })

            model.setHunkIncluded(true, hunks[1], in: changed)
            #expect(model.isIncluded(changed))
            #expect(model.isPartiallyIncluded(changed))
            #expect(model.excludedIDs.contains(changed.id) == false)
            #expect(model.isHunkIncluded(hunks[1], in: changed))
            #expect(model.isHunkIncluded(hunks[0], in: changed) == false)

            model.setHunkIncluded(true, hunks[0], in: changed)
            model.setHunkIncluded(true, hunks[2], in: changed)
            #expect(model.isPartiallyIncluded(changed) == false)
            #expect(model.excludedHunkIDs.isEmpty)
            #expect(model.excludedIDs.isEmpty)

            model.setHunkIncluded(false, hunks[0], in: changed)
            model.setIncluded(false, for: changed)
            #expect(model.excludedHunkIDs.isEmpty)
            #expect(model.isHunkIncluded(hunks[1], in: changed) == false)
            model.setHunkIncluded(true, hunks[2], in: changed)
            #expect(model.isIncluded(changed))
            #expect(model.isHunkIncluded(hunks[2], in: changed))
            #expect(model.isHunkIncluded(hunks[0], in: changed) == false)
            #expect(model.isPartiallyIncluded(changed))

            model.setIncluded(true, for: changed)
            #expect(model.isPartiallyIncluded(changed) == false)
            #expect(model.excludedHunkIDs.isEmpty)
        }
    }

    @Test
    func aPartialCommitStagesOnlyTheCheckedHunksAndLeavesTheRestUnstaged() async throws {
        try await withTempDir { directory in
            let (fixture, manager) = try await makeRepo(directory)
            let edited = numbered(replacing: [2: "L2", 10: "L10", 19: "L19"])
            try fixture.write("a.txt", edited)
            await manager.refreshAllChangedFiles()
            let (model, changed) = try await expandedModel(manager)
            model.setHunkIncluded(false, model.hunks(for: changed)[1], in: changed)
            model.message = "Partial"

            await model.commit(using: manager, andPush: false)

            #expect(try await fixture.run("log", "-1", "--format=%s") == "Partial\n")
            #expect(try await fixture.run("show", "HEAD:a.txt") == numbered(replacing: [2: "L2", 19: "L19"]))
            #expect(try fixture.read("a.txt") == edited)
            #expect(try await fixture.stagedPaths().isEmpty)
            #expect(try await hunkCount(fixture, "diff", "-U0", "--", "a.txt") == 1)
            #expect(changedNames(manager) == ["a.txt"])
            #expect(model.message.isEmpty)
            #expect(model.excludedHunkIDs.isEmpty)
            #expect(model.excludedIDs.isEmpty)
            #expect(model.isPartiallyIncluded(changed) == false)
            let remaining = try file("a.txt", in: manager)
            #expect(model.hunks(for: remaining).map(\.preview) == ["L10"])
            #expect(model.isExpanded(remaining))
            #expect(model.isIncluded(remaining))
        }
    }

    @Test
    func aPartialCommitReplacesWhateverWasStagedForTheFileBefore() async throws {
        try await withTempDir { directory in
            let (fixture, manager) = try await makeRepo(directory)
            try fixture.write("a.txt", numbered(replacing: [2: "L2"]))
            try await fixture.run("add", "a.txt")
            try fixture.write("a.txt", numbered(replacing: [2: "L2", 10: "L10", 19: "L19"]))
            try fixture.write("b.txt", "b changed\n")
            await manager.refreshAllChangedFiles()
            let (model, changed) = try await expandedModel(manager)
            #expect(changed.isStaged)
            model.setHunkIncluded(false, model.hunks(for: changed)[0], in: changed)
            model.message = "Mixed"

            await model.commit(using: manager, andPush: false)

            #expect(try await fixture.run("show", "HEAD:a.txt") == numbered(replacing: [10: "L10", 19: "L19"]))
            #expect(try await fixture.run("show", "HEAD:b.txt") == "b changed\n")
            #expect(try await fixture.run("show", "--name-only", "--format=", "HEAD").split(separator: "\n").count == 2)
            #expect(try fixture.read("a.txt") == numbered(replacing: [2: "L2", 10: "L10", 19: "L19"]))
            #expect(try await hunkCount(fixture, "diff", "-U0", "--", "a.txt") == 1)
        }
    }

    @Test
    func aPartialAmendRewritesTheLastCommitWithTheCheckedHunksOnly() async throws {
        try await withTempDir { directory in
            let (fixture, manager) = try await makeRepo(directory)
            try fixture.write("a.txt", numbered(replacing: [5: "L5"]))
            try await fixture.commit("second")
            try fixture.write("a.txt", numbered(replacing: [2: "L2", 5: "L5", 10: "L10"]))
            await manager.refreshAllChangedFiles()
            let (model, changed) = try await expandedModel(manager)
            #expect(model.hunks(for: changed).map(\.preview) == ["L2", "L10"])
            model.setHunkIncluded(false, model.hunks(for: changed)[1], in: changed)
            model.amend = true
            model.message = "Amended"

            await model.commit(using: manager, andPush: false)

            #expect(try await fixture.run("rev-list", "--count", "HEAD") == "2\n")
            #expect(try await fixture.run("log", "-1", "--format=%s") == "Amended\n")
            #expect(try await fixture.run("show", "HEAD:a.txt") == numbered(replacing: [2: "L2", 5: "L5"]))
            #expect(try await hunkCount(fixture, "diff", "-U0", "--", "a.txt") == 1)
        }
    }

    @Test
    func hunksThatVanishedBeforeTheNextRefreshExcludeTheFileWhenNothingIsLeft() async throws {
        try await withTempDir { directory in
            let (fixture, manager) = try await makeRepo(directory)
            try fixture.write("a.txt", numbered(replacing: [2: "L2", 10: "L10", 19: "L19"]))
            await manager.refreshAllChangedFiles()
            let (model, changed) = try await expandedModel(manager)
            let hunks = model.hunks(for: changed)
            model.setHunkIncluded(false, hunks[0], in: changed)
            model.setHunkIncluded(false, hunks[1], in: changed)
            #expect(model.isPartiallyIncluded(changed))

            try fixture.write("a.txt", numbered(replacing: [2: "L2", 10: "L10"]))
            await model.refreshHunks(using: manager)

            #expect(model.hunks(for: changed).map(\.preview) == ["L2", "L10"])
            #expect(model.isIncluded(changed) == false)
            #expect(model.isPartiallyIncluded(changed) == false)
            #expect(model.excludedIDs.contains(changed.id))
        }
    }

    @Test
    func refreshingDropsSelectionsForHunksThatChangedAndStateForFilesThatLeftTheList() async throws {
        try await withTempDir { directory in
            let (fixture, manager) = try await makeRepo(directory)
            try fixture.write("a.txt", numbered(replacing: [2: "L2", 10: "L10", 19: "L19"]))
            await manager.refreshAllChangedFiles()
            let (model, changed) = try await expandedModel(manager)
            let hunks = model.hunks(for: changed)
            model.setHunkIncluded(false, hunks[0], in: changed)
            model.setHunkIncluded(false, hunks[1], in: changed)

            try fixture.write("a.txt", numbered(replacing: [2: "edited", 10: "L10", 19: "L19"]))
            await model.refreshHunks(using: manager)
            #expect(model.hunks(for: changed).map(\.preview) == ["edited", "L10", "L19"])
            #expect(model.excludedHunkIDs[changed.id]?.count == 1)
            #expect(model.isPartiallyIncluded(changed))

            try fixture.write("a.txt", numbered())
            await manager.refreshAllChangedFiles()
            await model.refreshHunks(using: manager)
            #expect(model.expandedIDs.isEmpty)
            #expect(model.hunks(for: changed).isEmpty)
            #expect(model.excludedHunkIDs.isEmpty)
        }
    }

    @Test
    func aSelectionWhoseHunksAllVanishedCommitsOnlyTheOtherFiles() async throws {
        try await withTempDir { directory in
            let (fixture, manager) = try await makeRepo(directory)
            try fixture.write("a.txt", numbered(replacing: [2: "L2", 10: "L10", 19: "L19"]))
            try fixture.write("b.txt", "b changed\n")
            await manager.refreshAllChangedFiles()
            let (model, changed) = try await expandedModel(manager)
            let hunks = model.hunks(for: changed)
            model.setHunkIncluded(false, hunks[0], in: changed)
            model.setHunkIncluded(false, hunks[1], in: changed)
            try fixture.write("a.txt", numbered(replacing: [2: "L2", 10: "L10"]))
            model.message = "Only b"

            await model.commit(using: manager, andPush: false)

            #expect(try await fixture.run("show", "--name-only", "--format=", "HEAD") == "b.txt\n")
            #expect(try fixture.read("a.txt") == numbered(replacing: [2: "L2", 10: "L10"]))
            #expect(try await fixture.stagedPaths().isEmpty)
            #expect(changedNames(manager) == ["a.txt"])
        }
    }

    @Test
    func aSelectionWhoseExcludedHunkVanishedFallsBackToTheWholeFile() async throws {
        try await withTempDir { directory in
            let (fixture, manager) = try await makeRepo(directory)
            try fixture.write("a.txt", numbered(replacing: [2: "L2", 10: "L10", 19: "L19"]))
            await manager.refreshAllChangedFiles()
            let (model, changed) = try await expandedModel(manager)
            model.setHunkIncluded(false, model.hunks(for: changed)[1], in: changed)
            try fixture.write("a.txt", numbered(replacing: [2: "L2", 19: "L19"]))
            model.message = "Whole"

            await model.commit(using: manager, andPush: false)

            #expect(try await fixture.run("show", "HEAD:a.txt") == numbered(replacing: [2: "L2", 19: "L19"]))
            #expect(manager.changedFiles.isEmpty)
        }
    }

    @Test
    func aFailingStagingKeepsTheSelectionAndReportsTheFailure() async throws {
        try await withTempDir { directory in
            let (fixture, manager) = try await makeRepo(directory)
            try fixture.write("a.txt", numbered(replacing: [2: "L2", 10: "L10", 19: "L19"]))
            await manager.refreshAllChangedFiles()
            let (model, changed) = try await expandedModel(manager)
            model.setHunkIncluded(false, model.hunks(for: changed)[1], in: changed)
            model.message = "Try"
            let lock = directory.appending(path: ".git/index.lock")
            try Data().write(to: lock)

            await model.commit(using: manager, andPush: true)
            try FileManager.default.removeItem(at: lock)

            #expect(manager.lastAlert?.title == "Failed to commit")
            #expect(manager.lastAlert?.message.contains("index.lock") == true)
            #expect(manager.pushSheetIsPresented == false)
            #expect(model.isCommitting == false)
            #expect(model.message == "Try")
            #expect(model.isPartiallyIncluded(changed))
            #expect(model.excludedHunkIDs[changed.id]?.count == 1)
            #expect(try await fixture.run("rev-list", "--count", "HEAD") == "1\n")
        }
    }

    @Test
    func expandingAFileWhoseHunksCannotBeLoadedReportsItAndStaysCollapsed() async throws {
        try await withTempDir { directory in
            let fixture = try await GitMergeFixture(root: directory)
            try fixture.write("f.txt", "x\n")
            let manager = SourceControlManager(workspaceURL: directory, editorManager: EditorManager())
            let changed = GitChangedFile(
                status: .modified,
                stagedStatus: .none,
                fileURL: URL(filePath: "f.txt", relativeTo: directory),
                originalFilename: nil
            )
            let model = CommitToolWindowViewModel()

            await model.toggleExpansion(of: changed, using: manager)

            #expect(manager.lastAlert?.title == "Failed to load changes")
            #expect(model.expandedIDs.isEmpty)
            #expect(model.hunks(for: changed).isEmpty)
            #expect(model.isExpanded(changed) == false)
        }
    }

    @Test
    func theClientStagesNothingWhenNoExcludedHunkMatches() async throws {
        try await withTempDir { directory in
            let (fixture, manager) = try await makeRepo(directory)
            try fixture.write("a.txt", numbered(replacing: [2: "L2"]))

            let outcome = try await manager.gitClient.stageSelectedHunks(path: "a.txt", excluding: ["none"])

            #expect(outcome == .wholeFile)
            #expect(try await fixture.stagedPaths().isEmpty)
            #expect(try await manager.gitClient.lastCommitMessage() == "initial")
        }
    }

    @Test
    func theClientStagesTheSelectedHunksAndReportsWhenNothingIsSelected() async throws {
        try await withTempDir { directory in
            let (fixture, manager) = try await makeRepo(directory)
            try fixture.write("a.txt", numbered(replacing: [2: "L2", 10: "L10"]))
            let hunks = try await manager.gitClient.commitToolWindowHunks(path: "a.txt")
            #expect(hunks.count == 2)

            let staged = try await manager.gitClient.stageSelectedHunks(path: "a.txt", excluding: [hunks[0].id])
            #expect(staged == .staged)
            #expect(try await fixture.run("diff", "--cached", "--name-only") == "a.txt\n")
            #expect(try await hunkCount(fixture, "diff", "--cached", "-U0", "--", "a.txt") == 1)
            #expect(try await hunkCount(fixture, "diff", "-U0", "--", "a.txt") == 1)

            let none = try await manager.gitClient.stageSelectedHunks(path: "a.txt", excluding: Set(hunks.map(\.id)))
            #expect(none == .nothingSelected)
            #expect(try await fixture.stagedPaths().isEmpty)
        }
    }

    @MainActor
    private struct HostedCommitWindow {
        let fixture: GitMergeFixture
        let workspace: WorkspaceDocument
        let manager: SourceControlManager
        let viewModel: CommitToolWindowViewModel
        let hosted: HostedView
        let actions: CommitToolWindowActions

        func checkbox(_ label: String) throws -> NSButton {
            try #require(hosted.views(of: NSButton.self).first { $0.accessibilityLabel() == label })
        }

        func changed(_ name: String) throws -> GitChangedFile {
            try #require(manager.changedFiles.first { $0.fileURL.lastPathComponent == name })
        }

        func click(_ label: String) async throws {
            try checkbox(label).performClick(nil)
            try await hosted.settle(.milliseconds(100))
        }

        func close() {
            hosted.close()
            workspace.close()
        }
    }

    private func hostCommitWindow(_ directory: URL, edited: String) async throws -> HostedCommitWindow {
        let fixture = try await GitMergeFixture(root: directory)
        try fixture.write("a.txt", numbered())
        try await fixture.commit("initial")
        try fixture.write("a.txt", edited)
        let workspace = try HostedViewFixture.makeWorkspace(in: directory)
        let manager = try #require(workspace.sourceControlManager)
        await manager.refreshAllChangedFiles()
        try await eventually { manager.changedFiles.count == 1 }
        let viewModel = CommitToolWindowViewModel()
        let hosted = try HostedViewFixture.hostInWorkspace(workspace, size: NSSize(width: 360, height: 640)) {
            CommitToolWindow(viewModel: viewModel, makeAlert: NSAlert.init)
        }
        try await hosted.settle()
        let actions = CommitToolWindowActions(
            workspace: workspace,
            sourceControlManager: manager,
            viewModel: viewModel,
            makeAlert: NSAlert.init
        )
        return HostedCommitWindow(
            fixture: fixture,
            workspace: workspace,
            manager: manager,
            viewModel: viewModel,
            hosted: hosted,
            actions: actions
        )
    }

    @Test
    func hunkCheckboxesInTheHostedWindowDriveWhichHunksGetCommitted() async throws {
        try await withTempDir { directory in
            let edited = numbered(replacing: [2: "L2", 10: "L10", 19: "L19"])
            let window = try await hostCommitWindow(directory, edited: edited)
            defer { window.close() }
            let viewModel = window.viewModel
            let changed = try window.changed("a.txt")
            #expect(window.hosted.views(of: NSButton.self).contains { $0.accessibilityLabel() == "Include a.txt" })

            window.actions.actions(for: changed).toggleExpansion()
            try await eventually { viewModel.isExpanded(changed) && viewModel.hunks(for: changed).count == 3 }
            try await window.hosted.settle()
            #expect(try window.checkbox("Include a.txt").state == .on)
            #expect(try window.checkbox("Include lines -2 +2").state == .on)
            #expect(try window.checkbox("Include lines -10 +10").state == .on)
            #expect(try window.checkbox("Include lines -19 +19").state == .on)

            try await window.click("Include lines -10 +10")
            #expect(viewModel.isPartiallyIncluded(changed))
            #expect(try window.checkbox("Include lines -10 +10").state == .off)
            #expect(try window.checkbox("Include lines -2 +2").state == .on)
            #expect(try window.checkbox("Include a.txt").state == .mixed)

            try await window.click("Include a.txt")
            #expect(viewModel.excludedHunkIDs.isEmpty)
            #expect(try window.checkbox("Include a.txt").state == .on)
            #expect(try window.checkbox("Include lines -10 +10").state == .on)

            try await window.click("Include a.txt")
            #expect(viewModel.isIncluded(changed) == false)
            #expect(try window.checkbox("Include a.txt").state == .off)
            #expect(try window.checkbox("Include lines -2 +2").state == .off)

            try await window.click("Include lines -2 +2")
            try await window.click("Include lines -19 +19")
            #expect(viewModel.isPartiallyIncluded(changed))
            #expect(try window.checkbox("Include a.txt").state == .mixed)
            #expect(try window.checkbox("Include lines -10 +10").state == .off)

            viewModel.message = "Partial from the window"
            window.actions.startCommit()
            try await eventually {
                (try? await window.fixture.run("log", "-1", "--format=%s")) == "Partial from the window\n"
                    && viewModel.message.isEmpty
            }
            #expect(
                try await window.fixture.run("show", "HEAD:a.txt") == numbered(replacing: [2: "L2", 19: "L19"])
            )
            #expect(try window.fixture.read("a.txt") == edited)
            #expect(try await window.fixture.stagedPaths().isEmpty)

            try await eventually { viewModel.hunks(for: changed).map(\.preview) == ["L10"] }
            try await window.hosted.settle()
            #expect(try window.checkbox("Include a.txt").state == .on)
            #expect(try window.checkbox("Include lines -10 +10").state == .on)
        }
    }

    @Test
    func theAmendCheckboxActionPrefillsAndRestoresTheMessage() async throws {
        try await withTempDir { directory in
            let window = try await hostCommitWindow(directory, edited: numbered(replacing: [2: "L2"]))
            defer { window.close() }

            window.actions.startSetAmend(true)
            try await eventually { window.viewModel.message == "initial" }
            #expect(window.viewModel.amend)
            try await window.hosted.settle()
            #expect(window.hosted.renders())

            window.actions.startSetAmend(false)
            try await eventually { window.viewModel.message.isEmpty }
            #expect(window.viewModel.amend == false)
        }
    }

    @Test
    func hunkRowsAndExpandableFileRowsRenderAndExposeTheirCallbacks() async throws {
        let headers = [GitDiffParser.Hunk(oldStart: 1, oldCount: 1, newStart: 1, newCount: 1)]
        let hunks = PartialCommitPatchBuilder.hunks(from: headers, head: Data("a\n".utf8), worktree: Data("b\n".utf8))
        let hunk = try #require(hunks.first)
        var toggles: [Bool] = []
        var snapshots: [NSBitmapImageRep?] = []
        let included = CommitHunkRow(hunk: hunk, isIncluded: true, onToggle: { toggles.append($0) }, onShowDiff: {})
        let excluded = CommitHunkRow(hunk: hunk, isIncluded: false, onToggle: { toggles.append($0) }, onShowDiff: {})
        for row in [included, excluded] {
            let hosted = HostedViewFixture.host(size: NSSize(width: 360, height: 30)) { row }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(50))
            #expect(hosted.renders())
            snapshots.append(hosted.snapshot())
            row.setHovering(true)
            row.setHovering(false)
        }
        #expect(HostedView.pixelsDiffer(snapshots[0], snapshots[1]))
        included.onToggle(false)
        excluded.onToggle(true)
        #expect(toggles == [false, true])

        let file = GitChangedFile(
            status: .modified,
            stagedStatus: GitStatus.none,
            fileURL: URL(fileURLWithPath: "/tmp/repo/src/f.swift"),
            originalFilename: nil
        )
        let defaults = CommitChangedFileRow(
            file: file,
            directory: "src",
            isIncluded: true,
            onToggle: { _ in },
            onShowDiff: {},
            onOpen: {},
            onRollback: {},
            onShowInProject: {}
        )
        defaults.onToggleExpansion()
        for expanded in [false, true] {
            let row = CommitChangedFileRow(
                file: file,
                directory: "src",
                isIncluded: true,
                onToggle: { _ in },
                onShowDiff: {},
                onOpen: {},
                onRollback: {},
                onShowInProject: {},
                isPartiallyIncluded: expanded,
                isExpandable: true,
                isExpanded: expanded
            )
            let hosted = HostedViewFixture.host(size: NSSize(width: 360, height: 30)) { row }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(50))
            #expect(hosted.renders())
        }
    }
}
