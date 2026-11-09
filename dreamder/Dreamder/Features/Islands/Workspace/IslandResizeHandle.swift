import AppKit
import SwiftUI

struct IslandResizeHandle: View {
    enum Orientation {
        case vertical
        case horizontal

        var cursor: NSCursor {
            switch self {
            case .vertical: NSCursor.resizeLeftRight
            case .horizontal: NSCursor.resizeUpDown
            }
        }

        func component(of translation: CGSize) -> CGFloat {
            switch self {
            case .vertical: translation.width
            case .horizontal: translation.height
            }
        }

        @discardableResult
        func apply(_ phase: HoverPhase) -> NSCursor {
            let cursor = switch phase {
            case .active: self.cursor
            case .ended: NSCursor.arrow
            }
            cursor.set()
            return cursor
        }
    }

    struct DragTracker: Equatable {
        private(set) var lastTranslation: CGFloat = 0

        mutating func advance(to translation: CGSize, along orientation: Orientation) -> CGFloat {
            let current = orientation.component(of: translation)
            let delta = current - lastTranslation
            lastTranslation = current
            orientation.cursor.set()
            return delta
        }
    }

    let orientation: Orientation
    let onDrag: (CGFloat) -> Void
    let onDragEnded: () -> Void

    @State private var tracker = DragTracker()

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .onContinuousHover(perform: hover)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged(reading(\.translation, into: dragChanged))
                    .onEnded(discarding(dragEnded))
            )
            .accessibilityHidden(true)
    }

    func hover(_ phase: HoverPhase) {
        orientation.apply(phase)
    }

    func dragChanged(_ translation: CGSize) {
        onDrag(tracker.advance(to: translation, along: orientation))
    }

    func dragEnded() {
        tracker = DragTracker()
        onDragEnded()
    }
}
