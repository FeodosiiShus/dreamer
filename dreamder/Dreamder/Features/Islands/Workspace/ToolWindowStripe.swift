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
        VStack(spacing: 0) {
            anchorGroup(.left)
            Spacer(minLength: 0)
            anchorGroup(.bottom)
        }
        .frame(width: Islands.stripeWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(backgroundColor)
    }

    private func anchorGroup(_ anchor: ToolWindowAnchor) -> some View {
        let groups = toolWindowManager.placement.stripeGroups(on: anchor, ordered: ToolWindowID.allCases)
        return VStack(spacing: 0) {
            ForEach(groups.main) { id in
                stripeButton(id)
            }
            if !groups.main.isEmpty, !groups.split.isEmpty {
                stripeSeparator
            }
            ForEach(groups.split) { id in
                stripeButton(id)
            }
        }
    }

    private var stripeSeparator: some View {
        Rectangle()
            .fill(Islands.stripeSeparator)
            .frame(width: Islands.stripeSeparatorWidth, height: 1)
            .frame(width: Islands.stripeButtonWidth, height: Islands.stripeSeparatorCellHeight)
            .padding(.leading, Islands.stripeButtonInsets.leading)
            .padding(.trailing, Islands.stripeButtonInsets.trailing)
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
                    .offset(x: -Islands.stripeButtonInsets.trailing - 1, y: Islands.stripeButtonInsets.top + 1)
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

    var body: some View {
        Button(action: bound(toolWindowManager.toggle, id)) {
            Image(id.icon)
                .renderingMode(isSelected ? .template : .original)
                .resizable()
                .interpolation(.high)
                .frame(width: Islands.stripeIconSize, height: Islands.stripeIconSize)
                .foregroundStyle(Islands.stripeSelectedForeground)
        }
        .buttonStyle(.actionButton(look: .toolWindowStripe, isHovering: isHovering, isSelected: isSelected))
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
