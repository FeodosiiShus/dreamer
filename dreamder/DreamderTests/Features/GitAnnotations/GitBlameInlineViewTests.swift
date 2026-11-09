import AppKit
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct GitBlameInlineViewTests {
    private let anchor = CGRect(x: 40, y: 100, width: 8, height: 20)

    @Test
    func textStartsThreeSmallFontSizesAfterTheAnchor() throws {
        let view = GitBlameInlineView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        view.setText("Author, just now • Subject")

        let origin = try #require(view.textOrigin(anchor: anchor))

        #expect(origin.x == anchor.maxX + Islands.smallFontSize * 3)
        #expect(origin.y >= anchor.minY)
        #expect(origin.y <= anchor.midY)
    }

    @Test
    func clearingTheTextRemovesTheOrigin() {
        let view = GitBlameInlineView(frame: .zero)
        view.setText("Author, just now • Subject")
        view.setText(nil)

        #expect(view.text == nil)
        #expect(view.textOrigin(anchor: anchor) == nil)
    }

    @Test
    func overlayStaysOutsideAutoLayoutAndIgnoresHits() {
        let view = GitBlameInlineView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))

        #expect(view.translatesAutoresizingMaskIntoConstraints == false)
        #expect(view.autoresizingMask.isEmpty)
        #expect(view.hitTest(NSPoint(x: 10, y: 10)) == nil)
    }

    @Test
    func overlayIsTransparentAndTopLeftOriented() {
        let view = GitBlameInlineView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))

        #expect(!view.isOpaque)
        #expect(view.isFlipped)
    }

    @Test
    func overlayFollowsItsSuperviewBounds() {
        let host = NSView(frame: CGRect(x: 0, y: 0, width: 500, height: 700))
        let view = GitBlameInlineView(frame: .zero)
        host.addSubview(view)

        view.matchSuperviewBounds()
        #expect(view.frame == host.bounds)

        host.setFrameSize(NSSize(width: 900, height: 200))
        view.matchSuperviewBounds()
        #expect(view.frame == CGRect(x: 0, y: 0, width: 900, height: 200))
    }
}
