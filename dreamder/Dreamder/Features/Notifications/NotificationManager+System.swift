//
//  NotificationManager+System.swift
//  Dreamder
//
//  Created by Austin Condiff on 2/14/24.
//

import Foundation
import UserNotifications

protocol SystemNotificationCenter: AnyObject {
    func attach(delegate: any UNUserNotificationCenterDelegate)
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>)
    func requestAuthorization(options: UNAuthorizationOptions) async
    func add(_ request: UNNotificationRequest)
    func removeDeliveredNotifications(withIdentifiers identifiers: [String])
    func removeAllDeliveredNotifications()
}

final class LiveSystemNotificationCenter: SystemNotificationCenter {
    private var current: UNUserNotificationCenter { UNUserNotificationCenter.current() }

    func attach(delegate: any UNUserNotificationCenterDelegate) {
        current.delegate = delegate
    }

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        current.setNotificationCategories(categories)
    }

    func requestAuthorization(options: UNAuthorizationOptions) async {
        _ = try? await current.requestAuthorization(options: options)
    }

    func add(_ request: UNNotificationRequest) {
        current.add(request)
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        current.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func removeAllDeliveredNotifications() {
        current.removeAllDeliveredNotifications()
    }
}

extension NotificationManager {
    /// Shows a system notification when app is in background
    func showSystemNotification(_ notification: CENotification) {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.description

        if !notification.actionButtonTitle.isEmpty {
            content.categoryIdentifier = "ACTIONABLE"
        }

        let request = UNNotificationRequest(
            identifier: notification.id.uuidString,
            content: content,
            trigger: nil
        )

        center.add(request)
    }

    /// Removes a system notification
    func removeSystemNotification(_ notification: CENotification) {
        center.removeDeliveredNotifications(
            withIdentifiers: [notification.id.uuidString]
        )
    }

    /// Handles response from system notification
    func handleSystemNotificationResponse(id: String) {
        if let uuid = UUID(uuidString: id),
           let notification = notifications.first(where: { $0.id == uuid }) {
            notification.action()
            dismissNotification(notification)
        }
    }
}
