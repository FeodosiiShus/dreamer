import AppKit

@MainActor
final class SearchEverywhereShiftMonitor {
    struct Windows {
        let keyWindow: NSWindow?
        let mainWindow: NSWindow?
        let all: [NSWindow]

        static func application() -> Windows {
            Windows(keyWindow: NSApp.keyWindow, mainWindow: NSApp.mainWindow, all: NSApp.windows)
        }
    }

    static let shared = SearchEverywhereShiftMonitor()

    private var monitor: Any?
    private var shiftDown = false
    private var pressedAt: TimeInterval?
    private var releasedAt: TimeInterval?
    private let interval: TimeInterval = 0.5
    private let keymap: Keymap
    private let windows: @MainActor () -> Windows
    private let open: @MainActor (Windows) -> Void

    init(
        keymap: Keymap = .shared,
        windows: @escaping @MainActor () -> Windows = SearchEverywhereShiftMonitor.Windows.application,
        open: @escaping @MainActor (Windows) -> Void = SearchEverywhereShiftMonitor.openActiveController
    ) {
        self.keymap = keymap
        self.windows = windows
        self.open = open
    }

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handle(event)
            }
            return event
        }
    }

    func handle(_ event: NSEvent) {
        if event.type == .keyDown {
            reset()
            return
        }

        guard keymap.shortcuts(for: .searchEverywhere).contains(.doubleModifier(.shift)) else {
            reset()
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if flags.contains(.command) || flags.contains(.option) || flags.contains(.control) {
            reset()
            return
        }

        let isDown = flags.contains(.shift)

        if isDown && !shiftDown {
            shiftDown = true
            if let releasedAt, event.timestamp - releasedAt <= interval {
                reset()
                open(windows())
                return
            }
            pressedAt = event.timestamp
        } else if !isDown && shiftDown {
            shiftDown = false
            if pressedAt != nil {
                releasedAt = event.timestamp
            }
            pressedAt = nil
        }
    }

    private func reset() {
        shiftDown = false
        pressedAt = nil
        releasedAt = nil
    }

    static func openActiveController(_ windows: Windows) {
        openController(keyWindow: windows.keyWindow, mainWindow: windows.mainWindow, windows: windows.all)
    }

    static func openController(keyWindow: NSWindow?, mainWindow: NSWindow?, windows: [NSWindow]) {
        guard let controller = activeController(keyWindow: keyWindow, mainWindow: mainWindow, windows: windows) else {
            return
        }
        controller.openSearchEverywhere(nil)
    }

    static func activeController(
        keyWindow: NSWindow?,
        mainWindow: NSWindow?,
        windows: [NSWindow]
    ) -> DreamderWindowController? {
        if let controller = keyWindow?.windowController as? DreamderWindowController {
            return controller
        }
        if let parent = keyWindow?.parent,
           let controller = parent.windowController as? DreamderWindowController {
            return controller
        }
        if let controller = mainWindow?.windowController as? DreamderWindowController {
            return controller
        }
        return windows.compactMap { $0.windowController as? DreamderWindowController }.first
    }
}
