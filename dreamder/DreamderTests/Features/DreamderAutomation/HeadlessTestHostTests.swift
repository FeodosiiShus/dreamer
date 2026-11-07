import AppKit
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized)
struct HeadlessTestHostTests {
    @Test
    func theTestHostRunsHeadless() {
        #expect(DreamderHeadless.isEnabled)
        #expect(NSApp.activationPolicy() == .accessory)
    }

    @Test
    func orderedWindowsAreHiddenBelowTheDesktopBeforeTheyAppear() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }

        window.makeKeyAndOrderFront(nil)

        #expect(window.level == DreamderHeadless.hiddenLevel)
        #expect(window.collectionBehavior.contains(.transient))
        #expect(window.isRestorable == false)
        #expect(NSApp.isActive == false)
    }
}
