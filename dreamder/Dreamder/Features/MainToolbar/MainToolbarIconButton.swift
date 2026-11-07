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

struct MainToolbarIconButton: View {
    let icon: String
    let help: String
    var isEnabled = true
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            MainToolbarIconContent(icon: icon, isEnabled: isEnabled, isHovering: isHovering)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovering = $0 }
        .help(help)
    }
}
