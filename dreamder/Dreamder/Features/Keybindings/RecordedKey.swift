import AppKit

nonisolated enum RecordedKey: Equatable, Sendable {
    case stroke(KeyStroke)
    case rejected(KeyStroke)
    case cancel
    case clear
    case unrecognized

    static func interpret(keyCode: UInt16, characters: String?, flags: NSEvent.ModifierFlags) -> RecordedKey {
        let modifiers = ShortcutModifiers(flags)
        guard let key = KeyNames.byKeyCode[keyCode] ?? KeyNames.fallbackKey(characters) else { return .unrecognized }
        if modifiers.isEmpty {
            if key == KeyNames.escape { return .cancel }
            if key == KeyNames.backspace || key == KeyNames.forwardDelete { return .clear }
        }
        let stroke = KeyStroke(key, modifiers)
        return stroke.isAssignable ? .stroke(stroke) : .rejected(stroke)
    }
}
