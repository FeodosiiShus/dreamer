import AppKit
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct QuickDocumentationPanelPlacementTests {
    @Test
    func aParentOnNoScreenIsClampedToTheMainScreen() {
        let parent = ScreenlessWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        parent.isReleasedWhenClosed = false
        parent.setFrame(NSRect(x: -6000, y: -6000, width: 1200, height: 800), display: false)
        let size = NSSize(width: 420, height: 240)
        let panel = QuickDocumentationPanel(size: size)
        defer {
            panel.close()
            parent.close()
        }
        #expect(parent.screen == nil)

        panel.place(in: parent, beside: nil)

        #expect(panel.frame.size == size)
        if let visible = NSScreen.main?.visibleFrame {
            #expect(visible.insetBy(dx: 7, dy: 7).contains(panel.frame))
        } else {
            #expect(panel.frame.minX < parent.frame.maxX)
        }
    }
}
