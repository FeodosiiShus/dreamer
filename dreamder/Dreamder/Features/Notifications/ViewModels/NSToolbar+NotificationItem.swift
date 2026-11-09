import AppKit

extension NSToolbar {
    var hasNotificationItem: Bool {
        items.contains { $0.itemIdentifier == .notificationItem }
    }

    func showNotificationItem() {
        guard !hasNotificationItem,
              let activityIndex = items.firstIndex(where: { $0.itemIdentifier == .activityViewer })
        else { return }
        insertItem(withItemIdentifier: .space, at: activityIndex + 1)
        insertItem(withItemIdentifier: .notificationItem, at: activityIndex + 2)
    }

    func hideNotificationItem() {
        guard let index = items.firstIndex(where: { $0.itemIdentifier == .notificationItem }) else { return }
        removeItem(at: index)
        let spacerIndex = index - 1
        guard items.indices.contains(spacerIndex), items[spacerIndex].itemIdentifier == .space else { return }
        removeItem(at: spacerIndex)
    }
}
