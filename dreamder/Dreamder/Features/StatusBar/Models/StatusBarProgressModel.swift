import Observation

struct StatusBarProgressModel: Equatable {
    let entries: [TaskNotificationModel]

    init(notifications: [TaskNotificationModel]) {
        entries = notifications
    }

    var isEmpty: Bool {
        entries.isEmpty
    }

    var first: TaskNotificationModel? {
        entries.first
    }

    var extraCount: Int {
        max(0, entries.count - 1)
    }

    var counterText: String? {
        extraCount > 0 ? "+\(extraCount)" : nil
    }

    var summaryHelp: String {
        entries.count > 1 ? "\(entries.count) processes running" : (first?.title ?? "")
    }

    static func fraction(of notification: TaskNotificationModel) -> Double? {
        notification.percentage.map { min(max($0, 0), 1) }
    }

    static func isIndeterminate(_ notification: TaskNotificationModel) -> Bool {
        notification.percentage == nil && notification.isLoading
    }
}

@Observable
@MainActor
final class StatusBarProgressPresenter {
    private(set) var isRequested = false

    init(isRequested: Bool = false) {
        self.isRequested = isRequested
    }

    func toggle() {
        isRequested.toggle()
    }

    func setPresented(_ presented: Bool) {
        isRequested = presented
    }

    func isPresented(hasNotifications: Bool) -> Bool {
        isRequested && hasNotifications
    }

    func emptinessChanged(_ wasEmpty: Bool, _ isEmpty: Bool) {
        if isEmpty {
            isRequested = false
        }
    }
}
