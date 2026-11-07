import SwiftUI

/// A button style for overlay buttons (like close, action buttons in notifications)
struct OverlayButtonStyle: ButtonStyle {
    @Environment(\.colorScheme)
    private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10))
            .foregroundColor(.secondary)
            .frame(width: 20, height: 20, alignment: .center)
            .glassEffect(.regular.interactive(), in: .capsule)
            .shadow(
                color: Color(.black.withAlphaComponent(colorScheme == .dark ? 0.2 : 0.1)),
                radius: 5,
                x: 0,
                y: 2
            )
    }
}

extension ButtonStyle where Self == OverlayButtonStyle {
    /// A button style for overlay buttons
    static var overlay: OverlayButtonStyle {
        OverlayButtonStyle()
    }
}
