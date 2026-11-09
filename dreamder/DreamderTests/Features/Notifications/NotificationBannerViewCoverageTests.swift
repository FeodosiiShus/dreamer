import AppKit
import SwiftUI
import Testing
@testable import Dreamder

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
