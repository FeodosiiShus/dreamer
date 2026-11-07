import AppKit
import SwiftUI

struct SearchEverywhereToolbarWidget: View {
    @State private var isHovering = false

    var body: some View {
        Button(action: openSearchEverywhere) {
            HStack(spacing: 6) {
                Image("general/search")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 14, height: 14)
                Text("Search everywhere")
                    .font(Islands.uiFont)
                    .foregroundColor(Islands.secondaryForeground)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("⇧⇧")
                    .font(Islands.smallFont)
                    .foregroundColor(Islands.disabledForeground)
            }
            .padding(.horizontal, 12)
            .frame(width: 260, height: Islands.toolbarControlHeight)
            .mainToolbarGlass(isHovering: isHovering)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Search everywhere")
        .accessibilityLabel("Search everywhere")
    }

    private func openSearchEverywhere() {
        NSApp.sendAction(
            #selector(DreamderWindowController.openSearchEverywhere(_:)),
            to: nil,
            from: nil
        )
    }
}
