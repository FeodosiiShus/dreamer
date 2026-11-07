import Foundation
import Testing
@testable import Dreamder

extension NotificationSuites {
    @MainActor
    @Suite
    struct NotificationManagerTests {
        private let manager = NotificationManager.shared

        private func stored(_ notification: CENotification) -> CENotification? {
            manager.notifications.first { $0.id == notification.id }
        }

        @Test
        func postedNotificationIsStoredUnreadWithItsContent() async throws {
            let owned = OwnedNotifications()
            defer { owned.dismissAll() }

            let notification = try await owned.post("stored")

            #expect(notification.title.hasPrefix("stored-"))
            #expect(notification.description == "\(notification.title) description")
            #expect(notification.actionButtonTitle == "Open")
            #expect(notification.isRead == false)
            #expect(notification.isSticky == false)
            #expect(notification.isBeingDismissed == false)
        }

        @Test
        func stickyFlagIsPreserved() async throws {
            let owned = OwnedNotifications()
            defer { owned.dismissAll() }

            let notification = try await owned.post("sticky", sticky: true)

            #expect(notification.isSticky)
        }

        @Test
        func notificationsKeepPostingOrder() async throws {
            let owned = OwnedNotifications()
            defer { owned.dismissAll() }
            let first = try await owned.post("first")
            let second = try await owned.post("second")
            let third = try await owned.post("third")

            let order = subset(manager.notifications, of: [first, second, third])

            #expect(order == [first.id, second.id, third.id])
        }

        @Test
        func iconTextVariantIsStoredUnreadLikeTheSymbolVariant() async throws {
            let owned = OwnedNotifications()
            defer { owned.dismissAll() }
            let textTitle = "text-\(UUID().uuidString)"

            manager.post(
                iconText: "!",
                title: textTitle,
                description: "",
                actionButtonTitle: "",
                action: {}
            )
            let notification = try await owned.adopt(title: textTitle)

            #expect(notification.isRead == false)
            #expect(notification.actionButtonTitle.isEmpty)
        }

        @Test
        func markAsReadOnlyAffectsTheGivenNotification() async throws {
            let owned = OwnedNotifications()
            defer { owned.dismissAll() }
            let target = try await owned.post("target")
            let bystander = try await owned.post("bystander")

            manager.markAsRead(target)

            let updatedTarget = try #require(stored(target))
            let updatedBystander = try #require(stored(bystander))
            #expect(updatedTarget.isRead)
            #expect(updatedBystander.isRead == false)
        }

        @Test
        func markAsReadLowersTheUnreadCountOnceAndIsIdempotent() async throws {
            let owned = OwnedNotifications()
            defer { owned.dismissAll() }
            let notification = try await owned.post("unread")

            let before = manager.unreadCount
            manager.markAsRead(notification)
            let afterFirst = manager.unreadCount
            manager.markAsRead(notification)
            let afterSecond = manager.unreadCount

            #expect(afterFirst == before - 1)
            #expect(afterSecond == afterFirst)
        }

        @Test
        func markAsReadForAnUnknownNotificationChangesNothing() {
            let stranger = makeTestNotification("stranger")

            let before = manager.unreadCount
            manager.markAsRead(stranger)

            #expect(manager.unreadCount == before)
            #expect(stored(stranger) == nil)
        }

        @Test
        func markAllAsReadMarksEveryNotificationRead() async throws {
            let owned = OwnedNotifications()
            defer { owned.dismissAll() }
            let first = try await owned.post("all-one")
            let second = try await owned.post("all-two")
            let firstBefore = try #require(stored(first))
            let secondBefore = try #require(stored(second))
            #expect(firstBefore.isRead == false)
            #expect(secondBefore.isRead == false)

            manager.markAllAsRead()

            #expect(manager.unreadCount == 0)
            let firstAfter = try #require(stored(first))
            let secondAfter = try #require(stored(second))
            #expect(firstAfter.isRead)
            #expect(secondAfter.isRead)
        }

        @Test
        func markAllAsReadWhenNothingIsUnreadKeepsTheCountAtZero() {
            manager.markAllAsRead()
            manager.markAllAsRead()

            #expect(manager.unreadCount == 0)
        }

        @Test
        func dismissRemovesOnlyThatNotification() async throws {
            let owned = OwnedNotifications()
            defer { owned.dismissAll() }
            let dismissed = try await owned.post("dismissed")
            let kept = try await owned.post("kept")

            manager.dismissNotification(dismissed)

            #expect(stored(dismissed) == nil)
            #expect(stored(kept) != nil)
        }

        @Test
        func dismissingAnUnreadNotificationRemovesItFromTheUnreadCount() async throws {
            let owned = OwnedNotifications()
            defer { owned.dismissAll() }
            let notification = try await owned.post("unread-dismiss")

            let before = manager.unreadCount
            manager.dismissNotification(notification)

            #expect(manager.unreadCount == before - 1)
        }

        @Test
        func dismissingTwiceOrDismissingAnUnknownNotificationIsHarmless() async throws {
            let owned = OwnedNotifications()
            defer { owned.dismissAll() }
            let notification = try await owned.post("twice")
            let kept = try await owned.post("twice-kept")
            manager.dismissNotification(notification)

            let idsBefore = manager.notifications.map(\.id)
            let unreadBefore = manager.unreadCount
            manager.dismissNotification(notification)
            manager.dismissNotification(makeTestNotification("never posted"))

            #expect(manager.notifications.map(\.id) == idsBefore)
            #expect(manager.unreadCount == unreadBefore)
            #expect(stored(kept) != nil)
        }

        @Test
        func systemNotificationResponseRunsTheActionAndDismisses() async throws {
            let owned = OwnedNotifications()
            defer { owned.dismissAll() }
            let recorder = NotificationActionRecorder()
            let notification = try await owned.post("response") { recorder.record() }

            manager.handleSystemNotificationResponse(id: notification.id.uuidString)

            #expect(recorder.invocations == 1)
            #expect(stored(notification) == nil)
        }

        @Test
        func systemNotificationResponseWithMalformedIdDoesNothing() async throws {
            let owned = OwnedNotifications()
            defer { owned.dismissAll() }
            let recorder = NotificationActionRecorder()
            let notification = try await owned.post("malformed") { recorder.record() }

            manager.handleSystemNotificationResponse(id: "not-a-uuid")

            #expect(recorder.invocations == 0)
            #expect(stored(notification) != nil)
        }

        @Test
        func systemNotificationResponseWithUnknownIdDoesNothing() async throws {
            let owned = OwnedNotifications()
            defer { owned.dismissAll() }
            let recorder = NotificationActionRecorder()
            let notification = try await owned.post("unknown") { recorder.record() }

            manager.handleSystemNotificationResponse(id: UUID().uuidString)

            #expect(recorder.invocations == 0)
            #expect(stored(notification) != nil)
        }

        @Test
        func systemNotificationResponseForAnAlreadyDismissedNotificationDoesNotRunTheActionAgain() async throws {
            let owned = OwnedNotifications()
            defer { owned.dismissAll() }
            let recorder = NotificationActionRecorder()
            let notification = try await owned.post("replay") { recorder.record() }

            manager.handleSystemNotificationResponse(id: notification.id.uuidString)
            manager.handleSystemNotificationResponse(id: notification.id.uuidString)

            #expect(recorder.invocations == 1)
        }
    }
}

@MainActor
@Suite
struct CENotificationTests {
    @Test
    func equalityIsByIdentifierOnly() {
        let id = UUID()
        let original = makeTestNotification("original", id: id)
        var changed = makeTestNotification("changed", sticky: true, id: id)
        changed.isRead = true
        changed.isBeingDismissed = true
        let other = makeTestNotification("original")

        #expect(original == changed)
        #expect(original != other)
    }

    @Test
    func defaultsAreUnreadAndNotBeingDismissed() {
        let notification = CENotification(
            iconSymbol: "bell",
            title: "t",
            description: "d",
            actionButtonTitle: "a",
            action: {}
        )

        #expect(notification.isRead == false)
        #expect(notification.isSticky == false)
        #expect(notification.isBeingDismissed == false)
    }

    @Test
    func timestampIsTakenAtCreation() {
        let before = Date()
        let notification = makeTestNotification("timed")
        let after = Date()

        #expect(notification.timestamp >= before)
        #expect(notification.timestamp <= after)
    }

    @Test
    func providedReadStateAndStickinessAreKept() {
        let notification = makeTestNotification("kept", sticky: true, isRead: true)

        #expect(notification.isRead)
        #expect(notification.isSticky)
    }
}
