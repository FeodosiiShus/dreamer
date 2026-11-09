//
//  NotificationManager.swift
//  Dreamder
//
//  Created by Austin Condiff on 2/10/24.
//

import SwiftUI
import Observation
import UserNotifications

/// Manages the application's notification system, handling both in-app notifications and system notifications.
/// This class is responsible for:
/// - Managing notification persistence
/// - Tracking notification read status
/// - Broadcasting notifications to workspaces
@Observable
final class NotificationManager: NSObject {
    static let shared = NotificationManager()

    let center: any SystemNotificationCenter

    let notificationCenter: NotificationCenter

    /// Collection of all notifications, both read and unread
    private(set) var notifications: [CENotification] = []

    @ObservationIgnored
    private var isAppActive: Bool = true

    /// Number of unread notifications
    var unreadCount: Int {
        notifications.filter { !$0.isRead }.count
    }

    /// Posts a new notification
    /// - Parameters:
    ///   - iconSymbol: SF Symbol or DreamderSymbol name for the notification icon
    ///   - iconColor: Color for the icon
    ///   - title: Main notification title
    ///   - description: Detailed notification message
    ///   - actionButtonTitle: Title for the action button
    ///   - action: Closure to execute when action button is clicked
    ///   - isSticky: Whether the notification should persist until manually dismissed
    func post(
        iconSymbol: String,
        iconColor: Color? = Color(.systemBlue),
        title: String,
        description: String,
        actionButtonTitle: String,
        action: @escaping () -> Void,
        isSticky: Bool = false
    ) {
        let notification = CENotification(
            iconSymbol: iconSymbol,
            iconColor: iconColor,
            title: title,
            description: description,
            actionButtonTitle: actionButtonTitle,
            action: action,
            isSticky: isSticky,
            isRead: false
        )

        postNotification(notification)
    }

    /// Posts a new notification
    /// - Parameters:
    ///   - iconImage: Image for the notification icon
    ///   - title: Main notification title
    ///   - description: Detailed notification message
    ///   - actionButtonTitle: Title for the action button
    ///   - action: Closure to execute when action button is clicked
    ///   - isSticky: Whether the notification should persist until manually dismissed
    func post(
        iconImage: Image,
        title: String,
        description: String,
        actionButtonTitle: String,
        action: @escaping () -> Void,
        isSticky: Bool = false
    ) {
        let notification = CENotification(
            iconImage: iconImage,
            title: title,
            description: description,
            actionButtonTitle: actionButtonTitle,
            action: action,
            isSticky: isSticky
        )

        postNotification(notification)
    }

    /// Posts a new notification
    /// - Parameters:
    ///   - iconText: Text or emoji for the notification icon
    ///   - iconTextColor: Color of the text/emoji (defaults to primary label color)
    ///   - iconColor: Background color for the icon
    ///   - title: Main notification title
    ///   - description: Detailed notification message
    ///   - actionButtonTitle: Title for the action button
    ///   - action: Closure to execute when action button is clicked
    ///   - isSticky: Whether the notification should persist until manually dismissed
    func post(
        iconText: String,
        iconTextColor: Color? = nil,
        iconColor: Color? = Color(.systemBlue),
        title: String,
        description: String,
        actionButtonTitle: String,
        action: @escaping () -> Void,
        isSticky: Bool = false
    ) {
        let notification = CENotification(
            iconText: iconText,
            iconTextColor: iconTextColor,
            iconColor: iconColor,
            title: title,
            description: description,
            actionButtonTitle: actionButtonTitle,
            action: action,
            isSticky: isSticky
        )

        postNotification(notification)
    }

    /// Dismisses a specific notification
    func dismissNotification(_ notification: CENotification) {
        notifications.removeAll(where: { $0.id == notification.id })
        markAsRead(notification)

        // Remove system notification if it exists
        removeSystemNotification(notification)

        notificationCenter.post(
            name: .init("NotificationDismissed"),
            object: notification
        )
    }

    /// Marks a notification as read
    /// - Parameter notification: The notification to mark as read
    func markAsRead(_ notification: CENotification) {
        if let index = notifications.firstIndex(where: { $0.id == notification.id }) {
            notifications[index].isRead = true
        }
    }

    func markAllAsRead() {
        for index in notifications.indices where !notifications[index].isRead {
            notifications[index].isRead = true
        }
    }

    init(
        center: any SystemNotificationCenter = LiveSystemNotificationCenter(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.center = center
        self.notificationCenter = notificationCenter
        super.init()
        setupNotificationDelegate()

        // Observe app active state
        notificationCenter.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )

        notificationCenter.addObserver(
            self,
            selector: #selector(handleAppDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }

    @objc
    private func handleAppDidBecomeActive() {
        isAppActive = true
        // Remove any system notifications when app becomes active
        center.removeAllDeliveredNotifications()
    }

    @objc
    private func handleAppDidResignActive() {
        isAppActive = false
    }

    /// Posts a notification to workspaces and system
    private func postNotification(_ notification: CENotification) {
        Task { [weak self] in
            guard let self else { return }
            notifications.append(notification)

            notificationCenter.post(
                name: .init("NewNotificationAdded"),
                object: notification
            )

            if !isAppActive {
                showSystemNotification(notification)
            }
        }
    }
}
