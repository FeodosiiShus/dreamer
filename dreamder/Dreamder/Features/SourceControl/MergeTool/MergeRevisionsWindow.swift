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
        fatalError("init(coder:) is not supported")
    }

    func place(relativeTo parent: NSWindow?) {
        guard let window else { return }
        window.setContentSize(preferredContentSize)
        let size = window.frame.size
        var origin = NSPoint.zero
        if let parent {
            origin = NSPoint(
                x: parent.frame.midX - size.width / 2,
                y: parent.frame.midY - size.height / 2
            )
        } else if let screen = NSScreen.main {
            origin = NSPoint(
                x: screen.visibleFrame.midX - size.width / 2,
                y: screen.visibleFrame.midY - size.height / 2
            )
        }
        if let screen = parent?.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 12), visible.maxX - size.width - 12)
            origin.y = min(max(origin.y, visible.minY + 12), visible.maxY - size.height - 12)
        }
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
