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
    private(set) var visible: [ToolWindowAnchor: ToolWindowID] = [.left: .project, .bottom: .terminal]
    var leftWidth: CGFloat = 280
    var bottomHeight: CGFloat = 300
    var bottomMaximized = false

    func active(_ anchor: ToolWindowAnchor) -> ToolWindowID? {
        visible[anchor]
    }

    func isVisible(_ id: ToolWindowID) -> Bool {
        visible[id.anchor] == id
    }

    func toggle(_ id: ToolWindowID) {
        if isVisible(id) {
            hide(id.anchor)
        } else {
            show(id)
        }
    }

    func show(_ id: ToolWindowID) {
        visible[id.anchor] = id
    }

    func hide(_ anchor: ToolWindowAnchor) {
        visible[anchor] = nil
        if anchor == .bottom {
            bottomMaximized = false
        }
    }

    func hideAll() {
        visible.removeAll()
        bottomMaximized = false
    }
}
