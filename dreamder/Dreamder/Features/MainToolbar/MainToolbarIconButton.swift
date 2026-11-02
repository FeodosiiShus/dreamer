import SwiftUI

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
            .background {
                RoundedRectangle(cornerRadius: Islands.controlRadius)
                    .fill(isHovering && isEnabled ? Islands.actionHover : Color.clear)
            }
            .opacity(isEnabled ? 1.0 : 0.4)
            .contentShape(Rectangle())
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
