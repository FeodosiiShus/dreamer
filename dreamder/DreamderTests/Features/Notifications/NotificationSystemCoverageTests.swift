import AppKit
import Foundation
import SwiftUI
import Testing
import UserNotifications
@testable import Dreamder

@MainActor
final class NotificationsFakeCenter: SystemNotificationCenter {
    weak var attachedDelegate: (any UNUserNotificationCenterDelegate)?
    private(set) var categories: Set<UNNotificationCategory> = []
    private(set) var authorizationRequests: [UNAuthorizationOptions] = []
    private(set) var added: [UNNotificationRequest] = []
    private(set) var removedIdentifiers: [[String]] = []
    private(set) var removeAllCount = 0

    func attach(delegate: any UNUserNotificationCenterDelegate) {
        attachedDelegate = delegate
    }

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        self.categories = categories
    }

    func requestAuthorization(options: UNAuthorizationOptions) async {
        authorizationRequests.append(options)
    }

    func add(_ request: UNNotificationRequest) {
        added.append(request)
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        removedIdentifiers.append(identifiers)
    }

    func removeAllDeliveredNotifications() {
        removeAllCount += 1
    }
}

@MainActor
final class NotificationsEventLog {
    private(set) var objects: [Any?] = []

    func record(_ object: Any?) {
        objects.append(object)
    }
}

nonisolated func notificationsEmptyCoder() -> NSKeyedUnarchiver? {
    let archiver = NSKeyedArchiver(requiringSecureCoding: false)
    archiver.finishEncoding()
    guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: archiver.encodedData) else { return nil }
    unarchiver.requiresSecureCoding = false
    return unarchiver
}

final class NotificationsFakeSystemNotification: UNNotification {
    let fakeRequest: UNNotificationRequest

    init?(request: UNNotificationRequest) {
        fakeRequest = request
        guard let coder = notificationsEmptyCoder() else { return nil }
        super.init(coder: coder)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var request: UNNotificationRequest {
        fakeRequest
    }
}

final class NotificationsFakeSystemResponse: UNNotificationResponse {
    let fakeNotification: UNNotification
    let fakeAction: String

    init?(notification: UNNotification, action: String) {
        fakeNotification = notification
        fakeAction = action
        guard let coder = notificationsEmptyCoder() else { return nil }
        super.init(coder: coder)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var notification: UNNotification {
        fakeNotification
    }

    override var actionIdentifier: String {
        fakeAction
    }
}

@MainActor
struct NotificationsSystemHarness {
    let manager: NotificationManager
    let center: NotificationsFakeCenter
    let notificationCenter: NotificationCenter

    init() {
        let center = NotificationsFakeCenter()
        let notificationCenter = NotificationCenter()
        self.center = center
        self.notificationCenter = notificationCenter
        manager = NotificationManager(center: center, notificationCenter: notificationCenter)
    }

    func post(
        _ title: String,
        actionTitle: String = "Open",
        sticky: Bool = false,
        action: @escaping () -> Void = {}
    ) async throws -> CENotification {
        manager.post(
            iconSymbol: "bell",
            title: title,
            description: "\(title) description",
            actionButtonTitle: actionTitle,
            action: action,
            isSticky: sticky
        )
        try await eventually(timeout: .seconds(5)) {
            manager.notifications.contains { $0.title == title }
        }
        return try #require(manager.notifications.first { $0.title == title })
    }

    func response(for notification: CENotification, action: String) throws -> NotificationsFakeSystemResponse {
        let request = UNNotificationRequest(
            identifier: notification.id.uuidString,
            content: UNMutableNotificationContent(),
            trigger: nil
        )
        let system = try #require(NotificationsFakeSystemNotification(request: request))
        return try #require(NotificationsFakeSystemResponse(notification: system, action: action))
    }
}

@MainActor
@Suite(.uiGate)
struct NotificationSystemCoverageTests {
    @Test
    func initialisationAttachesTheDelegateRegistersTheActionCategoryAndRequestsAuthorization() async throws {
        let harness = NotificationsSystemHarness()

        #expect(harness.center.attachedDelegate === harness.manager)
        let category = try #require(harness.center.categories.first)
        #expect(harness.center.categories.count == 1)
        #expect(category.identifier == "ACTIONABLE")
        #expect(category.options == .customDismissAction)
        let action = try #require(category.actions.first)
        #expect(category.actions.count == 1)
        #expect(action.identifier == "ACTION_BUTTON")
        #expect(action.options == .foreground)
        try await eventually(timeout: .seconds(5)) { !harness.center.authorizationRequests.isEmpty }
        #expect(harness.center.authorizationRequests == [[.alert, .sound, .badge]])
    }

    @Test
    func activeAppPostsBroadcastToWorkspacesWithoutShowingSystemNotifications() async throws {
        let harness = NotificationsSystemHarness()
        let log = NotificationsEventLog()
        let token = harness.notificationCenter.addObserver(
            forName: .init("NewNotificationAdded"),
            object: nil,
            queue: nil
        ) { notification in
            let object = notification.object as? CENotification
            MainActor.assumeIsolated { log.record(object) }
        }
        defer { harness.notificationCenter.removeObserver(token) }

        let symbol = try await harness.post("symbol")
        harness.manager.post(
            iconText: "T",
            iconTextColor: .red,
            title: "text",
            description: "d",
            actionButtonTitle: "a",
            action: {}
        )
        harness.manager.post(
            iconImage: Image(systemName: "bell"),
            title: "image",
            description: "d",
            actionButtonTitle: "a",
            action: {},
            isSticky: true
        )
        try await eventually(timeout: .seconds(5)) { harness.manager.notifications.count == 3 }

        #expect(harness.manager.notifications.map(\.title) == ["symbol", "text", "image"])
        #expect(harness.manager.notifications[2].isSticky)
        #expect(harness.manager.unreadCount == 3)
        #expect(log.objects.count == 3)
        #expect((log.objects.first as? CENotification)?.id == symbol.id)
        #expect(harness.center.added.isEmpty)
    }

    @Test
    func backgroundedAppShowsASystemNotificationWithTheActionCategory() async throws {
        let harness = NotificationsSystemHarness()
        harness.notificationCenter.post(name: NSApplication.didResignActiveNotification, object: nil)

        let actionable = try await harness.post("actionable")
        let plain = try await harness.post("plain", actionTitle: "")

        try await eventually(timeout: .seconds(5)) { harness.center.added.count == 2 }
        let first = harness.center.added[0]
        #expect(first.identifier == actionable.id.uuidString)
        #expect(first.content.title == "actionable")
        #expect(first.content.body == "actionable description")
        #expect(first.content.categoryIdentifier == "ACTIONABLE")
        #expect(first.trigger == nil)
        let second = harness.center.added[1]
        #expect(second.identifier == plain.id.uuidString)
        #expect(second.content.categoryIdentifier.isEmpty)
    }

    @Test
    func becomingActiveClearsDeliveredNotificationsAndStopsSystemNotifications() async throws {
        let harness = NotificationsSystemHarness()
        harness.notificationCenter.post(name: NSApplication.didResignActiveNotification, object: nil)
        _ = try await harness.post("background")
        try await eventually(timeout: .seconds(5)) { harness.center.added.count == 1 }

        harness.notificationCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        #expect(harness.center.removeAllCount == 1)
        _ = try await harness.post("foreground")
        try await Task.sleep(for: .milliseconds(50))

        #expect(harness.center.added.count == 1)
    }

    @Test
    func dismissingRemovesTheSystemNotificationAndBroadcastsTheDismissal() async throws {
        let harness = NotificationsSystemHarness()
        let log = NotificationsEventLog()
        let token = harness.notificationCenter.addObserver(
            forName: .init("NotificationDismissed"),
            object: nil,
            queue: nil
        ) { notification in
            let object = notification.object as? CENotification
            MainActor.assumeIsolated { log.record(object) }
        }
        defer { harness.notificationCenter.removeObserver(token) }
        let notification = try await harness.post("dismissed")

        harness.manager.dismissNotification(notification)

        #expect(harness.center.removedIdentifiers == [[notification.id.uuidString]])
        #expect(harness.manager.notifications.isEmpty)
        #expect((log.objects.first as? CENotification)?.id == notification.id)
    }

    @Test
    func systemResponseRunsTheActionAndDismissesThroughTheFakeCenter() async throws {
        let harness = NotificationsSystemHarness()
        let recorder = NotificationActionRecorder()
        let notification = try await harness.post("response") { recorder.record() }

        harness.manager.handleSystemNotificationResponse(id: notification.id.uuidString)

        #expect(recorder.invocations == 1)
        #expect(harness.manager.notifications.isEmpty)
        #expect(harness.center.removedIdentifiers == [[notification.id.uuidString]])
    }

    @Test
    func liveCenterForwardsEveryOperationToTheSystemCenter() async throws {
        _ = NotificationManager.shared
        let live = LiveSystemNotificationCenter()
        let identifier = "coverage-\(UUID().uuidString)"
        let content = UNMutableNotificationContent()
        content.title = "coverage"
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)
        )

        live.add(request)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        live.removeDeliveredNotifications(withIdentifiers: [identifier])
        live.removeAllDeliveredNotifications()
        try await Task.sleep(for: .milliseconds(50))
    }
}

@MainActor
@Suite(.uiGate)
struct NotificationDelegateCoverageTests {
    private let systemCenter = UNUserNotificationCenter.current()

    private func receive(
        _ harness: NotificationsSystemHarness,
        notification: CENotification,
        action: String
    ) throws -> Int {
        let response = try harness.response(for: notification, action: action)
        let completions = NotificationActionRecorder()
        harness.manager.userNotificationCenter(
            systemCenter,
            didReceive: response,
            withCompletionHandler: { completions.record() }
        )
        return completions.invocations
    }

    @Test
    func actionButtonRunsTheActionAndDismissesTheNotification() async throws {
        let harness = NotificationsSystemHarness()
        let recorder = NotificationActionRecorder()
        let notification = try await harness.post("action") { recorder.record() }

        let completions = try receive(harness, notification: notification, action: "ACTION_BUTTON")

        #expect(completions == 1)
        #expect(recorder.invocations == 1)
        #expect(harness.manager.notifications.isEmpty)
    }

    @Test
    func defaultActionRunsTheActionAndDismissesTheNotification() async throws {
        let harness = NotificationsSystemHarness()
        let recorder = NotificationActionRecorder()
        let notification = try await harness.post("default") { recorder.record() }

        let completions = try receive(harness, notification: notification, action: UNNotificationDefaultActionIdentifier)

        #expect(completions == 1)
        #expect(recorder.invocations == 1)
        #expect(harness.manager.notifications.isEmpty)
    }

    @Test
    func dismissActionRemovesTheNotificationWithoutRunningTheAction() async throws {
        let harness = NotificationsSystemHarness()
        let recorder = NotificationActionRecorder()
        let notification = try await harness.post("dismiss") { recorder.record() }

        let completions = try receive(harness, notification: notification, action: UNNotificationDismissActionIdentifier)

        #expect(completions == 1)
        #expect(recorder.invocations == 0)
        #expect(harness.manager.notifications.isEmpty)
    }

    @Test
    func unknownActionKeepsTheNotificationAndStillCompletes() async throws {
        let harness = NotificationsSystemHarness()
        let recorder = NotificationActionRecorder()
        let notification = try await harness.post("unknown") { recorder.record() }

        let completions = try receive(harness, notification: notification, action: "SOMETHING_ELSE")

        #expect(completions == 1)
        #expect(recorder.invocations == 0)
        #expect(harness.manager.notifications.count == 1)
    }

    @Test
    func responseForAnUnknownNotificationOnlyCompletes() async throws {
        let harness = NotificationsSystemHarness()
        let recorder = NotificationActionRecorder()
        let kept = try await harness.post("kept") { recorder.record() }
        let stranger = makeTestNotification("stranger")

        let completions = try receive(harness, notification: stranger, action: "ACTION_BUTTON")

        #expect(completions == 1)
        #expect(recorder.invocations == 0)
        #expect(harness.manager.notifications.map(\.id) == [kept.id])
    }

    @Test
    func presentationShowsBannerAndSound() async throws {
        let harness = NotificationsSystemHarness()
        let notification = try await harness.post("present")
        let request = UNNotificationRequest(
            identifier: notification.id.uuidString,
            content: UNMutableNotificationContent(),
            trigger: nil
        )
        let system = try #require(NotificationsFakeSystemNotification(request: request))
        var presented: UNNotificationPresentationOptions = []

        harness.manager.userNotificationCenter(
            systemCenter,
            willPresent: system,
            withCompletionHandler: { presented = $0 }
        )

        #expect(presented == [.banner, .sound])
    }
}

@MainActor
@Suite(.uiGate)
struct NotificationIconCoverageTests {
    @Test
    func everyIconVariantIsStoredOnTheNotification() {
        let symbol = CENotification(
            iconSymbol: "bell",
            title: "s",
            description: "d",
            actionButtonTitle: "a",
            action: {}
        )
        let text = CENotification(
            iconText: "T",
            iconTextColor: .red,
            iconColor: .blue,
            title: "t",
            description: "d",
            actionButtonTitle: "a",
            action: {}
        )
        let image = CENotification(
            iconImage: Image(systemName: "bell"),
            title: "i",
            description: "d",
            actionButtonTitle: "a",
            action: {},
            isSticky: true,
            isRead: true
        )

        guard case let .symbol(name, color) = symbol.icon else {
            Issue.record("symbol icon expected")
            return
        }
        #expect(name == "bell")
        #expect(color == nil)
        guard case let .text(string, background, foreground) = text.icon else {
            Issue.record("text icon expected")
            return
        }
        #expect(string == "T")
        #expect(background == .blue)
        #expect(foreground == .red)
        guard case .image = image.icon else {
            Issue.record("image icon expected")
            return
        }
        #expect(image.isSticky)
        #expect(image.isRead)
    }
}
