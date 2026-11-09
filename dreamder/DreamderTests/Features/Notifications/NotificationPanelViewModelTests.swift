import Foundation
import Testing
@testable import Dreamder

extension NotificationSuites {
    @MainActor
    @Suite(.uiGate)
    struct NotificationPanelViewModelTests {
        private let manager = NotificationManager.shared

        private func makeModel(adding notifications: [CENotification]) -> NotificationPanelViewModel {
            let model = NotificationPanelViewModel()
            for notification in notifications {
                model.handleNewNotification(notification)
            }
            return model
        }

        private func hideRegularNotifications(_ model: NotificationPanelViewModel) {
            model.toggleNotificationsVisibility()
            model.toggleNotificationsVisibility()
        }

        @Test
        func startsHiddenAndScrolledToTop() {
            let model = NotificationPanelViewModel()

            #expect(model.hiddenNotificationIds.isEmpty)
            #expect(model.isPresented == false)
            #expect(model.scrolledToTop)
        }

        @Test
        func stickyNotificationsStayAboveRegularOnesAndNewestComesFirstInEachGroup() {
            let first = makeTestNotification("first")
            let second = makeTestNotification("second")
            let stickyOne = makeTestNotification("sticky-one", sticky: true)
            let third = makeTestNotification("third")
            let stickyTwo = makeTestNotification("sticky-two", sticky: true)

            let model = makeModel(adding: [first, second, stickyOne, third, stickyTwo])

            let order = subset(model.activeNotifications, of: [first, second, stickyOne, third, stickyTwo])
            #expect(order == [stickyTwo.id, stickyOne.id, third.id, second.id, first.id])
        }

        @Test
        func regularNotificationAddedAfterOnlyStickyOnesGoesBelowThem() {
            let sticky = makeTestNotification("sticky", sticky: true)
            let regular = makeTestNotification("regular")

            let model = makeModel(adding: [sticky, regular])

            #expect(subset(model.activeNotifications, of: [sticky, regular]) == [sticky.id, regular.id])
        }

        @Test
        func everyAddedNotificationStartsVisible() {
            let regular = makeTestNotification("regular")
            let sticky = makeTestNotification("sticky", sticky: true)

            let model = makeModel(adding: [regular, sticky])

            #expect(subset(model.visibleNotifications, of: [regular, sticky]) == [sticky.id, regular.id])
            #expect(model.isNotificationVisible(regular))
            #expect(model.isNotificationVisible(sticky))
        }

        @Test
        func unknownNotificationsCountAsVisible() {
            let model = NotificationPanelViewModel()

            #expect(model.isNotificationVisible(makeTestNotification("unknown")))
        }

        @Test
        func togglingTwiceHidesRegularNotificationsButKeepsStickyOnes() {
            let regular = makeTestNotification("regular")
            let sticky = makeTestNotification("sticky", sticky: true)
            let model = makeModel(adding: [regular, sticky])

            model.toggleNotificationsVisibility()
            #expect(model.isPresented)

            model.toggleNotificationsVisibility()
            #expect(model.isPresented == false)
            #expect(model.hiddenNotificationIds.contains(regular.id))
            #expect(model.hiddenNotificationIds.contains(sticky.id) == false)
            #expect(subset(model.visibleNotifications, of: [regular, sticky]) == [sticky.id])
            #expect(model.isNotificationVisible(regular) == false)
            #expect(model.isNotificationVisible(sticky))
        }

        @Test
        func hiddenNotificationStaysVisibleWhileItIsBeingDismissed() {
            let regular = makeTestNotification("regular")
            let model = makeModel(adding: [regular])
            hideRegularNotifications(model)
            var dismissing = regular
            dismissing.isBeingDismissed = true

            #expect(model.isNotificationVisible(regular) == false)
            #expect(model.isNotificationVisible(dismissing))
        }

        @Test
        func presentingThePanelRevealsHiddenNotifications() {
            let regular = makeTestNotification("regular")
            let sticky = makeTestNotification("sticky", sticky: true)
            let model = makeModel(adding: [regular, sticky])
            hideRegularNotifications(model)
            #expect(model.hiddenNotificationIds.contains(regular.id))

            model.toggleNotificationsVisibility()

            #expect(model.isPresented)
            #expect(model.hiddenNotificationIds.isEmpty)
            #expect(subset(model.visibleNotifications, of: [regular, sticky]) == [sticky.id, regular.id])
            #expect(model.isNotificationVisible(regular))
        }

        @Test
        func addingAHiddenNotificationAgainMakesItVisibleAgain() {
            let regular = makeTestNotification("regular")
            let model = makeModel(adding: [regular])
            hideRegularNotifications(model)
            #expect(model.isNotificationVisible(regular) == false)

            model.handleNewNotification(regular)

            #expect(model.hiddenNotificationIds.contains(regular.id) == false)
            #expect(model.isNotificationVisible(regular))
        }

        @Test
        func losingFocusWhilePresentedHidesTheRegularNotifications() {
            let regular = makeTestNotification("regular")
            let sticky = makeTestNotification("sticky", sticky: true)
            let model = makeModel(adding: [regular, sticky])
            model.toggleNotificationsVisibility()

            model.handleFocusChange(isFocused: false)

            #expect(model.isPresented == false)
            #expect(model.hiddenNotificationIds.contains(regular.id))
            #expect(model.hiddenNotificationIds.contains(sticky.id) == false)
        }

        @Test
        func gainingFocusOrLosingItWhileNotPresentedChangesNothing() {
            let regular = makeTestNotification("regular")
            let model = makeModel(adding: [regular])

            model.handleFocusChange(isFocused: false)
            model.handleFocusChange(isFocused: true)
            #expect(model.hiddenNotificationIds.contains(regular.id) == false)

            model.toggleNotificationsVisibility()
            model.handleFocusChange(isFocused: true)

            #expect(model.isPresented)
            #expect(model.hiddenNotificationIds.isEmpty)
            #expect(subset(model.activeNotifications, of: [regular]) == [regular.id])
        }

        @Test
        func closingTheScrolledPanelClosesItAtOnceAndHidesNotificationsAfterTheSlideOut() async {
            let regular = makeTestNotification("regular")
            let sticky = makeTestNotification("sticky", sticky: true)
            let model = makeModel(adding: [regular, sticky])
            model.toggleNotificationsVisibility()
            model.scrolledToTop = false

            model.toggleNotificationsVisibility()

            #expect(model.isPresented == false)
            #expect(model.hiddenNotificationIds.isEmpty)

            let hidden = await awaitNotificationCondition { model.hiddenNotificationIds.contains(regular.id) }
            #expect(hidden)
            let scrolledBack = await awaitNotificationCondition { model.scrolledToTop }
            #expect(scrolledBack)
            #expect(model.hiddenNotificationIds.contains(sticky.id) == false)
            #expect(model.isNotificationVisible(sticky))
        }

        @Test
        func dismissingWithoutAnimationRemovesOnlyThatNotificationImmediately() {
            let first = makeTestNotification("first")
            let second = makeTestNotification("second")
            let third = makeTestNotification("third")
            let model = makeModel(adding: [first, second, third])

            model.dismissNotification(second, disableAnimation: true)

            #expect(subset(model.activeNotifications, of: [first, second, third]) == [third.id, first.id])
        }

        @Test
        func dismissingAHiddenNotificationForgetsItsHiddenState() {
            let regular = makeTestNotification("regular")
            let model = makeModel(adding: [regular])
            hideRegularNotifications(model)
            #expect(model.hiddenNotificationIds.contains(regular.id))

            model.dismissNotification(regular, disableAnimation: true)

            #expect(model.hiddenNotificationIds.contains(regular.id) == false)
            #expect(subset(model.activeNotifications, of: [regular]).isEmpty)
        }

        @Test
        func animatedDismissalFlagsTheNotificationFirstThenRemovesIt() async throws {
            let first = makeTestNotification("first")
            let second = makeTestNotification("second")
            let model = makeModel(adding: [first, second])

            model.dismissNotification(first)

            let flagged = try #require(model.activeNotifications.first { $0.id == first.id })
            #expect(flagged.isBeingDismissed)
            #expect(model.isNotificationVisible(flagged))
            let untouched = try #require(model.activeNotifications.first { $0.id == second.id })
            #expect(untouched.isBeingDismissed == false)

            let removed = await awaitNotificationCondition {
                subset(model.activeNotifications, of: [first]).isEmpty
            }
            #expect(removed)
            #expect(subset(model.activeNotifications, of: [first, second]) == [second.id])
        }

        @Test
        func dismissingAnUnknownNotificationChangesNothing() async throws {
            let known = makeTestNotification("known")
            let model = makeModel(adding: [known])

            model.dismissNotification(makeTestNotification("ghost"))
            model.dismissNotification(makeTestNotification("ghost"), disableAnimation: true)
            try await Task.sleep(for: .milliseconds(100))

            #expect(subset(model.activeNotifications, of: [known]) == [known.id])
            let entry = try #require(model.activeNotifications.first { $0.id == known.id })
            #expect(entry.isBeingDismissed == false)
        }

        @Test
        func notificationsPostedToTheManagerReachThePanelNewestFirstWithStickyOnTop() async throws {
            let owned = OwnedNotifications()
            defer { owned.dismissAll() }
            let model = NotificationPanelViewModel()
            let regularOne = try await owned.post("regular-one")
            let sticky = try await owned.post("sticky", sticky: true)
            let regularTwo = try await owned.post("regular-two")

            let order = subset(model.activeNotifications, of: [regularOne, sticky, regularTwo])

            #expect(order == [sticky.id, regularTwo.id, regularOne.id])
            let ownIds = [regularOne.id, sticky.id, regularTwo.id]
            let ownEntries = model.activeNotifications.filter { ownIds.contains($0.id) }
            #expect(ownEntries.allSatisfy { $0.isRead == false })
        }

        @Test
        func panelCreatedLaterLoadsTheNotificationsAlreadyInTheManager() async throws {
            let owned = OwnedNotifications()
            defer { owned.dismissAll() }
            let first = try await owned.post("early-one")
            let second = try await owned.post("early-two")

            let model = NotificationPanelViewModel()

            #expect(subset(model.activeNotifications, of: [first, second]) == [second.id, first.id])
        }

        @Test
        func dismissingInThePanelRemovesItFromTheManagerAndTheUnreadCount() async throws {
            let owned = OwnedNotifications()
            defer { owned.dismissAll() }
            let model = NotificationPanelViewModel()
            let notification = try await owned.post("panel-dismiss")
            let stays = try await owned.post("stays")

            let unreadBefore = manager.unreadCount
            model.dismissNotification(notification, disableAnimation: true)

            #expect(subset(model.activeNotifications, of: [notification, stays]) == [stays.id])
            #expect(manager.notifications.contains { $0.id == notification.id } == false)
            #expect(manager.notifications.contains { $0.id == stays.id })
            #expect(manager.unreadCount == unreadBefore - 1)
        }

        @Test
        func animatedDismissalInThePanelEventuallyRemovesItFromTheManager() async throws {
            let owned = OwnedNotifications()
            defer { owned.dismissAll() }
            let model = NotificationPanelViewModel()
            let notification = try await owned.post("animated")

            model.dismissNotification(notification)

            let removedEverywhere = await awaitNotificationCondition {
                let inPanel = subset(model.activeNotifications, of: [notification])
                let inManager = manager.notifications.contains { $0.id == notification.id }
                return inPanel.isEmpty && inManager == false
            }
            #expect(removedEverywhere)
        }

        @Test
        func dismissingInTheManagerRemovesItFromThePanel() async throws {
            let owned = OwnedNotifications()
            defer { owned.dismissAll() }
            let model = NotificationPanelViewModel()
            let dismissed = try await owned.post("manager-dismiss")
            let kept = try await owned.post("manager-kept")

            manager.dismissNotification(dismissed)

            #expect(subset(model.activeNotifications, of: [dismissed, kept]) == [kept.id])
        }

        @Test
        func removingTheLastNotificationClosesAPresentedPanel() async throws {
            let owned = OwnedNotifications()
            defer { owned.dismissAll() }
            let model = NotificationPanelViewModel()
            let notification = try await owned.post("last")
            model.toggleNotificationsVisibility()
            #expect(model.isPresented)
            dismissForeignNotifications(in: model, keeping: [notification])

            manager.dismissNotification(notification)

            #expect(model.activeNotifications.isEmpty)
            #expect(model.isPresented == false)
        }

        @Test
        func removingOneOfSeveralNotificationsKeepsAPresentedPanelOpen() async throws {
            let owned = OwnedNotifications()
            defer { owned.dismissAll() }
            let model = NotificationPanelViewModel()
            let removed = try await owned.post("removed")
            let kept = try await owned.post("kept")
            model.toggleNotificationsVisibility()

            manager.dismissNotification(removed)

            #expect(subset(model.activeNotifications, of: [removed, kept]) == [kept.id])
            #expect(model.isPresented)
        }

        @Test
        func animatedDismissalOfTheLastNotificationClosesAPresentedPanel() async {
            let notification = makeTestNotification("last")
            let model = makeModel(adding: [notification])
            dismissForeignNotifications(in: model, keeping: [notification])
            model.toggleNotificationsVisibility()

            model.dismissNotification(notification)

            let closed = await awaitNotificationCondition {
                model.activeNotifications.isEmpty && model.isPresented == false
            }
            #expect(closed)
        }

        @Test
        func autoHideTimersHideOnlyRunningRegularNotificationsAfterTheDisplayDuration() async throws {
            let regular = makeTestNotification("regular")
            let sticky = makeTestNotification("sticky", sticky: true)
            let running = makeModel(adding: [regular, sticky])

            let pausedBefore = NotificationPanelViewModel()
            let pausedBeforeNotification = makeTestNotification("paused-before")
            pausedBefore.pauseTimer()
            pausedBefore.handleNewNotification(pausedBeforeNotification)

            let pausedAfter = NotificationPanelViewModel()
            let pausedAfterNotification = makeTestNotification("paused-after")
            pausedAfter.handleNewNotification(pausedAfterNotification)
            pausedAfter.pauseTimer()

            let resumed = NotificationPanelViewModel()
            let resumedNotification = makeTestNotification("resumed")
            resumed.handleNewNotification(resumedNotification)
            resumed.pauseTimer()
            resumed.resumeTimer()

            let presented = NotificationPanelViewModel()
            let presentedNotification = makeTestNotification("presented")
            presented.toggleNotificationsVisibility()
            presented.handleNewNotification(presentedNotification)

            #expect(running.hiddenNotificationIds.contains(regular.id) == false)
            #expect(resumed.hiddenNotificationIds.contains(resumedNotification.id) == false)

            let hidden = await awaitNotificationCondition(timeout: .seconds(10)) {
                running.hiddenNotificationIds.contains(regular.id)
            }
            #expect(hidden)
            let resumedHidden = await awaitNotificationCondition(timeout: .seconds(3)) {
                resumed.hiddenNotificationIds.contains(resumedNotification.id)
            }
            #expect(resumedHidden)
            try await Task.sleep(for: .milliseconds(300))

            #expect(running.hiddenNotificationIds.contains(sticky.id) == false)
            #expect(running.isNotificationVisible(sticky))
            #expect(subset(running.visibleNotifications, of: [regular, sticky]) == [sticky.id])
            #expect(pausedBefore.hiddenNotificationIds.contains(pausedBeforeNotification.id) == false)
            #expect(pausedAfter.hiddenNotificationIds.contains(pausedAfterNotification.id) == false)
            #expect(presented.hiddenNotificationIds.contains(presentedNotification.id) == false)
            #expect(presented.isNotificationVisible(presentedNotification))
        }
    }
}
