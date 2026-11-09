import AppKit
import CodeEditSourceEditor

final class EditorBackgroundCoordinator: TextViewCoordinator {
    private weak var controller: TextViewController?
    private var observer: NSObjectProtocol?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func prepareCoordinator(controller: TextViewController) {
        self.controller = controller
    }

    func controllerDidAppear(controller: TextViewController) {
        if observer == nil {
            observer = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.applyTransparency()
                }
            }
        }
        applyTransparency()
    }

    func controllerDidDisappear(controller: TextViewController) {
        removeObserver()
    }

    func destroy() {
        removeObserver()
        controller = nil
    }

    private func removeObserver() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
    }

    private func applyTransparency() {
        guard let controller, let scrollView = controller.scrollView else { return }
        let hasBackgroundImage = !(defaults.string(forKey: Islands.BackgroundImageKey.path) ?? "").isEmpty
        if hasBackgroundImage {
            scrollView.drawsBackground = false
            scrollView.contentView.drawsBackground = false
            scrollView.contentView.backgroundColor = .clear
            controller.textView?.layer?.backgroundColor = .clear
        } else {
            scrollView.drawsBackground = true
            scrollView.contentView.drawsBackground = true
            if controller.useThemeBackground {
                scrollView.backgroundColor = controller.theme.background
            }
        }
    }
}
