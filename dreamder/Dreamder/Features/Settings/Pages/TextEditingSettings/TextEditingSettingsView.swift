//
//  TextEditingSettingsView.swift
//  Dreamder
//
//  Created by Austin Condiff on 4/2/23.
//

import SwiftUI

/// A view that implements the `Text Editing` settings page
struct TextEditingSettingsView: View {
    @AppSettings(\.textEditing)
    var textEditing

    @State private var isShowingInvisibleCharacterSettings = false
    @State private var isShowingWarningCharactersSettings = false

    var body: some View {
        SettingsForm {
            Section {
                indentOption
                defaultTabWidth
                wrapLinesToEditorWidth
                useSystemCursor
                overscroll
            }
            Section {
                showGutter
                showMinimap
                showFoldingRibbon
                reformatSettings
            }
            Section {
                fontSelector
                fontSizeSelector
                fontWeightSelector
                lineHeight
                letterSpacing
            }
            Section {
                autocompleteBraces
                enableTypeOverCompletion
            }
            Section("Actions on save") {
                formatOnSave
                stripTrailingSpaces
                keepTrailingSpacesOnCaretLine
                ensureFinalNewline
            }
            Section("Inlay hints") {
                inlayHintsEnabled
                inlayParameterNames
                inlayTypes
                inlayReturnTypes
            }
            Section {
                bracketPairHighlight
            }
            Section {
                invisibles
                warningCharacters
            }
        }
    }

    func intBinding(_ keyPath: WritableKeyPath<SettingsData.TextEditingSettings, Int>) -> Binding<Double> {
        Binding<Double>(
            get: { Double(textEditing[keyPath: keyPath]) },
            set: { textEditing[keyPath: keyPath] = Int($0) }
        )
    }

    func openInvisibleCharacterSettings() {
        isShowingInvisibleCharacterSettings = true
    }

    func openWarningCharactersSettings() {
        isShowingWarningCharactersSettings = true
    }

    func openInvisibleCharacterSettingsIfEnabled() {
        if textEditing.invisibleCharacters.enabled {
            openInvisibleCharacterSettings()
        }
    }

    func openWarningCharactersSettingsIfEnabled() {
        if textEditing.warningCharacters.enabled {
            openWarningCharactersSettings()
        }
    }

    func invisiblesSheetContent() -> some View {
        InvisiblesSettingsView(invisibleCharacters: $textEditing.invisibleCharacters)
    }

    func warningCharactersSheetContent() -> some View {
        WarningCharactersView(warningCharacters: $textEditing.warningCharacters)
    }
}

private extension TextEditingSettingsView {
    @ViewBuilder private var fontSelector: some View {
        MonospacedFontPicker(title: "Font", selectedFontName: $textEditing.font.name)
    }

    @ViewBuilder private var fontSizeSelector: some View {
        Stepper(
            "Font Size",
            value: $textEditing.font.size,
            in: 1...288,
            step: 1,
            format: .number
        )
    }

    @ViewBuilder private var inlayHintsEnabled: some View {
        Toggle("Show inlay hints", isOn: $textEditing.inlayHints.enabled)
    }

    @ViewBuilder private var inlayParameterNames: some View {
        Picker("Parameter name hints", selection: $textEditing.inlayHints.parameterNames) {
            Text("None").tag(InlayHintSettings.ParameterNameHints.none)
            Divider()
            Text("Literals").tag(InlayHintSettings.ParameterNameHints.literals)
            Text("All").tag(InlayHintSettings.ParameterNameHints.all)
        }
        .disabled(!textEditing.inlayHints.enabled)
    }

    @ViewBuilder private var inlayTypes: some View {
        Toggle("Type hints", isOn: $textEditing.inlayHints.types)
            .disabled(!textEditing.inlayHints.enabled)
    }

    @ViewBuilder private var inlayReturnTypes: some View {
        Toggle("Return type hints", isOn: $textEditing.inlayHints.returnTypes)
            .disabled(!textEditing.inlayHints.enabled)
    }

    @ViewBuilder private var fontWeightSelector: some View {
        FontWeightPicker(selection: $textEditing.font.weight)
    }

    @ViewBuilder private var autocompleteBraces: some View {
        Toggle(isOn: $textEditing.autocompleteBraces) {
            Text("Autocomplete braces")
            Text("Automatically insert closing braces (\"}\")")
        }
    }

    @ViewBuilder private var enableTypeOverCompletion: some View {
        Toggle("Enable type-over completion", isOn: $textEditing.enableTypeOverCompletion)
    }

    @ViewBuilder private var stripTrailingSpaces: some View {
        Picker("Remove trailing spaces on", selection: $textEditing.stripTrailingSpaces) {
            Text("None").tag(TrailingSpacesMode.none)
            Divider()
            Text("Modified lines").tag(TrailingSpacesMode.modifiedLines)
            Text("All lines").tag(TrailingSpacesMode.allLines)
        }
    }

    @ViewBuilder private var keepTrailingSpacesOnCaretLine: some View {
        Toggle("Keep trailing spaces on caret line", isOn: $textEditing.keepTrailingSpacesOnCaretLine)
            .disabled(textEditing.stripTrailingSpaces == .none)
    }

    @ViewBuilder private var ensureFinalNewline: some View {
        Toggle("Ensure every saved file ends with a line break", isOn: $textEditing.ensureFinalNewline)
    }

    @ViewBuilder private var formatOnSave: some View {
        Toggle("Format on save", isOn: $textEditing.formatOnSave)
    }

    @ViewBuilder private var wrapLinesToEditorWidth: some View {
        Toggle("Wrap lines to editor width", isOn: $textEditing.wrapLinesToEditorWidth)
    }

    @ViewBuilder private var useSystemCursor: some View {
        Toggle("Use System Cursor", isOn: $textEditing.useSystemCursor)
    }

    @ViewBuilder private var overscroll: some View {
        Group {
            Picker(
                "Editor Overscroll",
                selection: $textEditing.overscroll
            ) {
                Text("None")
                    .tag(SettingsData.TextEditingSettings.OverscrollOption.none)
                Divider()
                Text("Small")
                    .tag(
                        SettingsData.TextEditingSettings.OverscrollOption.small
                    )
                Text("Medium")
                    .tag(
                        SettingsData.TextEditingSettings.OverscrollOption.medium
                    )
                Text("Large")
                    .tag(
                        SettingsData.TextEditingSettings.OverscrollOption.large
                    )
            }
        }
    }

    @ViewBuilder private var lineHeight: some View {
        Stepper(
            "Line Height",
            value: $textEditing.lineHeightMultiple,
            in: 0.75...2.0,
            step: 0.05,
            format: .number
        )
    }

    @ViewBuilder private var indentOption: some View {
        Group {
            Picker("Prefer Indent Using", selection: $textEditing.indentOption.indentType) {
                Text("Tabs")
                    .tag(SettingsData.TextEditingSettings.IndentOption.IndentType.tab)
                Text("Spaces")
                    .tag(SettingsData.TextEditingSettings.IndentOption.IndentType.spaces)
            }
            if textEditing.indentOption.indentType == .spaces {
                HStack {
                    Stepper(
                        "Indent Width",
                        value: intBinding(\.indentOption.spaceCount),
                        in: 0...10,
                        step: 1,
                        format: .number
                    )
                    Text("spaces")
                        .foregroundColor(.secondary)
                }
                .help("The number of spaces to insert when the tab key is pressed.")
            }
        }
    }

    @ViewBuilder private var defaultTabWidth: some View {
        HStack(alignment: .top) {
            Stepper(
                "Tab Width",
                value: intBinding(\.defaultTabWidth),
                in: 1...16,
                step: 1,
                format: .number
            )
            Text("spaces")
                .foregroundColor(.secondary)
        }
        .help("The visual width of tabs.")
    }

    @ViewBuilder private var letterSpacing: some View {
        Stepper(
            "Letter Spacing",
            value: $textEditing.letterSpacing,
            in: 0.5...2.0,
            step: 0.05,
            format: .number
        )
    }

    @ViewBuilder private var bracketPairHighlight: some View {
        Group {
            Picker(
                "Bracket Pair Highlight",
                selection: $textEditing.bracketEmphasis.highlightType
            ) {
                Text("Disabled").tag(SettingsData.TextEditingSettings.BracketPairEmphasis.HighlightType.disabled)
                Divider()
                Text("Bordered").tag(SettingsData.TextEditingSettings.BracketPairEmphasis.HighlightType.bordered)
                Text("Flash").tag(SettingsData.TextEditingSettings.BracketPairEmphasis.HighlightType.flash)
                Text("Underline").tag(SettingsData.TextEditingSettings.BracketPairEmphasis.HighlightType.underline)
            }
            if [.bordered, .underline].contains(textEditing.bracketEmphasis.highlightType) {
                Toggle("Use Custom Color", isOn: $textEditing.bracketEmphasis.useCustomColor)
                SettingsColorPicker(
                    "Bracket Pair Highlight Color",
                    color: $textEditing.bracketEmphasis.color.swiftColor
                )
                .foregroundColor(
                    textEditing.bracketEmphasis.useCustomColor
                        ? Color(.labelColor)
                        : Color(.secondaryLabelColor)
                )
                .disabled(!textEditing.bracketEmphasis.useCustomColor)
            }
        }
    }

    @ViewBuilder private var showGutter: some View {
        Toggle("Show Gutter", isOn: $textEditing.showGutter)
            .help("The gutter displays line numbers and code folding regions.")
    }

    @ViewBuilder private var showMinimap: some View {
        Toggle("Show Minimap", isOn: $textEditing.showMinimap)
            // swiftlint:disable:next line_length
            .help("The minimap gives you a high-level summary of your source code, with controls to quickly navigate your document.")
    }

    @ViewBuilder private var showFoldingRibbon: some View {
        Toggle("Show Code Folding Ribbon", isOn: $textEditing.showFoldingRibbon)
            .disabled(!textEditing.showGutter) // Disabled when the gutter is disabled
            // swiftlint:disable:next line_length
            .help("The code folding ribbon lets you fold regions of code. When the gutter is disabled, the folding ribbon is disabled.")
    }

    @ViewBuilder private var reformatSettings: some View {
        Toggle("Show Reformatting Guide", isOn: $textEditing.showReformattingGuide)
            .help("Shows a vertical guide at the reformat column.")

        Stepper(
            "Reformat at Column",
            value: intBinding(\.reformatAtColumn),
            in: 40...200,
            step: 1,
            format: .number
        )
        .help("The column at which text should be reformatted.")
    }

    @ViewBuilder private var invisibles: some View {
        HStack {
            Text("Show Invisible Characters")
            Spacer()
            Toggle(isOn: $textEditing.invisibleCharacters.enabled, label: { EmptyView() })
            Button(action: openInvisibleCharacterSettings) {
                Text("Configure...")
            }
            .disabled(textEditing.invisibleCharacters.enabled == false)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: openInvisibleCharacterSettingsIfEnabled)
        .sheet(isPresented: $isShowingInvisibleCharacterSettings, content: invisiblesSheetContent)
    }

    @ViewBuilder private var warningCharacters: some View {
        HStack {
            Text("Show Warning Characters")
            Spacer()
            Toggle(isOn: $textEditing.warningCharacters.enabled, label: { EmptyView() })
            Button(action: openWarningCharactersSettings) {
                Text("Configure...")
            }
            .disabled(textEditing.warningCharacters.enabled == false)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: openWarningCharactersSettingsIfEnabled)
        .sheet(isPresented: $isShowingWarningCharactersSettings, content: warningCharactersSheetContent)
    }
}
