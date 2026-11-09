import SwiftUI

struct MainToolbarIconContent: View {
    let icon: String
    var size: CGFloat = MainToolbarMetrics.iconSize
    var tint: Color?

    var body: some View {
        glyph
            .frame(width: size, height: size)
            .frame(width: MainToolbarMetrics.buttonSize, height: MainToolbarMetrics.buttonSize)
    }

    @ViewBuilder private var glyph: some View {
        if let tint {
            Image(icon)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .foregroundStyle(tint)
        } else {
            Image(icon)
                .resizable()
                .interpolation(.high)
        }
    }
}

struct MainToolbarDropdownLabel<Leading: View>: View {
    let text: String
    private let leading: Leading

    init(text: String, @ViewBuilder leading: () -> Leading) {
        self.text = text
        self.leading = leading()
    }

    var body: some View {
        HStack(spacing: MainToolbarMetrics.dropdownIconTextGap) {
            leading
            HStack(spacing: MainToolbarMetrics.chevronGap) {
                Text(text)
                    .font(Islands.uiFont)
                    .foregroundColor(Islands.foreground)
                    .lineLimit(1)
                Image("general/chevronDown")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: MainToolbarMetrics.chevronSize, height: MainToolbarMetrics.chevronSize)
            }
        }
        .padding(MainToolbarMetrics.dropdownMargin)
        .frame(height: MainToolbarMetrics.buttonSize)
        .frame(maxWidth: MainToolbarMetrics.dropdownMaxWidth)
    }
}

extension MainToolbarDropdownLabel where Leading == EmptyView {
    init(text: String) {
        self.init(text: text) { EmptyView() }
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
    var iconSize = MainToolbarMetrics.iconSize
    var tint: Color?
    var accent: ActionButtonAccent?
    let action: () -> Void

    @State private var hover: MainToolbarHoverState

    init(
        icon: String,
        help: String,
        isEnabled: Bool = true,
        iconSize: CGFloat = MainToolbarMetrics.iconSize,
        tint: Color? = nil,
        accent: ActionButtonAccent? = nil,
        action: @escaping () -> Void,
        hover: MainToolbarHoverState = MainToolbarHoverState()
    ) {
        self.icon = icon
        self.help = help
        self.isEnabled = isEnabled
        self.iconSize = iconSize
        self.tint = tint
        self.accent = accent
        self.action = action
        _hover = State(initialValue: hover)
    }

    var look: ActionButtonLook {
        ActionButtonLook.mainToolbarButton.accented(accent)
    }

    var body: some View {
        Button(action: action) {
            MainToolbarIconContent(icon: icon, size: iconSize, tint: tint)
        }
        .buttonStyle(.actionButton(look: look, isHovering: hover.isHovering))
        .disabled(!isEnabled)
        .onHover(perform: hover.setHovering)
        .help(help)
        .accessibilityLabel(help)
        .fixedSize()
    }
}
