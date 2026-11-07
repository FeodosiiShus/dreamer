import SwiftUI
import Synchronization

nonisolated final class SplitLayoutProbe: Sendable {
    private struct Snapshot {
        var panes: [SplitLayoutPane] = []
        var lengths: [CGFloat] = []
    }

    private let snapshot = Mutex(Snapshot())

    var panes: [SplitLayoutPane] {
        snapshot.withLock { $0.panes }
    }

    var lengths: [CGFloat] {
        snapshot.withLock { $0.lengths }
    }

    func record(panes: [SplitLayoutPane], lengths: [CGFloat]) {
        snapshot.withLock {
            $0.panes = panes
            $0.lengths = lengths
        }
    }
}

struct SplitLayout: Layout {
    var axis: Axis
    var dividerThickness: CGFloat
    var hitThickness: CGFloat
    var weights: [CGFloat]
    var probe: SplitLayoutProbe

    private struct Entry {
        var subviewIndex: Int
        var pane: SplitLayoutPane
    }

    private var isRow: Bool { axis == .horizontal }

    private func main(_ size: CGSize) -> CGFloat {
        isRow ? size.width : size.height
    }

    private func cross(_ size: CGSize) -> CGFloat {
        isRow ? size.height : size.width
    }

    private func size(main: CGFloat, cross: CGFloat) -> CGSize {
        isRow ? CGSize(width: main, height: cross) : CGSize(width: cross, height: main)
    }

    private func proposed(main: CGFloat?, cross: CGFloat?) -> ProposedViewSize {
        isRow ? ProposedViewSize(width: main, height: cross) : ProposedViewSize(width: cross, height: main)
    }

    private func entries(in subviews: Subviews) -> [Entry] {
        var result: [Entry] = []
        for index in subviews.indices where subviews[index][SplitLayoutRoleKey.self] == .pane {
            let subview = subviews[index]
            let pane = SplitLayoutPane(
                minLength: subview[SplitLayoutMinLengthKey.self],
                maxLength: subview[SplitLayoutMaxLengthKey.self],
                isCollapsed: subview[SplitLayoutCollapsedKey.self],
                holdingPriority: subview[SplitLayoutHoldingPriorityKey.self]
            )
            result.append(Entry(subviewIndex: index, pane: pane))
        }
        let normalized = SplitLayoutMath.normalizedWeights(weights, count: result.count)
        for offset in result.indices {
            result[offset].pane.weight = normalized[offset]
        }
        return result
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let visible = entries(in: subviews).filter { !$0.pane.isCollapsed }
        let gaps = dividerThickness * CGFloat(max(0, visible.count - 1))
        let minimumMain = visible.reduce(gaps) { $0 + $1.pane.lowerBound }
        let mainProposal = isRow ? proposal.width : proposal.height
        let crossProposal = isRow ? proposal.height : proposal.width
        return size(main: mainProposal ?? minimumMain, cross: crossProposal ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let crossLength = cross(bounds.size)
        let paneEntries = entries(in: subviews)
        let math = SplitLayoutMath(panes: paneEntries.map(\.pane))
        let mainStart = isRow ? bounds.minX : bounds.minY
        let mainEnd = isRow ? bounds.maxX : bounds.maxY
        let crossStart = isRow ? bounds.minY : bounds.minX
        let lengths = math.distribute(length: main(bounds.size), dividerThickness: dividerThickness)
        probe.record(panes: math.panes, lengths: lengths)

        func point(main: CGFloat, cross: CGFloat) -> CGPoint {
            isRow ? CGPoint(x: main, y: cross) : CGPoint(x: cross, y: main)
        }

        let dividerIndices = subviews.indices.filter { subviews[$0][SplitLayoutRoleKey.self] == .divider }
        let lastVisible = paneEntries.lastIndex { !$0.pane.isCollapsed }
        var offset = mainStart
        var dividerOrdinal = 0
        for (position, entry) in paneEntries.enumerated() {
            let length = lengths[position]
            subviews[entry.subviewIndex].place(
                at: point(main: offset, cross: crossStart),
                anchor: .topLeading,
                proposal: proposed(main: length, cross: crossLength)
            )
            guard !entry.pane.isCollapsed else { continue }
            offset += length
            guard let lastVisible, position < lastVisible else { continue }
            if dividerOrdinal < dividerIndices.count {
                let center = min(offset + dividerThickness / 2, mainEnd)
                subviews[dividerIndices[dividerOrdinal]].place(
                    at: point(main: center, cross: crossStart + crossLength / 2),
                    anchor: .center,
                    proposal: proposed(main: hitThickness, cross: crossLength)
                )
            }
            dividerOrdinal += 1
            offset += dividerThickness
        }
        for index in dividerIndices.dropFirst(dividerOrdinal) {
            subviews[index].place(
                at: point(main: mainStart, cross: crossStart),
                anchor: .topLeading,
                proposal: .zero
            )
        }
    }
}
