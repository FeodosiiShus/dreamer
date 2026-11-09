import AppKit
import CodeEditSourceEditor
import SwiftUI

final class QuickDocumentationPanel: NSPanel, NSWindowDelegate {
    var onClose: (() -> Void)?

    private let panelSize: NSSize

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

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func place(in parent: NSWindow, beside anchor: NSRect?) {
        let size = panelSize
        let parentFrame = parent.frame
        let screen = parent.screen ?? NSScreen.main
        var origin = NSPoint(
            x: parentFrame.midX - size.width / 2,
            y: parentFrame.maxY - size.height - 92
        )

        if let anchor {
            origin.x = anchor.minX
            let below = anchor.minY - size.height - 6
            let visibleMinY = screen?.visibleFrame.minY ?? 0
            origin.y = below >= visibleMinY + 8 ? below : anchor.maxY + 6
        }

        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        }

        setFrame(NSRect(origin: origin, size: size), display: false)
    }

    func windowWillClose(_ notification: Notification) {
        parent?.removeChildWindow(self)
        onClose?()
        onClose = nil
    }
}

@MainActor
final class QuickDocumentationPanelHost {
    static let shared = QuickDocumentationPanelHost()

    private struct Entry {
        weak var panel: QuickDocumentationPanel?
        var escapeMonitor: Any?
        var cursorObservation: Task<Void, Never>?
    }

    private var entries: [ObjectIdentifier: Entry] = [:]

    func show(content: QuickDocumentationContent, tab: EditorInstance, in controller: DreamderWindowController) {
        present(QuickDocumentationViewModel(content: content), tab: tab, in: controller)
    }

    func showMessage(_ message: String, in controller: DreamderWindowController) {
        present(QuickDocumentationViewModel(message: message), tab: nil, in: controller)
    }

    private func present(
        _ model: QuickDocumentationViewModel,
        tab: EditorInstance?,
        in controller: DreamderWindowController
    ) {
        entries = entries.filter { $0.value.panel != nil }
        guard let window = controller.window else { return }
        let key = ObjectIdentifier(controller)
        entries[key]?.panel?.close()

        let size = model.size
        let panel = QuickDocumentationPanel(size: size)
        let hostingView = NSHostingView(rootView: QuickDocumentationView(model: model))
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hostingView

        model.dismiss = { [weak panel] in
            panel?.close()
        }

        var entry = Entry(panel: panel, escapeMonitor: nil, cursorObservation: nil)
        entry.escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak panel] event in
            guard event.keyCode == 53 else { return event }
            guard let panel, panel.isVisible else {
                self?.removeEntry(for: key)
                return event
            }
            panel.close()
            return nil
        }
        if let tab {
            entry.cursorObservation = Task { [weak panel] in
                var previous: [CursorPosition]?
                for await positions in Observations({ tab.cursorPositions }) {
                    let changed = previous.map { $0 != positions } ?? false
                    previous = positions
                    guard changed else { continue }
                    guard let panel, panel.isVisible else { return }
                    panel.close()
                }
            }
        }
        panel.onClose = { [weak self] in
            self?.removeEntry(for: key)
        }
        entries[key] = entry

        window.addChildWindow(panel, ordered: .above)
        panel.place(in: window, beside: LSPCaretAnchor.screenRect(in: window))
        panel.orderFront(nil)
    }

    private func removeEntry(for key: ObjectIdentifier) {
        guard let entry = entries.removeValue(forKey: key) else { return }
        if let monitor = entry.escapeMonitor {
            NSEvent.removeMonitor(monitor)
        }
        entry.cursorObservation?.cancel()
    }
}
