import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct ViewExtensionsCoverageTests {
    @Test
    func isHoveringPushesTheCursorWhileHoveredAndPopsWhenLeft() {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        let cursor = NSCursor(image: image, hotSpot: .zero)

        Color.clear.isHovering(true, cursor: cursor)
        #expect(NSCursor.current == cursor)

        Color.clear.isHovering(false)
        #expect(NSCursor.current != cursor)
    }

    @Test
    func isHoveringDoesNothingWhileDragging() {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        let cursor = NSCursor(image: image, hotSpot: .zero)

        Color.clear.isHovering(true, isDragging: true, cursor: cursor)
        #expect(NSCursor.current != cursor)

        Color.clear.isHovering(true, cursor: cursor)
        Color.clear.isHovering(false, isDragging: true)
        #expect(NSCursor.current == cursor)

        Color.clear.isHovering(false)
        #expect(NSCursor.current != cursor)
    }

    @Test
    func isHoveringUsesTheArrowCursorByDefault() {
        Color.clear.isHovering(true)
        #expect(NSCursor.current == NSCursor.arrow)
        Color.clear.isHovering(false)
    }
}
