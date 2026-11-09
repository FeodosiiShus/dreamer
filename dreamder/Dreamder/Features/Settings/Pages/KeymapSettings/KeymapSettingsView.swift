import SwiftUI

struct KeymapSettingsView: View {
    @State private var model: KeymapSettingsModel

    init(model: KeymapSettingsModel = KeymapSettingsModel()) {
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            KeymapToolbar(model: model)
            Rectangle()
                .fill(Islands.separator)
                .frame(height: 1)
            KeymapCommandList(model: model)
            if let hint = model.recordingHint {
                KeymapRecordingFooter(hint: hint)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Islands.island)
        .onDisappear(perform: model.cancelRecording)
    }
}

struct KeymapToolbar: View {
    @Bindable var model: KeymapSettingsModel

    var body: some View {
        HStack(spacing: 8) {
            SettingsSearchField("Search actions", text: $model.query)
            shortcutFilterButton
            Button("Reset All", action: model.resetAll)
                .disabled(model.keymap.overrides.isEmpty)
        }
        .padding(.horizontal, 12)
        .frame(height: Islands.toolWindowHeaderHeight + 4)
    }

    @ViewBuilder private var shortcutFilterButton: some View {
        if let filter = model.shortcutFilter {
            Button(action: model.clearShortcutFilter) {
                HStack(spacing: 4) {
                    Text(filter.displayText)
                        .font(Islands.codeFont)
                    Image("general/close")
                        .resizable()
                        .frame(width: 12, height: 12)
                }
            }
            .help("Clear Shortcut Filter")
        } else if model.recording == .filter {
            Button("Press a shortcut\u{2026}", action: model.cancelRecording)
        } else {
            Button(action: model.beginFilterRecording) {
                HStack(spacing: 4) {
                    Image("general/keyboard")
                        .resizable()
                        .frame(width: 14, height: 14)
                    Text("Find by Shortcut")
                }
            }
            .help("Show only actions that use a shortcut")
        }
    }
}

struct KeymapCommandList: View {
    let model: KeymapSettingsModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(model.sections) { section in
                    Section {
                        ForEach(section.commands) { command in
                            KeymapCommandRow(model: model, command: command)
                        }
                    } header: {
                        KeymapSectionHeader(title: section.group.title)
                    }
                }
                if model.sections.isEmpty {
                    Text("No matching actions")
                        .font(Islands.uiFont)
                        .foregroundStyle(Islands.secondaryForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                }
            }
        }
    }
}

struct KeymapSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(Islands.headerTitleFont)
            .foregroundStyle(Islands.foreground)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: Islands.listRowHeight + 4, alignment: .leading)
            .background(Islands.islandRaised)
    }
}

struct KeymapRecordingFooter: View {
    let hint: String

    var body: some View {
        Text(hint)
            .font(Islands.smallFont)
            .foregroundStyle(Islands.secondaryForeground)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: Islands.statusBarHeight, alignment: .leading)
            .background(Islands.islandRaised)
    }
}
