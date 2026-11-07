import CoreGraphics
import Foundation

enum ToolWindowSide: String, CaseIterable, Hashable {
    case main
    case split

    init(isSplit: Bool) {
        self = isSplit ? .split : .main
    }

    var isSplit: Bool {
        self == .split
    }
}

struct ToolWindowSlot: Hashable {
    let anchor: ToolWindowAnchor
    let side: ToolWindowSide

    init(_ anchor: ToolWindowAnchor, _ side: ToolWindowSide) {
        self.anchor = anchor
        self.side = side
    }
}

struct ToolWindowStripeGroups: Equatable {
    var main: [ToolWindowID]
    var split: [ToolWindowID]
}

extension ToolWindowAnchor {
    var splitsVertically: Bool {
        self == .left
    }
}

struct ToolWindowSplitState: Equatable {
    static let defaultSideWeight = 0.5
    static let defaultWeight = 0.33
    static let defaultVisible: [ToolWindowSlot: ToolWindowID] = [
        ToolWindowSlot(.left, .main): .project,
        ToolWindowSlot(.bottom, .main): .terminal
    ]

    private(set) var splitWindows: Set<ToolWindowID>
    private(set) var visible: [ToolWindowSlot: ToolWindowID]
    private(set) var sideWeights: [ToolWindowID: Double]

    init(
        splitWindows: Set<ToolWindowID> = [],
        visible: [ToolWindowSlot: ToolWindowID] = ToolWindowSplitState.defaultVisible,
        sideWeights: [ToolWindowID: Double] = [:]
    ) {
        self.splitWindows = splitWindows
        self.visible = visible
        self.sideWeights = sideWeights
    }

    static func normalizeWeight(_ weight: Double) -> Double {
        if weight <= 0 {
            return defaultWeight
        }
        return weight >= 1 ? 1 - defaultWeight : weight
    }

    func side(of id: ToolWindowID) -> ToolWindowSide {
        ToolWindowSide(isSplit: splitWindows.contains(id))
    }

    func slot(of id: ToolWindowID) -> ToolWindowSlot {
        ToolWindowSlot(id.anchor, side(of: id))
    }

    func window(at slot: ToolWindowSlot) -> ToolWindowID? {
        visible[slot]
    }

    func isVisible(_ id: ToolWindowID) -> Bool {
        visible[slot(of: id)] == id
    }

    func isSplit(_ id: ToolWindowID) -> Bool {
        splitWindows.contains(id)
    }

    func hasVisibleWindow(on anchor: ToolWindowAnchor) -> Bool {
        ToolWindowSide.allCases.contains { visible[ToolWindowSlot(anchor, $0)] != nil }
    }

    func sideWeight(of id: ToolWindowID) -> Double {
        sideWeights[id] ?? Self.defaultSideWeight
    }

    var customSideWeights: [ToolWindowID: Double] {
        sideWeights.filter { $0.value != Self.defaultSideWeight }
    }

    mutating func show(_ id: ToolWindowID) {
        visible[slot(of: id)] = id
    }

    mutating func hide(_ id: ToolWindowID) {
        let slot = slot(of: id)
        if visible[slot] == id {
            visible[slot] = nil
        }
    }

    mutating func hide(anchor: ToolWindowAnchor) {
        for side in ToolWindowSide.allCases {
            visible[ToolWindowSlot(anchor, side)] = nil
        }
    }

    mutating func hideAll() {
        visible.removeAll()
    }

    mutating func setSplit(_ id: ToolWindowID, _ isSplit: Bool) {
        guard splitWindows.contains(id) != isSplit else { return }
        let wasVisible = isVisible(id)
        hide(id)
        if isSplit {
            splitWindows.insert(id)
        } else {
            splitWindows.remove(id)
        }
        if wasVisible {
            show(id)
        }
    }

    mutating func setSideWeight(_ id: ToolWindowID, _ weight: Double) {
        let clamped = max(0, min(1, weight))
        if clamped == Self.defaultSideWeight {
            sideWeights[id] = nil
        } else {
            sideWeights[id] = clamped
        }
    }

    func isShownSideBySide(on anchor: ToolWindowAnchor) -> Bool {
        visible[ToolWindowSlot(anchor, .main)] != nil && visible[ToolWindowSlot(anchor, .split)] != nil
    }

    func mainProportion(on anchor: ToolWindowAnchor) -> Double {
        guard let main = visible[ToolWindowSlot(anchor, .main)],
              let split = visible[ToolWindowSlot(anchor, .split)] else {
            return 1
        }
        let mainWeight = sideWeight(of: main)
        let splitWeight = sideWeight(of: split)
        let total = mainWeight + splitWeight
        guard total > 0 else { return Self.defaultSideWeight }
        return Self.normalizeWeight(mainWeight / total)
    }

    mutating func setMainProportion(on anchor: ToolWindowAnchor, _ proportion: Double) {
        guard let main = visible[ToolWindowSlot(anchor, .main)],
              let split = visible[ToolWindowSlot(anchor, .split)] else {
            return
        }
        let normalized = Self.normalizeWeight(proportion)
        setSideWeight(main, normalized)
        setSideWeight(split, 1 - normalized)
    }

    func stripeGroups(on anchor: ToolWindowAnchor, ordered ids: [ToolWindowID]) -> ToolWindowStripeGroups {
        let onAnchor = ids.filter { $0.anchor == anchor }
        return ToolWindowStripeGroups(
            main: onAnchor.filter { !splitWindows.contains($0) },
            split: onAnchor.filter { splitWindows.contains($0) }
        )
    }
}

extension ToolWindowSplitState {
    static func partSizes(
        total: CGFloat,
        proportion: Double,
        gap: CGFloat,
        minimumPart: CGFloat
    ) -> (first: CGFloat, second: CGFloat) {
        let available = max(0, total - gap)
        let minimum = min(minimumPart, available / 2)
        let first = min(max(available * CGFloat(normalizeWeight(proportion)), minimum), available - minimum)
        return (first, available - first)
    }

    static func proportion(
        movingDividerBy delta: CGFloat,
        from proportion: Double,
        total: CGFloat,
        gap: CGFloat,
        minimumPart: CGFloat
    ) -> Double {
        let available = max(0, total - gap)
        guard available > 0 else { return defaultSideWeight }
        let current = partSizes(total: total, proportion: proportion, gap: gap, minimumPart: minimumPart).first
        let minimum = min(minimumPart, available / 2)
        let moved = min(max(current + delta, minimum), available - minimum)
        return Double(moved / available)
    }
}
