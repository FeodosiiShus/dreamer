import AppKit
import SwiftUI

struct IslandResizeHandle: View {
    enum Orientation {
        case vertical
        case horizontal
    }

    let orientation: Orientation
    let onDrag: (CGFloat) -> Void
    let onDragEnded: () -> Void

    @State private var lastTranslation: CGFloat = 0

    private var cursor: NSCursor {
        switch orientation {
        case .vertical: NSCursor.resizeLeftRight
        case .horizontal: NSCursor.resizeUpDown
        }
    }

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    cursor.set()
                case .ended:
                    NSCursor.arrow.set()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let translation = switch orientation {
                        case .vertical: value.translation.width
                        case .horizontal: value.translation.height
                        }
                        let delta = translation - lastTranslation
                        lastTranslation = translation
                        cursor.set()
                        onDrag(delta)
                    }
                    .onEnded { _ in
                        lastTranslation = 0
                        onDragEnded()
                    }
            )
            .accessibilityHidden(true)
    }
}
