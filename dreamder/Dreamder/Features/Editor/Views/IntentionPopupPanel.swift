import AppKit
import SwiftUI

final class IntentionPopupPanel: NSPanel, NSWindowDelegate {
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

    static func origin(size: NSSize, parentFrame: NSRect, anchor: NSRect?, visibleFrame: NSRect?) -> NSPoint {
        var origin = NSPoint(
            x: parentFrame.midX - size.width / 2,
            y: parentFrame.maxY - size.height - 92
        )

        if let anchor {
            origin.x = anchor.minX
            let below = anchor.minY - size.height - 4
            let visibleMinY = visibleFrame?.minY ?? 0
            origin.y = below >= visibleMinY + 8 ? below : anchor.maxY + 4
        }

        if let visibleFrame {
            origin.x = min(max(origin.x, visibleFrame.minX + 8), visibleFrame.maxX - size.width - 8)
            origin.y = min(max(origin.y, visibleFrame.minY + 8), visibleFrame.maxY - size.height - 8)
        }
        return origin
    }

    func place(in parent: NSWindow, below anchor: NSRect?) {
        let origin = Self.origin(
            size: panelSize,
            parentFrame: parent.frame,
            anchor: anchor,
            visibleFrame: (parent.screen ?? NSScreen.main)?.visibleFrame
        )

        if previousResponder == nil {
            previousResponder = parent.firstResponder
        }
        setFrame(NSRect(origin: origin, size: panelSize), display: false)
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
final class IntentionPopupHost {
    static let shared = IntentionPopupHost()

    private struct Entry {
        weak var panel: IntentionPopupPanel?
        let model: IntentionPopupModel
    }

    private var entries: [ObjectIdentifier: Entry] = [:]

    func show(
        groups: [IntentionGroup],
        in controller: DreamderWindowController,
        anchor: NSRect?,
        apply: @escaping (IntentionAction) -> Void
    ) {
        let model = IntentionPopupModel(groups: groups)
        model.onApply = { [weak model] action in
            model?.close()
            apply(action)
        }
        present(model, anchor: anchor, in: controller)
    }

    func showMessage(_ message: String, in controller: DreamderWindowController) {
        present(
            IntentionPopupModel(message: message),
            anchor: LSPCaretAnchor.screenRect(in: controller.window),
            in: controller
        )
    }

    private func present(
        _ model: IntentionPopupModel,
        anchor: NSRect?,
        in controller: DreamderWindowController
    ) {
        entries = entries.filter { $0.value.panel != nil }
        guard let window = controller.window else { return }
        let key = ObjectIdentifier(controller)
        entries[key]?.panel?.close()

        let size = NSSize(width: model.panelWidth, height: model.preferredHeight)
        let panel = IntentionPopupPanel(size: size)
        let hostingView = NSHostingView(rootView: IntentionPopupView(model: model))
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hostingView

        model.dismiss = { [weak panel] in
            panel?.close()
        }
        panel.onKeyEvent = { [weak model] event in
            guard let model else { return false }
            return model.handle(event: event)
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
