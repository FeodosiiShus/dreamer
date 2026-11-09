import AppKit
import Foundation
import Testing
@testable import Dreamder

extension SearchEverywherePanelTests {
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

    @Test
    func placementClampsToTheMainScreenWhenTheParentIsOnNoScreen() {
        let parent = ScreenlessWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        parent.isReleasedWhenClosed = false
        parent.setFrame(NSRect(x: -6000, y: -6000, width: 1200, height: 800), display: false)
        let panel = SearchEverywherePanel()
        defer {
            panel.close()
            parent.close()
        }
        #expect(parent.screen == nil)

        panel.place(in: parent)

        #expect(panel.frame.size == NSSize(width: 670, height: 520))
        if let visible = NSScreen.main?.visibleFrame {
            #expect(panel.frame.minX == visible.minX + 8)
            #expect(panel.frame.minY == visible.minY + 8)
        } else {
            #expect(panel.frame.midX == parent.frame.midX)
        }
    }

    @Test
    func theKeyHandlerOfAReleasedModelDeclinesEveryKey() async throws {
        try await withTempDir { dir in
            let rig = try makeRig(dir)
            defer { rig.close() }
            rig.host.toggle(in: rig.controller)
            let panel = try #require(rig.panels.first)
            let handler = try #require(panel.onKeyEvent)
            let escape = try SearchEverywhereFixtures.keyEvent(53)
            #expect(handler(escape))

            panel.contentView = nil

            try await eventually { handler(escape) == false }
        }
    }

    @Test
    func aHiddenPanelStaysHiddenWhenTheControllerHasNoWindow() throws {
        try withTempDir { dir in
            let rig = try makeRig(dir)
            defer { rig.close() }
            rig.host.toggle(in: rig.controller)
            let panel = try #require(rig.panels.first)
            hide(panel)
            #expect(!panel.isVisible)
            rig.controller.window = nil

            rig.host.toggle(in: rig.controller)

            #expect(!panel.isVisible)
            rig.controller.window = rig.window
        }
    }
}
