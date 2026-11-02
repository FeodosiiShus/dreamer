import AppKit
import Foundation

@MainActor
final class MergeScrollCoordinator: ObservableObject {
    private final class Registration {
        weak var scrollView: NSScrollView?
        var observer: NSObjectProtocol?
    }

    private var registrations: [String: Registration] = [:]
    private var isSyncing = false

    deinit {
        for registration in registrations.values {
            if let observer = registration.observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }

    func register(_ scrollView: NSScrollView, id: String) {
        guard registrations[id]?.scrollView !== scrollView else { return }
        unregister(id: id)

        let registration = Registration()
        registration.scrollView = scrollView
        scrollView.contentView.postsBoundsChangedNotifications = true
        registration.observer = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self, weak scrollView] _ in
            MainActor.assumeIsolated {
                guard let self, let scrollView else { return }
                self.scrollDidChange(id: id, scrollView: scrollView)
            }
        }
        registrations[id] = registration
    }

    func unregister(id: String) {
        if let observer = registrations[id]?.observer {
            NotificationCenter.default.removeObserver(observer)
        }
        registrations[id] = nil
    }

    private func scrollDidChange(id: String, scrollView: NSScrollView) {
        guard !isSyncing else { return }
        let clipView = scrollView.contentView
        let documentHeight = scrollView.documentView?.frame.height ?? 0
        let maximumY = max(documentHeight - clipView.bounds.height, 1)
        let fraction = min(max(clipView.bounds.origin.y / maximumY, 0), 1)

        isSyncing = true
        for (otherID, registration) in registrations where otherID != id {
            guard let other = registration.scrollView, let documentView = other.documentView else { continue }
            let otherClip = other.contentView
            let otherMaximum = max(documentView.frame.height - otherClip.bounds.height, 0)
            let target = NSPoint(x: otherClip.bounds.origin.x, y: otherMaximum * fraction)
            otherClip.scroll(to: target)
            other.reflectScrolledClipView(otherClip)
        }
        isSyncing = false
    }
}
