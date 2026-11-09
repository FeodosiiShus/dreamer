import SwiftUI

struct EditorEmptyStateView: View {
    let sendAction: @MainActor (Selector) -> Void

    init(sendAction: @escaping @MainActor (Selector) -> Void) {
        self.sendAction = sendAction
    }

    var body: some View {
        VStack(spacing: 8) {
            hint(title: "Search Everywhere", keys: "Double ⇧", action: openSearchEverywhere)
            hint(title: "Go to File", keys: "⇧⌘O", action: openQuickly)
            Text("Drop files here to open them")
                .font(Islands.uiFont)
                .foregroundStyle(Islands.secondaryForeground)
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func openSearchEverywhere() {
        sendAction(#selector(DreamderWindowController.openSearchEverywhere(_:)))
    }

    func openQuickly() {
        sendAction(#selector(DreamderWindowController.openQuickly(_:)))
    }

    private func hint(title: String, keys: String, action: @escaping @MainActor () -> Void) -> some View {
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
