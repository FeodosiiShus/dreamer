import SwiftUI

struct KeymapShortcutModifier: ViewModifier {
    let command: KeymapCommand
    let index: Int
    let isEnabled: Bool

    @Environment(Keymap.self)
    private var injectedKeymap: Keymap?

    static func shortcut(
        for command: KeymapCommand,
        at index: Int,
        isEnabled: Bool,
        in keymap: Keymap
    ) -> KeyboardShortcut? {
        isEnabled ? keymap.keyboardShortcut(for: command, at: index) : nil
    }

    func body(content: Content) -> some View {
        content.keyboardShortcut(
            Self.shortcut(for: command, at: index, isEnabled: isEnabled, in: injectedKeymap ?? .shared)
        )
    }
}

extension View {
    func keymapShortcut(_ command: KeymapCommand, at index: Int = 0, when isEnabled: Bool = true) -> some View {
        modifier(KeymapShortcutModifier(command: command, index: index, isEnabled: isEnabled))
    }
}
