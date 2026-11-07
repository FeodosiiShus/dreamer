import SwiftUI

enum ToolWindowAnchor: String, Codable, CaseIterable {
    case left
    case bottom
}

enum ToolWindowID: String, Codable, CaseIterable, Identifiable {
    case project
    case commit
    case structure
    case run
    case find
    case terminal
    case problems
    case git
    case languageServices

    var id: String { rawValue }

    var title: String {
        switch self {
        case .project: "Project"
        case .commit: "Commit"
        case .structure: "Structure"
        case .run: "Run"
        case .find: "Find"
        case .terminal: "Terminal"
        case .problems: "Problems"
        case .git: "Git"
        case .languageServices: "Language Services"
        }
    }

    var icon: String {
        let sizeSuffix = Islands.isCompact ? "" : "_20"
        switch self {
        case .project: return "toolwindows/project\(sizeSuffix)"
        case .commit: return "toolwindows/commit\(sizeSuffix)"
        case .structure: return "toolwindows/structure\(sizeSuffix)"
        case .run: return "toolwindows/run\(sizeSuffix)"
        case .find: return "toolwindows/find\(sizeSuffix)"
        case .terminal: return "toolwindows/terminal\(sizeSuffix)"
        case .problems: return "toolwindows/problems\(sizeSuffix)"
        case .git: return "toolwindows/vcs\(sizeSuffix)"
        case .languageServices: return "toolwindows/languageServices\(sizeSuffix)"
        }
    }

    var anchor: ToolWindowAnchor {
        switch self {
        case .project, .commit, .structure: .left
        case .run, .find, .terminal, .problems, .git, .languageServices: .bottom
        }
    }

    var shortcutHint: String {
        switch self {
        case .project: "⌘1"
        case .commit: "⌘0"
        case .structure: "⌘7"
        case .run: "⌘4"
        case .find: "⌘3"
        case .terminal: "⌥F12"
        case .problems: "⌘6"
        case .git: "⌘9"
        case .languageServices: "⌃⌘L"
        }
    }
}

@Observable
@MainActor
final class ToolWindowManager {
    private(set) var placement = ToolWindowSplitState()
    var leftWidth: CGFloat = 280
    var bottomHeight: CGFloat = 300
    var bottomMaximized = false

    var visibleWindows: [ToolWindowSlot: ToolWindowID] {
        placement.visible
    }

    func active(_ anchor: ToolWindowAnchor) -> ToolWindowID? {
        visible(on: anchor, side: .main) ?? visible(on: anchor, side: .split)
    }

    func visible(on anchor: ToolWindowAnchor, side: ToolWindowSide) -> ToolWindowID? {
        placement.window(at: ToolWindowSlot(anchor, side))
    }

    func isVisible(_ id: ToolWindowID) -> Bool {
        placement.isVisible(id)
    }

    func isSplit(_ id: ToolWindowID) -> Bool {
        placement.isSplit(id)
    }

    func setSplit(_ id: ToolWindowID, _ isSplit: Bool) {
        placement.setSplit(id, isSplit)
    }

    func sideWeight(of id: ToolWindowID) -> Double {
        placement.sideWeight(of: id)
    }

    func setSideWeight(_ id: ToolWindowID, _ weight: Double) {
        placement.setSideWeight(id, weight)
    }

    func mainProportion(on anchor: ToolWindowAnchor) -> Double {
        placement.mainProportion(on: anchor)
    }

    func setMainProportion(on anchor: ToolWindowAnchor, _ proportion: Double) {
        placement.setMainProportion(on: anchor, proportion)
    }

    func toggle(_ id: ToolWindowID) {
        if isVisible(id) {
            hide(id)
        } else {
            show(id)
        }
    }

    func show(_ id: ToolWindowID) {
        placement.show(id)
    }

    func hide(_ id: ToolWindowID) {
        placement.hide(id)
        clearMaximizedIfBottomIsEmpty()
    }

    func hide(_ anchor: ToolWindowAnchor) {
        placement.hide(anchor: anchor)
        clearMaximizedIfBottomIsEmpty()
    }

    func hideAll() {
        placement.hideAll()
        bottomMaximized = false
    }

    private func clearMaximizedIfBottomIsEmpty() {
        if !placement.hasVisibleWindow(on: .bottom) {
            bottomMaximized = false
        }
    }
}
