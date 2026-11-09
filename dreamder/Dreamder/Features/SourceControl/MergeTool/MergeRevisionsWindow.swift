import AppKit
import SwiftUI

@MainActor
final class MergeRevisionsWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    let model: MergeRevisionsViewModel
    private let preferredContentSize = NSSize(width: 1240, height: 780)
    private var isClosingAfterConfirmation = false

    init(model: MergeRevisionsViewModel) {
        self.model = model

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 1240, height: 812)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = model.title
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(Islands.frame)
        window.contentMinSize = NSSize(width: 720, height: 460)
        window.isReleasedWhenClosed = false

        let rootView = MergeRevisionsView(model: model) { [weak window] in
            window?.performClose(nil)
        }
        window.contentViewController = NSHostingController(rootView: rootView)
        window.setContentSize(preferredContentSize)

        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func place(relativeTo parent: NSWindow?) {
        guard let window else { return }
        window.setContentSize(preferredContentSize)
        let size = window.frame.size
        let anchor = parent?.frame ?? NSScreen.main?.visibleFrame
        let visible = (parent?.screen ?? NSScreen.main)?.visibleFrame
        let origin = MergeConflictsWindowController.origin(size: size, anchor: anchor, visible: visible)
        window.setFrame(NSRect(origin: origin, size: size), display: false)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !isClosingAfterConfirmation, model.isResultEdited else { return true }
        Task { @MainActor in
            guard await model.requestCancel(window: sender) else { return }
            isClosingAfterConfirmation = true
            sender.performClose(nil)
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
