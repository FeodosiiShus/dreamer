@preconcurrency import ObjectiveC
import AppKit
import SwiftUI

final class BranchesPopupRowAnchors {
    private var views: [BranchesPopupItemID: NSView] = [:]

    func register(_ view: NSView, for id: BranchesPopupItemID) {
        views[id] = view
    }

    func view(for id: BranchesPopupItemID) -> NSView? {
        guard let view = views[id], view.window != nil else { return nil }
        return view
    }
}

@Observable
final class ToolbarPopupAnchor {
    @ObservationIgnored weak var view: NSView?
}

struct ToolbarPopupAnchorView: NSViewRepresentable {
    let anchor: ToolbarPopupAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        anchor.view = nsView
    }
}

enum BranchesPopupMenuTracking {
    static let begin = Notification.Name("NSMenuDidBeginTrackingNotification")
    static let end = Notification.Name("NSMenuDidEndTrackingNotification")
}

final class BranchesPopupPanel: NSPanel, NSWindowDelegate {
    var onClose: (() -> Void)?

    private var menuTracking = false
    private var menuObservers: [NSObjectProtocol] = []
    private let notificationCenter: NotificationCenter

    init(size: NSSize, notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
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
        observeMenuTracking()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func resize(to size: CGSize) {
        guard size.width > 1, size.height > 1, size != frame.size else { return }
        setFrame(
            NSRect(
                x: frame.minX,
                y: frame.maxY - size.height,
                width: size.width,
                height: size.height
            ),
            display: true
        )
    }

    func place(below anchor: NSRect) {
        var origin = NSPoint(x: anchor.minX, y: anchor.minY - frame.height - Islands.islandGap)
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - frame.width - 8)
            if origin.y < visible.minY + 8 {
                origin.y = anchor.maxY + Islands.islandGap
            }
        }
        setFrameOrigin(origin)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard isVisible, !menuTracking else { return }
        close()
    }

    func windowWillClose(_ notification: Notification) {
        parent?.removeChildWindow(self)
        onClose?()
        onClose = nil
    }

    private func observeMenuTracking() {
        let center = notificationCenter
        menuObservers.append(center.addObserver(
            forName: BranchesPopupMenuTracking.begin,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.menuTracking = true
            }
        })
        menuObservers.append(center.addObserver(
            forName: BranchesPopupMenuTracking.end,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.menuTrackingEnded()
            }
        })
    }

    private func menuTrackingEnded() {
        menuTracking = false
        Task { self.closeWhenBackgrounded() }
    }

    private func closeWhenBackgrounded() {
        if isVisible && !isKeyWindow {
            close()
        }
    }

    isolated deinit {
        for observer in menuObservers {
            notificationCenter.removeObserver(observer)
        }
    }
}

@MainActor
final class BranchesPopupPanelHost {
    static let shared = BranchesPopupPanelHost()

    private var panels: [ObjectIdentifier: BranchesPopupPanel] = [:]

    func show(
        sourceControlManager: SourceControlManager,
        workspace: WorkspaceDocument,
        anchoredTo anchorView: NSView
    ) {
        guard let window = anchorView.window else { return }
        dismiss(in: window)

        let panel = BranchesPopupPanel(size: NSSize(width: 380, height: 260))
        let content = GitBranchesPopupView(
            sourceControlManager: sourceControlManager,
            workspace: workspace,
            dismiss: { [weak panel] in
                panel?.close()
            },
            onSizeChange: { [weak panel] size in
                panel?.resize(to: size)
            }
        )
        let hostingView = NSHostingView(rootView: content)
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(origin: .zero, size: panel.frame.size)
        panel.contentView = hostingView
        panel.onClose = { [weak self, weak panel] in
            if let panel {
                self?.panels.removeValue(forKey: ObjectIdentifier(panel))
            }
        }
        panels[ObjectIdentifier(panel)] = panel

        window.addChildWindow(panel, ordered: .above)
        let anchorRect = window.convertToScreen(anchorView.convert(anchorView.bounds, to: nil))
        panel.place(below: anchorRect)
        panel.makeKeyAndOrderFront(nil)
    }

    func dismiss(in window: NSWindow) {
        for panel in panels.values where panel.parent === window {
            panel.close()
        }
    }
}

struct BranchesPopupSizeReporter: ViewModifier {
    let onSizeChange: ((CGSize) -> Void)?

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { onSizeChange?(proxy.size) }
                    .onChange(of: proxy.size) { _, size in onSizeChange?(size) }
            }
        )
    }
}

class BranchesPopupNonInteractiveView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

struct BranchesPopupAnchorView: NSViewRepresentable {
    let id: BranchesPopupItemID
    let anchors: BranchesPopupRowAnchors

    func makeNSView(context: Context) -> NSView {
        let view = BranchesPopupNonInteractiveView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        anchors.register(view, for: id)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        anchors.register(nsView, for: id)
    }
}

final class BranchesPopupKeyMonitor {
    private var monitor: Any?
    private weak var window: NSWindow?
    private let handler: (NSEvent) -> Bool
    private var menuTrackingCount = 0
    private var menuObservers: [NSObjectProtocol] = []
    private let notificationCenter: NotificationCenter

    init(handler: @escaping (NSEvent) -> Bool, notificationCenter: NotificationCenter = .default) {
        self.handler = handler
        self.notificationCenter = notificationCenter
    }

    func install(on window: NSWindow) {
        remove()
        self.window = window
        observeMenuTracking()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  self.menuTrackingCount == 0,
                  event.window === self.window,
                  self.handler(event) else {
                return event
            }
            return nil
        }
    }

    func remove() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    isolated deinit {
        remove()
        for observer in menuObservers {
            notificationCenter.removeObserver(observer)
        }
    }

    private func observeMenuTracking() {
        guard menuObservers.isEmpty else { return }
        let center = notificationCenter
        menuObservers.append(center.addObserver(
            forName: BranchesPopupMenuTracking.begin,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.menuTrackingCount += 1
            }
        })
        menuObservers.append(center.addObserver(
            forName: BranchesPopupMenuTracking.end,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.menuTrackingEnded()
            }
        })
    }

    private func menuTrackingEnded() {
        menuTrackingCount = max(0, menuTrackingCount - 1)
    }
}

struct BranchesPopupMenuPresentation {
    var popUp: (NSMenu, NSPoint, NSView) -> Void
    var fallbackView: () -> NSView?

    static let live = BranchesPopupMenuPresentation(
        popUp: { menu, point, view in
            _ = menu.popUp(positioning: nil, at: point, in: view)
        },
        fallbackView: {
            NSApp.keyWindow?.contentView ?? NSApp.mainWindow?.contentView
        }
    )
}

enum BranchesPopupMenuPresenter {
    static func present(
        row: BranchesPopupRow,
        anchors: BranchesPopupRowAnchors,
        model: BranchesPopupViewModel,
        presentation: BranchesPopupMenuPresentation = .live
    ) {
        guard row.kind == .ref, let ref = row.ref else {
            model.toggleExpansion(row.id)
            return
        }
        let menu = BranchesPopupMenuFactory.menu(for: ref, model: model)
        model.isBlockingInput = true
        defer { model.isBlockingInput = false }
        if let anchor = anchors.view(for: row.id) {
            presentation.popUp(menu, NSPoint(x: anchor.bounds.width + 2, y: 0), anchor)
        } else if let content = presentation.fallbackView() {
            presentation.popUp(
                menu,
                NSPoint(x: max(content.bounds.width - 380, 0), y: max(content.bounds.height - 40, 0)),
                content
            )
        }
    }
}

enum BranchesPopupKeyboard {
    static func handle(
        _ event: NSEvent,
        model: BranchesPopupViewModel,
        anchors: BranchesPopupRowAnchors,
        presentation: BranchesPopupMenuPresentation = .live,
        dismiss: () -> Void
    ) -> Bool {
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return false }
        guard !model.isBlockingInput else { return false }
        switch event.keyCode {
        case 53:
            dismiss()
            return true
        case 126:
            model.moveSelection(-1)
            return true
        case 125:
            model.moveSelection(1)
            return true
        case 124:
            if let row = model.selectedRow, row.kind == .ref {
                BranchesPopupMenuPresenter.present(
                    row: row,
                    anchors: anchors,
                    model: model,
                    presentation: presentation
                )
            } else {
                model.toggleSelectionExpansion()
            }
            return true
        case 123:
            model.toggleSelectionExpansion()
            return true
        case 36, 76:
            model.activateSelection()
            return true
        case 49:
            guard !(event.window?.firstResponder is NSTextView) else { return false }
            model.toggleSelectedFavorite()
            return true
        default:
            return false
        }
    }
}

struct BranchesPopupWindowReader: NSViewRepresentable {
    let onWindowChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> BranchesPopupWindowReaderView {
        let view = BranchesPopupWindowReaderView(frame: .zero)
        view.onWindowChange = onWindowChange
        return view
    }

    func updateNSView(_ nsView: BranchesPopupWindowReaderView, context: Context) {
        nsView.onWindowChange = onWindowChange
        nsView.report()
    }
}

final class BranchesPopupWindowReaderView: BranchesPopupNonInteractiveView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        report()
    }

    func report() {
        let window = window
        Task { [weak self] in
            self?.onWindowChange?(window)
        }
    }
}
