import SwiftUI

struct InlayHintCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .toolbar) {
            ToggleInlayHintsButton()
        }
    }
}

extension InlayHintCommands {
    struct ToggleInlayHintsButton: View {
        @AppSettings(\.textEditing.inlayHints.enabled)
        var enabled

        var body: some View {
            Toggle("Toggle Inlay Hints", isOn: $enabled)
                .keymapShortcut(.toggleInlayHints)
        }
    }
}
