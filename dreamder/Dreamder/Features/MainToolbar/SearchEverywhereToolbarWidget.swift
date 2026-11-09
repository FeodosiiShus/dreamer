import AppKit
import SwiftUI

struct SearchEverywhereToolbarWidget: View {
    private let send: @MainActor (Selector) -> Void

    init(send: @escaping @MainActor (Selector) -> Void = SearchEverywhereToolbarWidget.sendToResponderChain) {
        self.send = send
    }

    private var fieldShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: MainToolbarMetrics.searchFieldRadius, style: .continuous)
    }

    var body: some View {
        Button(action: openSearchEverywhere) {
            HStack(spacing: MainToolbarMetrics.searchFieldIconTextGap) {
                Image("general/search")
                    .resizable()
                    .interpolation(.high)
                    .frame(
                        width: MainToolbarMetrics.searchFieldIconSize,
                        height: MainToolbarMetrics.searchFieldIconSize
                    )
                Text("Search everywhere")
                    .font(Islands.uiFont)
                    .foregroundColor(Islands.secondaryForeground)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("⇧⇧")
                    .font(Islands.uiFont)
                    .foregroundColor(Islands.disabledForeground)
            }
            .padding(.horizontal, MainToolbarMetrics.searchFieldPadding)
            .frame(width: MainToolbarMetrics.searchFieldWidth, height: MainToolbarMetrics.searchFieldHeight)
            .background(fieldShape.fill(Islands.island))
            .overlay {
                fieldShape.strokeBorder(Islands.componentBorder, lineWidth: MainToolbarMetrics.searchFieldBorderWidth)
            }
            .contentShape(fieldShape)
        }
        .buttonStyle(.plain)
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
