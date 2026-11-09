import AppKit
import SwiftUI

final class SignatureHelpPanel: NSPanel {
    init(size: NSSize) {
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
        animationBehavior = .none
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class SignatureHelpPopup {
    typealias VisibleFrameProvider = @MainActor (NSRect) -> NSRect?
    typealias KeyHandler = @MainActor (NSEvent) -> Bool

    private let visibleFrameProvider: VisibleFrameProvider
    private var panel: SignatureHelpPanel?
    private var model: SignatureHelpViewModel?
    private var monitor: Any?
    private(set) var isShown = false
    var keyHandler: KeyHandler?

    init(visibleFrameProvider: @escaping VisibleFrameProvider = SignatureHelpPopup.screenVisibleFrame) {
        self.visibleFrameProvider = visibleFrameProvider
    }

    isolated deinit {
        removeMonitor()
        panel?.close()
    }

    static func screenVisibleFrame(containing anchor: NSRect) -> NSRect? {
        NSScreen.screens.first { $0.frame.intersects(anchor) }?.visibleFrame
    }

    var presentation: SignatureHelpPresentation? {
        isShown ? model?.presentation : nil
    }

    var panelFrame: NSRect? {
        panel?.frame
    }

    func show(_ presentation: SignatureHelpPresentation, anchor: NSRect, in window: NSWindow) {
        let size = SignatureHelpMetrics.size(for: presentation.rows)
        let model = self.model ?? SignatureHelpViewModel(presentation: presentation)
        model.apply(presentation)
        self.model = model
        let panel = self.panel ?? makePanel(model: model, size: size)
        self.panel = panel
        panel.setFrame(
            SignatureHelpPlacement.frame(size: size, anchor: anchor, visibleFrame: visibleFrameProvider(anchor)),
            display: false
        )
        if panel.parent !== window {
            panel.parent?.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
        installMonitor()
        isShown = true
    }

    func cycle(by step: Int) {
        guard isShown, let model else { return }
        model.apply(model.presentation.cycled(by: step))
    }

    func hide() {
        isShown = false
        removeMonitor()
        guard let panel else { return }
        panel.orderOut(nil)
        panel.parent?.removeChildWindow(panel)
    }

    func close() {
        hide()
        panel?.close()
        panel = nil
        model = nil
    }

    private func makePanel(model: SignatureHelpViewModel, size: NSSize) -> SignatureHelpPanel {
        let panel = SignatureHelpPanel(size: size)
        let hostingView = NSHostingView(rootView: SignatureHelpView(model: model))
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hostingView
        return panel
    }

    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.keyHandler?(event) ?? false }
            return consumed ? nil : event
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}
