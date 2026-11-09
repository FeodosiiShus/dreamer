import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
extension CommitToolWindowCoverage {
    @Test
    func rollbackOfTheCheckedFilesAsksForConfirmationFirst() async throws {
        try await withTempDir { dir in
            let rig = try await CommitToolWindowCoverageRig.make(in: dir, scenario: .full)
            defer { rig.close() }
            let actions = rig.actions
            for file in rig.manager.changedFiles where file.fileURL.lastPathComponent != "a.txt" {
                rig.viewModel.setIncluded(false, for: file)
            }

            rig.alerts.response = .alertSecondButtonReturn
            actions.rollbackIncluded()
            let cancelled = try #require(rig.alerts.created.first)
            #expect(cancelled.messageText == "Discard local changes to \"a.txt\"?")
            #expect(cancelled.informativeText == "Local changes will be discarded. This action cannot be undone.")
            #expect(cancelled.alertStyle == .warning)
            #expect(cancelled.buttons.map(\.title) == ["Rollback", "Cancel"])
            #expect(try rig.fixture.read("a.txt") == "a changed\n")

            rig.alerts.response = .alertFirstButtonReturn
            actions.rollbackIncluded()
            try await eventually { (try? rig.fixture.read("a.txt")) == "a\n" }

            for file in rig.manager.changedFiles {
                rig.viewModel.setIncluded(true, for: file)
            }
            try await eventually { rig.names().contains("a.txt") == false }
            let remaining = actions.includedFiles.count
            #expect(remaining > 1)
            actions.rollbackIncluded()
            #expect(rig.alerts.created.last?.messageText == "Discard local changes to \(remaining) files?")
            try await eventually { rig.manager.changedFiles.isEmpty }
            #expect(rig.fixture.exists("d.txt"))
            #expect(try rig.fixture.read("b.txt") == "b\n")
            #expect(rig.fixture.exists("staged.txt") == false)
            #expect(rig.fixture.exists("u.txt") == false)

            let asked = rig.alerts.created.count
            actions.rollbackIncluded()
            #expect(rig.alerts.created.count == asked)
        }
    }

    @Test
    func fileActionsToggleRollbackOpenAndRevealTheFile() async throws {
        try await withTempDir { dir in
            let rig = try await CommitToolWindowCoverageRig.make(in: dir, scenario: .full)
            defer { rig.close() }
            let actions = rig.actions
            let tracked = actions.actions(for: try rig.file("a.txt"))
            let untracked = actions.actions(for: try rig.file("u.txt"))

            #expect(rig.viewModel.isIncluded(tracked.file))
            tracked.setIncluded(false)
            #expect(rig.viewModel.isIncluded(tracked.file) == false)
            tracked.setIncluded(true)
            #expect(rig.viewModel.isIncluded(tracked.file))
            #expect(rig.viewModel.isIncluded(untracked.file) == false)
            untracked.setIncluded(true)
            #expect(rig.viewModel.isIncluded(untracked.file))

            rig.alerts.response = .alertSecondButtonReturn
            tracked.rollback()
            #expect(rig.alerts.created.last?.messageText == "Discard local changes to \"a.txt\"?")
            #expect(try rig.fixture.read("a.txt") == "a changed\n")
            rig.alerts.response = .alertFirstButtonReturn
            tracked.rollback()
            try await eventually { (try? rig.fixture.read("a.txt")) == "a\n" }

            tracked.open()
            let editor = try #require(rig.workspace.editorManager?.activeEditor)
            try await eventually { editor.selectedTab?.file.url.lastPathComponent == "a.txt" }

            rig.workspace.toolWindowManager.hide(.project)
            rig.workspace.listenerModel.highlightedFileItem = nil
            untracked.showInProject()
            #expect(rig.workspace.toolWindowManager.isVisible(.project))
            #expect(rig.workspace.listenerModel.highlightedFileItem?.url.lastPathComponent == "u.txt")
        }
    }

    @Test
    func fileActionsDoNothingWithoutAWorkspaceFileManager() async throws {
        try await withTempDir { dir in
            let rig = try await CommitToolWindowCoverageRig.make(in: dir, scenario: .full)
            defer { rig.close() }
            let saved = rig.workspace.workspaceFileManager
            rig.workspace.workspaceFileManager = nil
            defer { rig.workspace.workspaceFileManager = saved }
            let editor = try #require(rig.workspace.editorManager?.activeEditor)
            let tabsBefore = editor.tabs.count
            let actions = rig.actions.actions(for: try rig.file("a.txt"))
            rig.workspace.toolWindowManager.hide(.project)
            rig.workspace.listenerModel.highlightedFileItem = nil

            actions.open()
            actions.showInProject()

            #expect(editor.tabs.count == tabsBefore)
            #expect(rig.workspace.toolWindowManager.isVisible(.project) == false)
            #expect(rig.workspace.listenerModel.highlightedFileItem == nil)
        }
    }

    @Test
    func showingTheDiffOpensTheDiffWindowForTheFile() async throws {
        try await withTempDir { dir in
            let rig = try await CommitToolWindowCoverageRig.make(in: dir, scenario: .full)
            defer { rig.close() }
            let actions = rig.actions.actions(for: try rig.file(CommitToolWindowCoverageRig.diffName))

            actions.showDiff()

            let marker = CommitToolWindowCoverageRig.diffName
            try await eventually {
                NSApp.windows.contains {
                    $0.windowController is DiffViewerWindowController && $0.title.contains(marker)
                }
            }
            let window = try #require(
                NSApp.windows.first { $0.windowController is DiffViewerWindowController && $0.title.contains(marker) }
            )
            window.close()
        }
    }

    @Test
    func defaultInitializerCreatesFreshSystemAlerts() {
        let window = CommitToolWindow()

        let first = window.makeAlert()
        let second = window.makeAlert()

        #expect(first !== second)
    }
}
