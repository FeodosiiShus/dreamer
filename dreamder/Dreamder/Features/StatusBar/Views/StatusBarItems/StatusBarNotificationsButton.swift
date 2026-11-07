import SwiftUI

struct StatusBarNotificationsButton: View {
    @Environment(WorkspaceDocument.self) private var workspace
    private let notificationManager = NotificationManager.shared

    @State private var isHovering = false

    var body: some View {
        Button {
            let panel = workspace.notificationPanel
            panel.toggleNotificationsVisibility()
            if panel.isPresented {
                notificationManager.markAllAsRead()
            }
        } label: {
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
                    .fill(isHovering ? Islands.hover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Notifications")
        .onHover { isHovering = $0 }
    }
}
