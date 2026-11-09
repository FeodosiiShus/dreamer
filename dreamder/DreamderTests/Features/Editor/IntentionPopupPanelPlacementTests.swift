import AppKit
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct IntentionPopupPanelPlacementTests {
    private let size = NSSize(width: 100, height: 50)
    private let parent = NSRect(x: 0, y: 0, width: 1000, height: 800)
    private let visible = NSRect(x: 0, y: 0, width: 1000, height: 800)

    @Test
    func withoutAnAnchorThePanelCentersNearTheTopOfTheParent() {
        let origin = IntentionPopupPanel.origin(size: size, parentFrame: parent, anchor: nil, visibleFrame: visible)

        #expect(origin == NSPoint(x: 450, y: 658))
    }

    @Test
    func anAnchorPlacesThePanelBelowItWhenThereIsRoom() {
        let anchor = NSRect(x: 300, y: 400, width: 20, height: 18)

        let origin = IntentionPopupPanel.origin(size: size, parentFrame: parent, anchor: anchor, visibleFrame: visible)

        #expect(origin == NSPoint(x: 300, y: 346))
    }

    @Test
    func anAnchorNearTheBottomFlipsThePanelAboveIt() {
        let anchor = NSRect(x: 300, y: 20, width: 20, height: 18)

        let origin = IntentionPopupPanel.origin(size: size, parentFrame: parent, anchor: anchor, visibleFrame: visible)

        #expect(origin == NSPoint(x: 300, y: 42))
    }

    @Test
    func theOriginIsClampedIntoTheVisibleFrame() {
        let left = IntentionPopupPanel.origin(
            size: size,
            parentFrame: parent,
            anchor: NSRect(x: 2, y: 400, width: 20, height: 18),
            visibleFrame: visible
        )
        let right = IntentionPopupPanel.origin(
            size: size,
            parentFrame: parent,
            anchor: NSRect(x: 990, y: 400, width: 20, height: 18),
            visibleFrame: visible
        )
        let tall = IntentionPopupPanel.origin(
            size: size,
            parentFrame: NSRect(x: 0, y: 0, width: 1000, height: 2000),
            anchor: nil,
            visibleFrame: visible
        )

        #expect(left.x == 8)
        #expect(right.x == 892)
        #expect(tall.y == 742)
    }

    @Test
    func withoutAVisibleFrameTheOriginIsNotClamped() {
        let anchor = NSRect(x: -50, y: 20, width: 20, height: 18)

        let origin = IntentionPopupPanel.origin(size: size, parentFrame: parent, anchor: anchor, visibleFrame: nil)

        #expect(origin == NSPoint(x: -50, y: 42))
    }
}
