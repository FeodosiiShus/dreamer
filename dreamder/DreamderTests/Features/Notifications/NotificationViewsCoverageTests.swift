import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Observable
final class NotificationsActiveState {
    var value: ControlActiveState = .key
}

struct NotificationsPanelRoot: View {
    let state: NotificationsActiveState

    var body: some View {
        NotificationPanelView()
            .environment(\.controlActiveState, state.value)
    }
}

@MainActor
func notificationsMixedSet(count: Int = 0) -> [CENotification] {
    var result = [
        CENotification(
            iconSymbol: "bell",
            title: "Symbol default color",
            description: "Plain description",
            actionButtonTitle: "Open",
            action: {}
        ),
        CENotification(
            iconSymbol: "bell",
            iconColor: .green,
            title: "Symbol colored",
            description: "Plain description",
            actionButtonTitle: "Open",
            action: {}
        ),
        CENotification(
            iconText: "T",
            title: "Text default colors",
            description: "Plain description",
            actionButtonTitle: "Open",
            action: {}
        ),
        CENotification(
            iconText: "T",
            iconTextColor: .red,
            iconColor: .orange,
            title: "Text colored",
            description: "Plain description",
            actionButtonTitle: "Open",
            action: {}
        ),
        CENotification(
            iconImage: Image(systemName: "bell"),
            title: "Image",
            description: "Plain description",
            actionButtonTitle: "Open",
            action: {}
        ),
        CENotification(
            iconSymbol: "bell",
            title: "Sticky",
            description: "Sticky description",
            actionButtonTitle: "Open",
            action: {},
            isSticky: true
        )
    ]
    for index in 0..<count {
        result.append(makeTestNotification("extra-\(index)"))
    }
    return result
}

@MainActor
@Suite(.uiGate)
struct NotificationPanelViewCoverageTests {
    private func host(
        _ workspace: WorkspaceDocument,
        state: NotificationsActiveState,
        size: NSSize = NSSize(width: 700, height: 600)
    ) throws -> HostedView {
        try HostedViewFixture.hostInWorkspace(workspace, size: size) {
            NotificationsPanelRoot(state: state)
        }
    }

    private func install(_ model: NotificationPanelViewModel, in workspace: WorkspaceDocument) {
        workspace.notificationPanel = model
        model.workspace = workspace
    }

    @Test
    func emptyAndPopulatedPanelsRenderDifferently() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let model = NotificationsPanelHarness().model
            install(model, in: workspace)
            let state = NotificationsActiveState()
            let hosted = try host(workspace, state: state)
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(100))
            let empty = hosted.snapshot()

            for notification in notificationsMixedSet() {
                model.handleNewNotification(notification)
            }
            try await hosted.settle(.milliseconds(300))

            #expect(HostedView.pixelsDiffer(empty, hosted.snapshot()))
            try await eventually(timeout: .seconds(5)) { model.contentHeight > 0 }
        }
    }

    @Test
    func inactiveWindowHidesThePanel() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let model = NotificationsPanelHarness().model
            install(model, in: workspace)
            for notification in notificationsMixedSet() {
                model.handleNewNotification(notification)
            }
            let state = NotificationsActiveState()
            let hosted = try host(workspace, state: state)
            defer { hosted.close() }
            try await eventually(timeout: .seconds(5)) { model.contentHeight > 0 }
            try await hosted.settle(.milliseconds(300))
            let active = hosted.snapshot()

            state.value = .inactive

            try await eventually(timeout: .seconds(10)) { HostedView.pixelsDiffer(active, hosted.snapshot()) }
        }
    }

    @Test
    func losingControlWhilePresentedHidesTheNotificationsAfterTheDelay() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let model = NotificationsPanelHarness().model
            install(model, in: workspace)
            let regular = makeTestNotification("regular")
            model.handleNewNotification(regular)
            let state = NotificationsActiveState()
            let hosted = try host(workspace, state: state)
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(100))
            model.toggleNotificationsVisibility()
            try await hosted.settle(.milliseconds(200))
            #expect(model.isPresented)

            state.value = .inactive

            try await eventually(timeout: .seconds(5)) { model.isPresented == false }
            #expect(model.hiddenNotificationIds.contains(regular.id))
        }
    }

    @Test
    func controlChangesWhileNotPresentedLeaveThePanelAlone() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let model = NotificationsPanelHarness().model
            install(model, in: workspace)
            model.handleNewNotification(makeTestNotification("quiet"))
            let state = NotificationsActiveState()
            let hosted = try host(workspace, state: state)
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(100))

            state.value = .inactive
            try await hosted.settle(.milliseconds(100))
            state.value = .key
            try await hosted.settle(.milliseconds(100))

            #expect(model.isPresented == false)
            #expect(model.hiddenNotificationIds.isEmpty)
        }
    }

    @Test
    func closingAScrolledPanelScrollsBackToTheTop() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let clock = TestClock()
            let model = NotificationsPanelHarness(clock: clock).model
            install(model, in: workspace)
            let regular = makeTestNotification("regular")
            model.handleNewNotification(regular)
            let state = NotificationsActiveState()
            let hosted = try host(workspace, state: state)
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(100))
            model.toggleNotificationsVisibility()
            try await hosted.settle(.milliseconds(200))
            model.scrolledToTop = false
            try await hosted.settle(.milliseconds(100))

            model.toggleNotificationsVisibility()

            #expect(model.isPresented == false)
            try await hosted.settle(.milliseconds(300))
            let slideOutDeadline = clock.now.advanced(by: .milliseconds(300))
            try await eventually { clock.pendingDeadlines.contains(slideOutDeadline) }
            clock.advance(by: .milliseconds(300))
            try await eventually { model.hiddenNotificationIds.contains(regular.id) }
            let scrollResetDeadline = clock.now.advanced(by: .milliseconds(100))
            try await eventually { clock.pendingDeadlines.contains(scrollResetDeadline) }
            #expect(model.scrolledToTop == false)
            clock.advance(by: .milliseconds(100))
            try await eventually { model.scrolledToTop }
        }
    }

    @Test
    func overflowAppearsInASmallPanelAndDisappearsWhenItGrows() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let model = NotificationsPanelHarness().model
            install(model, in: workspace)
            for notification in notificationsMixedSet(count: 6) {
                model.handleNewNotification(notification)
            }
            let state = NotificationsActiveState()
            let hosted = try host(workspace, state: state, size: NSSize(width: 700, height: 200))
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(300))
            try await eventually(timeout: .seconds(5)) { model.hasOverflow }

            hosted.window.setContentSize(NSSize(width: 700, height: 3000))
            try await hosted.settle(.milliseconds(300))

            try await eventually(timeout: .seconds(5)) { model.hasOverflow == false }
        }
    }

    @Test
    func panelWithOnlyHiddenNotificationsIgnoresHitTesting() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let model = NotificationsPanelHarness().model
            install(model, in: workspace)
            let regular = makeTestNotification("regular")
            model.handleNewNotification(regular)
            model.toggleNotificationsVisibility()
            model.toggleNotificationsVisibility()
            #expect(model.isNotificationVisible(regular) == false)
            let state = NotificationsActiveState()
            let hosted = try host(workspace, state: state)
            defer { hosted.close() }

            try await hosted.settle(.milliseconds(100))

            #expect(model.visibleNotifications.isEmpty)
        }
    }
}
