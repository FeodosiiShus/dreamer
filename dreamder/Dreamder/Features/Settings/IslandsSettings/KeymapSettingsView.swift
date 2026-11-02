import SwiftUI

struct KeymapSettingsView: View {
    private var bindings: [KeyboardShortcutWrapper] {
        KeybindingManager.shared.keyboardShortcuts.values
            .sorted { $0.description.localizedStandardCompare($1.description) == .orderedAscending }
    }

    var body: some View {
        SettingsForm {
            Section {
                if bindings.isEmpty {
                    Text("No key bindings")
                        .foregroundStyle(Islands.secondaryForeground)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                ForEach(bindings, id: \.id) { binding in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(binding.description)
                            Text(binding.context)
                                .font(Islands.smallFont)
                                .foregroundStyle(Islands.secondaryForeground)
                        }
                        Spacer(minLength: 8)
                        Text(KeymapShortcutDisplay.shortcut(for: binding))
                            .font(Islands.codeFont)
                            .foregroundStyle(Islands.secondaryForeground)
                    }
                }
            } header: {
                Text("Actions")
            }
        }
    }
}
