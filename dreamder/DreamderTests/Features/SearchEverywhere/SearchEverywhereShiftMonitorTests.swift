import AppKit
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct SearchEverywhereShiftMonitorTests {
    private final class Counter {
        var opens = 0
    }

    private final class WindowRecorder {
        var windows: [NSWindow]?
    }

    private struct Session {
        let monitor: SearchEverywhereShiftMonitor
        let keymap: Keymap
        let counter: Counter
        let defaults: UserDefaults
        let suiteName: String

        func tearDown() {
            removeIsolatedDefaults(defaults, suiteName: suiteName)
        }
    }

    private func makeSession() throws -> Session {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        let keymap = Keymap(defaults: defaults)
        let counter = Counter()
        let monitor = SearchEverywhereShiftMonitor(keymap: keymap, open: { _ in counter.opens += 1 })
        return Session(monitor: monitor, keymap: keymap, counter: counter, defaults: defaults, suiteName: suiteName)
    }

    private func flags(_ flags: NSEvent.ModifierFlags, at time: TimeInterval) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .flagsChanged,
            location: .zero,
            modifierFlags: flags,
            timestamp: time,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 56
        ))
    }

    private func keyDown(at time: TimeInterval) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: time,
            windowNumber: 0,
            context: nil,
            characters: "a",
            charactersIgnoringModifiers: "a",
            isARepeat: false,
            keyCode: 0
        ))
    }

    private func tapShiftTwice(_ session: Session, gap: TimeInterval = 0.1) throws {
        session.monitor.handle(try flags(.shift, at: 1))
        session.monitor.handle(try flags([], at: 1.05))
        session.monitor.handle(try flags(.shift, at: 1.05 + gap))
    }

    @Test
    func doubleShiftOpensSearchEverywhereWhileItIsBoundToDoubleShift() throws {
        let session = try makeSession()
        defer { session.tearDown() }

        try tapShiftTwice(session)

        #expect(session.counter.opens == 1)
    }

    @Test
    func aSlowSecondTapDoesNotOpen() throws {
        let session = try makeSession()
        defer { session.tearDown() }

        try tapShiftTwice(session, gap: 0.9)

        #expect(session.counter.opens == 0)
    }

    @Test
    func typingOrOtherModifiersBetweenTapsResetTheGesture() throws {
        let session = try makeSession()
        defer { session.tearDown() }

        session.monitor.handle(try flags(.shift, at: 1))
        session.monitor.handle(try flags([], at: 1.05))
        session.monitor.handle(try keyDown(at: 1.06))
        session.monitor.handle(try flags(.shift, at: 1.1))
        session.monitor.handle(try flags([.shift, .command], at: 1.12))
        session.monitor.handle(try flags([], at: 1.13))
        session.monitor.handle(try flags(.shift, at: 1.15))

        #expect(session.counter.opens == 0)
    }

    @Test
    func reboundSearchEverywhereDisablesDoubleShift() throws {
        let session = try makeSession()
        defer { session.tearDown() }
        session.keymap.replaceShortcuts(of: .searchEverywhere, with: .stroke("e", [.option, .command]))

        try tapShiftTwice(session)

        #expect(session.counter.opens == 0)
    }

    @Test
    func clearedSearchEverywhereDisablesDoubleShiftAndResetRestoresIt() throws {
        let session = try makeSession()
        defer { session.tearDown() }
        session.keymap.removeAllShortcuts(from: .searchEverywhere)

        try tapShiftTwice(session)
        #expect(session.counter.opens == 0)

        session.keymap.reset(.searchEverywhere)
        try tapShiftTwice(session)
        #expect(session.counter.opens == 1)
    }

    private func makeController(workspace: WorkspaceDocument? = nil) -> (DreamderWindowController, NSWindow) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let controller = DreamderWindowController(window: window, workspace: nil)
        controller.workspace = workspace
        window.windowController = controller
        return (controller, window)
    }

    private func makePlainWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        return window
    }

    private func closeSearchPanels(in windows: [NSWindow]) {
        for window in windows {
            for child in window.childWindows ?? [] where child is SearchEverywherePanel {
                child.close()
            }
        }
    }

    @Test
    func theActiveControllerIsTheKeyWindowsThenItsParentsThenTheMainWindowsThenAnyWindows() {
        let (keyController, keyWindow) = makeController()
        let (mainController, mainWindow) = makeController()
        let (otherController, otherWindow) = makeController()
        let (parentController, parentWindow) = makeController()
        let orphan = makePlainWindow()
        let plain = makePlainWindow()
        let child = makePlainWindow()
        parentWindow.addChildWindow(child, ordered: .above)
        defer { parentWindow.removeChildWindow(child) }
        typealias Monitor = SearchEverywhereShiftMonitor

        #expect(Monitor.activeController(keyWindow: keyWindow, mainWindow: mainWindow, windows: [otherWindow]) === keyController)
        #expect(Monitor.activeController(keyWindow: child, mainWindow: mainWindow, windows: [otherWindow]) === parentController)
        #expect(Monitor.activeController(keyWindow: orphan, mainWindow: mainWindow, windows: [otherWindow]) === mainController)
        #expect(Monitor.activeController(keyWindow: nil, mainWindow: nil, windows: [plain, otherWindow]) === otherController)
        #expect(Monitor.activeController(keyWindow: nil, mainWindow: plain, windows: [plain]) == nil)
        #expect(Monitor.activeController(keyWindow: nil, mainWindow: nil, windows: []) == nil)
    }

    @Test
    func openingTheControllerShowsSearchEverywhereInItsWindowOnly() throws {
        try withTempDir { dir in
            let workspace = try SearchEverywhereFixtures.makeWorkspace(dir)
            let (controller, window) = makeController(workspace: workspace)
            let untouched = makePlainWindow()
            let workspaceKey = "dreamder.recentFiles.\(workspace.fileURL?.standardizedFileURL.path ?? "untitled")"
            defer {
                closeSearchPanels(in: [window])
                window.close()
                workspace.tearDownFileScope()
                UserDefaults.standard.removeObject(forKey: workspaceKey)
            }

            SearchEverywhereShiftMonitor.openController(keyWindow: untouched, mainWindow: nil, windows: [])
            #expect((window.childWindows ?? []).isEmpty)

            SearchEverywhereShiftMonitor.openController(keyWindow: window, mainWindow: nil, windows: [])

            let panel = try #require((window.childWindows ?? []).compactMap { $0 as? SearchEverywherePanel }.first)
            #expect(panel.isVisible)
            #expect(controller.window === window)
        }
    }

    @Test
    func theDefaultWindowSourceReadsTheApplicationsWindows() throws {
        let session = try makeSession()
        defer { session.tearDown() }
        let recorder = WindowRecorder()
        let monitor = SearchEverywhereShiftMonitor(keymap: session.keymap, open: { recorder.windows = $0.all })

        monitor.handle(try flags(.shift, at: 2))
        monitor.handle(try flags([], at: 2.05))
        monitor.handle(try flags(.shift, at: 2.15))

        #expect(recorder.windows == NSApp.windows)
    }

    @Test
    func theDefaultOpenActionOpensSearchEverywhereInTheControllerOfTheGivenWindows() throws {
        let session = try makeSession()
        defer { session.tearDown() }
        try withTempDir { dir in
            let workspace = try SearchEverywhereFixtures.makeWorkspace(dir)
            let (controller, window) = makeController(workspace: workspace)
            let workspaceKey = "dreamder.recentFiles.\(workspace.fileURL?.standardizedFileURL.path ?? "untitled")"
            defer {
                closeSearchPanels(in: [window])
                window.close()
                workspace.tearDownFileScope()
                UserDefaults.standard.removeObject(forKey: workspaceKey)
            }
            let windows = SearchEverywhereShiftMonitor.Windows(keyWindow: window, mainWindow: nil, all: [window])
            let monitor = SearchEverywhereShiftMonitor(keymap: session.keymap, windows: { windows })

            monitor.handle(try flags(.shift, at: 2))
            monitor.handle(try flags([], at: 2.05))
            monitor.handle(try flags(.shift, at: 2.15))

            let panel = try #require((window.childWindows ?? []).compactMap { $0 as? SearchEverywherePanel }.first)
            #expect(panel.isVisible)
            #expect(controller.window === window)
        }
    }
}
