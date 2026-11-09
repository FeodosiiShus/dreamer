import Foundation
import SwiftUI

@Observable
final class Keymap {
    static let storageKey = "dreamder.keymap.overrides"

    static let shared = Keymap(defaults: .standard)

    private(set) var overrides: [KeymapCommand: [Shortcut]]

    var isRecording = false

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        self.overrides = Self.load(from: defaults)
    }

    func shortcuts(for command: KeymapCommand) -> [Shortcut] {
        overrides[command] ?? command.defaultShortcuts
    }

    func keyboardShortcut(for command: KeymapCommand, at index: Int = 0) -> KeyboardShortcut? {
        let strokes = shortcuts(for: command).compactMap(\.keyStroke)
        return strokes.indices.contains(index) ? strokes[index].keyboardShortcut : nil
    }

    func isModified(_ command: KeymapCommand) -> Bool {
        overrides[command] != nil
    }

    func conflicts(for shortcut: Shortcut, excluding command: KeymapCommand) -> [KeymapCommand] {
        KeymapCommand.allCases.filter { $0 != command && shortcuts(for: $0).contains(shortcut) }
    }

    func conflicts(of command: KeymapCommand) -> [KeymapCommand] {
        let conflicting = Set(shortcuts(for: command).flatMap { conflicts(for: $0, excluding: command) })
        return KeymapCommand.allCases.filter { conflicting.contains($0) }
    }

    func replaceShortcuts(of command: KeymapCommand, with shortcut: Shortcut) {
        store([shortcut], for: command)
    }

    func addShortcut(_ shortcut: Shortcut, to command: KeymapCommand) {
        store(shortcuts(for: command) + [shortcut], for: command)
    }

    func removeShortcut(_ shortcut: Shortcut, from command: KeymapCommand) {
        store(shortcuts(for: command).filter { $0 != shortcut }, for: command)
    }

    func removeAllShortcuts(from command: KeymapCommand) {
        store([], for: command)
    }

    func reset(_ command: KeymapCommand) {
        overrides[command] = nil
        persist()
    }

    func resetAll() {
        overrides = [:]
        persist()
    }

    private func store(_ shortcuts: [Shortcut], for command: KeymapCommand) {
        var unique: [Shortcut] = []
        for shortcut in shortcuts where !unique.contains(shortcut) {
            unique.append(shortcut)
        }
        overrides[command] = Self.sameShortcuts(unique, command.defaultShortcuts) ? nil : unique
        persist()
    }

    private func persist() {
        let stored = Dictionary(uniqueKeysWithValues: overrides.map { ($0.key.rawValue, $0.value.map(\.text)) })
        if overrides.isEmpty {
            defaults.removeObject(forKey: Self.storageKey)
        } else if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    private static func sameShortcuts(_ lhs: [Shortcut], _ rhs: [Shortcut]) -> Bool {
        Set(lhs) == Set(rhs)
    }

    private static func load(from defaults: UserDefaults) -> [KeymapCommand: [Shortcut]] {
        guard let data = defaults.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode([String: [String]].self, from: data) else { return [:] }
        var result: [KeymapCommand: [Shortcut]] = [:]
        for (identifier, texts) in stored {
            guard let command = KeymapCommand(rawValue: identifier) else { continue }
            let shortcuts = texts.compactMap(Shortcut.init(text:))
            if !sameShortcuts(shortcuts, command.defaultShortcuts) {
                result[command] = shortcuts
            }
        }
        return result
    }
}
