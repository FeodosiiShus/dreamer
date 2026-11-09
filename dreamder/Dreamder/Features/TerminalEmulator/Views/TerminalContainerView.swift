import AppKit

final class TerminalContainerView: NSView {
    typealias Scheduler = (@escaping @MainActor () -> Void) -> Void

    static let nextRunLoopTurn: Scheduler = { work in
        DispatchQueue.main.async {
            MainActor.assumeIsolated { work() }
        }
    }

    let terminal: CELocalShellTerminalView
    var schedule: Scheduler
    private var isLayoutScheduled = false

    init(terminal: CELocalShellTerminalView, schedule: @escaping Scheduler = TerminalContainerView.nextRunLoopTurn) {
        self.terminal = terminal
        self.schedule = schedule
        super.init(frame: .zero)
        terminal.autoresizingMask = []
        addSubview(terminal)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        scheduleTerminalLayout()
    }

    override var frame: NSRect {
        get {
            super.frame
        }
        set {
            super.frame = newValue
            scheduleTerminalLayout()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleTerminalLayout()
    }

    override func isAccessibilityElement() -> Bool {
        false
    }

    func scheduleTerminalLayout() {
        guard !isLayoutScheduled else { return }
        isLayoutScheduled = true
        schedule { [weak self] in
            self?.applyTerminalLayout()
        }
    }

    func applyTerminalLayout() {
        isLayoutScheduled = false
        let size = bounds.size
        guard window != nil, terminal.superview === self, size.width > 0, size.height > 0 else { return }
        guard terminal.frame.size != size else { return }
        terminal.frame = NSRect(origin: .zero, size: size)
    }
}
