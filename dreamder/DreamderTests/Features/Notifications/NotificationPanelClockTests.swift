import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct NotificationPanelClockTests {
    @Test
    func regularNotificationsHideOnlyAfterTheDisplayDuration() async throws {
        let clock = TestClock()
        let model = NotificationsPanelHarness(clock: clock).model
        let regular = makeTestNotification("regular")
        let sticky = makeTestNotification("sticky", sticky: true)
        model.handleNewNotification(regular)
        model.handleNewNotification(sticky)
        try await clock.waitForSleepers()

        clock.advance(by: .seconds(4))
        #expect(clock.pendingSleeperCount == 1)
        #expect(model.hiddenNotificationIds.isEmpty)

        clock.advance(by: .seconds(1))
        try await eventually(timeout: .seconds(5)) { model.hiddenNotificationIds == [regular.id] }
    }

    @Test
    func pausingCancelsPendingHidesAndResumingRestartsThem() async throws {
        let clock = TestClock()
        let model = NotificationsPanelHarness(clock: clock).model
        let regular = makeTestNotification("regular")
        model.handleNewNotification(regular)
        try await clock.waitForSleepers()

        model.pauseTimer()
        try await eventually(timeout: .seconds(5)) { clock.pendingSleeperCount == 0 }
        clock.advance(by: .seconds(10))
        #expect(model.hiddenNotificationIds.isEmpty)

        model.resumeTimer()
        try await clock.waitForSleepers()
        clock.advance(by: .seconds(5))
        try await eventually(timeout: .seconds(5)) { model.hiddenNotificationIds.contains(regular.id) }
    }

    @Test
    func dismissingANotificationCancelsItsPendingHide() async throws {
        let clock = TestClock()
        let model = NotificationsPanelHarness(clock: clock).model
        let regular = makeTestNotification("regular")
        model.handleNewNotification(regular)
        try await clock.waitForSleepers()

        model.dismissNotification(regular, disableAnimation: true)

        try await eventually(timeout: .seconds(5)) { clock.pendingSleeperCount == 0 }
        #expect(model.hiddenNotificationIds.isEmpty)
    }

    @Test
    func animatedDismissalRemovesTheNotificationOnlyAfterTheFadeDelay() async throws {
        let clock = TestClock()
        let model = NotificationsPanelHarness(clock: clock).model
        model.pauseTimer()
        let regular = makeTestNotification("regular")
        model.handleNewNotification(regular)

        model.dismissNotification(regular)
        try await clock.waitForSleepers()

        let flagged = try #require(model.activeNotifications.first { $0.id == regular.id })
        #expect(flagged.isBeingDismissed)

        clock.advance(by: .milliseconds(10))
        try await eventually(timeout: .seconds(5)) { model.activeNotifications.isEmpty }
    }

    @Test
    func closingAScrolledPanelHidesTheNotificationsAfterTheSlideOutAndThenResetsTheScroll() async throws {
        let clock = TestClock()
        let model = NotificationsPanelHarness(clock: clock).model
        model.pauseTimer()
        let regular = makeTestNotification("regular")
        let sticky = makeTestNotification("sticky", sticky: true)
        model.handleNewNotification(regular)
        model.handleNewNotification(sticky)
        model.toggleNotificationsVisibility()
        model.scrolledToTop = false

        model.toggleNotificationsVisibility()
        try await clock.waitForSleepers()
        #expect(model.isPresented == false)
        #expect(model.hiddenNotificationIds.isEmpty)

        clock.advance(by: .milliseconds(300))
        try await eventually(timeout: .seconds(5)) { model.hiddenNotificationIds == [regular.id] }
        #expect(model.scrolledToTop == false)

        try await clock.waitForSleepers()
        clock.advance(by: .milliseconds(100))
        try await eventually(timeout: .seconds(5)) { model.scrolledToTop }
    }

    @Test
    func presentingThePanelAgainCancelsThePendingSlideOut() async throws {
        let clock = TestClock()
        let model = NotificationsPanelHarness(clock: clock).model
        model.pauseTimer()
        let regular = makeTestNotification("regular")
        model.handleNewNotification(regular)
        model.toggleNotificationsVisibility()
        model.scrolledToTop = false
        model.toggleNotificationsVisibility()
        try await clock.waitForSleepers()

        model.toggleNotificationsVisibility()

        try await eventually(timeout: .seconds(5)) { clock.pendingSleeperCount == 0 }
        clock.advance(by: .seconds(1))
        #expect(model.isPresented)
        #expect(model.hiddenNotificationIds.isEmpty)
    }

    @Test
    func losingControlWhilePresentedClosesThePanelAfterTheSlideOutDelay() async throws {
        let clock = TestClock()
        let model = NotificationsPanelHarness(clock: clock).model
        model.pauseTimer()
        let regular = makeTestNotification("regular")
        model.handleNewNotification(regular)
        model.toggleNotificationsVisibility()

        model.controlStateChanged(isActive: false)
        try await clock.waitForSleepers()
        #expect(model.isPresented)

        clock.advance(by: .milliseconds(300))
        try await eventually(timeout: .seconds(5)) { model.isPresented == false }
        #expect(model.hiddenNotificationIds.contains(regular.id))
    }

    @Test
    func regainingControlCancelsThePendingClose() async throws {
        let clock = TestClock()
        let model = NotificationsPanelHarness(clock: clock).model
        model.pauseTimer()
        model.handleNewNotification(makeTestNotification("regular"))
        model.toggleNotificationsVisibility()
        model.controlStateChanged(isActive: false)
        try await clock.waitForSleepers()

        model.controlStateChanged(isActive: true)

        try await eventually(timeout: .seconds(5)) { clock.pendingSleeperCount == 0 }
        clock.advance(by: .seconds(1))
        #expect(model.isPresented)
    }

    @Test
    func losingControlWhileNotPresentedSchedulesNothing() {
        let clock = TestClock()
        let model = NotificationsPanelHarness(clock: clock).model
        model.pauseTimer()
        model.handleNewNotification(makeTestNotification("regular"))

        model.controlStateChanged(isActive: false)

        #expect(clock.pendingSleeperCount == 0)
        #expect(model.isPresented == false)
    }

    @Test
    func aPanelClosedBeforeTheDelayElapsesIsNotReopened() async throws {
        let clock = TestClock()
        let model = NotificationsPanelHarness(clock: clock).model
        model.pauseTimer()
        model.handleNewNotification(makeTestNotification("regular"))
        model.toggleNotificationsVisibility()
        model.controlStateChanged(isActive: false)
        try await clock.waitForSleepers()
        model.toggleNotificationsVisibility()

        clock.advance(by: .milliseconds(300))
        try await Task.sleep(for: .milliseconds(50))

        #expect(model.isPresented == false)
    }

    @Test
    func discardedPanelCancelsItsPendingWork() async throws {
        let clock = TestClock()
        weak var discarded: NotificationPanelViewModel?
        do {
            let model = NotificationsPanelHarness(clock: clock).model
            discarded = model
            model.handleNewNotification(makeTestNotification("pending"))
            try await clock.waitForSleepers()
        }

        try await eventually(timeout: .seconds(5)) { discarded == nil }
        try await eventually(timeout: .seconds(5)) { clock.pendingSleeperCount == 0 }
    }
}
