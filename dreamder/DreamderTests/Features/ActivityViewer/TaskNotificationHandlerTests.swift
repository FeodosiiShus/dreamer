import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct TaskNotificationHandlerTests {
    private func post(_ center: NotificationCenter, _ userInfo: [String: Any]) {
        center.post(name: .taskNotification, object: nil, userInfo: userInfo)
    }

    private func flush(_ handlers: [TaskNotificationHandler], through center: NotificationCenter) async throws {
        let sentinel = UUID().uuidString
        post(center, ["id": sentinel, "action": "create", "title": "sentinel"])
        try await eventually(timeout: .seconds(5)) {
            handlers.allSatisfy { handler in handler.notifications.contains { $0.id == sentinel } }
        }
        post(center, ["id": sentinel, "action": "delete"])
        try await eventually(timeout: .seconds(5)) {
            handlers.allSatisfy { handler in !handler.notifications.contains { $0.id == sentinel } }
        }
    }

    @Test
    func createAppendsInArrivalOrderAndCarriesEveryField() async throws {
        let center = NotificationCenter()
        let handler = TaskNotificationHandler(center: center)

        post(center, [
            "id": "first",
            "action": "create",
            "title": "First",
            "message": "Working",
            "percentage": 0.25,
            "isLoading": true
        ])
        post(center, ["id": "second", "action": "create", "title": "Second"])

        try await eventually(timeout: .seconds(5)) { handler.notifications.count == 2 }
        #expect(handler.notifications == [
            TaskNotificationModel(id: "first", title: "First", message: "Working", percentage: 0.25, isLoading: true),
            TaskNotificationModel(id: "second", title: "Second")
        ])
    }

    @Test
    func createWithPriorityInsertsAtTheFront() async throws {
        let center = NotificationCenter()
        let handler = TaskNotificationHandler(center: center)

        post(center, ["id": "regular", "action": "create", "title": "Regular"])
        post(center, ["id": "urgent", "action": "createWithPriority", "title": "Priority Task Title"])

        try await eventually(timeout: .seconds(5)) { handler.notifications.count == 2 }
        #expect(handler.notifications.map(\.id) == ["urgent", "regular"])
        #expect(handler.notifications.first?.title == "Priority Task Title")
    }

    @Test
    func createWithoutATitleIsIgnored() async throws {
        let center = NotificationCenter()
        let handler = TaskNotificationHandler(center: center)

        post(center, ["id": "untitled", "action": "create"])
        try await flush([handler], through: center)

        #expect(handler.notifications.isEmpty)
    }

    @Test
    func updateChangesOnlyTheProvidedFieldsOfTheMatchingTask() async throws {
        let center = NotificationCenter()
        let handler = TaskNotificationHandler(center: center)
        post(center, ["id": "task", "action": "create", "title": "Task", "message": "Before", "isLoading": true])
        post(center, ["id": "other", "action": "create", "title": "Other"])
        try await eventually(timeout: .seconds(5)) { handler.notifications.count == 2 }

        post(center, [
            "id": "task",
            "action": "update",
            "title": "Updated Task Title",
            "message": "After",
            "percentage": 0.5,
            "isLoading": false
        ])
        try await eventually(timeout: .seconds(5)) { handler.notifications.first?.title == "Updated Task Title" }

        #expect(handler.notifications.first == TaskNotificationModel(
            id: "task",
            title: "Updated Task Title",
            message: "After",
            percentage: 0.5,
            isLoading: false
        ))
        #expect(handler.notifications.last == TaskNotificationModel(id: "other", title: "Other"))

        post(center, ["id": "task", "action": "update"])
        post(center, ["id": "ghost", "action": "update", "title": "Ghost"])
        try await flush([handler], through: center)

        #expect(handler.notifications.first?.title == "Updated Task Title")
        #expect(handler.notifications.map(\.id) == ["task", "other"])
    }

    @Test
    func deleteRemovesTheTask() async throws {
        let center = NotificationCenter()
        let handler = TaskNotificationHandler(center: center)
        post(center, ["id": "task", "action": "create", "title": "Task"])
        post(center, ["id": "kept", "action": "create", "title": "Kept"])
        try await eventually(timeout: .seconds(5)) { handler.notifications.count == 2 }

        post(center, ["id": "task", "action": "delete"])

        try await eventually(timeout: .seconds(5)) { handler.notifications.map(\.id) == ["kept"] }
    }

    @Test
    func deleteWithDelayRemovesTheTaskOnlyOnceTheDelayElapsed() async throws {
        let center = NotificationCenter()
        let clock = TestClock()
        let handler = TaskNotificationHandler(center: center, clock: clock)
        post(center, ["id": "task", "action": "create", "title": "Task"])
        try await eventually(timeout: .seconds(5)) { handler.notifications.count == 1 }

        post(center, ["id": "task", "action": "deleteWithDelay", "delay": 5.0])
        try await clock.waitForSleepers()
        clock.advance(by: .seconds(4))

        #expect(clock.pendingSleeperCount == 1)
        #expect(handler.notifications.count == 1)

        clock.advance(by: .seconds(1))
        try await eventually(timeout: .seconds(5)) { handler.notifications.isEmpty }
    }

    @Test
    func deleteWithDelayWithoutADelayIsIgnored() async throws {
        let center = NotificationCenter()
        let clock = TestClock()
        let handler = TaskNotificationHandler(center: center, clock: clock)
        post(center, ["id": "task", "action": "create", "title": "Task"])
        try await eventually(timeout: .seconds(5)) { handler.notifications.count == 1 }

        post(center, ["id": "task", "action": "deleteWithDelay"])
        try await flush([handler], through: center)

        #expect(clock.pendingSleeperCount == 0)
        #expect(handler.notifications.map(\.id) == ["task"])
    }

    @Test
    func malformedNotificationsAreIgnored() async throws {
        let center = NotificationCenter()
        let handler = TaskNotificationHandler(center: center)

        center.post(name: .taskNotification, object: nil)
        post(center, ["action": "create", "title": "No id"])
        post(center, ["id": "no-action", "title": "No action"])
        post(center, ["id": "unknown-action", "action": "explode", "title": "Unknown action"])
        try await flush([handler], through: center)

        #expect(handler.notifications.isEmpty)
    }

    @Test
    func handlersOnlyAcceptTasksForTheirOwnWorkspace() async throws {
        let center = NotificationCenter()
        let workspace = URL(fileURLWithPath: "/tmp/project-a")
        let otherWorkspace = URL(fileURLWithPath: "/tmp/project-b")
        let scoped = TaskNotificationHandler(workspaceURL: workspace, center: center)
        let unscoped = TaskNotificationHandler(center: center)

        post(center, ["id": "foreign", "action": "create", "title": "Foreign", "workspace": otherWorkspace])
        post(center, ["id": "own", "action": "create", "title": "Own", "workspace": workspace])
        post(center, ["id": "shared", "action": "create", "title": "Shared"])
        try await eventually(timeout: .seconds(5)) {
            scoped.notifications.count == 2 && unscoped.notifications.count == 1
        }

        #expect(scoped.notifications.map(\.id) == ["own", "shared"])
        #expect(unscoped.notifications.map(\.id) == ["shared"])
    }

    @Test
    func discardedHandlerStopsObservingAndCancelsPendingDeletions() async throws {
        let center = NotificationCenter()
        let clock = TestClock()
        weak var discarded: TaskNotificationHandler?
        do {
            let handler = TaskNotificationHandler(center: center, clock: clock)
            discarded = handler
            post(center, ["id": "task", "action": "create", "title": "Task"])
            try await eventually(timeout: .seconds(5)) { handler.notifications.count == 1 }
            post(center, ["id": "task", "action": "deleteWithDelay", "delay": 60.0])
            try await clock.waitForSleepers()
        }

        try await eventually(timeout: .seconds(5)) { discarded == nil }
        try await eventually(timeout: .seconds(5)) { clock.pendingSleeperCount == 0 }
    }
}
