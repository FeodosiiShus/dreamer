import AppKit
import SwiftUI

@MainActor
final class MergeConflictsWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    let model: MergeConflictsViewModel
    private let preferredContentSize = NSSize(width: 900, height: 420)

    init(model: MergeConflictsViewModel) {
        self.model = model
        let hostingController = NSHostingController(rootView: MergeConflictsView(model: model))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Conflicts"
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(Islands.frame)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.contentMinSize = NSSize(width: 640, height: 300)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.setContentSize(preferredContentSize)
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

    func reload() {
        Task { [model] in
            await model.reload()
        }
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
