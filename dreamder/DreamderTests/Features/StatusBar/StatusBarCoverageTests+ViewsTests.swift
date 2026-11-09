import AppKit
import CodeEditSourceEditor
import SwiftUI
import Testing
@testable import Dreamder

extension StatusBarCoverageTests {
    @Test
    func statusBarRendersBreadcrumbsForNestedFilesAndFilesOutsideTheProject() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let empty = try HostedViewFixture.hostInWorkspace(workspace, size: NSSize(width: 900, height: 40)) {
                StatusBarView()
            }
            defer { empty.close() }
            try await empty.settle()
            #expect(empty.renders())
            let emptySnapshot = empty.snapshot()

            let nested = try writeFile(in: dir, "Sources/App/Main.swift")
            try open(nested, in: workspace)
            let nestedView = try HostedViewFixture.hostInWorkspace(workspace, size: NSSize(width: 900, height: 40)) {
                StatusBarView()
            }
            defer { nestedView.close() }
            try await nestedView.settle()
            #expect(nestedView.renders())
            #expect(HostedView.pixelsDiffer(emptySnapshot, nestedView.snapshot()))

            try await withTempDir { outside in
                let foreign = try writeFile(in: outside, "Foreign.swift")
                let editor = try #require(workspace.editorManager?.activeEditor)
                editor.workspace = workspace
                editor.openTab(file: CEWorkspaceFile(url: foreign), asTemporary: false)
                let foreignView = try HostedViewFixture.hostInWorkspace(
                    workspace,
                    size: NSSize(width: 900, height: 40)
                ) {
                    StatusBarView()
                }
                defer { foreignView.close() }
                try await foreignView.settle()
                #expect(foreignView.renders())
            }
        }
    }

    @Test
    func breadcrumbActionsRevealTheProjectToolWindow() async throws {
        try withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            _ = try writeFile(in: dir, "Sources/Main.swift")

            StatusBarProjectBreadcrumbs.reveal(relativePath: "Sources", projectURL: dir, workspace: workspace)
            #expect(workspace.toolWindowManager.isVisible(.project))

            StatusBarProjectBreadcrumbs.reveal(relativePath: "Sources", projectURL: nil, workspace: workspace)
            StatusBarProjectBreadcrumbs.revealFile(workspace: workspace)
            #expect(workspace.toolWindowManager.isVisible(.project))
        }
    }

    @Test
    func notificationsButtonTogglesThePanelAndMarksNotificationsRead() async throws {
        let harness = NotificationsPanelHarness()
        harness.manager.post(
            iconSymbol: "bell",
            title: "status-bar",
            description: "d",
            actionButtonTitle: "a",
            action: {}
        )
        try await eventually { harness.manager.unreadCount == 1 }

        StatusBarNotificationsButton.toggle(panel: harness.model, notificationManager: harness.manager)
        #expect(harness.model.isPresented)
        #expect(harness.manager.unreadCount == 0)

        StatusBarNotificationsButton.toggle(panel: harness.model, notificationManager: harness.manager)
        #expect(!harness.model.isPresented)
    }

    @Test
    func notificationsButtonRendersWithAndWithoutUnreadNotifications() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let quiet = NotificationsPanelHarness()
            let busy = NotificationsPanelHarness()
            busy.manager.post(
                iconSymbol: "bell",
                title: "unread",
                description: "d",
                actionButtonTitle: "a",
                action: {}
            )
            try await eventually { busy.manager.unreadCount == 1 }
            let quietView = try HostedViewFixture.hostInWorkspace(workspace, size: NSSize(width: 40, height: 40)) {
                StatusBarNotificationsButton(notificationManager: quiet.manager)
            }
            let busyView = try HostedViewFixture.hostInWorkspace(workspace, size: NSSize(width: 40, height: 40)) {
                StatusBarNotificationsButton(notificationManager: busy.manager)
            }
            defer {
                quietView.close()
                busyView.close()
            }
            try await quietView.settle()
            try await busyView.settle()

            #expect(quietView.renders())
            #expect(HostedView.pixelsDiffer(quietView.snapshot(), busyView.snapshot()))
        }
    }

    @Test
    func statusBarMenuStyleRendersAMenu() async throws {
        let hosted = HostedViewFixture.host(size: NSSize(width: 120, height: 40)) {
            Menu("Encoding") {
                Button("UTF-8") {}
            }
            .menuStyle(.statusBar)
        }
        defer { hosted.close() }

        try await hosted.settle()

        #expect(hosted.renders())
    }

    @Test
    func cursorModifierPushesAndPopsTheCursor() async throws {
        let hosted = HostedViewFixture.host(size: NSSize(width: 80, height: 40)) {
            Text("Hover").cursor(.pointingHand)
        }
        defer { hosted.close() }
        try await hosted.settle()
        #expect(hosted.renders())

        NSCursor.pointingHand.setHovering(true)
        NSCursor.pointingHand.setHovering(false)
    }

    @Test
    func utilityAreaCommandTogglesThePanel() throws {
        try withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let model = try #require(workspace.utilityAreaModel)
            let before = model.isCollapsed

            StatusBarView.togglePanelCommand(for: model)()

            #expect(model.isCollapsed != before)
        }
    }

    @Test
    func breadcrumbClosuresRevealTheProjectToolWindow() throws {
        try withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            _ = try writeFile(in: dir, "Sources/Main.swift")
            workspace.toolWindowManager.hide(.project)

            StatusBarProjectBreadcrumbs.revealing(relativePath: "Sources", projectURL: dir, workspace: workspace)()
            #expect(workspace.toolWindowManager.isVisible(.project))

            workspace.toolWindowManager.hide(.project)
            StatusBarProjectBreadcrumbs.revealingFile(workspace: workspace)()
            #expect(workspace.toolWindowManager.isVisible(.project))
        }
    }

    @Test
    func projectNameFallsBackToEmptyWithoutAProject() {
        let url = URL(fileURLWithPath: "/tmp/Project", isDirectory: true)

        #expect(StatusBarProjectBreadcrumbs(file: nil, projectURL: nil).projectName == "Empty")
        #expect(StatusBarProjectBreadcrumbs(file: nil, projectURL: url).projectName == "Project")
    }

    @Test
    func notificationsActionTogglesThePanel() async throws {
        let harness = NotificationsPanelHarness()

        let action = StatusBarNotificationsButton.togglingAction(
            panel: harness.model,
            notificationManager: harness.manager
        )
        action()

        #expect(harness.model.isPresented)
    }

    @Test
    func statusBarItemsTrackHover() {
        let button = StatusBarWidgetButton(action: {}, label: { _ in Text("x") })
        button.setHovering(true)
        button.setHovering(false)

        let label = StatusBarCursorPositionLabel()
        label.hoverChanged(true)
        label.hoverChanged(false)
    }
}
