import SwiftUI

struct MainToolbarGlass: ViewModifier {
    var isHovering = false
    var isEnabled = true

    private var tint: Color {
        isHovering && isEnabled
            ? Islands.glassHoverTint
            : Islands.glassIslandTint
    }

    func body(content: Content) -> some View {
        content
            .environment(\.colorScheme, .dark)
            .glassEffect(.regular.tint(tint).interactive(isEnabled), in: .capsule)
            .overlay {
                Capsule()
                    .strokeBorder(Islands.glassBorder, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

extension View {
    func mainToolbarGlass(isHovering: Bool = false, isEnabled: Bool = true) -> some View {
        modifier(MainToolbarGlass(isHovering: isHovering, isEnabled: isEnabled))
    }
}

struct MainToolbarIconContent: View {
    let icon: String
    var isEnabled = true
    var isHovering = false

    var body: some View {
        Image(icon)
            .resizable()
            .interpolation(.high)
            .frame(width: 16, height: 16)
            .frame(width: Islands.toolbarControlHeight, height: Islands.toolbarControlHeight)
            .mainToolbarGlass(isHovering: isHovering, isEnabled: isEnabled)
            .opacity(isEnabled ? 1.0 : 0.4)
            .contentShape(Capsule())
    }
}

@Observable
final class MainToolbarHoverState {
    var isHovering = false

    func setHovering(_ hovering: Bool) {
        isHovering = hovering
    }
}

struct MainToolbarIconButton: View {
    let icon: String
    let help: String
    var isEnabled = true
    let action: () -> Void

    @State private var hover: MainToolbarHoverState

    init(
        icon: String,
        help: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void,
        hover: MainToolbarHoverState = MainToolbarHoverState()
    ) {
        self.icon = icon
        self.help = help
        self.isEnabled = isEnabled
        self.action = action
        _hover = State(initialValue: hover)
    }

    var body: some View {
        Button(action: action) {
            MainToolbarIconContent(icon: icon, isEnabled: isEnabled, isHovering: hover.isHovering)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover(perform: hover.setHovering)
        .help(help)
        .fixedSize()
    }
}
