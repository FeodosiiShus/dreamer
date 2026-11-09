import AppKit
import SwiftUI

final class SearchEverywherePanel: NSPanel, NSWindowDelegate {
    var onKeyEvent: ((NSEvent) -> Bool)?
    var onClose: (() -> Void)?

    private let panelSize: NSSize

    init(size: NSSize = NSSize(width: 670, height: 520)) {
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

    func place(in parent: NSWindow) {
        let size = panelSize
        let parentFrame = parent.frame
        var origin = NSPoint(
            x: parentFrame.midX - size.width / 2,
            y: parentFrame.maxY - size.height - 92
        )

        if let screen = parent.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        }

        setFrame(NSRect(origin: origin, size: size), display: false)
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    func windowWillClose(_ notification: Notification) {
        parent?.removeChildWindow(self)
        onClose?()
        onClose = nil
    }
}

@MainActor
final class SearchEverywherePanelHost {
    static let shared = SearchEverywherePanelHost()

    private struct Key: Hashable {
        let controller: ObjectIdentifier
        let mode: SearchEverywhereMode
    }

    private struct Entry {
        weak var panel: SearchEverywherePanel?
        let model: SearchEverywhereViewModel
    }

    private var entries: [Key: Entry] = [:]
    private let defaults: UserDefaults
    private let recentFiles: SearchEverywhereRecentFilesStore

    init(defaults: UserDefaults = .standard, recentFiles: SearchEverywhereRecentFilesStore = .shared) {
        self.defaults = defaults
        self.recentFiles = recentFiles
    }

    func toggle(in controller: DreamderWindowController) {
        let key = Key(controller: ObjectIdentifier(controller), mode: .everywhere)
        if let entry = entries[key], let panel = entry.panel {
            if panel.isVisible {
                panel.close()
            } else {
                entry.model.selectTab(.all)
                present(panel, in: controller.window)
            }
            return
        }
        open(tab: .all, in: controller)
    }

    func open(tab: SearchEverywhereTab, in controller: DreamderWindowController) {
        open(tab: tab, mode: .everywhere, in: controller)
    }

    func openRecentFiles(in controller: DreamderWindowController) {
        open(tab: .files, mode: .recentFiles, in: controller)
    }

    private func open(
        tab: SearchEverywhereTab,
        mode: SearchEverywhereMode,
        in controller: DreamderWindowController
    ) {
        entries = entries.filter { $0.value.panel != nil }
        guard let window = controller.window, let workspace = controller.workspace else { return }
        let key = Key(controller: ObjectIdentifier(controller), mode: mode)

        if let entry = entries[key], let panel = entry.panel {
            entry.model.selectTab(tab)
            present(panel, in: window)
            return
        }

        let model = SearchEverywhereViewModel(
            workspace: workspace,
            mode: mode,
            defaults: defaults,
            recentFiles: recentFiles
        )
        let size = NSSize(width: model.panelWidth, height: model.panelHeight)
        let panel = SearchEverywherePanel(size: size)
        let hostingView = NSHostingView(rootView: SearchEverywhereView(model: model))
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hostingView

        model.dismiss = { [weak panel] in
            panel?.close()
        }
        model.start(on: tab)

        panel.onKeyEvent = { [weak model] event in
            model?.handle(event: event) ?? false
        }
        panel.onClose = { [weak self] in
            self?.entries.removeValue(forKey: key)
        }

        entries[key] = Entry(panel: panel, model: model)

        window.addChildWindow(panel, ordered: .above)
        panel.place(in: window)
        panel.makeKeyAndOrderFront(nil)
    }

    private func present(_ panel: SearchEverywherePanel, in window: NSWindow?) {
        guard let window else { return }
        if panel.parent !== window {
            panel.parent?.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
        }
        panel.place(in: window)
        panel.makeKeyAndOrderFront(nil)
    }
}
