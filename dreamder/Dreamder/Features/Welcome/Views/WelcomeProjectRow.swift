import SwiftUI

struct WelcomeProjectRow: View {
    let project: RecentProject
    let isSelected: Bool
    let model: WelcomeViewModel

    @State private var hoverState: WelcomeHoverState

    init(
        project: RecentProject,
        isSelected: Bool,
        model: WelcomeViewModel,
        hoverState: WelcomeHoverState = WelcomeHoverState()
    ) {
        self.project = project
        self.isSelected = isSelected
        self.model = model
        _hoverState = State(initialValue: hoverState)
    }

    private var iconName: String {
        project.isDirectory ? "nodes/folder" : IntelliJIcon.fileIcon(for: project.displayName)
    }

    private var fill: Color {
        if isSelected { return Islands.selection }
        return hoverState.isHovering ? Islands.hover : .clear
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(iconName)
                .resizable()
                .frame(width: 20, height: 20)
                .frame(width: WelcomeMetrics.rowIconSize, height: WelcomeMetrics.rowIconSize)
                .background {
                    RoundedRectangle(cornerRadius: Islands.controlRadius)
                        .fill(Islands.islandRaised)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(project.displayName)
                    .font(Islands.uiFont)
                    .foregroundStyle(Islands.foreground)
                    .lineLimit(1)
                Text(project.abbreviatedPath)
                    .font(Islands.smallFont)
                    .foregroundStyle(Islands.secondaryForeground)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            HStack(spacing: 2) {
                WelcomeRowButton(icon: "general/locate", help: "Reveal in Finder", action: reveal)
                WelcomeRowButton(icon: "general/copy", help: "Copy Path", action: copyPath)
                WelcomeRowButton(icon: "general/close", help: "Remove from Recent Projects", action: remove)
            }
            .opacity(hoverState.isHovering || isSelected ? 1 : 0)
        }
        .padding(.horizontal, 10)
        .frame(height: WelcomeMetrics.rowHeight)
        .background {
            RoundedRectangle(cornerRadius: Islands.rowRadius)
                .fill(fill)
        }
        .contentShape(Rectangle())
        .onHover(perform: hoverState.setHovering)
        .onTapGesture(perform: openProject)
    }

    func openProject() {
        model.open(project)
    }

    func reveal() {
        model.reveal(project)
    }

    func copyPath() {
        model.copyPath(of: project)
    }

    func remove() {
        model.remove(project)
    }
}

struct WelcomeRowButton: View {
    let icon: String
    let help: String
    let action: @MainActor () -> Void

    @State private var hoverState: WelcomeHoverState

    init(
        icon: String,
        help: String,
        hoverState: WelcomeHoverState = WelcomeHoverState(),
        action: @escaping @MainActor () -> Void
    ) {
        self.icon = icon
        self.help = help
        self.action = action
        _hoverState = State(initialValue: hoverState)
    }

    var body: some View {
        Button(action: action) {
            Image(icon)
                .resizable()
                .frame(width: 16, height: 16)
                .frame(width: 24, height: 24)
                .background {
                    RoundedRectangle(cornerRadius: Islands.rowRadius)
                        .fill(hoverState.isHovering ? Islands.actionHover : .clear)
                }
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover(perform: hoverState.setHovering)
    }
}
