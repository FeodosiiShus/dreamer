//
//  NotificationPanelViewModel.swift
//  Dreamder
//
//  Created by Austin Condiff on 2/14/24.
//

import SwiftUI

@Observable
final class NotificationPanelViewModel {
    /// Currently displayed notifications in the panel
    private(set) var activeNotifications: [CENotification] = []

    /// Whether notifications panel was manually shown via toolbar
    private(set) var isPresented: Bool = false

    /// Set of hidden notification IDs
    private(set) var hiddenNotificationIds: Set<UUID> = []

    @ObservationIgnored
    private var hideTasks: [UUID: Task<Void, Never>] = [:]

    @ObservationIgnored
    private var slideOutTask: Task<Void, Never>?

    @ObservationIgnored
    private var deactivationTask: Task<Void, Never>?

    private static let displayDuration: Duration = .seconds(5)
    private static let slideOutDuration: Duration = .milliseconds(300)
    private static let scrollResetDelay: Duration = .milliseconds(100)
    private static let dismissalFadeDelay: Duration = .milliseconds(10)

    @ObservationIgnored
    private let clock: any Clock<Duration>

    /// Whether notifications are paused
    @ObservationIgnored
    private var isPaused: Bool = false

    private let notificationManager: NotificationManager

    private let notificationCenter: NotificationCenter

    var scrolledToTop: Bool = true

    private(set) var hasOverflow: Bool = false

    private(set) var contentHeight: CGFloat = 0.0

    func updateOverflow(contentHeight: CGFloat, containerHeight: CGFloat) {
        if !hasOverflow && contentHeight > containerHeight {
            hasOverflow = true
        } else if hasOverflow && contentHeight <= containerHeight {
            hasOverflow = false
        }
    }

    func contentHeightChanged(_ newHeight: CGFloat, containerHeight: CGFloat) {
        contentHeight = newHeight
        updateOverflow(contentHeight: newHeight, containerHeight: containerHeight)
    }

    func containerHeightChanged(_ newHeight: CGFloat) {
        updateOverflow(contentHeight: contentHeight, containerHeight: newHeight)
    }

    /// A filtered list of active notifications.
    var visibleNotifications: [CENotification] {
        activeNotifications.filter { !hiddenNotificationIds.contains($0.id) }
    }

    @ObservationIgnored
    weak var workspace: WorkspaceDocument?

    /// Whether a notification should be visible in the panel
    func isNotificationVisible(_ notification: CENotification) -> Bool {
        if notification.isBeingDismissed {
            return true // Always show notifications being dismissed
        }
        if notification.isSticky {
            return true // Always show sticky notifications
        }
        if isPresented {
            return true // Show all notifications when manually shown
        }
        return !hiddenNotificationIds.contains(notification.id)
    }

    /// Handles focus changes for the notification panel
    func handleFocusChange(isFocused: Bool) {
        if !isFocused {
            // Only hide if manually shown and focus is completely lost
            if isPresented {
                toggleNotificationsVisibility()
            }
        }
    }

    /// Toggles visibility of notifications in the panel
    func toggleNotificationsVisibility() {
        if isPresented {
            if !scrolledToTop {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isPresented = false
                }
                slideOutTask?.cancel()
                slideOutTask = Task { [weak self, clock] in
                    guard await Self.pause(Self.slideOutDuration, on: clock) else { return }
                    self?.hideRegularNotifications()
                    guard await Self.pause(Self.scrollResetDelay, on: clock) else { return }
                    self?.scrolledToTop = true
                }
            } else {
                hideNotifications()
            }
        } else {
            slideOutTask?.cancel()
            withAnimation(.easeInOut(duration: 0.3)) {
                isPresented = true
                hiddenNotificationIds.removeAll()
            }
        }
    }

    func controlStateChanged(isActive: Bool) {
        deactivationTask?.cancel()
        guard !isActive, isPresented else { return }
        deactivationTask = Task { [weak self, clock] in
            guard await Self.pause(Self.slideOutDuration, on: clock) else { return }
            guard let self, isPresented else { return }
            toggleNotificationsVisibility()
        }
    }

    private static func pause(_ duration: Duration, on clock: any Clock<Duration>) async -> Bool {
        do {
            try await Task.sleep(for: duration, clock: clock)
            return !Task.isCancelled
        } catch {
            return false
        }
    }

    private func hideRegularNotifications() {
        activeNotifications
            .filter { !$0.isSticky }
            .forEach { hiddenNotificationIds.insert($0.id) }
    }

    private func hideNotifications() {
        withAnimation(.easeInOut(duration: 0.3)) {
            isPresented = false
            hideRegularNotifications()
        }
    }

    func startHideTimer(for notification: CENotification) {
        guard !notification.isSticky && !isPresented else { return }

        let id = notification.id
        hideTasks[id]?.cancel()
        hideTasks[id] = nil

        guard !isPaused else { return }

        hideTasks[id] = Task { [weak self, clock] in
            guard await Self.pause(Self.displayDuration, on: clock) else { return }
            self?.hideAfterDisplayDuration(id)
        }
    }

    private func hideAfterDisplayDuration(_ id: UUID) {
        hideTasks[id] = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.allowsImplicitAnimation = true

            withAnimation(.easeInOut(duration: 0.3)) {
                var newHiddenIds = hiddenNotificationIds
                newHiddenIds.insert(id)
                hiddenNotificationIds = newHiddenIds
            }
        }
    }

    func pauseTimer() {
        isPaused = true
        hideTasks.values.forEach { $0.cancel() }
        hideTasks.removeAll()
    }

    func resumeTimer() {
        isPaused = false
        activeNotifications
            .filter { !$0.isSticky && isNotificationVisible($0) }
            .forEach { startHideTimer(for: $0) }
    }

    /// Inserts a notification in the correct position (sticky notifications on top)
    private func insertNotification(_ notification: CENotification) {
        if notification.isSticky {
            // Find the first sticky notification (to insert before it)
            if let firstStickyIndex = activeNotifications.firstIndex(where: { $0.isSticky }) {
                // Insert at the very start of sticky group
                activeNotifications.insert(notification, at: firstStickyIndex)
            } else {
                // No sticky notifications yet, insert at the start
                activeNotifications.insert(notification, at: 0)
            }
        } else {
            // Find the first non-sticky notification
            if let firstNonStickyIndex = activeNotifications.firstIndex(where: { !$0.isSticky }) {
                // Insert at the start of non-sticky group
                activeNotifications.insert(notification, at: firstNonStickyIndex)
            } else {
                // No non-sticky notifications yet, append at the end
                activeNotifications.append(notification)
            }
        }
    }

    /// Handles a new notification being added
    func handleNewNotification(_ notification: CENotification) {
        let operation = {
            self.insertNotification(notification)
            self.hiddenNotificationIds.remove(notification.id)
            if !self.isPresented && !notification.isSticky {
                self.startHideTimer(for: notification)
            }
        }

        withAnimation(.easeInOut(duration: 0.3), operation) {
            self.updateToolbarItem()
        }
    }

    /// Dismisses a specific notification
    func dismissNotification(_ notification: CENotification, disableAnimation: Bool = false) {
        hideTasks[notification.id]?.cancel()
        hideTasks[notification.id] = nil
        hiddenNotificationIds.remove(notification.id)

        // Mark as being dismissed for animation
        if let index = activeNotifications.firstIndex(where: { $0.id == notification.id }) {
            if disableAnimation {
                self.activeNotifications.removeAll(where: { $0.id == notification.id })
                notificationManager.markAsRead(notification)
                notificationManager.dismissNotification(notification)
                return
            }

            var dismissingNotification = activeNotifications[index]
            dismissingNotification.isBeingDismissed = true
            activeNotifications[index] = dismissingNotification

            Task { [self, clock] in
                guard await Self.pause(Self.dismissalFadeDelay, on: clock) else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    activeNotifications.removeAll(where: { $0.id == notification.id })
                    if activeNotifications.isEmpty && isPresented {
                        isPresented = false
                    }
                }

                notificationManager.markAsRead(notification)
                notificationManager.dismissNotification(notification)
            }
        }
    }

    func updateToolbarItem() {
        let shouldShow = !visibleNotifications.isEmpty || notificationManager.unreadCount > 0
        workspace?.windowControllers.compactMap { $0.window?.toolbar }.forEach { toolbar in
            if shouldShow {
                toolbar.showNotificationItem()
            } else {
                toolbar.hideNotificationItem()
            }
        }
    }

    func dismissHandler(for notification: CENotification) -> () -> Void {
        { [self] in dismissNotification(notification) }
    }

    func actionHandler(for notification: CENotification) -> () -> Void {
        { [self] in performAction(of: notification) }
    }

    func performAction(of notification: CENotification) {
        notification.action()
        if isPresented {
            toggleNotificationsVisibility()
            dismissNotification(notification, disableAnimation: true)
        } else {
            dismissNotification(notification)
        }
    }

    func updateScrollOffset(_ offset: CGFloat) {
        if offset <= 0.0 && !scrolledToTop {
            scrolledToTop = true
        } else if offset > 0.0 && scrolledToTop {
            scrolledToTop = false
        }
    }

    func focusChanged(_ oldValue: Bool, _ newValue: Bool) {
        handleFocusChange(isFocused: newValue)
    }

    func hoverChanged(_ hovering: Bool) {
        if hovering {
            pauseTimer()
        } else {
            resumeTimer()
        }
    }

    init(
        notificationManager: NotificationManager = .shared,
        notificationCenter: NotificationCenter = .default,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.notificationManager = notificationManager
        self.notificationCenter = notificationCenter
        self.clock = clock
        // Observe new notifications
        notificationCenter.addObserver(
            self,
            selector: #selector(handleNewNotificationAdded(_:)),
            name: .init("NewNotificationAdded"),
            object: nil
        )

        // Observe notification dismissals
        notificationCenter.addObserver(
            self,
            selector: #selector(handleNotificationRemoved(_:)),
            name: .init("NotificationDismissed"),
            object: nil
        )

        // Load initial notifications from NotificationManager
        notificationManager.notifications.forEach { notification in
            handleNewNotification(notification)
        }
    }

    isolated deinit {
        notificationCenter.removeObserver(self)
        hideTasks.values.forEach { $0.cancel() }
        slideOutTask?.cancel()
        deactivationTask?.cancel()
    }

    @objc
    private func handleNewNotificationAdded(_ notification: Notification) {
        guard let ceNotification = notification.object as? CENotification else { return }
        handleNewNotification(ceNotification)
    }

    @objc
    private func handleNotificationRemoved(_ notification: Notification) {
        guard let ceNotification = notification.object as? CENotification else { return }

        let operation: () -> Void = {
            self.activeNotifications.removeAll(where: { $0.id == ceNotification.id })

            // If this was the last notification and they were manually shown, hide the panel
            if self.activeNotifications.isEmpty && self.isPresented {
                self.isPresented = false
            }
        }

        // Just remove from active notifications without triggering global state changes
        withAnimation(.easeOut(duration: 0.2), operation) {
            self.updateToolbarItem()
        }
    }
}
