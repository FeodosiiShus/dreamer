import AppKit
import CodeEditSourceEditor
import CodeEditTextView

final class IndentGuideCoordinator: TextViewCoordinator {
    private weak var controller: TextViewController?
    private weak var overlay: IndentGuideOverlayView?

    func prepareCoordinator(controller: TextViewController) {
        self.controller = controller
    }

    func controllerDidAppear(controller: TextViewController) {
        installIfNeeded(controller: controller)
        invalidate()
    }

    func controllerDidDisappear(controller: TextViewController) {
        overlay?.removeFromSuperview()
        overlay = nil
    }

    func textViewDidChangeText(controller: TextViewController) {
        invalidate()
    }

    func textViewDidChangeSelection(controller: TextViewController, newPositions: [CursorPosition]) {
        invalidate()
    }

    func destroy() {
        overlay?.removeFromSuperview()
        overlay = nil
        controller = nil
    }

    private func installIfNeeded(controller: TextViewController) {
        guard overlay == nil, let textView = controller.textView else { return }
        let view = IndentGuideOverlayView()
        view.textView = textView
        view.tabWidth = controller.tabWidth
        view.frame = textView.bounds
        view.autoresizingMask = [.width, .height]
        textView.addSubview(view, positioned: .below, relativeTo: nil)
        overlay = view
    }

    private func invalidate() {
        guard let controller, let overlay, let textView = controller.textView else { return }
        overlay.tabWidth = controller.tabWidth
        if overlay.frame.size != textView.bounds.size {
            overlay.frame = textView.bounds
        }
        overlay.needsDisplay = true
    }
}
