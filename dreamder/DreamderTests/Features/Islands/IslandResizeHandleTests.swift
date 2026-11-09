import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct IslandResizeHandleTests {
    @Test
    func verticalHandleUsesTheLeftRightCursorAndTheHorizontalTranslation() {
        let orientation = IslandResizeHandle.Orientation.vertical

        #expect(orientation.cursor == NSCursor.resizeLeftRight)
        #expect(orientation.component(of: CGSize(width: 12, height: 34)) == 12)
    }

    @Test
    func horizontalHandleUsesTheUpDownCursorAndTheVerticalTranslation() {
        let orientation = IslandResizeHandle.Orientation.horizontal

        #expect(orientation.cursor == NSCursor.resizeUpDown)
        #expect(orientation.component(of: CGSize(width: 12, height: 34)) == 34)
    }

    @Test
    func hoverPhasesSelectTheResizeCursorWhileActiveAndTheArrowWhenEnded() {
        let orientation = IslandResizeHandle.Orientation.vertical

        #expect(orientation.apply(.active(CGPoint(x: 1, y: 1))) == NSCursor.resizeLeftRight)
        #expect(orientation.apply(.ended) == NSCursor.arrow)
        #expect(IslandResizeHandle.Orientation.horizontal.apply(.active(.zero)) == NSCursor.resizeUpDown)
    }

    @Test
    func dragTrackerReportsIncrementsBetweenTranslations() {
        var tracker = IslandResizeHandle.DragTracker()

        #expect(tracker.advance(to: CGSize(width: 10, height: 3), along: .vertical) == 10)
        #expect(tracker.advance(to: CGSize(width: 25, height: 9), along: .vertical) == 15)
        #expect(tracker.advance(to: CGSize(width: 20, height: 9), along: .vertical) == -5)
        #expect(tracker.lastTranslation == 20)
    }

    @Test
    func dragTrackerFollowsTheOrientationAxis() {
        var tracker = IslandResizeHandle.DragTracker()

        #expect(tracker.advance(to: CGSize(width: 10, height: 4), along: .horizontal) == 4)
        #expect(tracker.advance(to: CGSize(width: 10, height: 10), along: .horizontal) == 6)
    }

    @Test
    func aFreshTrackerStartsFromZeroAgain() {
        var tracker = IslandResizeHandle.DragTracker()
        _ = tracker.advance(to: CGSize(width: 30, height: 0), along: .vertical)

        tracker = IslandResizeHandle.DragTracker()

        #expect(tracker == IslandResizeHandle.DragTracker())
        #expect(tracker.advance(to: CGSize(width: 5, height: 0), along: .vertical) == 5)
    }

    @Test
    func handlesRenderInBothOrientations() async throws {
        for orientation in [IslandResizeHandle.Orientation.vertical, .horizontal] {
            let hosted = HostedViewFixture.host(size: NSSize(width: 40, height: 40)) {
                ZStack {
                    Color.red
                    IslandResizeHandle(orientation: orientation, onDrag: { _ in }, onDragEnded: {})
                }
            }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(50))

            #expect(hosted.renders())
        }
    }
}
