import SwiftUI

nonisolated enum KeymapShortcutDisplay {
    static func shortcut(for binding: KeyboardShortcutWrapper) -> String {
        let modifiers = binding.parsedModifier
        var symbols = ""
        if modifiers.contains(.control) {
            symbols += "\u{2303}"
        }
        if modifiers.contains(.option) {
            symbols += "\u{2325}"
        }
        if modifiers.contains(.shift) {
            symbols += "\u{21E7}"
        }
        if modifiers.contains(.command) {
            symbols += "\u{2318}"
        }
        return symbols + binding.keybinding.uppercased()
    }
}
