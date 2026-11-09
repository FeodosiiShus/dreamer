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
struct NotificationBannerViewCoverageTests {
    private func host(
        _ workspace: WorkspaceDocument,
        _ notification: CENotification,
        panel: NotificationPanelViewModel,
        hover: NotificationBannerHover?
    ) throws -> HostedView {
        try HostedViewFixture.hostInWorkspace(workspace, size: NSSize(width: 360, height: 160)) {
            NotificationBannerView(
                notification: notification,
                panel: panel,
                hover: hover,
                onDismiss: {},
                onAction: {}
            )
        }
    }

    @Test
    func everyIconVariantRendersWithStickyAndRegularLayouts() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let panel = NotificationsPanelHarness().model
            var snapshots: [NSBitmapImageRep?] = []

            for notification in notificationsMixedSet() {
                let hosted = try host(workspace, notification, panel: panel, hover: nil)
                try await hosted.settle(.milliseconds(60))
                snapshots.append(hosted.snapshot())
                hosted.close()
            }

            #expect(snapshots.count == 6)
            #expect(HostedView.pixelsDiffer(snapshots[0], snapshots[5]))
            #expect(HostedView.pixelsDiffer(snapshots[0], snapshots[4]))
            #expect(HostedView.pixelsDiffer(snapshots[0], snapshots[2]))
        }
    }

    @Test
    func hoveringARegularNotificationRevealsItsButtonsAndPausesTheTimers() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let clock = TestClock()
            let panel = NotificationsPanelHarness(clock: clock).model
            let notification = makeTestNotification("hover")
            panel.handleNewNotification(notification)
            try await clock.waitForSleepers()
            let hover = NotificationBannerHover(panel: panel)
            let hosted = try host(workspace, notification, panel: panel, hover: hover)
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(100))
            #expect(hover.isHovering == false)
            #expect(clock.pendingSleeperCount == 1)

            hover.changed(true)
            try await hosted.settle(.milliseconds(100))

            #expect(hover.isHovering)
            try await eventually(timeout: .seconds(30)) { clock.pendingSleeperCount == 0 }
            #expect(hosted.renders())

            hover.changed(false)
            try await hosted.settle(.milliseconds(100))

            #expect(hover.isHovering == false)
            try await clock.waitForSleepers(1, timeout: .seconds(30))
            clock.advance(by: .seconds(5))
            try await eventually(timeout: .seconds(30)) { panel.hiddenNotificationIds.contains(notification.id) }
        }
    }

    @Test
    func hoveringAStickyNotificationKeepsItsLayout() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let panel = NotificationsPanelHarness().model
            let sticky = makeTestNotification("sticky", sticky: true)
            let hover = NotificationBannerHover(panel: panel)
            let hosted = try host(workspace, sticky, panel: panel, hover: hover)
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(60))

            hover.changed(true)
            try await hosted.settle(.milliseconds(250))

            #expect(hover.isHovering)
            #expect(hosted.renders())
        }
    }

    @Test
    func dismissTransitionFadesOrSlidesOnlyWhileActive() async throws {
        func render(useOpacity: Bool, isIdentity: Bool) async throws -> NSBitmapImageRep? {
            let hosted = HostedViewFixture.host(size: NSSize(width: 600, height: 100)) {
                Color.red
                    .frame(width: 40, height: 40)
                    .modifier(DismissTransition(useOpactityTransition: useOpacity, isIdentity: isIdentity))
                    .frame(width: 600, height: 100, alignment: .leading)
            }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(40))
            return hosted.snapshot()
        }

        let identity = try await render(useOpacity: true, isIdentity: true)
        let faded = try await render(useOpacity: true, isIdentity: false)
        let slidIdentity = try await render(useOpacity: false, isIdentity: true)
        let slid = try await render(useOpacity: false, isIdentity: false)

        #expect(HostedView.pixelsDiffer(identity, faded))
        #expect(HostedView.pixelsDiffer(slidIdentity, slid))
        #expect(HostedView.pixelsDiffer(identity, slidIdentity) == false)
    }

    @Test
    func glassContainerHostsItsContent() async throws {
        let hosted = HostedViewFixture.host(size: NSSize(width: 200, height: 100)) {
            Text("container").modifier(NotificationGlassContainer())
        }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(60))

        #expect(hosted.renders())
    }

    @Test
    func hoverControlsAreDrawnOnlyWhileVisible() async throws {
        func snapshot(isVisible: Bool) async throws -> NSBitmapImageRep? {
            let hosted = HostedViewFixture.host(size: NSSize(width: 240, height: 120)) {
                ZStack {
                    NotificationBannerActionButton(isVisible: isVisible, title: "Open", action: {})
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    NotificationBannerDismissButton(isVisible: isVisible, action: {})
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(60))
            return hosted.snapshot()
        }

        let hidden = try await snapshot(isVisible: false)
        let visible = try await snapshot(isVisible: true)

        #expect(HostedView.pixelsDiffer(hidden, visible))
    }
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
            model.scrolledToTop = false
            try await hosted.settle(.milliseconds(100))

            model.toggleNotificationsVisibility()

            #expect(model.isPresented == false)
            try await eventually(timeout: .seconds(5)) { model.hiddenNotificationIds.contains(regular.id) }
            try await hosted.settle(.milliseconds(300))
            try await eventually(timeout: .seconds(5)) { model.scrolledToTop }
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
