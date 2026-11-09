import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct CommitToolWindowCoverage {
    private func changed(
        _ status: GitStatus,
        staged: GitStatus = .none,
        _ name: String
    ) -> GitChangedFile {
        GitChangedFile(
            status: status,
            stagedStatus: staged,
            fileURL: URL(fileURLWithPath: "/tmp/repo/src/\(name)"),
            originalFilename: nil
        )
    }

    @Test
    func aDirectoryWithoutARepositoryShowsTheHintAndBecomesTheTreeAfterInit() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let manager = try #require(workspace.sourceControlManager)
            #expect(manager.isGitRepository == false)
            let viewModel = CommitToolWindowViewModel()
            let alerts = CommitToolWindowCoverageAlerts()
            let hosted = try HostedViewFixture.hostInWorkspace(workspace, size: NSSize(width: 360, height: 640)) {
                CommitToolWindow(viewModel: viewModel, makeAlert: alerts.make)
            }
            defer { hosted.close() }
            try await hosted.settle()
            #expect(hosted.renders())
            let notRepository = hosted.snapshot()
            let actions = CommitToolWindowActions(
                workspace: workspace,
                sourceControlManager: manager,
                viewModel: viewModel,
                makeAlert: alerts.make
            )

            let fixture = try await GitMergeFixture(root: dir)
            try fixture.write("seed.txt", "seed\n")
            try await fixture.commit("seed")
            actions.startRefresh()
            try await eventually { manager.isGitRepository && manager.changedFiles.isEmpty }
            try await hosted.settle()
            let noChanges = hosted.snapshot()
            #expect(HostedView.pixelsDiffer(notRepository, noChanges))

            try Data("x\n".utf8).write(to: dir.appending(path: "x.txt"))
            await actions.refresh()
            try await eventually { manager.changedFiles.count == 1 }
            try await hosted.settle()
            #expect(manager.changedFiles.first.map(CommitToolWindowViewModel.isUnversioned) == true)
            #expect(HostedView.pixelsDiffer(noChanges, hosted.snapshot()))
        }
    }

    @Test
    func theTreeRendersGroupsAndEveryCommitButtonState() async throws {
        try await withTempDir { dir in
            let rig = try await CommitToolWindowCoverageRig.make(in: dir, scenario: .full)
            defer { rig.close() }
            #expect(rig.names() == [
                "a.txt", "b.txt", "c.txt", "d.txt", "staged.txt", CommitToolWindowCoverageRig.diffName,
                "u.txt", "u2.txt"
            ].sorted())
            let hosted = try rig.host()
            defer { hosted.close() }
            try await hosted.settle()
            #expect(hosted.renders())
            let disabled = hosted.snapshot()
            #expect(rig.viewModel.canCommit(in: rig.manager.changedFiles) == false)

            rig.viewModel.message = "Ship it"
            try await hosted.settle()
            #expect(rig.viewModel.canCommit(in: rig.manager.changedFiles))
            #expect(HostedView.pixelsDiffer(disabled, hosted.snapshot()))

            rig.viewModel.amend = true
            try await hosted.settle()
            #expect(hosted.renders())

            for file in rig.manager.changedFiles {
                rig.viewModel.setIncluded(false, for: file)
            }
            try await hosted.settle()
            #expect(rig.viewModel.canCommit(in: rig.manager.changedFiles))
            rig.viewModel.amend = false
            try await hosted.settle()
            #expect(rig.viewModel.canCommit(in: rig.manager.changedFiles) == false)
            #expect(hosted.renders())

            for file in rig.manager.changedFiles {
                rig.viewModel.setIncluded(true, for: file)
            }
            try await hosted.settle()
            #expect(rig.viewModel.canCommit(in: rig.manager.changedFiles))
            #expect(hosted.renders())
        }
    }

    @Test
    func singleFileGroupsUseTheSingularCountAndACleanRepositoryShowsNoChanges() async throws {
        try await withTempDir { dir in
            let rig = try await CommitToolWindowCoverageRig.make(in: dir, scenario: .singleModified)
            defer { rig.close() }
            let hosted = try rig.host()
            defer { hosted.close() }
            try await hosted.settle()
            #expect(hosted.renders())
            let single = hosted.snapshot()

            try await rig.fixture.commit("second")
            await rig.actions.refresh()
            try await eventually { rig.manager.changedFiles.isEmpty }
            try await hosted.settle()
            #expect(HostedView.pixelsDiffer(single, hosted.snapshot()))

            try rig.fixture.write("only-untracked.txt", "u\n")
            await rig.actions.refresh()
            try await eventually { rig.names() == ["only-untracked.txt"] }
            try await hosted.settle()
            #expect(hosted.renders())
        }
    }

    @Test
    func aRepositoryInTheMiddleOfAMergeRenders() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.mergeConflict(in: dir)
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let manager = try #require(workspace.sourceControlManager)
            await manager.refreshAllChangedFiles()
            let hosted = try HostedViewFixture.hostInWorkspace(workspace, size: NSSize(width: 360, height: 640)) {
                CommitToolWindow()
            }
            defer { hosted.close() }
            try await hosted.settle()
            #expect(manager.isGitRepository)
            #expect(hosted.renders())
        }
    }

    @Test
    func theCommitMessageEditorShowsThePlaceholderOnlyWhenEmpty() async throws {
        let empty = HostedViewFixture.host(size: NSSize(width: 300, height: 100)) {
            CommitMessageEditor(text: .constant(""))
        }
        defer { empty.close() }
        let filled = HostedViewFixture.host(size: NSSize(width: 300, height: 100)) {
            CommitMessageEditor(text: .constant("Fix the build"))
        }
        defer { filled.close() }
        try await empty.settle()
        try await filled.settle()

        #expect(empty.renders())
        #expect(filled.renders())
        #expect(HostedView.pixelsDiffer(empty.snapshot(), filled.snapshot()))
    }

    @Test
    func rowsRenderEveryStatusAndExposeTheirMenuAndHoverState() async throws {
        let calls = CommitToolWindowCoverageCalls()
        let statuses: [GitStatus] = [
            .none, .modified, .untracked, .fileTypeChange, .added, .deleted, .renamed, .copied, .unmerged
        ]
        for (index, status) in statuses.enumerated() {
            let file = changed(status, staged: index.isMultiple(of: 2) ? .added : .none, "File\(index).swift")
            let row = CommitChangedFileRow(
                file: file,
                directory: index == 0 ? "" : "src/deeply/nested/directory",
                isIncluded: index.isMultiple(of: 2),
                onToggle: { calls.toggles.append($0) },
                onShowDiff: { calls.showDiff += 1 },
                onOpen: { calls.open += 1 },
                onRollback: { calls.rollback += 1 },
                onShowInProject: { calls.showInProject += 1 }
            )
            let hosted = HostedViewFixture.host(size: NSSize(width: 360, height: 40)) { row }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(50))
            #expect(hosted.renders())
            _ = row.menuItems
            row.setHovering(true)
            row.setHovering(false)
        }
        #expect(calls.toggles.isEmpty)
    }

    @Test
    func theHeaderActionsDriveRefreshFetchAndHide() async throws {
        try await withTempDir { dir in
            let rig = try await CommitToolWindowCoverageRig.make(in: dir, scenario: .singleModified)
            defer { rig.close() }
            let actions = rig.actions
            #expect(actions.includedFiles.map(\.fileURL.lastPathComponent) == ["a.txt"])

            try rig.fixture.write("b.txt", "b changed\n")
            actions.startRefresh()
            try await eventually { rig.names() == ["a.txt", "b.txt"] }

            await actions.fetch()
            #expect(rig.manager.lastAlert == nil)

            let missing = dir.appending(path: "missing.git").path(percentEncoded: false)
            try await rig.fixture.run("remote", "add", "origin", missing)
            actions.startFetch()
            try await eventually { rig.manager.lastAlert?.title == "Failed to fetch" }
            #expect(rig.manager.lastAlert?.message.isEmpty == false)

            rig.workspace.toolWindowManager.show(.commit)
            #expect(rig.workspace.toolWindowManager.isVisible(.commit))
            actions.hide()
            #expect(rig.workspace.toolWindowManager.isVisible(.commit) == false)
        }
    }

    @Test
    func commitAndCommitAndPushRunThroughTheViewModel() async throws {
        try await withTempDir { dir in
            let rig = try await CommitToolWindowCoverageRig.make(in: dir, scenario: .singleModified)
            defer { rig.close() }
            let actions = rig.actions
            rig.viewModel.message = "Commit from the tool window"
            actions.startCommit()
            try await eventually {
                (try? await rig.fixture.run("log", "-1", "--format=%s"))?
                    .trimmingCharacters(in: .newlines) == "Commit from the tool window"
            }
            try await eventually { rig.viewModel.message.isEmpty && rig.manager.changedFiles.isEmpty }
            #expect(rig.manager.pushSheetIsPresented == false)

            try rig.fixture.write("a.txt", "a changed again\n")
            await actions.refresh()
            try await eventually { rig.names() == ["a.txt"] }
            rig.viewModel.message = "Commit and push"
            actions.startCommitAndPush()
            try await eventually { rig.manager.pushSheetIsPresented }
            #expect(try await rig.fixture.run("log", "-1", "--format=%s") == "Commit and push\n")
        }
    }
}
