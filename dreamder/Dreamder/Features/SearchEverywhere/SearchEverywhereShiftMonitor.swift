import AppKit

@MainActor
final class SearchEverywhereShiftMonitor {
    static let shared = SearchEverywhereShiftMonitor()

    private var monitor: Any?
    private var shiftDown = false
    private var pressedAt: TimeInterval?
    private var releasedAt: TimeInterval?
    private let interval: TimeInterval = 0.5

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handle(event)
            }
            return event
        }
    }

    private func handle(_ event: NSEvent) {
        if event.type == .keyDown {
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
                openPopover()
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

    private func openPopover() {
        guard let controller = Self.activeController() else { return }
        controller.openSearchEverywhere(nil)
    }

    private static func activeController() -> DreamderWindowController? {
        if let controller = NSApp.keyWindow?.windowController as? DreamderWindowController {
            return controller
        }
        if let parent = NSApp.keyWindow?.parent,
           let controller = parent.windowController as? DreamderWindowController {
            return controller
        }
        if let controller = NSApp.mainWindow?.windowController as? DreamderWindowController {
            return controller
        }
        return NSApp.windows.compactMap { $0.windowController as? DreamderWindowController }.first
    }
}
