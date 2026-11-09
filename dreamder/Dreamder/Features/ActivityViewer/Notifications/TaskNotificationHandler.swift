//
//  TaskNotificationHandler.swift
//  Dreamder
//
//  Created by Tommy Ludwig on 21.06.24.
//

import Foundation
import Observation

/// Manages task-related notifications.
///
/// This class listens for notifications named `.taskNotification` and performs actions
/// such as creating, updating, or deleting tasks based on the notification's content.
///
/// When a task is created, it is added to the end of the array. The activity viewer displays
/// only the first item in the array. To immediately display a notification, use the 
/// `"action": "createWithPriority"` option to insert the task at the beginning of the array.
/// *Note: This option should be reserved for important notifications only.*
///
/// It is recommended to use `UUID().uuidString` to generate a unique identifier for each task.
/// This identifier can then be used to update or delete the task. Alternatively, you can use any
/// unique identifier, such as a token sent from a language server.
///
/// Remember to manage your task notifications appropriately. You should either delete task 
/// notifications manually or schedule their deletion in advance using the `deleteWithDelay` method.
///
/// Some tasks should be restricted to a specific workspace. To do this, specify the `workspace` attribute in the
/// notification's `userInfo` dictionary as a `URL`, or use the `toWorkspace` parameter on
/// ``TaskNotificationHandler/postTask(toWorkspace:action:model:)``.
///
/// ## Available Methods
/// - `create`:
///     Creates a new Task Notification. 
///     Required fields: `id` (String), `action` (String), `title` (String). 
///     Optional fields: `message` (String), `percentage` (Double), `isLoading` (Bool), `workspace` (URL).
/// - `createWithPriority`:
///     Creates a new Task Notification and inserts it at the start of the array.
///     This ensures it appears in the activity viewer even if there are other task notifications before it.
///     **Note:** This should only be used for important notifications!
///     Required fields: `id` (String), `action` (String), `title` (String). 
///     Optional fields: `message` (String), `percentage` (Double), `isLoading` (Bool), `workspace` (URL).
/// - `update`:
///     Updates an existing task notification. It's important to pass the same `id` to update the correct task.
///     Required fields: `id` (String), `action` (String). 
///     Optional fields: `title` (String), `message` (String), `percentage` (Double), `isLoading` (Bool),
///     `workspace` (URL).
/// - `delete`:
///     Deletes an existing task notification.
///     Required fields: `id` (String), `action` (String).
///     Optional field: `workspace` (URL).
/// - `deleteWithDelay`:
///     Deletes an existing task notification after a certain `TimeInterval`.
///     Required fields: `id` (String), `action` (String), `delay` (Double).
///     Optional field: `workspace` (URL).
///     **Important:** When specifying the delay, ensure it's a double.
///     For example, '2' would be invalid because it would count as an integer, use '2.0' instead.
///
/// ## Example Usage:
/// ```swift
/// let uuidString = UUID().uuidString
///
/// func createTask() {
///     let userInfo: [String: Any] = [
///         "id": "uniqueTaskID",
///         "action": "create",
///         "title": "Task Title"
///     ]
///     NotificationCenter.default.post(name: .taskNotification, object: nil, userInfo: userInfo)
/// }
///
/// func createTaskWithPriority() {
///     let userInfo: [String: Any] = [
///         "id": "uniqueTaskID",
///         "action": "createWithPriority",
///         "title": "Priority Task Title"
///     ]
///     NotificationCenter.default.post(name: .taskNotification, object: nil, userInfo: userInfo)
/// }
///
/// func updateTask() {
///     var userInfo: [String: Any] = [
///         "id": "uniqueTaskID",
///         "action": "update",
///         "title": "Updated Task Title",
///         "message": "Updated Task Message",
///         "percentage": 0.5,
///         "isLoading": true
///     ]
///     NotificationCenter.default.post(name: .taskNotification, object: nil, userInfo: userInfo)
/// }
///
/// func deleteTask() {
///     let userInfo: [String: Any] = [
///         "id": "uniqueTaskID",
///         "action": "delete"
///     ]
///     NotificationCenter.default.post(name: .taskNotification, object: nil, userInfo: userInfo)
/// }
///
/// func deleteTaskWithDelay() {
///     let userInfo: [String: Any] = [
///         "id": "uniqueTaskID",
///         "action": "deleteWithDelay",
///         "delay": 4.0 // 4 would be invalid, because it would count as an int
///     ]
///     NotificationCenter.default.post(name: .taskNotification, object: nil, userInfo: userInfo)
/// }
/// ```
///
/// You can also use the static helper method instead of creating dictionaries manually:
/// ```swift
/// TaskNotificationHandler.postTask(action: .create, model: .init(id: "task_id", "title": "New Task"))
/// ```
///
/// - Important: Please refer to ``Dreamder/TaskNotificationModel`` and ensure you pass the correct values.
@Observable
final class TaskNotificationHandler {
    private(set) var notifications: [TaskNotificationModel] = []
    var workspaceURL: URL?

    @ObservationIgnored private let center: NotificationCenter
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private var observer: (any NSObjectProtocol)?
    @ObservationIgnored private var deletionTasks: [UUID: Task<Void, Never>] = [:]

    nonisolated enum Action: String, Sendable {
        case create
        case createWithPriority
        case update
        case delete
        case deleteWithDelay
    }

    /// Post a new task.
    /// - Parameters:
    ///   - toWorkspace: The workspace to restrict the task to. Defaults to `nil`, which is received by all workspaces.
    ///   - action: The action being taken on the task.
    ///   - model: The task contents.
    @MainActor
    static func postTask(toWorkspace: URL? = nil, action: Action, model: TaskNotificationModel) {
        NotificationCenter.default.post(name: .taskNotification, object: nil, userInfo: [
            "id": model.id,
            "title": model.title,
            "message": model.message as Any,
            "percentage": model.percentage as Any,
            "isLoading": model.isLoading,
            "action": action.rawValue,
            "workspace": toWorkspace as Any
        ])
    }

    /// Initialises a new `TaskNotificationHandler` and starts observing for task notifications.
    init(
        workspaceURL: URL? = nil,
        center: NotificationCenter = .default,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.workspaceURL = workspaceURL
        self.center = center
        self.clock = clock

        observer = center.addObserver(
            forName: .taskNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let event = TaskNotificationEvent(userInfo: notification.userInfo)
            MainActor.assumeIsolated {
                self?.handle(event)
            }
        }
    }

    isolated deinit {
        if let observer {
            center.removeObserver(observer)
        }
        deletionTasks.values.forEach { $0.cancel() }
    }

    private func handle(_ event: TaskNotificationEvent) {
        guard let taskID = event.id, let action = event.action else { return }

        if let workspaceURL = event.workspace, workspaceURL != self.workspaceURL {
            return
        }

        switch action {
        case .create, .createWithPriority:
            createTask(event, taskID: taskID, action: action)
        case .update:
            updateTask(event, taskID: taskID)
        case .delete:
            deleteTask(taskID: taskID)
        case .deleteWithDelay:
            if let delay = event.delay {
                deleteTaskAfterDelay(taskID: taskID, delay: delay)
            }
        }
    }

    private func createTask(_ event: TaskNotificationEvent, taskID: String, action: Action) {
        guard let title = event.title else { return }

        let task = TaskNotificationModel(
            id: taskID,
            title: title,
            message: event.message,
            percentage: event.percentage,
            isLoading: event.isLoading ?? false
        )

        if action == .create {
            notifications.append(task)
        } else {
            notifications.insert(task, at: 0)
        }
    }

    private func updateTask(_ event: TaskNotificationEvent, taskID: String) {
        guard let index = notifications.firstIndex(where: { $0.id == taskID }) else { return }
        if let title = event.title {
            notifications[index].title = title
        }
        if let message = event.message {
            notifications[index].message = message
        }
        if let percentage = event.percentage {
            notifications[index].percentage = percentage
        }
        if let isLoading = event.isLoading {
            notifications[index].isLoading = isLoading
        }
    }

    private func deleteTask(taskID: String) {
        notifications.removeAll { $0.id == taskID }
    }

    private func deleteTaskAfterDelay(taskID: String, delay: Double) {
        let key = UUID()
        deletionTasks[key] = Task { [weak self, clock] in
            do {
                try await Task.sleep(for: Duration.seconds(delay), clock: clock)
            } catch {
                return
            }
            self?.deleteTask(taskID: taskID)
            self?.deletionTasks[key] = nil
        }
    }
}

nonisolated struct TaskNotificationEvent: Sendable, Equatable {
    let id: String?
    let action: TaskNotificationHandler.Action?
    let workspace: URL?
    let title: String?
    let message: String?
    let percentage: Double?
    let isLoading: Bool?
    let delay: Double?

    init(userInfo: [AnyHashable: Any]?) {
        let info = userInfo ?? [:]
        id = info["id"] as? String
        action = (info["action"] as? String).flatMap(TaskNotificationHandler.Action.init(rawValue:))
        workspace = info["workspace"] as? URL
        title = info["title"] as? String
        message = info["message"] as? String
        percentage = info["percentage"] as? Double
        isLoading = info["isLoading"] as? Bool
        delay = info["delay"] as? Double
    }
}

nonisolated extension Notification.Name {
    static let taskNotification = Notification.Name("taskNotification")
}
