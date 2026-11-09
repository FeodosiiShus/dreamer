import AppKit

extension Keymap {
    func apply(_ command: KeymapCommand, to item: NSMenuItem) {
        let stroke = shortcuts(for: command).compactMap(\.keyStroke).first
        item.keyEquivalent = stroke.map { String($0.key) } ?? ""
        item.keyEquivalentModifierMask = stroke?.modifiers.eventFlags ?? []
    }
}
