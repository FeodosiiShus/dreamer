import Foundation
import Testing
@testable import Dreamder

@Suite(.serialized)
struct NotificationSuites {}

@MainActor
func awaitNotificationCondition(
    timeout: Duration = .seconds(3),
    _ condition: () -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return condition()
}

@MainActor
func makeTestNotification(
    _ title: String,
    sticky: Bool = false,
    id: UUID = UUID(),
    isRead: Bool = false
) -> CENotification {
    CENotification(
        id: id,
        iconSymbol: "bell",
        title: title,
        description: "\(title) description",
        actionButtonTitle: "Open",
        action: {},
        isSticky: sticky,
        isRead: isRead
    )
}

@MainActor
func subset(_ list: [CENotification], of owned: [CENotification]) -> [UUID] {
    let ownedIds = owned.map(\.id)
    return list.map(\.id).filter { ownedIds.contains($0) }
}

@MainActor
func dismissForeignNotifications(in model: NotificationPanelViewModel, keeping owned: [CENotification]) {
    let ownedIds = owned.map(\.id)
    for notification in model.activeNotifications where !ownedIds.contains(notification.id) {
        NotificationCenter.default.post(name: .init("NotificationDismissed"), object: notification)
    }
}

@MainActor
final class OwnedNotifications {
    private(set) var ids: [UUID] = []
    private let manager = NotificationManager.shared

    func post(
        _ label: String,
        sticky: Bool = false,
        action: @escaping () -> Void = {}
    ) async throws -> CENotification {
        let title = "\(label)-\(UUID().uuidString)"
        manager.post(
            iconSymbol: "bell",
            title: title,
            description: "\(title) description",
            actionButtonTitle: "Open",
            action: action,
            isSticky: sticky
        )
        let arrived = await awaitNotificationCondition {
            manager.notifications.contains { $0.title == title }
        }
        #expect(arrived)
        let notification = try #require(manager.notifications.first { $0.title == title })
        ids.append(notification.id)
        return notification
    }

    func adopt(title: String) async throws -> CENotification {
        let arrived = await awaitNotificationCondition {
            manager.notifications.contains { $0.title == title }
        }
        #expect(arrived)
        let notification = try #require(manager.notifications.first { $0.title == title })
        ids.append(notification.id)
        return notification
    }

    func dismissAll() {
        for id in ids {
            if let notification = manager.notifications.first(where: { $0.id == id }) {
                manager.dismissNotification(notification)
            }
        }
        ids = []
    }
}

@MainActor
final class NotificationActionRecorder {
    private(set) var invocations = 0

    func record() {
        invocations += 1
    }
}
