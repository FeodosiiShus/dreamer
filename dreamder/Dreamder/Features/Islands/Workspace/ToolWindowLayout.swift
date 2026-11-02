import CoreGraphics
import Foundation

struct ToolWindowLayout: Equatable {
    var left: ToolWindowID?
    var bottom: ToolWindowID?
    var leftWidth: CGFloat
    var bottomHeight: CGFloat
    var bottomMaximized: Bool

    static let defaultLeftWidth: CGFloat = 280
    static let defaultBottomHeight: CGFloat = 300
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
            bottomMaximized: workspace.getFromWorkspaceState(.toolWindowBottomMaximized) as? Bool ?? false
        )
    }

    init(manager: ToolWindowManager) {
        self.init(
            left: manager.active(.left),
            bottom: manager.active(.bottom),
            leftWidth: manager.leftWidth,
            bottomHeight: manager.bottomHeight,
            bottomMaximized: manager.bottomMaximized
        )
    }

    func apply(to manager: ToolWindowManager) {
        manager.hideAll()

        if let left, left.anchor == .left {
            manager.show(left)
        }
        if let bottom, bottom.anchor == .bottom {
            manager.show(bottom)
        }

        manager.leftWidth = Self.clampLeftWidth(leftWidth, availableWidth: .greatestFiniteMagnitude)
        manager.bottomHeight = max(bottomHeight, Self.minBottomHeight)
        manager.bottomMaximized = bottomMaximized && manager.active(.bottom) != nil
    }

    func save(to workspace: WorkspaceDocument) {
        workspace.addToWorkspaceState(key: .toolWindowLeft, value: left?.rawValue ?? "")
        workspace.addToWorkspaceState(key: .toolWindowBottom, value: bottom?.rawValue ?? "")
        workspace.addToWorkspaceState(key: .toolWindowLeftWidth, value: Double(leftWidth))
        workspace.addToWorkspaceState(key: .toolWindowBottomHeight, value: Double(bottomHeight))
        workspace.addToWorkspaceState(key: .toolWindowBottomMaximized, value: bottomMaximized)
    }
}
