import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct ToolbarBranchPickerTests {
    @MainActor
    private struct Session {
        let workspace: WorkspaceDocument
        let manager: SourceControlManager
        let hosted: HostedView

        var popupPanels: [BranchesPopupPanel] {
            (hosted.window.childWindows ?? []).compactMap { $0 as? BranchesPopupPanel }
        }

        func close() {
            BranchesPopupPanelHost.shared.dismiss(in: hosted.window)
            hosted.close()
            workspace.close()
        }
    }

    private func openSession(
        repository: URL,
        settingsDirectory: URL,
        sourceControlEnabled: Bool = true,
        withManager: Bool = true
    ) throws -> Session {
        let workspace = try HostedViewFixture.makeWorkspace(in: repository)
        let manager = SourceControlManager(workspaceURL: repository, editorManager: EditorManager())
        let settings = Settings(baseURL: settingsDirectory)
        settings.preferences.sourceControl.general.sourceControlIsEnabled = sourceControlEnabled
        let hosted = try HostedViewFixture.hostInWorkspace(workspace, size: NSSize(width: 400, height: 200)) {
            ToolbarBranchPicker(sourceControlManager: withManager ? manager : nil, settings: settings)
        }
        return Session(workspace: workspace, manager: manager, hosted: hosted)
    }

    private func commitInitialFile(in directory: URL) async throws -> String {
        let fixture = try await GitMergeFixture(root: directory)
        try fixture.write("a.txt", "a\n")
        try await fixture.commit("initial")
        return try await fixture.run("rev-parse", "--abbrev-ref", "HEAD")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Test
    func missingManagerRendersNothing() async throws {
        try await withTempDir { repository in
            try await withTempDir { settingsDirectory in
                _ = try await commitInitialFile(in: repository)
                let session = try openSession(
                    repository: repository,
                    settingsDirectory: settingsDirectory,
                    withManager: false
                )
                defer { session.close() }

                try await session.hosted.settle(.milliseconds(100))

                #expect(session.hosted.renders() == false)
            }
        }
    }

    @Test
    func folderWithoutARepositoryRendersNothing() async throws {
        try await withTempDir { directory in
            try await withTempDir { settingsDirectory in
                let session = try openSession(repository: directory, settingsDirectory: settingsDirectory)
                defer { session.close() }

                try await session.hosted.settle(.milliseconds(100))

                #expect(session.manager.isGitRepository == false)
                #expect(session.hosted.renders() == false)
                #expect(session.manager.currentBranch == nil)
            }
        }
    }

    @Test
    func repositoryShowsAndRefreshesTheCurrentBranch() async throws {
        try await withTempDir { repository in
            try await withTempDir { settingsDirectory in
                let expectedBranch = try await commitInitialFile(in: repository)
                let session = try openSession(repository: repository, settingsDirectory: settingsDirectory)
                defer { session.close() }

                try await eventually(timeout: .seconds(30)) {
                    session.manager.currentBranch?.name == expectedBranch && !session.manager.branches.isEmpty
                }

                #expect(session.hosted.renders())
            }
        }
    }

    @Test
    func disabledSourceControlLeavesTheBranchUntouched() async throws {
        try await withTempDir { repository in
            try await withTempDir { settingsDirectory in
                _ = try await commitInitialFile(in: repository)
                let session = try openSession(
                    repository: repository,
                    settingsDirectory: settingsDirectory,
                    sourceControlEnabled: false
                )
                defer { session.close() }

                try await session.hosted.settle(.milliseconds(400))

                #expect(session.manager.isGitRepository)
                #expect(session.manager.currentBranch == nil)
                #expect(session.manager.branches.isEmpty)
                #expect(session.hosted.renders())
            }
        }
    }

    @Test
    func showBranchesNotificationForTheWorkspaceOpensThePopupBelowTheWidget() async throws {
        try await withTempDir { repository in
            try await withTempDir { settingsDirectory in
                _ = try await commitInitialFile(in: repository)
                let session = try openSession(repository: repository, settingsDirectory: settingsDirectory)
                defer { session.close() }
                try await session.hosted.settle(.milliseconds(100))
                #expect(session.popupPanels.isEmpty)

                NotificationCenter.default.post(name: .showGitBranchesPopup, object: session.workspace)

                try await eventually(timeout: .seconds(30)) { !session.popupPanels.isEmpty }
                #expect(session.popupPanels.count == 1)
            }
        }
    }

    @Test
    func showBranchesNotificationForAnotherWorkspaceIsIgnored() async throws {
        try await withTempDir { repository in
            try await withTempDir { settingsDirectory in
                _ = try await commitInitialFile(in: repository)
                let session = try openSession(repository: repository, settingsDirectory: settingsDirectory)
                defer { session.close() }
                try await session.hosted.settle(.milliseconds(100))

                NotificationCenter.default.post(name: .showGitBranchesPopup, object: WorkspaceDocument())
                NotificationCenter.default.post(name: .showGitBranchesPopup, object: nil)
                try await session.hosted.settle(.milliseconds(300))

                #expect(session.popupPanels.isEmpty)
            }
        }
    }
}
