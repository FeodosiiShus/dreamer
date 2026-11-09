import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
final class NotificationsToolbarDelegate: NSObject, NSToolbarDelegate {
    private let defaults: [NSToolbarItem.Identifier]

    init(defaults: [NSToolbarItem.Identifier]) {
        self.defaults = defaults
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        defaults
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        defaults + [.space, .notificationItem, .activityViewer]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        NSToolbarItem(itemIdentifier: itemIdentifier)
    }
}

@MainActor
struct NotificationsPanelHarness {
    let center: NotificationsFakeCenter
    let notificationCenter: NotificationCenter
    let manager: NotificationManager
    let model: NotificationPanelViewModel

    init(clock: any Clock<Duration> = ContinuousClock()) {
        let center = NotificationsFakeCenter()
        let notificationCenter = NotificationCenter()
        let manager = NotificationManager(center: center, notificationCenter: notificationCenter)
        self.center = center
        self.notificationCenter = notificationCenter
        self.manager = manager
        model = NotificationPanelViewModel(
            notificationManager: manager,
            notificationCenter: notificationCenter,
            clock: clock
        )
    }
}

@MainActor
@Suite(.uiGate)
struct NotificationPanelCoverageTests {
    @Test
    func hoverPausesAndResumesTheAutoHideTimers() async throws {
        let harness = NotificationsPanelHarness()
        let notification = makeTestNotification("hover")
        harness.model.handleNewNotification(notification)

        harness.model.hoverChanged(true)
        harness.model.hoverChanged(false)
        harness.model.hoverChanged(true)

        try await Task.sleep(for: .milliseconds(50))
        #expect(harness.model.hiddenNotificationIds.isEmpty)
    }

    @Test
    func scrollOffsetTracksWhetherThePanelIsScrolledToTop() {
        let model = NotificationsPanelHarness().model
        #expect(model.scrolledToTop)

        model.updateScrollOffset(-3)
        #expect(model.scrolledToTop)

        model.updateScrollOffset(0)
        #expect(model.scrolledToTop)

        model.updateScrollOffset(40)
        #expect(model.scrolledToTop == false)

        model.updateScrollOffset(80)
        #expect(model.scrolledToTop == false)

        model.updateScrollOffset(0)
        #expect(model.scrolledToTop)
    }

    @Test
    func focusChangeHidesAPresentedPanelOnlyWhenFocusIsLost() {
        let model = NotificationsPanelHarness().model
        let regular = makeTestNotification("focus")
        model.handleNewNotification(regular)
        model.toggleNotificationsVisibility()

        model.focusChanged(false, true)
        #expect(model.isPresented)

        model.focusChanged(true, false)
        #expect(model.isPresented == false)
        #expect(model.hiddenNotificationIds.contains(regular.id))
    }

    @Test
    func overflowFollowsContentAndContainerHeights() {
        let model = NotificationsPanelHarness().model
        #expect(model.hasOverflow == false)
        #expect(model.contentHeight == 0)

        model.contentHeightChanged(300, containerHeight: 200)
        #expect(model.contentHeight == 300)
        #expect(model.hasOverflow)

        model.contentHeightChanged(320, containerHeight: 200)
        #expect(model.hasOverflow)

        model.containerHeightChanged(400)
        #expect(model.hasOverflow == false)

        model.containerHeightChanged(500)
        #expect(model.hasOverflow == false)

        model.containerHeightChanged(100)
        #expect(model.hasOverflow)
    }

    @Test
    func dismissHandlerDismissesThroughThePanel() async throws {
        let harness = NotificationsPanelHarness()
        let notification = makeTestNotification("handler-dismiss")
        harness.model.handleNewNotification(notification)

        harness.model.dismissHandler(for: notification)()

        try await eventually(timeout: .seconds(5)) { harness.model.activeNotifications.isEmpty }
    }

    @Test
    func actionHandlerRunsTheActionAndDismissesAnimatedWhenNotPresented() async throws {
        let harness = NotificationsPanelHarness()
        let recorder = NotificationActionRecorder()
        let notification = CENotification(
            iconSymbol: "bell",
            title: "act",
            description: "d",
            actionButtonTitle: "a",
            action: { recorder.record() }
        )
        harness.model.handleNewNotification(notification)

        harness.model.actionHandler(for: notification)()

        #expect(recorder.invocations == 1)
        #expect(harness.model.activeNotifications.first?.isBeingDismissed == true)
        try await eventually(timeout: .seconds(5)) { harness.model.activeNotifications.isEmpty }
    }

    @Test
    func performingTheActionOfAPresentedPanelClosesItAndDismissesImmediately() {
        let harness = NotificationsPanelHarness()
        let recorder = NotificationActionRecorder()
        let notification = CENotification(
            iconSymbol: "bell",
            title: "presented",
            description: "d",
            actionButtonTitle: "a",
            action: { recorder.record() }
        )
        harness.model.handleNewNotification(notification)
        harness.model.toggleNotificationsVisibility()
        #expect(harness.model.isPresented)

        harness.model.performAction(of: notification)

        #expect(recorder.invocations == 1)
        #expect(harness.model.isPresented == false)
        #expect(harness.model.activeNotifications.isEmpty)
    }

    @Test
    func foreignObjectsInBroadcastsAreIgnored() {
        let harness = NotificationsPanelHarness()
        let known = makeTestNotification("known")
        harness.model.handleNewNotification(known)

        harness.notificationCenter.post(name: .init("NewNotificationAdded"), object: "not a notification")
        harness.notificationCenter.post(name: .init("NotificationDismissed"), object: nil)

        #expect(harness.model.activeNotifications.map(\.id) == [known.id])
    }

    @Test
    func managerBroadcastsReachThePanelThroughTheInjectedCenter() async throws {
        let harness = NotificationsPanelHarness()
        harness.manager.post(
            iconSymbol: "bell",
            title: "broadcast",
            description: "d",
            actionButtonTitle: "a",
            action: {}
        )
        try await eventually(timeout: .seconds(5)) { harness.model.activeNotifications.count == 1 }
        let posted = try #require(harness.model.activeNotifications.first)

        harness.manager.dismissNotification(posted)

        #expect(harness.model.activeNotifications.isEmpty)
        #expect(harness.manager.notifications.isEmpty)
    }

    @Test
    func toolbarGainsAndLosesTheNotificationItemWithTheNotifications() throws {
        try withTempDir { dir in
            let harness = NotificationsPanelHarness()
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let toolbarDelegate = NotificationsToolbarDelegate(defaults: [.activityViewer])
            let toolbar = NSToolbar(identifier: "notifications-\(UUID().uuidString)")
            toolbar.delegate = toolbarDelegate
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.toolbar = toolbar
            window.orderFront(nil)
            let plainWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            plainWindow.isReleasedWhenClosed = false
            workspace.addWindowController(NSWindowController(window: window))
            workspace.addWindowController(NSWindowController(window: plainWindow))
            harness.model.workspace = workspace
            #expect(toolbar.items.map(\.itemIdentifier) == [.activityViewer])

            harness.model.updateToolbarItem()
            #expect(toolbar.items.map(\.itemIdentifier) == [.activityViewer])

            let notification = makeTestNotification("toolbar")
            harness.model.handleNewNotification(notification)
            harness.model.updateToolbarItem()
            #expect(toolbar.items.map(\.itemIdentifier) == [.activityViewer, .space, .notificationItem])

            harness.model.updateToolbarItem()
            #expect(toolbar.items.map(\.itemIdentifier) == [.activityViewer, .space, .notificationItem])

            harness.model.dismissNotification(notification, disableAnimation: true)
            harness.model.updateToolbarItem()
            #expect(toolbar.items.map(\.itemIdentifier) == [.activityViewer])

            window.close()
            plainWindow.close()
        }
    }

    @Test
    func toolbarWithoutTheActivityViewerIsLeftAlone() throws {
        try withTempDir { dir in
            let harness = NotificationsPanelHarness()
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let toolbarDelegate = NotificationsToolbarDelegate(defaults: [])
            let toolbar = NSToolbar(identifier: "notifications-bare-\(UUID().uuidString)")
            toolbar.delegate = toolbarDelegate
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.toolbar = toolbar
            window.orderFront(nil)
            workspace.addWindowController(NSWindowController(window: window))
            harness.model.workspace = workspace
            harness.model.handleNewNotification(makeTestNotification("bare"))

            harness.model.updateToolbarItem()

            #expect(toolbar.items.isEmpty)
            window.close()
        }
    }

    private func makeToolbarWindow(
        workspace: WorkspaceDocument,
        defaults: [NSToolbarItem.Identifier] = [.activityViewer]
    ) -> (window: NSWindow, toolbar: NSToolbar, delegate: NotificationsToolbarDelegate) {
        let delegate = NotificationsToolbarDelegate(defaults: defaults)
        let toolbar = NSToolbar(identifier: "notifications-extra-\(UUID().uuidString)")
        toolbar.delegate = delegate
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.toolbar = toolbar
        window.orderFront(nil)
        workspace.addWindowController(NSWindowController(window: window))
        return (window, toolbar, delegate)
    }

    @Test
    func repeatedDismissalsKeepTheToolbarConsistent() throws {
        try withTempDir { dir in
            let harness = NotificationsPanelHarness()
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let fixture = makeToolbarWindow(workspace: workspace)
            defer { fixture.window.close() }
            harness.model.workspace = workspace
            let notification = makeTestNotification("repeated")
            harness.model.handleNewNotification(notification)
            #expect(fixture.toolbar.items.map(\.itemIdentifier) == [.activityViewer, .space, .notificationItem])

            harness.model.dismissNotification(notification, disableAnimation: true)
            harness.model.dismissNotification(notification, disableAnimation: true)
            harness.model.updateToolbarItem()
            harness.model.updateToolbarItem()

            #expect(fixture.toolbar.items.map(\.itemIdentifier) == [.activityViewer])
        }
    }

    @Test
    func hidingToleratesAToolbarWhoseItemsWereRemovedByHand() throws {
        try withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let fixture = makeToolbarWindow(workspace: workspace)
            defer { fixture.window.close() }
            fixture.toolbar.showNotificationItem()
            fixture.toolbar.showNotificationItem()
            #expect(fixture.toolbar.items.map(\.itemIdentifier) == [.activityViewer, .space, .notificationItem])

            fixture.toolbar.removeItem(at: 1)
            fixture.toolbar.hideNotificationItem()
            #expect(fixture.toolbar.items.map(\.itemIdentifier) == [.activityViewer])

            fixture.toolbar.hideNotificationItem()
            #expect(fixture.toolbar.items.map(\.itemIdentifier) == [.activityViewer])

            fixture.toolbar.showNotificationItem()
            fixture.toolbar.removeItem(at: 2)
            fixture.toolbar.hideNotificationItem()
            #expect(fixture.toolbar.items.map(\.itemIdentifier) == [.activityViewer, .space])
        }
    }

    @Test
    func everyWindowOfTheWorkspaceGainsAndLosesTheItem() throws {
        try withTempDir { dir in
            let harness = NotificationsPanelHarness()
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let first = makeToolbarWindow(workspace: workspace)
            let second = makeToolbarWindow(workspace: workspace)
            defer {
                first.window.close()
                second.window.close()
            }
            harness.model.workspace = workspace
            let notification = makeTestNotification("several")

            harness.model.handleNewNotification(notification)
            #expect(first.toolbar.items.map(\.itemIdentifier) == [.activityViewer, .space, .notificationItem])
            #expect(second.toolbar.items.map(\.itemIdentifier) == [.activityViewer, .space, .notificationItem])

            second.toolbar.removeItem(at: 2)
            harness.model.dismissNotification(notification, disableAnimation: true)
            harness.model.updateToolbarItem()

            #expect(first.toolbar.items.map(\.itemIdentifier) == [.activityViewer])
            #expect(second.toolbar.items.map(\.itemIdentifier) == [.activityViewer, .space])
        }
    }
}
