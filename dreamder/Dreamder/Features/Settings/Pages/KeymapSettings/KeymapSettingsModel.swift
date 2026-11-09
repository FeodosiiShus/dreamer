import AppKit
import Foundation

enum KeymapRecordingMode: Equatable {
    case replace
    case add
}

enum KeymapRecordingTarget: Equatable {
    case command(KeymapCommand, KeymapRecordingMode)
    case filter
}

enum KeymapConflictResolution {
    case remove
    case leave
    case cancel
}

struct PendingKeymapAssignment: Equatable {
    let command: KeymapCommand
    let shortcut: Shortcut
    let mode: KeymapRecordingMode
    let conflicts: [KeymapCommand]

    var message: String {
        "\(shortcut.displayText) is already assigned to \(conflicts.map(\.title).joined(separator: ", "))"
    }
}

struct KeymapSection: Identifiable, Equatable {
    let group: KeymapGroup
    let commands: [KeymapCommand]

    var id: String { group.title }
}

@Observable
final class KeymapSettingsModel {
    let keymap: Keymap

    var query = ""

    private(set) var shortcutFilter: Shortcut?
    private(set) var recording: KeymapRecordingTarget?
    private(set) var pending: PendingKeymapAssignment?
    private(set) var rejectedStroke: KeyStroke?

    @ObservationIgnored private let monitoring: any NSEventMonitoring
    @ObservationIgnored private var monitor: Any?

    init(keymap: Keymap = .shared, monitoring: any NSEventMonitoring = LiveNSEventMonitoring()) {
        self.keymap = keymap
        self.monitoring = monitoring
    }

    isolated deinit {
        keymap.isRecording = false
        removeMonitor()
    }

    var sections: [KeymapSection] {
        let visible = KeymapCommand.allCases.filter(isVisible)
        return KeymapGroup.allCases.compactMap { group in
            let commands = visible.filter { $0.group == group }
            return commands.isEmpty ? nil : KeymapSection(group: group, commands: commands)
        }
    }

    var recordingHint: String? {
        guard recording != nil else { return nil }
        if let rejectedStroke {
            return "\(rejectedStroke.displayText) needs \u{2318}, \u{2303} or \u{2325}. Press another shortcut."
        }
        return "Press the shortcut. Esc cancels, \u{232B} clears."
    }

    func shortcutText(for command: KeymapCommand) -> String {
        let shortcuts = keymap.shortcuts(for: command)
        return shortcuts.isEmpty ? "\u{2014}" : shortcuts.map(\.displayText).joined(separator: ", ")
    }

    func isRecording(_ command: KeymapCommand) -> Bool {
        guard case .command(let target, _) = recording else { return false }
        return target == command
    }

    func beginRecording(_ command: KeymapCommand, mode: KeymapRecordingMode = .replace) {
        start(.command(command, mode))
    }

    func beginFilterRecording() {
        start(.filter)
    }

    func cancelRecording() {
        recording = nil
        rejectedStroke = nil
        keymap.isRecording = false
        removeMonitor()
    }

    func clearShortcutFilter() {
        shortcutFilter = nil
    }

    func handleKeyDown(keyCode: UInt16, characters: String?, flags: NSEvent.ModifierFlags) -> Bool {
        guard let target = recording else { return false }
        switch RecordedKey.interpret(keyCode: keyCode, characters: characters, flags: flags) {
        case .stroke(let stroke): finish(target, with: .keyStroke(stroke))
        case .rejected(let stroke): rejectedStroke = stroke
        case .cancel: cancelRecording()
        case .clear: clear(target)
        case .unrecognized: break
        }
        return true
    }

    func resolvePending(_ resolution: KeymapConflictResolution) {
        guard let assignment = pending else { return }
        pending = nil
        switch resolution {
        case .remove:
            for command in assignment.conflicts {
                keymap.removeShortcut(assignment.shortcut, from: command)
            }
            apply(assignment.shortcut, to: assignment.command, mode: assignment.mode)
        case .leave:
            apply(assignment.shortcut, to: assignment.command, mode: assignment.mode)
        case .cancel:
            break
        }
    }

    func conflicts(of command: KeymapCommand) -> [KeymapCommand] {
        keymap.conflicts(of: command)
    }

    func remove(_ shortcut: Shortcut, from command: KeymapCommand) {
        keymap.removeShortcut(shortcut, from: command)
    }

    func reset(_ command: KeymapCommand) {
        keymap.reset(command)
    }

    func resetAll() {
        pending = nil
        keymap.resetAll()
    }

    private func isVisible(_ command: KeymapCommand) -> Bool {
        let text = query.trimmingCharacters(in: .whitespaces)
        let matchesText = text.isEmpty
            || command.title.localizedCaseInsensitiveContains(text)
            || command.group.title.localizedCaseInsensitiveContains(text)
        let matchesShortcut = shortcutFilter.map { keymap.shortcuts(for: command).contains($0) } ?? true
        return matchesText && matchesShortcut
    }

    private func start(_ target: KeymapRecordingTarget) {
        pending = nil
        rejectedStroke = nil
        recording = target
        keymap.isRecording = true
        removeMonitor()
        monitor = monitoring.addLocalMonitor(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            let characters = event.charactersIgnoringModifiers
            let flags = event.modifierFlags
            let consumed = MainActor.assumeIsolated {
                self?.handleKeyDown(keyCode: keyCode, characters: characters, flags: flags)
            } == true
            return consumed ? nil : event
        }
    }

    private func finish(_ target: KeymapRecordingTarget, with shortcut: Shortcut) {
        cancelRecording()
        switch target {
        case .filter:
            shortcutFilter = shortcut
        case .command(let command, let mode):
            assign(shortcut, to: command, mode: mode)
        }
    }

    private func clear(_ target: KeymapRecordingTarget) {
        cancelRecording()
        switch target {
        case .filter:
            shortcutFilter = nil
        case .command(let command, _):
            keymap.removeAllShortcuts(from: command)
        }
    }

    private func assign(_ shortcut: Shortcut, to command: KeymapCommand, mode: KeymapRecordingMode) {
        let conflicts = keymap.conflicts(for: shortcut, excluding: command)
        if conflicts.isEmpty {
            apply(shortcut, to: command, mode: mode)
        } else {
            pending = PendingKeymapAssignment(command: command, shortcut: shortcut, mode: mode, conflicts: conflicts)
        }
    }

    private func apply(_ shortcut: Shortcut, to command: KeymapCommand, mode: KeymapRecordingMode) {
        switch mode {
        case .replace: keymap.replaceShortcuts(of: command, with: shortcut)
        case .add: keymap.addShortcut(shortcut, to: command)
        }
    }

    private func removeMonitor() {
        if let monitor {
            monitoring.removeMonitor(monitor)
        }
        monitor = nil
    }
}
