import AppKit
import SwiftUI

final class GoToLinePopupPresenter: NSObject, NSPopoverDelegate {
    private(set) var popover: NSPopover?

    var isPresented: Bool {
        popover?.isShown == true
    }

    func present(model: GoToLinePopupModel, relativeTo rect: NSRect, of view: NSView) {
        dismiss()
        guard view.window != nil else { return }
        let controller = NSHostingController(rootView: GoToLinePopupView(model: model))
        controller.sizingOptions = [.preferredContentSize]
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentViewController = controller
        popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)
        self.popover = popover
    }

    func dismiss() {
        popover?.close()
        popover = nil
    }

    func popoverDidClose(_ notification: Notification) {
        if (notification.object as? NSPopover) === popover {
            popover = nil
        }
    }
}
