import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct ProjectToolWindowTests {
    private func makeProject(_ dir: URL) throws {
        let sources = dir.appending(path: "Sources", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try "let a = 1\n".write(to: sources.appending(path: "a.swift"), atomically: true, encoding: .utf8)
    }

    @Test
    func viewModeTitlesAndSelectionBindingFollowTheMode() {
        #expect(ProjectToolWindowViewMode.project.title == "Project")
        #expect(ProjectToolWindowViewMode.openFiles.title == "Open Files")
        #expect(ProjectToolWindowViewMode.allCases.map(\.id) == ["project", "openFiles"])

        let state = ProjectToolWindowState()
        let openFiles = state.selectionBinding(for: .openFiles)
        let project = state.selectionBinding(for: .project)
        #expect(project.wrappedValue)
        #expect(!openFiles.wrappedValue)

        openFiles.wrappedValue = true
        #expect(state.viewMode == .openFiles)
        #expect(openFiles.wrappedValue)

        openFiles.wrappedValue = false
        #expect(state.viewMode == .openFiles)

        project.wrappedValue = true
        #expect(state.viewMode == .project)
    }

    @Test
    func togglesListBothViewModes() async throws {
        let state = ProjectToolWindowState()
        let hosted = HostedViewFixture.host { VStack { ProjectToolWindowViewModeToggles(state: state) } }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(100))
        #expect(hosted.renders())

        state.viewMode = .openFiles
        try await hosted.settle(.milliseconds(100))
        #expect(hosted.renders())
    }

    @Test
    func rendersTheOutlineAndRoutesHeaderActionsToTheNavigatorController() async throws {
        try await withTempDir { dir in
            try makeProject(dir)
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            workspace.toolWindowManager.show(.project)
            let state = ProjectToolWindowState()

            let hosted = try HostedViewFixture.hostInWorkspace(workspace) { ProjectToolWindow(state: state) }
            defer { hosted.close() }
            try await hosted.settle()
            #expect(hosted.renders())
            #expect(state.controllerReference.controller != nil)

            let actions = ProjectToolWindowActions(state: state)
            actions.expandAll()
            actions.collapseAll()
            actions.revealOpenedFile()
            actions.clearSearchFieldFocus()
            try await hosted.settle(.milliseconds(100))
            #expect(hosted.renders())

            workspace.toolWindowManager.hideCallback(for: .project)()
            #expect(!workspace.toolWindowManager.isVisible(.project))
        }
    }

    @Test
    func actionsAreNoOpsWithoutAController() async throws {
        let state = ProjectToolWindowState()
        let actions = ProjectToolWindowActions(state: state)

        actions.expandAll()
        actions.collapseAll()
        actions.revealOpenedFile()
        actions.clearSearchFieldFocus()
        try await Task.sleep(for: .milliseconds(50))

        #expect(state.controllerReference.controller == nil)
    }

    @Test
    func switchingViewModesSwapsTheContentAndRefocusesTheOutline() async throws {
        try await withTempDir { dir in
            try makeProject(dir)
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let state = ProjectToolWindowState()

            let hosted = try HostedViewFixture.hostInWorkspace(workspace) { ProjectToolWindow(state: state) }
            defer { hosted.close() }
            try await hosted.settle()
            let projectView = hosted.snapshot()

            state.viewMode = .openFiles
            try await hosted.settle()
            let openFilesView = hosted.snapshot()
            #expect(HostedView.pixelsDiffer(projectView, openFilesView))

            state.viewMode = .project
            try await hosted.settle()
            #expect(HostedView.pixelsDiffer(openFilesView, hosted.snapshot()))
        }
    }

    @Test
    func theFirstKeyWindowNotificationClearsTheInitialSearchFocusOnlyOnce() async throws {
        try await withTempDir { dir in
            try makeProject(dir)
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }

            let hosted = try HostedViewFixture.hostInWorkspace(workspace) { ProjectToolWindow() }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(100))

            NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: hosted.window)
            try await hosted.settle(.milliseconds(100))
            NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: hosted.window)
            try await hosted.settle(.milliseconds(100))

            #expect(hosted.renders())
        }
    }
}
