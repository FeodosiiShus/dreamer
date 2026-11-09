import SwiftUI
import Synchronization

nonisolated enum IslandSlot: Sendable {
    case left
    case leftDivider
    case editor
    case bottomDivider
    case bottom
}

nonisolated struct IslandSlotKey: LayoutValueKey {
    static let defaultValue = IslandSlot.editor
}

nonisolated final class IslandsLayoutProbe: Sendable {
    private struct Snapshot {
        var area: CGSize = .zero
        var frames = IslandsLayoutMetrics.Frames()
    }

    private let snapshot = Mutex(Snapshot())

    var area: CGSize {
        snapshot.withLock { $0.area }
    }

    var frames: IslandsLayoutMetrics.Frames {
        snapshot.withLock { $0.frames }
    }

    func record(area: CGSize, frames: IslandsLayoutMetrics.Frames) {
        snapshot.withLock {
            $0.area = area
            $0.frames = frames
        }
    }
}

struct IslandsColumnLayout: Layout {
    var metrics: IslandsLayoutMetrics
    var input: IslandsLayoutMetrics.Input
    var probe: IslandsLayoutProbe?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = metrics.frames(in: bounds.size, input: input)
        probe?.record(area: bounds.size, frames: frames)
        for subview in subviews {
            let frame = frames.frame(for: subview[IslandSlotKey.self])
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(frame.size)
            )
        }
    }
}

extension View {
    func islandSlot(_ slot: IslandSlot) -> some View {
        layoutValue(key: IslandSlotKey.self, value: slot)
    }
}
