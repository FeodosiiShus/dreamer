import SwiftUI

struct StatusBarNotificationsButton: View {
    @Environment(WorkspaceDocument.self) private var workspace
    private let notificationManager: NotificationManager

    @State private var isHovering = false

    init(notificationManager: NotificationManager = .shared) {
        self.notificationManager = notificationManager
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
        Button(action: Self.togglingAction(panel: workspace.notificationPanel, notificationManager: notificationManager)) {
            ZStack(alignment: .topTrailing) {
                Image("toolwindows/notifications")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
                if notificationManager.unreadCount > 0 {
                    Circle()
                        .fill(Islands.accent)
                        .frame(width: 6, height: 6)
                        .offset(x: 3, y: -2)
                }
            }
            .frame(width: 22, height: 22)
            .background(
                RoundedRectangle(cornerRadius: Islands.rowRadius)
                    .fill(isHovering ? Islands.islandRaised.opacity(0.8) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Notifications")
        .onHover(perform: setHovering)
    }

    func setHovering(_ hovering: Bool) {
        isHovering = hovering
    }
}
