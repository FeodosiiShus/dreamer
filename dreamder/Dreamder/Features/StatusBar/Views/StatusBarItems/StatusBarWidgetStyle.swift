import SwiftUI

enum StatusBarWidgetMetrics {
    static let horizontalPadding: CGFloat = 4
    static let widgetSpacing: CGFloat = 8
    static let barPadding: CGFloat = 4
    static let hoverHeight: CGFloat = 20
    static let iconSize: CGFloat = 16
    static let foreground = Color(hex: 0x9FA2A8)
    static let hoverForeground = Color(hex: 0xD1D3D9)

    static var font: Font {
        Islands.uiFont
    }

    static func foregroundColor(isHovering: Bool) -> Color {
        isHovering ? hoverForeground : foreground
    }
}

struct StatusBarWidgetText: View {
    let text: String
    var isHovering = false

    var body: some View {
        Text(text)
            .font(StatusBarWidgetMetrics.font)
            .foregroundColor(StatusBarWidgetMetrics.foregroundColor(isHovering: isHovering))
            .lineLimit(1)
    }
}

extension View {
    func statusBarWidgetFrame() -> some View {
        padding(.horizontal, StatusBarWidgetMetrics.horizontalPadding)
            .frame(height: StatusBarWidgetMetrics.hoverHeight)
    }

    func statusBarWidgetChrome(isHovering: Bool) -> some View {
        ActionButtonChrome(look: .statusBarWidget, isHovering: isHovering, isPressed: false) {
            statusBarWidgetFrame()
        }
    }
}

struct StatusBarWidgetButton<Label: View>: View {
    let action: () -> Void
    private let label: (Bool) -> Label

    @State private var isHovering: Bool

    init(
        isHovering: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping (Bool) -> Label
    ) {
        self.action = action
        self.label = label
        _isHovering = State(initialValue: isHovering)
    }

    func setHovering(_ hovering: Bool) {
        isHovering = hovering
    }

    var body: some View {
        Button(action: action) {
            label(isHovering).statusBarWidgetFrame()
        }
        .buttonStyle(.actionButton(look: .statusBarWidget, isHovering: isHovering))
        .onHover(perform: setHovering)
    }
}
