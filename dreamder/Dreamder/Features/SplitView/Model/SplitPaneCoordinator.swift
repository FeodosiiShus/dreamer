import CoreGraphics

nonisolated struct SplitPaneCoordinator {
    static let weightTolerance: CGFloat = 1e-9

    let probe = SplitLayoutProbe()
    private var dragOrigin: [CGFloat]?

    init() {}

    mutating func dragged(pair: Int, translation: CGFloat) -> [CGFloat] {
        let origin = dragOrigin ?? probe.lengths
        dragOrigin = origin
        return SplitLayoutMath(panes: probe.panes).drag(dividerIndex: pair, delta: translation, lengths: origin)
    }

    mutating func endDrag() {
        dragOrigin = nil
    }

    func nudged(pair: Int, delta: CGFloat) -> [CGFloat] {
        SplitLayoutMath(panes: probe.panes).drag(dividerIndex: pair, delta: delta, lengths: probe.lengths)
    }

    func resized(from oldLength: CGFloat, to newLength: CGFloat, dividerThickness: CGFloat) -> [CGFloat]? {
        guard oldLength > 0, newLength > 0, oldLength != newLength else { return nil }
        let math = SplitLayoutMath(panes: probe.panes)
        guard Set(math.visibleIndices.map { math.panes[$0].holdingPriority }).count > 1 else { return nil }
        let oldLengths = math.distribute(length: oldLength, dividerThickness: dividerThickness)
        return math.resize(lengths: oldLengths, newLength: newLength, dividerThickness: dividerThickness)
    }

    static func isUnchanged(_ current: [CGFloat], _ updated: [CGFloat]) -> Bool {
        current.count == updated.count && zip(current, updated).allSatisfy { abs($0 - $1) <= weightTolerance }
    }

    static func changed(_ updated: [CGFloat], from current: [CGFloat]) -> [CGFloat]? {
        isUnchanged(current, updated) ? nil : updated
    }
}
