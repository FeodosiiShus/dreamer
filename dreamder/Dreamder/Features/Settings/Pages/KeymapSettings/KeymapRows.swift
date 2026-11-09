import SwiftUI

struct KeymapCommandRow: View {
    let model: KeymapSettingsModel
    let command: KeymapCommand

    private var conflicts: [KeymapCommand] {
        model.conflicts(of: command)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(command.title)
                    .font(Islands.uiFont)
                    .foregroundStyle(Islands.foreground)
                Spacer(minLength: 8)
                KeymapShortcutField(model: model, command: command)
                if model.keymap.isModified(command) {
                    Button(action: reset) {
                        Image("general/undo")
                            .resizable()
                            .frame(width: 12, height: 12)
                    }
                    .buttonStyle(.plain)
                    .help("Reset to Default")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: Islands.listRowHeight + 6)
            .contentShape(Rectangle())
            .contextMenu { KeymapRowMenu(model: model, command: command) }
            if !conflicts.isEmpty {
                KeymapConflictNote(text: "Also assigned to \(conflicts.map(\.title).joined(separator: ", "))")
            }
            if let pending = model.pending, pending.command == command {
                KeymapConflictRow(model: model, pending: pending)
            }
        }
    }

    func reset() {
        model.reset(command)
    }
}

struct KeymapShortcutField: View {
    let model: KeymapSettingsModel
    let command: KeymapCommand

    private var isRecording: Bool {
        model.isRecording(command)
    }

    var body: some View {
        Button(action: record) {
            Text(isRecording ? "Press a shortcut\u{2026}" : model.shortcutText(for: command))
                .font(Islands.codeFont)
                .foregroundStyle(isRecording ? Islands.accent : Islands.secondaryForeground)
                .padding(.horizontal, 8)
                .frame(minWidth: 140, minHeight: Islands.listRowHeight, alignment: .trailing)
                .overlay {
                    RoundedRectangle(cornerRadius: Islands.rowRadius)
                        .stroke(isRecording ? Islands.accent : Islands.separator, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .help("Click, then press the new shortcut")
    }

    func record() {
        model.beginRecording(command)
    }
}

struct KeymapRowMenu: View {
    let model: KeymapSettingsModel
    let command: KeymapCommand

    var body: some View {
        Button("Add Keyboard Shortcut\u{2026}", action: add)
        ForEach(model.keymap.shortcuts(for: command), id: \.self) { shortcut in
            Button("Remove \(shortcut.displayText)") { model.remove(shortcut, from: command) }
        }
        Divider()
        Button("Reset to Default", action: reset)
            .disabled(!model.keymap.isModified(command))
    }

    func add() {
        model.beginRecording(command, mode: .add)
    }

    func reset() {
        model.reset(command)
    }
}

struct KeymapConflictNote: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image("status/warning")
                .resizable()
                .frame(width: 12, height: 12)
            Text(text)
                .font(Islands.smallFont)
                .foregroundStyle(Islands.warningForeground)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }
}

struct KeymapConflictRow: View {
    let model: KeymapSettingsModel
    let pending: PendingKeymapAssignment

    var body: some View {
        HStack(spacing: 8) {
            Image("status/warning")
                .resizable()
                .frame(width: 14, height: 14)
            Text(pending.message)
                .font(Islands.smallFont)
                .foregroundStyle(Islands.warningForeground)
            Spacer(minLength: 8)
            Button("Remove", action: remove)
            Button("Leave", action: leave)
            Button("Cancel", action: cancel)
        }
        .padding(.horizontal, 12)
        .frame(height: Islands.listRowHeight + 10)
        .background(Islands.islandRaised)
    }

    func remove() {
        model.resolvePending(.remove)
    }

    func leave() {
        model.resolvePending(.leave)
    }

    func cancel() {
        model.resolvePending(.cancel)
    }
}
