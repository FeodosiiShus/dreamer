import AppKit
import SwiftUI

struct ToolWindowStripe: View {
    @Environment(ToolWindowManager.self) private var toolWindowManager

    private var lspService: LSPService { .shared }

    @AppStorage(Islands.BackgroundImageKey.path)
    private var backgroundImagePath = ""

    @AppStorage(Islands.BackgroundImageKey.opacity)
    private var backgroundImageOpacity = Islands.BackgroundImageKey.defaultOpacity

    private var backgroundColor: Color {
        let opacity: Double = backgroundImagePath.isEmpty ? 1 : 1 - backgroundImageOpacity
        return Islands.frame.opacity(opacity)
    }

    var body: some View {
        VStack(spacing: 2) {
            anchorGroup(.left)
            Spacer(minLength: 0)
            anchorGroup(.bottom)
        }
        .padding(.vertical, Islands.isCompact ? 2 : 6)
        .frame(width: Islands.stripeWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(backgroundColor)
    }

    private func anchorGroup(_ anchor: ToolWindowAnchor) -> some View {
        let groups = toolWindowManager.placement.stripeGroups(on: anchor, ordered: ToolWindowID.allCases)
        return VStack(spacing: 2) {
            ForEach(groups.main) { id in
                stripeButton(id)
            }
            if !groups.main.isEmpty, !groups.split.isEmpty {
                Rectangle()
                    .fill(Islands.separator)
                    .frame(width: Islands.stripeIconSize, height: 1)
                    .padding(.vertical, 2)
            }
            ForEach(groups.split) { id in
                stripeButton(id)
            }
        }
    }

    @ViewBuilder
    private func stripeButton(_ id: ToolWindowID) -> some View {
        if id == .languageServices {
            LanguageServicesStripeButton(serverStates: lspService.serverStates)
        } else {
            ToolWindowStripeButton(id: id)
        }
    }
}

struct LanguageServicesStripeButton: View {
    let serverStates: [LSPService.ClientKey: LSPService.ServerState]

    @Environment(ToolWindowManager.self) private var toolWindowManager
    @Environment(WorkspaceDocument.self) private var workspace

    static func problemCount(in states: [LSPService.ClientKey: LSPService.ServerState], workspacePath: String?) -> Int {
        states.filter { key, state in
            guard workspacePath == nil || key.workspacePath == workspacePath else { return false }
            if case .failed = state { return true }
            return false
        }.count
    }

    private var problemCount: Int {
        Self.problemCount(in: serverStates, workspacePath: workspace.fileURL?.absolutePath)
    }

    var body: some View {
        let isSelected = toolWindowManager.isVisible(.languageServices)
        ToolWindowStripeButton(id: .languageServices)
        .overlay(alignment: .topTrailing) {
            if problemCount > 0, !isSelected {
                Text("\(problemCount)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 3)
                    .frame(minWidth: 12, minHeight: 12)
                    .background(Capsule().fill(Color(hex: 0xE55765)))
                    .offset(x: -1, y: 1)
            }
        }
    }
}

struct ToolWindowStripeButton: View {
    let id: ToolWindowID

    @Environment(ToolWindowManager.self) private var toolWindowManager

    @State private var isHovering = false

    private var isSelected: Bool {
        toolWindowManager.isVisible(id)
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.white.opacity(0.12)
        }
        return isHovering ? Islands.hover : Color.clear
    }

    var body: some View {
        Button(action: bound(toolWindowManager.toggle, id)) {
            Image(id.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: Islands.stripeIconSize, height: Islands.stripeIconSize)
                .frame(width: Islands.stripeButtonSize, height: Islands.stripeButtonSize)
                .background(
                    RoundedRectangle(cornerRadius: Islands.controlRadius)
                        .fill(backgroundColor)
                )
                .contentShape(RoundedRectangle(cornerRadius: Islands.controlRadius))
        }
        .buttonStyle(.plain)
        .help("\(id.title) \(id.shortcutHint)")
        .onHover(perform: setHovering)
        .contextMenu { ToolWindowSplitMenuItem(id: id) }
    }

    func setHovering(_ hovering: Bool) {
        isHovering = hovering
    }
}

struct ToolWindowSplitMenuItem: View {
    let id: ToolWindowID

    @Environment(ToolWindowManager.self) private var toolWindowManager

    var body: some View {
        Button(toolWindowManager.isSplit(id) ? "Move to Main" : "Move to Split", action: bound(toolWindowManager.toggleSplit, id))
    }
}

extension ToolWindowManager {
    func toggleSplit(_ id: ToolWindowID) {
        setSplit(id, !isSplit(id))
    }
}
