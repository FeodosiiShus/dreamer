import AppKit
import SwiftUI

struct SearchEverywhereToolbarWidget: View {
    @State private var hover: MainToolbarHoverState
    private let send: @MainActor (Selector) -> Void

    init(
        hover: MainToolbarHoverState = MainToolbarHoverState(),
        send: @escaping @MainActor (Selector) -> Void = SearchEverywhereToolbarWidget.sendToResponderChain
    ) {
        _hover = State(initialValue: hover)
        self.send = send
    }

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
            .mainToolbarGlass(isHovering: hover.isHovering)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover(perform: hover.setHovering)
        .help("Search everywhere")
        .accessibilityLabel("Search everywhere")
        .fixedSize()
    }

    static func sendToResponderChain(_ action: Selector) {
        _ = NSApp.sendAction(action, to: nil, from: nil)
    }

    func openSearchEverywhere() {
        send(#selector(DreamderWindowController.openSearchEverywhere(_:)))
    }
}
