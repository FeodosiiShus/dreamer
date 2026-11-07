import SwiftUI

struct ToolWindowHeader<Tabs: View, Actions: View>: View {
    let title: String
    let tabs: Tabs
    let actions: Actions

    init(
        title: String,
        @ViewBuilder tabs: () -> Tabs = { EmptyView() },
        @ViewBuilder actions: () -> Actions = { EmptyView() }
    ) {
        self.title = title
        self.tabs = tabs()
        self.actions = actions()
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(Islands.headerTitleFont)
                .foregroundStyle(Islands.foreground)
                .lineLimit(1)
                .fixedSize()
            tabs
            Spacer(minLength: 8)
            HStack(spacing: 2) {
                actions
            }
        }
        .padding(.horizontal, 12)
        .frame(height: Islands.toolWindowHeaderHeight)
    }
}

struct ToolWindowTab: View {
    let title: String
    var icon: String?
    let isSelected: Bool
    var onClose: (() -> Void)?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(icon)
                    .resizable()
                    .frame(width: 14, height: 14)
            }
            Text(title)
                .font(Islands.uiFont)
                .foregroundStyle(isSelected ? Islands.foreground : Islands.secondaryForeground)
                .lineLimit(1)
            if let onClose, isSelected || isHovering {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Islands.secondaryForeground)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: Islands.tabPillHeight)
        .background(
            RoundedRectangle(cornerRadius: Islands.controlRadius)
                .fill(isSelected ? Islands.actionHover : (isHovering ? Islands.hover : .clear))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onHover { isHovering = $0 }
    }
}

struct ToolWindowActionButton: View {
    let systemImage: String?
    let icon: String?
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    init(systemImage: String, help: String, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.icon = nil
        self.help = help
        self.action = action
    }

    init(icon: String, help: String, action: @escaping () -> Void) {
        self.systemImage = nil
        self.icon = icon
        self.help = help
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let icon {
                    Image(icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Islands.secondaryForeground)
                }
            }
            .frame(width: 26, height: 26)
            .background(
                RoundedRectangle(cornerRadius: Islands.controlRadius)
                    .fill(isHovering ? Islands.actionHover : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovering = $0 }
    }
}

struct IslandBackground: ViewModifier {
    @AppStorage(Islands.BackgroundImageKey.path)
    private var imagePath = ""
    @AppStorage(Islands.BackgroundImageKey.opacity)
    private var imageOpacity = Islands.BackgroundImageKey.defaultOpacity

    func body(content: Content) -> some View {
        content
            .background(Islands.island.opacity(imagePath.isEmpty ? 1 : 1 - imageOpacity))
            .clipShape(RoundedRectangle(cornerRadius: Islands.islandRadius, style: .continuous))
    }
}

struct GlassSurface: ViewModifier {
    let radius: CGFloat
    let tint: Color
    let followsBackgroundImage: Bool

    @AppStorage(Islands.BackgroundImageKey.path)
    private var imagePath = ""
    @AppStorage(Islands.BackgroundImageKey.opacity)
    private var imageOpacity = Islands.BackgroundImageKey.defaultOpacity

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    private var tintOpacity: Double {
        guard followsBackgroundImage, !imagePath.isEmpty else { return Islands.glassTintOpacity }
        return 1 - imageOpacity
    }

    func body(content: Content) -> some View {
        content
            .background(tint.opacity(tintOpacity), in: shape)
            .glassEffect(.regular, in: shape)
            .overlay {
                shape
                    .strokeBorder(Islands.glassBorder, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .environment(\.colorScheme, .dark)
    }
}

extension View {
    func island() -> some View {
        modifier(IslandBackground())
    }

    func glassIsland() -> some View {
        modifier(GlassSurface(radius: Islands.islandRadius, tint: Islands.island, followsBackgroundImage: true))
    }

    func glassPopup(radius: CGFloat = Islands.popupRadius) -> some View {
        modifier(GlassSurface(radius: radius, tint: Islands.popup, followsBackgroundImage: false))
    }
}
