import CoreGraphics
import Foundation

struct ToolWindowLayout: Equatable {
    var left: ToolWindowID?
    var bottom: ToolWindowID?
    var leftWidth: CGFloat
    var bottomHeight: CGFloat
    var bottomMaximized: Bool
    var leftSplit: ToolWindowID? = nil
    var bottomSplit: ToolWindowID? = nil
    var splitWindows: [ToolWindowID] = []
    var sideWeights: [ToolWindowID: Double] = [:]

    static let defaultLeftWidth: CGFloat = 280
    static let defaultBottomHeight: CGFloat = 300
    static let minSplitPart: CGFloat = 96
    static let minLeftWidth: CGFloat = 180
    static let maxLeftWidth: CGFloat = 640
    static let minBottomHeight: CGFloat = 120
    static let minEditorWidth: CGFloat = 320
    static let minEditorHeight: CGFloat = 160
}

extension ToolWindowLayout {
    static func clampLeftWidth(_ width: CGFloat, availableWidth: CGFloat) -> CGFloat {
        let upperBound = min(maxLeftWidth, max(minLeftWidth, availableWidth - minEditorWidth))
        return min(max(width, minLeftWidth), upperBound)
    }

    static func clampBottomHeight(_ height: CGFloat, availableHeight: CGFloat) -> CGFloat {
        let upperBound = max(minBottomHeight, availableHeight - minEditorHeight)
        return min(max(height, minBottomHeight), upperBound)
    }

    static func storedToolWindow(_ stored: Any?, default defaultValue: ToolWindowID?) -> ToolWindowID? {
        guard let rawValue = stored as? String else { return defaultValue }
        return ToolWindowID(rawValue: rawValue)
    }

    static func storedLength(_ stored: Any?, default defaultValue: CGFloat) -> CGFloat {
        guard let value = stored as? Double else { return defaultValue }
        return CGFloat(value)
    }

    static func storedSplitWindows(_ stored: Any?) -> [ToolWindowID] {
        guard let rawValues = stored as? [String] else { return [] }
        return rawValues.compactMap { ToolWindowID(rawValue: $0) }
    }

    static func storedSideWeights(_ stored: Any?) -> [ToolWindowID: Double] {
        guard let raw = stored as? [String: Double] else { return [:] }
        var weights: [ToolWindowID: Double] = [:]
        for (key, value) in raw {
            if let id = ToolWindowID(rawValue: key) {
                weights[id] = value
            }
        }
        return weights
    }
}

extension ToolWindowLayout {
    init(workspace: WorkspaceDocument) {
        self.init(
            left: Self.storedToolWindow(
                workspace.getFromWorkspaceState(.toolWindowLeft),
                default: .project
            ),
            bottom: Self.storedToolWindow(
                workspace.getFromWorkspaceState(.toolWindowBottom),
                default: .terminal
            ),
            leftWidth: Self.storedLength(
                workspace.getFromWorkspaceState(.toolWindowLeftWidth),
                default: Self.defaultLeftWidth
            ),
            bottomHeight: Self.storedLength(
                workspace.getFromWorkspaceState(.toolWindowBottomHeight),
                default: Self.defaultBottomHeight
            ),
            bottomMaximized: workspace.getFromWorkspaceState(.toolWindowBottomMaximized) as? Bool ?? false,
            leftSplit: Self.storedToolWindow(workspace.getFromWorkspaceState(.toolWindowLeftSplit), default: nil),
            bottomSplit: Self.storedToolWindow(workspace.getFromWorkspaceState(.toolWindowBottomSplit), default: nil),
            splitWindows: Self.storedSplitWindows(workspace.getFromWorkspaceState(.toolWindowSplitIDs)),
            sideWeights: Self.storedSideWeights(workspace.getFromWorkspaceState(.toolWindowSideWeights))
        )
    }

    init(manager: ToolWindowManager) {
        self.init(
            left: manager.visible(on: .left, side: .main),
            bottom: manager.visible(on: .bottom, side: .main),
            leftWidth: manager.leftWidth,
            bottomHeight: manager.bottomHeight,
            bottomMaximized: manager.bottomMaximized,
            leftSplit: manager.visible(on: .left, side: .split),
            bottomSplit: manager.visible(on: .bottom, side: .split),
            splitWindows: ToolWindowID.allCases.filter { manager.isSplit($0) },
            sideWeights: manager.placement.customSideWeights
        )
    }

    func apply(to manager: ToolWindowManager) {
        manager.hideAll()

        for id in ToolWindowID.allCases {
            manager.setSplit(id, splitWindows.contains(id))
            manager.setSideWeight(id, sideWeights[id] ?? ToolWindowSplitState.defaultSideWeight)
        }

        showIfDocked(left, on: .left, side: .main, in: manager)
        showIfDocked(leftSplit, on: .left, side: .split, in: manager)
        showIfDocked(bottom, on: .bottom, side: .main, in: manager)
        showIfDocked(bottomSplit, on: .bottom, side: .split, in: manager)

        manager.leftWidth = Self.clampLeftWidth(leftWidth, availableWidth: .greatestFiniteMagnitude)
        manager.bottomHeight = max(bottomHeight, Self.minBottomHeight)
        manager.bottomMaximized = bottomMaximized && manager.active(.bottom) != nil
    }

    private func showIfDocked(
        _ id: ToolWindowID?,
        on anchor: ToolWindowAnchor,
        side: ToolWindowSide,
        in manager: ToolWindowManager
    ) {
        guard let id, id.anchor == anchor, manager.isSplit(id) == side.isSplit else { return }
        manager.show(id)
    }

    func save(to workspace: WorkspaceDocument) {
        workspace.addToWorkspaceState(key: .toolWindowLeft, value: left?.rawValue ?? "")
        workspace.addToWorkspaceState(key: .toolWindowBottom, value: bottom?.rawValue ?? "")
        workspace.addToWorkspaceState(key: .toolWindowLeftSplit, value: leftSplit?.rawValue ?? "")
        workspace.addToWorkspaceState(key: .toolWindowBottomSplit, value: bottomSplit?.rawValue ?? "")
        workspace.addToWorkspaceState(key: .toolWindowSplitIDs, value: splitWindows.map(\.rawValue))
        workspace.addToWorkspaceState(
            key: .toolWindowSideWeights,
            value: Dictionary(uniqueKeysWithValues: sideWeights.map { ($0.key.rawValue, $0.value) })
        )
        workspace.addToWorkspaceState(key: .toolWindowLeftWidth, value: Double(leftWidth))
        workspace.addToWorkspaceState(key: .toolWindowBottomHeight, value: Double(bottomHeight))
        workspace.addToWorkspaceState(key: .toolWindowBottomMaximized, value: bottomMaximized)
    }
}
