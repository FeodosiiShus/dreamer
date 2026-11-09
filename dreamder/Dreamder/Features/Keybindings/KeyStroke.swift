import AppKit
import SwiftUI

nonisolated struct ShortcutModifiers: OptionSet, Hashable, Sendable {
    let rawValue: Int

    static let control = ShortcutModifiers(rawValue: 1 << 0)
    static let option = ShortcutModifiers(rawValue: 1 << 1)
    static let shift = ShortcutModifiers(rawValue: 1 << 2)
    static let command = ShortcutModifiers(rawValue: 1 << 3)

    static let canonicalOrder: [(modifier: ShortcutModifiers, name: String, glyph: String)] = [
        (.control, "control", "\u{2303}"),
        (.option, "option", "\u{2325}"),
        (.shift, "shift", "\u{21E7}"),
        (.command, "command", "\u{2318}")
    ]

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    init(_ flags: NSEvent.ModifierFlags) {
        var result: ShortcutModifiers = []
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.command) { result.insert(.command) }
        self = result
    }

    init?(name: String) {
        guard let match = Self.canonicalOrder.first(where: { $0.name == name }) else { return nil }
        self = match.modifier
    }

    var eventModifiers: EventModifiers {
        var result: EventModifiers = []
        if contains(.control) { result.insert(.control) }
        if contains(.option) { result.insert(.option) }
        if contains(.shift) { result.insert(.shift) }
        if contains(.command) { result.insert(.command) }
        return result
    }

    var eventFlags: NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        if contains(.control) { result.insert(.control) }
        if contains(.option) { result.insert(.option) }
        if contains(.shift) { result.insert(.shift) }
        if contains(.command) { result.insert(.command) }
        return result
    }

    var glyphs: String {
        Self.canonicalOrder.filter { contains($0.modifier) }.map(\.glyph).joined()
    }

    var names: [String] {
        Self.canonicalOrder.filter { contains($0.modifier) }.map(\.name)
    }

    var hasMenuModifier: Bool {
        !isDisjoint(with: [.control, .option, .command])
    }
}

nonisolated enum KeyNames {
    nonisolated struct Entry: Sendable {
        let name: String
        let key: Character
        let glyph: String
    }

    static let up: Character = "\u{F700}"
    static let down: Character = "\u{F701}"
    static let left: Character = "\u{F702}"
    static let right: Character = "\u{F703}"
    static let forwardDelete: Character = "\u{F728}"
    static let home: Character = "\u{F729}"
    static let end: Character = "\u{F72B}"
    static let pageUp: Character = "\u{F72C}"
    static let pageDown: Character = "\u{F72D}"
    static let backspace: Character = "\u{7F}"
    static let enter: Character = "\r"
    static let tab: Character = "\t"
    static let escape: Character = "\u{1B}"
    static let space: Character = " "

    static let functionKeys: [Character] = [
        "\u{F704}", "\u{F705}", "\u{F706}", "\u{F707}", "\u{F708}",
        "\u{F709}", "\u{F70A}", "\u{F70B}", "\u{F70C}", "\u{F70D}",
        "\u{F70E}", "\u{F70F}", "\u{F710}", "\u{F711}", "\u{F712}",
        "\u{F713}", "\u{F714}", "\u{F715}", "\u{F716}", "\u{F717}"
    ]

    static let f1 = functionKeys[0]
    static let f2 = functionKeys[1]
    static let f6 = functionKeys[5]
    static let f7 = functionKeys[6]
    static let f12 = functionKeys[11]

    static let entries: [Entry] = namedEntries + functionKeys.enumerated().map { offset, key in
        Entry(name: "f\(offset + 1)", key: key, glyph: "F\(offset + 1)")
    }

    static let byName: [String: Entry] = Dictionary(uniqueKeysWithValues: entries.map { ($0.name, $0) })
    static let byKey: [Character: Entry] = Dictionary(uniqueKeysWithValues: entries.map { ($0.key, $0) })

    static let byKeyCode: [UInt16: Character] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v", 11: "b",
        12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t", 31: "o", 32: "u", 34: "i", 35: "p",
        37: "l", 38: "j", 40: "k", 45: "n", 46: "m",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 25: "9", 26: "7", 28: "8", 29: "0",
        24: "=", 27: "-", 30: "]", 33: "[", 39: "'", 41: ";", 42: "\\", 43: ",", 44: "/", 47: ".", 50: "`",
        36: enter, 48: tab, 49: space, 51: backspace, 53: escape,
        117: forwardDelete, 115: home, 119: end, 116: pageUp, 121: pageDown,
        123: left, 124: right, 125: down, 126: up,
        122: functionKeys[0], 120: functionKeys[1], 99: functionKeys[2], 118: functionKeys[3],
        96: functionKeys[4], 97: functionKeys[5], 98: functionKeys[6], 100: functionKeys[7],
        101: functionKeys[8], 109: functionKeys[9], 103: functionKeys[10], 111: functionKeys[11],
        105: functionKeys[12], 107: functionKeys[13], 113: functionKeys[14], 106: functionKeys[15],
        64: functionKeys[16], 79: functionKeys[17], 80: functionKeys[18], 90: functionKeys[19]
    ]

    static func isFunctionKey(_ key: Character) -> Bool {
        functionKeys.contains(key)
    }

    static func fallbackKey(_ characters: String?) -> Character? {
        guard let character = characters?.lowercased().first, characters?.count == 1 else { return nil }
        let isPlain = character.isLetter || character.isNumber || character.isPunctuation || character.isSymbol
        return isPlain ? character : nil
    }

    private static let namedEntries: [Entry] = [
        Entry(name: "up", key: up, glyph: "\u{2191}"),
        Entry(name: "down", key: down, glyph: "\u{2193}"),
        Entry(name: "left", key: left, glyph: "\u{2190}"),
        Entry(name: "right", key: right, glyph: "\u{2192}"),
        Entry(name: "home", key: home, glyph: "\u{2196}"),
        Entry(name: "end", key: end, glyph: "\u{2198}"),
        Entry(name: "pageup", key: pageUp, glyph: "\u{21DE}"),
        Entry(name: "pagedown", key: pageDown, glyph: "\u{21DF}"),
        Entry(name: "forwarddelete", key: forwardDelete, glyph: "\u{2326}"),
        Entry(name: "backspace", key: backspace, glyph: "\u{232B}"),
        Entry(name: "return", key: enter, glyph: "\u{23CE}"),
        Entry(name: "tab", key: tab, glyph: "\u{21E5}"),
        Entry(name: "escape", key: escape, glyph: "\u{238B}"),
        Entry(name: "space", key: space, glyph: "\u{2423}")
    ]
}

nonisolated struct KeyStroke: Hashable, Sendable {
    let key: Character
    let modifiers: ShortcutModifiers

    init(_ key: Character, _ modifiers: ShortcutModifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }

    init?(text: String) {
        let tokens = text.split(separator: " ").map(String.init)
        guard let last = tokens.last else { return nil }
        var parsedModifiers: ShortcutModifiers = []
        for token in tokens.dropLast() {
            guard let modifier = ShortcutModifiers(name: token) else { return nil }
            parsedModifiers.insert(modifier)
        }
        if let entry = KeyNames.byName[last.lowercased()] {
            self.init(entry.key, parsedModifiers)
        } else if last.count == 1, let character = last.lowercased().first {
            self.init(character, parsedModifiers)
        } else {
            return nil
        }
    }

    var keyboardShortcut: KeyboardShortcut {
        KeyboardShortcut(keyEquivalent, modifiers: modifiers.eventModifiers)
    }

    private var keyEquivalent: KeyEquivalent {
        switch key {
        case KeyNames.backspace: .delete
        case KeyNames.forwardDelete: .deleteForward
        default: KeyEquivalent(key)
        }
    }

    var isAssignable: Bool {
        modifiers.hasMenuModifier || KeyNames.isFunctionKey(key)
    }

    var text: String {
        (modifiers.names + [KeyNames.byKey[key]?.name ?? String(key)]).joined(separator: " ")
    }

    var displayText: String {
        modifiers.glyphs + (KeyNames.byKey[key]?.glyph ?? String(key).uppercased())
    }
}

nonisolated enum Shortcut: Hashable, Sendable {
    case keyStroke(KeyStroke)
    case doubleModifier(ShortcutModifiers)

    static func stroke(_ key: Character, _ modifiers: ShortcutModifiers = []) -> Shortcut {
        .keyStroke(KeyStroke(key, modifiers))
    }

    init?(text: String) {
        let tokens = text.split(separator: " ").map(String.init)
        if tokens.count == 2, tokens[0] == "double", let modifier = ShortcutModifiers(name: tokens[1]) {
            self = .doubleModifier(modifier)
        } else if let stroke = KeyStroke(text: text) {
            self = .keyStroke(stroke)
        } else {
            return nil
        }
    }

    var keyStroke: KeyStroke? {
        guard case .keyStroke(let stroke) = self else { return nil }
        return stroke
    }

    var text: String {
        switch self {
        case .keyStroke(let stroke): stroke.text
        case .doubleModifier(let modifier): (["double"] + modifier.names).joined(separator: " ")
        }
    }

    var displayText: String {
        switch self {
        case .keyStroke(let stroke): stroke.displayText
        case .doubleModifier(let modifier): modifier.glyphs + modifier.glyphs
        }
    }
}
