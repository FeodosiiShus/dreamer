import SwiftUI

struct WelcomeActionButton: View {
    enum Style {
        case toolbar
        case large
    }

    let title: String
    let icon: String
    let style: Style
    let action: @MainActor () -> Void

    @State private var hoverState: WelcomeHoverState

    init(
        title: String,
        icon: String,
        style: Style,
        hoverState: WelcomeHoverState = WelcomeHoverState(),
        action: @escaping @MainActor () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.style = style
        self.action = action
        _hoverState = State(initialValue: hoverState)
    }

    private var height: CGFloat {
        style == .large ? WelcomeMetrics.largeButtonHeight : Islands.toolbarControlHeight
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(icon)
                    .resizable()
                    .frame(width: 16, height: 16)
                Text(title)
                    .font(Islands.uiFont)
                    .lineLimit(1)
            }
            .foregroundStyle(Islands.foreground)
            .padding(.horizontal, style == .large ? 16 : 10)
            .frame(height: height)
            .background {
                RoundedRectangle(cornerRadius: Islands.controlRadius)
                    .fill(hoverState.isHovering ? Islands.actionHover : .clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Islands.controlRadius)
                    .stroke(style == .large ? Islands.componentBorder : .clear, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover(perform: hoverState.setHovering)
    }
}
