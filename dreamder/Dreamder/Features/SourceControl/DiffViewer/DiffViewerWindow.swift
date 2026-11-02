import AppKit
import Combine
import SwiftUI

@MainActor
final class DiffViewerWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    private let model: DiffViewerViewModel
    private var titleCancellable: AnyCancellable?

    init(model: DiffViewerViewModel) {
        self.model = model
        let hostingController = NSHostingController(rootView: DiffViewerView(model: model))
        let window = NSWindow(contentViewController: hostingController)
        window.title = model.title
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(Islands.frame)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 1180, height: 760))
        window.minSize = NSSize(width: 640, height: 360)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        titleCancellable = model.$title
            .receive(on: RunLoop.main)
            .sink { [weak window] title in
                window?.title = title
            }
        Task { [model] in
            await model.loadInitial()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func place(relativeTo parent: NSWindow?) {
        guard let window else { return }
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
            await model.loadInitial()
        }
    }

    func update(files: [DiffFileRequest]) {
        Task { [model] in
            await model.updateFiles(files)
        }
    }

    func windowWillClose(_ notification: Notification) {
        titleCancellable = nil
        onClose?()
    }
}
