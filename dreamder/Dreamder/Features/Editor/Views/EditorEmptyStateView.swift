import SwiftUI

struct EditorEmptyStateView: View {
    var body: some View {
        VStack(spacing: 8) {
            hint(title: "Search Everywhere", keys: "Double ⇧") {
                NSApp.sendAction(#selector(DreamderWindowController.openSearchEverywhere(_:)), to: nil, from: nil)
            }
            hint(title: "Go to File", keys: "⇧⌘O") {
                NSApp.sendAction(#selector(DreamderWindowController.openQuickly(_:)), to: nil, from: nil)
            }
            Text("Drop files here to open them")
                .font(Islands.uiFont)
                .foregroundStyle(Islands.secondaryForeground)
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func hint(title: String, keys: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .foregroundStyle(Islands.secondaryForeground)
                Spacer(minLength: 16)
                Text(keys)
                    .foregroundStyle(Islands.disabledForeground)
            }
            .font(Islands.uiFont)
            .frame(width: 280)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
