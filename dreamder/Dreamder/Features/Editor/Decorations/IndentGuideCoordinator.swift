import AppKit
import CodeEditSourceEditor
import CodeEditTextView

final class IndentGuideCoordinator: TextViewCoordinator {
    private weak var controller: TextViewController?
    private weak var overlay: IndentGuideOverlayView?
    private var frameObserver: NSObjectProtocol?

    func prepareCoordinator(controller: TextViewController) {
        self.controller = controller
    }

    func controllerDidAppear(controller: TextViewController) {
        installIfNeeded(controller: controller)
        invalidate()
    }

    func controllerDidDisappear(controller: TextViewController) {
        removeOverlay()
    }

    func textViewDidChangeText(controller: TextViewController) {
        invalidate()
    }

    func textViewDidChangeSelection(controller: TextViewController, newPositions: [CursorPosition]) {
        invalidate()
    }

    func destroy() {
        removeOverlay()
        controller = nil
    }

    private func removeOverlay() {
        if let frameObserver {
            NotificationCenter.default.removeObserver(frameObserver)
        }
        frameObserver = nil
        overlay?.removeFromSuperview()
        overlay = nil
    }

    private func installIfNeeded(controller: TextViewController) {
        guard overlay == nil, let textView = controller.textView else { return }
        let view = IndentGuideOverlayView(frame: textView.bounds)
        view.textView = textView
        view.tabWidth = controller.tabWidth
        textView.addSubview(view, positioned: .below, relativeTo: nil)
        overlay = view
        frameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: textView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.overlay?.matchSuperviewBounds()
            }
        }
    }

    private func invalidate() {
        guard let controller, let overlay else { return }
        overlay.tabWidth = controller.tabWidth
        overlay.matchSuperviewBounds()
        overlay.needsDisplay = true
    }
}
