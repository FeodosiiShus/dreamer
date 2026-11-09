import SwiftUI

enum EditorTabMetrics {
    static let iconSize: CGFloat = 16
    static let iconTextGap: CGFloat = 4
    static let actionsLeadingGap: CGFloat = 2
    static let closeButtonSize: CGFloat = 16
    static let accessoryButtonSize = CGSize(width: 26, height: 24)

    static var leadingInset: CGFloat {
        Islands.isCompact ? 6 : 8
    }

    static var trailingInset: CGFloat {
        Islands.isCompact ? 4 : 8
    }
}

struct EditorTabAppearance: Equatable {
    let fill: Color
    let border: Color

    static func resolve(isSelected: Bool, isFocused: Bool, isHovering: Bool) -> EditorTabAppearance {
        if isSelected {
            if isFocused {
                return EditorTabAppearance(fill: Islands.tabSelectedBackground, border: Islands.tabSelectedBorder)
            }
            if isHovering {
                return EditorTabAppearance(fill: Islands.actionHover, border: Islands.tabInactiveSelectedBorder)
            }
            return EditorTabAppearance(
                fill: Islands.tabInactiveSelectedBackground,
                border: Islands.tabInactiveSelectedBorder
            )
        }
        if isHovering {
            return EditorTabAppearance(fill: Islands.actionHover, border: .clear)
        }
        return EditorTabAppearance(fill: .clear, border: .clear)
    }
}

struct EditorTabCloseGlyph: View {
    let state: ActionButtonState

    var body: some View {
        ZStack {
            if state == .pressed {
                Circle().fill(Islands.actionPressed)
            }
            Image(state == .normal ? "general/closeSmall" : "general/closeSmallHovered")
                .resizable()
        }
        .frame(width: EditorTabMetrics.closeButtonSize, height: EditorTabMetrics.closeButtonSize)
    }
}

struct EditorTabBarAccessoryIcon: View {
    let icon: String
    let isHovering: Bool

    var body: some View {
        ActionButtonChrome(look: .standard, isHovering: isHovering, isPressed: false) {
            Image(icon)
                .resizable()
                .frame(width: Islands.actionIconSize, height: Islands.actionIconSize)
                .frame(
                    width: EditorTabMetrics.accessoryButtonSize.width,
                    height: EditorTabMetrics.accessoryButtonSize.height
                )
        }
    }
}
