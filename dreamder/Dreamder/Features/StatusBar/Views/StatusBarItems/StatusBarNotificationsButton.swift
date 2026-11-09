import SwiftUI

struct StatusBarNotificationsButton: View {
    @Environment(WorkspaceDocument.self) private var workspace
    private let notificationManager: NotificationManager
    private let isHovering: Bool

    init(notificationManager: NotificationManager = .shared, isHovering: Bool = false) {
        self.notificationManager = notificationManager
        self.isHovering = isHovering
    }

    static func toggle(panel: NotificationPanelViewModel, notificationManager: NotificationManager) {
        panel.toggleNotificationsVisibility()
        if panel.isPresented {
            notificationManager.markAllAsRead()
        }
    }

    static func togglingAction(
        panel: NotificationPanelViewModel,
        notificationManager: NotificationManager
    ) -> () -> Void {
        { toggle(panel: panel, notificationManager: notificationManager) }
    }

    var body: some View {
        StatusBarWidgetButton(
            isHovering: isHovering,
            action: Self.togglingAction(panel: workspace.notificationPanel, notificationManager: notificationManager)
        ) { _ in
            ZStack(alignment: .topTrailing) {
                Image("toolwindows/notifications")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: StatusBarWidgetMetrics.iconSize, height: StatusBarWidgetMetrics.iconSize)
                if notificationManager.unreadCount > 0 {
                    Circle()
                        .fill(Islands.accent)
                        .frame(width: 6, height: 6)
                        .offset(x: 3, y: -2)
                }
            }
        }
        .help("Notifications")
    }
}
