import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
private final class KeyProbeView: NSView {
    var keyDowns = 0

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        keyDowns += 1
    }
}

@MainActor
private final class PanelCallLog {
    var keyCodes: [UInt16] = []
    var closes = 0
}

@MainActor
@Suite(.serialized, .isolatedDefaults, .uiGate)
struct SearchEverywherePanelTests {
    @MainActor
    private struct Rig {
        let workspace: WorkspaceDocument
        let controller: DreamderWindowController
        let window: NSWindow
        let host: SearchEverywherePanelHost

        var panels: [SearchEverywherePanel] {
            (window.childWindows ?? []).compactMap { $0 as? SearchEverywherePanel }
        }

        func panel(width: CGFloat) -> SearchEverywherePanel? {
            panels.first { $0.frame.width == width }
        }

        func close() {
            for child in window.childWindows ?? [] {
                child.close()
            }
            window.close()
            workspace.tearDownFileScope()
        }
    }

    private func makeRig(_ dir: URL) throws -> Rig {
        let defaults = try IsolatedDefaults.require()
        let workspace = try SearchEverywhereFixtures.makeWorkspace(dir)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let controller = DreamderWindowController(window: window, workspace: nil)
        controller.workspace = workspace
        window.windowController = controller
        let host = SearchEverywherePanelHost(
            defaults: defaults,
            recentFiles: SearchEverywhereRecentFilesStore(defaults: defaults)
        )
        return Rig(workspace: workspace, controller: controller, window: window, host: host)
    }

    private func hide(_ panel: SearchEverywherePanel) {
        let delegate = panel.delegate
        panel.delegate = nil
        panel.orderOut(nil)
        panel.delegate = delegate
    }

    @Test
    func togglingOpensClosesAndReopensAFreshPanel() throws {
        try withTempDir { dir in
            let rig = try makeRig(dir)
            defer { rig.close() }

            rig.host.toggle(in: rig.controller)
            let first = try #require(rig.panels.first)
            #expect(rig.panels.count == 1)
            #expect(first.isVisible)
            #expect(first.frame.size == NSSize(width: 670, height: 520))

            rig.host.toggle(in: rig.controller)
            #expect(!first.isVisible)
            #expect(rig.panels.isEmpty)

            rig.host.toggle(in: rig.controller)
            let second = try #require(rig.panels.first)
            #expect(second !== first)
            #expect(second.isVisible)
        }
    }

    @Test
    func aHiddenPanelIsPresentedAgainInTheSameWindow() throws {
        try withTempDir { dir in
            let rig = try makeRig(dir)
            defer { rig.close() }
            rig.host.toggle(in: rig.controller)
            let panel = try #require(rig.panels.first)
            hide(panel)
            rig.window.removeChildWindow(panel)
            #expect(!panel.isVisible)
            #expect(panel.parent == nil)

            rig.host.toggle(in: rig.controller)

            #expect(panel.isVisible)
            #expect(panel.parent === rig.window)
            #expect(rig.panels.count == 1)
        }
    }

    @Test
    func aHiddenPanelStillAttachedIsPresentedWithoutReparenting() throws {
        try withTempDir { dir in
            let rig = try makeRig(dir)
            defer { rig.close() }
            rig.host.toggle(in: rig.controller)
            let panel = try #require(rig.panels.first)
            hide(panel)

            rig.host.toggle(in: rig.controller)

            #expect(panel.isVisible)
            #expect(panel.parent === rig.window)
            #expect(rig.panels.count == 1)
        }
    }

    @Test
    func openingATabReusesTheExistingPanel() throws {
        try withTempDir { dir in
            let rig = try makeRig(dir)
            defer { rig.close() }

            rig.host.open(tab: .classes, in: rig.controller)
            let first = try #require(rig.panels.first)
            rig.host.open(tab: .symbols, in: rig.controller)

            #expect(rig.panels.count == 1)
            #expect(rig.panels.first === first)
            #expect(first.isVisible)
        }
    }

    @Test
    func recentFilesGetTheirOwnSmallerPanel() throws {
        try withTempDir { dir in
            let rig = try makeRig(dir)
            defer { rig.close() }

            rig.host.toggle(in: rig.controller)
            rig.host.openRecentFiles(in: rig.controller)
            let recent = try #require(rig.panel(width: 560))

            #expect(rig.panels.count == 2)
            #expect(recent.frame.size == NSSize(width: 560, height: 400))
            #expect(rig.panel(width: 670) !== recent)

            rig.host.openRecentFiles(in: rig.controller)
            #expect(rig.panels.count == 2)
            #expect(rig.panel(width: 560) === recent)
        }
    }

    @Test
    func theRecentFilesActionOpensTheRecentFilesPanelInTheWindow() throws {
        try withTempDir { dir in
            let rig = try makeRig(dir)
            let workspaceKey = "dreamder.recentFiles.\(rig.workspace.fileURL?.standardizedFileURL.path ?? "untitled")"
            defer {
                rig.close()
                UserDefaults.standard.removeObject(forKey: workspaceKey)
            }

            rig.controller.openRecentFiles(nil)

            let recent = try #require(rig.panel(width: 560))
            #expect(recent.isVisible)
            #expect(recent.frame.size == NSSize(width: 560, height: 400))
        }
    }

    @Test
    func theKeyHandlerFeedsTheModelAndEscapeClosesThePanel() throws {
        try withTempDir { dir in
            let rig = try makeRig(dir)
            defer { rig.close() }
            rig.host.toggle(in: rig.controller)
            let panel = try #require(rig.panels.first)
            let handler = try #require(panel.onKeyEvent)

            #expect(handler(try SearchEverywhereFixtures.keyEvent(0)) == false)
            #expect(panel.isVisible)

            #expect(handler(try SearchEverywhereFixtures.keyEvent(53)))
            #expect(!panel.isVisible)
            #expect(rig.panels.isEmpty)
        }
    }

    @Test
    func sendEventLetsTheHandlerConsumeKeyDownsAndForwardsEverythingElse() throws {
        let panel = SearchEverywherePanel()
        defer { panel.close() }
        let probe = KeyProbeView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
        panel.contentView = probe
        #expect(panel.makeFirstResponder(probe))
        let log = PanelCallLog()
        panel.onKeyEvent = { event in
            log.keyCodes.append(event.keyCode)
            return event.keyCode == 53
        }

        panel.sendEvent(try SearchEverywhereFixtures.keyEvent(53))
        #expect(log.keyCodes == [53])
        #expect(probe.keyDowns == 0)

        panel.sendEvent(try SearchEverywhereFixtures.keyEvent(0))
        #expect(log.keyCodes == [53, 0])
        #expect(probe.keyDowns == 1)

        let flagsChanged = try #require(NSEvent.keyEvent(
            with: .flagsChanged,
            location: .zero,
            modifierFlags: .shift,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 56
        ))
        panel.sendEvent(flagsChanged)
        #expect(log.keyCodes == [53, 0])

        panel.onKeyEvent = nil
        panel.sendEvent(try SearchEverywhereFixtures.keyEvent(53))
        #expect(probe.keyDowns == 2)
    }

    @Test
    func resigningKeyClosesThePanelAndNotifiesOnce() {
        let panel = SearchEverywherePanel()
        let log = PanelCallLog()
        panel.onClose = { log.closes += 1 }
        panel.orderFront(nil)
        #expect(panel.isVisible)
        #expect(panel.canBecomeKey)
        #expect(!panel.canBecomeMain)

        panel.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification))

        #expect(log.closes == 1)
        #expect(!panel.isVisible)
        #expect(panel.onClose == nil)
    }
}
