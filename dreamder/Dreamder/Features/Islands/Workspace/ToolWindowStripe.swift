import AppKit
import SwiftUI

struct ToolWindowStripe: View {
    @EnvironmentObject private var toolWindowManager: ToolWindowManager

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
            stripeButton(.project)
            stripeButton(.commit)
            stripeButton(.structure)
            Spacer(minLength: 0)
            stripeButton(.run)
            stripeButton(.find)
            stripeButton(.terminal)
            stripeButton(.problems)
            stripeButton(.git)
            LanguageServicesStripeButton()
        }
        .padding(.vertical, Islands.isCompact ? 2 : 6)
        .frame(width: Islands.stripeWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(backgroundColor)
    }

    private func stripeButton(_ id: ToolWindowID) -> some View {
        ToolWindowStripeButton(
            id: id,
            isSelected: toolWindowManager.isVisible(id),
            action: { toolWindowManager.toggle(id) }
        )
    }
}

private struct LanguageServicesStripeButton: View {
    @EnvironmentObject private var toolWindowManager: ToolWindowManager
    @EnvironmentObject private var workspace: WorkspaceDocument

    @Service private var lspService: LSPService

    @State private var problemCount = 0

    var body: some View {
        let isSelected = toolWindowManager.isVisible(.languageServices)
        ToolWindowStripeButton(
            id: .languageServices,
            isSelected: isSelected,
            action: { toolWindowManager.toggle(.languageServices) }
        )
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
        .onReceive(lspService.$serverStates) { states in
            let path = workspace.fileURL?.absolutePath
            problemCount = states.filter { key, state in
                guard path == nil || key.workspacePath == path else { return false }
                if case .failed = state { return true }
                return false
            }.count
        }
    }
}

struct ToolWindowStripeButton: View {
    let id: ToolWindowID
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    private var backgroundColor: Color {
        if isSelected {
            return Color.white.opacity(0.12)
        }
        return isHovering ? Islands.hover : Color.clear
    }

    var body: some View {
        Button(action: action) {
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
        .onHover { isHovering = $0 }
    }
}
