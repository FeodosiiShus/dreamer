import AppKit
import CodeEditSourceEditor
import CodeEditTextView

final class EditorInputInterceptor {
    typealias MenuKeyEquivalent = @MainActor (NSEvent) -> Bool

    private struct PendingClick {
        let previousSelections: [NSRange]
        let origin: NSPoint
        var dragged: Bool
    }

    private static let packageOwnedKeys: Set<String> = ["/", "[", "]"]
    private static let dragThreshold: CGFloat = 4
    private static let keyModifiers: NSEvent.ModifierFlags = [.shift, .control, .option, .command]

    private weak var controller: TextViewController?
    private let performMenuKeyEquivalent: MenuKeyEquivalent
    private var earlyKeyMonitor: Any?
    private var lateKeyMonitor: Any?
    private var mouseMonitor: Any?
    private var pendingClick: PendingClick?

    init(performMenuKeyEquivalent: @escaping MenuKeyEquivalent = EditorInputInterceptor.routeToMainMenu) {
        self.performMenuKeyEquivalent = performMenuKeyEquivalent
    }

    static func routeToMainMenu(_ event: NSEvent) -> Bool {
        guard let menu = NSApp.mainMenu else { return false }
        return menu.performKeyEquivalent(with: event)
    }

    isolated deinit {
        removeMonitors()
    }

    var installedMonitorCount: Int {
        [earlyKeyMonitor, lateKeyMonitor, mouseMonitor].compactMap { $0 }.count
    }

    func attach(controller: TextViewController) {
        self.controller = controller
    }

    func installEarlyKeyMonitor() {
        guard earlyKeyMonitor == nil else { return }
        earlyKeyMonitor = makeKeyMonitor()
    }

    func installLateKeyMonitor() {
        guard lateKeyMonitor == nil else { return }
        lateKeyMonitor = makeKeyMonitor()
    }

    func installMouseMonitor() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            MainActor.assumeIsolated { self?.handleMouse(event) }
            return event
        }
    }

    func detach() {
        removeMonitors()
        pendingClick = nil
        controller = nil
    }

    private func makeKeyMonitor() -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let consumed = MainActor.assumeIsolated { self.handleKey(event) }
            return consumed ? nil : event
        }
    }

    private func removeMonitors() {
        for monitor in [earlyKeyMonitor, lateKeyMonitor, mouseMonitor].compactMap({ $0 }) {
            NSEvent.removeMonitor(monitor)
        }
        earlyKeyMonitor = nil
        lateKeyMonitor = nil
        mouseMonitor = nil
    }

    func handleKey(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, focusedTextView(for: event) != nil else { return false }
        guard event.modifierFlags.intersection(Self.keyModifiers) == .command,
              let key = event.charactersIgnoringModifiers,
              Self.packageOwnedKeys.contains(key) else { return false }
        _ = performMenuKeyEquivalent(event)
        return true
    }

    func handleMouse(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            beginClick(event)
        case .leftMouseDragged:
            noteDrag(event)
        case .leftMouseUp:
            finishClick()
        default:
            break
        }
    }

    private func focusedTextView(for event: NSEvent) -> TextView? {
        guard let textView = controller?.textView,
              let window = textView.window,
              event.window === window,
              window.firstResponder === textView,
              !textView.hasMarkedText() else { return nil }
        return textView
    }

    private func clickedTextView(for event: NSEvent) -> TextView? {
        guard let textView = controller?.textView,
              let window = textView.window,
              event.window === window,
              let hit = window.contentView?.superview?.hitTest(event.locationInWindow),
              hit.isDescendant(of: textView) else { return nil }
        return textView
    }

    private func beginClick(_ event: NSEvent) {
        pendingClick = nil
        guard let textView = clickedTextView(for: event),
              textView.isEditable,
              event.clickCount == 1,
              event.modifierFlags.intersection(Self.keyModifiers) == .option else { return }
        pendingClick = PendingClick(
            previousSelections: textView.selectionManager.textSelections.map(\.range),
            origin: event.locationInWindow,
            dragged: false
        )
    }

    private func noteDrag(_ event: NSEvent) {
        guard let click = pendingClick else { return }
        let deltaX = event.locationInWindow.x - click.origin.x
        let deltaY = event.locationInWindow.y - click.origin.y
        if hypot(deltaX, deltaY) > Self.dragThreshold {
            pendingClick?.dragged = true
        }
    }

    private func finishClick() {
        guard let click = pendingClick else { return }
        pendingClick = nil
        guard !click.dragged, let textView = controller?.textView else { return }
        let current = textView.selectionManager.textSelections.map(\.range)
        guard current.count == 1, let clicked = current.first, clicked.length == 0 else { return }
        textView.selectionManager.setSelectedRanges(
            EditorCaretToggle.toggled(click.previousSelections, at: clicked.location)
        )
    }
}
