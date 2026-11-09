import Foundation

extension SettingsData.TextEditingSettings {

    func populateCommands() {
        populateCommands(manager: .shared, settings: SettingsData.TextEditingSettings.sharedStore)
    }

    /// Adds toggle-able preferences to the command palette via shared `CommandManager`
    func populateCommands(
        manager mgr: CommandManager,
        settings: @escaping @MainActor () -> Settings
    ) {
        mgr.addCommand(
            name: "Toggle Type-Over Completion",
            title: "Toggle Type-Over Completion",
            id: "prefs.text_editing.type_over_completion",
            command: {
                settings().preferences.textEditing.enableTypeOverCompletion.toggle()
            }
        )

        mgr.addCommand(
            name: "Toggle Autocomplete Braces",
            title: "Toggle Autocomplete Braces",
            id: "prefs.text_editing.autocomplete_braces",
            command: {
                settings().preferences.textEditing.autocompleteBraces.toggle()
            }
        )

        mgr.addCommand(
            name: "Toggle Word Wrap",
            title: "Toggle Word Wrap",
            id: "prefs.text_editing.wrap_lines_to_editor_width",
            command: {
                settings().preferences.textEditing.wrapLinesToEditorWidth.toggle()
            }
        )

        mgr.addCommand(name: "Toggle Minimap", title: "Toggle Minimap", id: "prefs.text_editing.toggle_minimap") {
            settings().preferences.textEditing.showMinimap.toggle()
        }

        mgr.addCommand(name: "Toggle Gutter", title: "Toggle Gutter", id: "prefs.text_editing.toggle_gutter") {
            settings().preferences.textEditing.showGutter.toggle()
        }

        mgr.addCommand(
            name: "Toggle Folding Ribbon",
            title: "Toggle Folding Ribbon",
            id: "prefs.text_editing.toggle_folding_ribbon"
        ) {
            settings().preferences.textEditing.showFoldingRibbon.toggle()
        }
    }

    @MainActor
    static func sharedStore() -> Settings {
        SettingsScope.current ?? .shared
    }
}
