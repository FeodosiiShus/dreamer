import AppKit
import SwiftUI

final class ShowUsagesPanel: NSPanel, NSWindowDelegate {
    var onKeyEvent: ((NSEvent) -> Bool)?
    var onClose: (() -> Void)?
    var restoresFocusOnClose = true

    private let panelSize: NSSize
    private weak var previousResponder: NSResponder?

    init(size: NSSize) {
        self.panelSize = size
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = true
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        delegate = self
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKeyEvent?(event) == true {
            return
        }
        super.sendEvent(event)
    }

    func place(in parent: NSWindow, below anchor: NSRect?) {
        let size = panelSize
        let parentFrame = parent.frame
        let screen = parent.screen ?? NSScreen.main
        var origin = NSPoint(
            x: parentFrame.midX - size.width / 2,
            y: parentFrame.maxY - size.height - 92
        )

        if let anchor {
            origin.x = anchor.minX
            let below = anchor.minY - size.height - 4
            let visibleMinY = screen?.visibleFrame.minY ?? 0
            origin.y = below >= visibleMinY + 8 ? below : anchor.maxY + 4
        }

        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        }

        if previousResponder == nil {
            previousResponder = parent.firstResponder
        }
        setFrame(NSRect(origin: origin, size: size), display: false)
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    func windowWillClose(_ notification: Notification) {
        let parentWindow = parent
        parentWindow?.removeChildWindow(self)
        if restoresFocusOnClose, let previousResponder, let parentWindow {
            _ = parentWindow.makeFirstResponder(previousResponder)
        }
        onClose?()
        onClose = nil
    }
}

@MainActor
final class ShowUsagesPanelHost {
    static let shared = ShowUsagesPanelHost()

    private struct Entry {
        weak var panel: ShowUsagesPanel?
        let model: ShowUsagesViewModel
    }

    private var entries: [ObjectIdentifier: Entry] = [:]

    func show(rows: [LSPUsageRow], symbol: String, in controller: DreamderWindowController) {
        present(
            ShowUsagesViewModel(rows: rows, symbol: symbol),
            anchor: LSPCaretAnchor.screenRect(in: controller.window),
            in: controller
        )
    }

    func showMessage(_ message: String, in controller: DreamderWindowController) {
        present(
            ShowUsagesViewModel(message: message),
            anchor: LSPCaretAnchor.screenRect(in: controller.window),
            in: controller
        )
    }

    private func present(
        _ model: ShowUsagesViewModel,
        anchor: NSRect?,
        in controller: DreamderWindowController
    ) {
        entries = entries.filter { $0.value.panel != nil }
        guard let window = controller.window else { return }
        let key = ObjectIdentifier(controller)
        entries[key]?.panel?.close()

        let size = NSSize(width: model.panelWidth, height: model.preferredHeight)
        let panel = ShowUsagesPanel(size: size)
        let hostingView = NSHostingView(rootView: ShowUsagesView(model: model))
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hostingView

        model.dismiss = { [weak panel] in
            panel?.close()
        }
        model.openRow = { [weak panel, weak controller] row in
            panel?.restoresFocusOnClose = false
            panel?.close()
            guard let workspace = controller?.workspace else { return }
            EditorLocationNavigation.open(
                fileURL: row.fileURL,
                line: row.line + 1,
                column: row.column + 1,
                workspace: workspace
            )
        }
        panel.onKeyEvent = { [weak model] event in
            model?.handle(event: event) ?? false
        }
        panel.onClose = { [weak self] in
            self?.entries.removeValue(forKey: key)
        }

        entries[key] = Entry(panel: panel, model: model)

        window.addChildWindow(panel, ordered: .above)
        panel.place(in: window, below: anchor)
        panel.makeKeyAndOrderFront(nil)
    }
}
