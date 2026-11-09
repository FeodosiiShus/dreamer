import SwiftUI

enum ActionButtonState: Equatable {
    case disabled
    case normal
    case hovered
    case pressed
    case selected

    static func resolve(
        isEnabled: Bool,
        isPressed: Bool,
        isHovering: Bool,
        isSelected: Bool = false
    ) -> ActionButtonState {
        guard isEnabled else { return .disabled }
        if isSelected { return .selected }
        if isPressed { return .pressed }
        if isHovering { return .hovered }
        return .normal
    }
}

struct ActionButtonAccent: Equatable {
    let background: Color
    let hoverShade: Color
    let pressedShade: Color

    static let run = ActionButtonAccent(
        background: Color(hex: 0x338555),
        hoverShade: Color.black.opacity(0x19 / 255),
        pressedShade: Color.black.opacity(0x28 / 255)
    )

    static let stop = ActionButtonAccent(
        background: Color(hex: 0xC54E58),
        hoverShade: Color.black.opacity(0x19 / 255),
        pressedShade: Color.black.opacity(0x28 / 255)
    )

    static let iconOverAccent = Color.white
}

struct ActionButtonLook: Equatable {
    static let disabledOpacity = 0.4

    var arc: CGFloat
    var hoverBackground: Color
    var pressedBackground: Color
    var selectedBackground: Color
    var accent: ActionButtonAccent?
    var size: CGSize?
    var insets: EdgeInsets
    var disabledOpacity: Double

    init(
        arc: CGFloat,
        hoverBackground: Color = Islands.actionHover,
        pressedBackground: Color = Islands.actionPressed,
        selectedBackground: Color? = nil,
        accent: ActionButtonAccent? = nil,
        size: CGSize? = nil,
        insets: EdgeInsets = EdgeInsets(),
        disabledOpacity: Double = ActionButtonLook.disabledOpacity
    ) {
        self.arc = arc
        self.hoverBackground = hoverBackground
        self.pressedBackground = pressedBackground
        self.selectedBackground = selectedBackground ?? pressedBackground
        self.accent = accent
        self.size = size
        self.insets = insets
        self.disabledOpacity = disabledOpacity
    }

    var cornerRadius: CGFloat {
        arc / 2
    }

    func accented(_ accent: ActionButtonAccent?) -> ActionButtonLook {
        var copy = self
        copy.accent = accent
        return copy
    }

    func fills(for state: ActionButtonState) -> [Color] {
        switch state {
        case .disabled:
            return []
        case .normal:
            return accent.map { [$0.background] } ?? []
        case .hovered:
            return accent.map { [$0.background, $0.hoverShade] } ?? [hoverBackground]
        case .pressed:
            return accent.map { [$0.background, $0.pressedShade] } ?? [pressedBackground]
        case .selected:
            return [selectedBackground]
        }
    }

    func opacity(for state: ActionButtonState) -> Double {
        state == .disabled ? disabledOpacity : 1
    }

    static let standard = ActionButtonLook(arc: 8)

    static var mainToolbarButton: ActionButtonLook {
        ActionButtonLook(arc: Islands.isCompact ? 8 : 12)
    }

    static let mainToolbarDropdown = ActionButtonLook(arc: 12)

    static let statusBarWidget = ActionButtonLook(
        arc: 4,
        hoverBackground: Islands.actionHover,
        pressedBackground: Islands.actionHover
    )

    static var toolWindowAction: ActionButtonLook {
        ActionButtonLook(
            arc: Islands.actionButtonRadius * 2,
            size: CGSize(width: Islands.actionButtonSize, height: Islands.actionButtonSize),
            disabledOpacity: 1
        )
    }

    static var toolWindowStripe: ActionButtonLook {
        ActionButtonLook(
            arc: Islands.stripeButtonRadius * 2,
            selectedBackground: Islands.stripeSelected,
            size: CGSize(width: Islands.stripeButtonWidth, height: Islands.stripeButtonHeight),
            insets: Islands.stripeButtonInsets,
            disabledOpacity: 1
        )
    }
}

struct ActionButtonChrome<Content: View>: View {
    @Environment(\.isEnabled)
    private var isEnabled

    let look: ActionButtonLook
    let isHovering: Bool
    let isPressed: Bool
    let isSelected: Bool
    private let content: Content

    init(
        look: ActionButtonLook = .standard,
        isHovering: Bool,
        isPressed: Bool,
        isSelected: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.look = look
        self.isHovering = isHovering
        self.isPressed = isPressed
        self.isSelected = isSelected
        self.content = content()
    }

    var state: ActionButtonState {
        ActionButtonState.resolve(
            isEnabled: isEnabled,
            isPressed: isPressed,
            isHovering: isHovering,
            isSelected: isSelected
        )
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: look.cornerRadius, style: .continuous)
    }

    var body: some View {
        content
            .frame(width: look.size?.width, height: look.size?.height)
            .background {
                ZStack {
                    ForEach(Array(look.fills(for: state).enumerated()), id: \.offset) { _, color in
                        shape.fill(color)
                    }
                }
            }
            .opacity(look.opacity(for: state))
            .padding(look.insets)
            .contentShape(Rectangle())
    }
}

struct ActionButtonStyle: ButtonStyle {
    var look: ActionButtonLook = .standard
    var isHovering = false
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        ActionButtonChrome(
            look: look,
            isHovering: isHovering,
            isPressed: configuration.isPressed,
            isSelected: isSelected
        ) {
            configuration.label
        }
    }
}

extension ButtonStyle where Self == ActionButtonStyle {
    static func actionButton(
        look: ActionButtonLook = .standard,
        isHovering: Bool = false,
        isSelected: Bool = false
    ) -> ActionButtonStyle {
        ActionButtonStyle(look: look, isHovering: isHovering, isSelected: isSelected)
    }
}
