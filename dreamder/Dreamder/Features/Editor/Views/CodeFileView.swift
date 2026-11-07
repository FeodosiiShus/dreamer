//
//  CodeFileView.swift
//  DreamderModules/CodeFile
//
//  Created by Marco Carnevali on 17/03/22.
//

import Foundation
import SwiftUI
import CodeEditSourceEditor
import CodeEditTextView
import CodeEditLanguages
import Combine

/// CodeFileView is just a wrapper of the `CodeEditor` dependency
struct CodeFileView: View {
    @ObservedObject private var editorInstance: EditorInstance
    private let codeFile: CodeFileDocument

    @StateObject private var sessionStore = CodeFileViewSessionStore()

    /// Any coordinators passed to the view.
    private var textViewCoordinators: [TextViewCoordinator]

    @AppSettings(\.textEditing.defaultTabWidth)
    var defaultTabWidth
    @AppSettings(\.textEditing.indentOption)
    var indentOption
    @AppSettings(\.textEditing.lineHeightMultiple)
    var lineHeightMultiple
    @AppSettings(\.textEditing.wrapLinesToEditorWidth)
    var wrapLinesToEditorWidth
    @AppSettings(\.textEditing.overscroll)
    var overscroll
    @AppSettings(\.textEditing.font)
    var settingsFont
    @AppSettings(\.theme.useThemeBackground)
    var useThemeBackground
    @AppSettings(\.theme.matchAppearance)
    var matchAppearance
    @AppSettings(\.textEditing.letterSpacing)
    var letterSpacing
    @AppSettings(\.textEditing.bracketEmphasis)
    var bracketEmphasis
    @AppSettings(\.textEditing.useSystemCursor)
    var useSystemCursor
    @AppSettings(\.textEditing.showGutter)
    var showGutter
    @AppSettings(\.textEditing.showMinimap)
    var showMinimap
    @AppSettings(\.textEditing.showFoldingRibbon)
    var showFoldingRibbon
    @AppSettings(\.textEditing.reformatAtColumn)
    var reformatAtColumn
    @AppSettings(\.textEditing.showReformattingGuide)
    var showReformattingGuide
    @AppSettings(\.textEditing.invisibleCharacters)
    var invisibleCharactersConfiguration
    @AppSettings(\.textEditing.warningCharacters)
    var warningCharacters

    @EnvironmentObject var undoRegistration: UndoManagerRegistration

    @ObservedObject private var themeModel: ThemeModel = .shared

    private let isEditable: Bool

    init(
        editorInstance: EditorInstance,
        codeFile: CodeFileDocument,
        textViewCoordinators: [TextViewCoordinator] = [],
        isEditable: Bool = true
    ) {
        self._editorInstance = .init(wrappedValue: editorInstance)
        self.codeFile = codeFile

        self.textViewCoordinators = textViewCoordinators
        self.isEditable = isEditable

        if let openOptions = codeFile.openOptions {
            codeFile.openOptions = nil
            editorInstance.cursorPositions = openOptions.cursorPositions
        }
    }

    private var currentTheme: Theme? {
        themeModel.selectedTheme ?? themeModel.themes.first
    }

    @AppStorage(Islands.BackgroundImageKey.path)
    private var backgroundImagePath = ""

    private func editorTheme(for theme: Theme) -> EditorTheme {
        var editorTheme = theme.editor.editorTheme
        if !backgroundImagePath.isEmpty {
            editorTheme.background = NSColor(srgbRed: 25 / 255, green: 26 / 255, blue: 28 / 255, alpha: 0)
        }
        return editorTheme
    }

    @State private var font: NSFont = Settings[\.textEditing].font.current

    @Environment(\.edgeInsets)
    private var edgeInsets

    var body: some View {
        if let theme = currentTheme {
            sourceEditor(
                theme: theme,
                session: sessionStore.session(editorInstance: editorInstance, codeFile: codeFile)
            )
        } else {
            Color.clear
        }
    }

    private func coordinators(for session: CodeFileViewSession) -> [TextViewCoordinator] {
        var coordinators = textViewCoordinators
        coordinators.append(editorInstance.rangeTranslator)
        coordinators.append(codeFile.contentCoordinator)
        coordinators.append(codeFile.languageServerObjects.textCoordinator)
        coordinators.append(contentsOf: session.coordinators)
        return coordinators
    }

    private func sourceEditor(theme: Theme, session: CodeFileViewSession) -> some View {
        let triggerCharacters = session.completionTriggerCharacters(
            requested: codeFile.languageServerObjects.completionDelegate?.completionTriggerCharacters() ?? []
        )
        return SourceEditor(
            codeFile.content ?? NSTextStorage(),
            language: codeFile.getLanguage(),
            configuration: SourceEditorConfiguration(
                appearance: .init(
                    theme: editorTheme(for: theme),
                    useThemeBackground: useThemeBackground,
                    font: font,
                    lineHeightMultiple: lineHeightMultiple,
                    letterSpacing: letterSpacing,
                    wrapLines: wrapLinesToEditorWidth,
                    useSystemCursor: useSystemCursor,
                    tabWidth: defaultTabWidth,
                    bracketPairEmphasis: getBracketPairEmphasis(for: theme)
                ),
                behavior: .init(
                    isEditable: isEditable,
                    indentOption: indentOption.textViewOption(),
                    reformatAtColumn: reformatAtColumn
                ),
                layout: .init(
                    editorOverscroll: overscroll.overscrollPercentage,
                    contentInsets: edgeInsets.nsEdgeInsets,
                    additionalTextInsets: NSEdgeInsets(top: 2, left: 0, bottom: 0, right: 0)
                ),
                peripherals: .init(
                    showGutter: showGutter,
                    showMinimap: showMinimap,
                    showReformattingGuide: showReformattingGuide,
                    showFoldingRibbon: showFoldingRibbon,
                    invisibleCharactersConfiguration: invisibleCharactersConfiguration.textViewOption(),
                    warningCharacters: Set(warningCharacters.characters.keys),
                    codeSuggestionTriggerCharacters: triggerCharacters
                )
            ),
            state: Binding(
                get: {
                    SourceEditorState(
                        cursorPositions: editorInstance.cursorPositions,
                        scrollPosition: editorInstance.scrollPosition,
                        findText: editorInstance.findText,
                        replaceText: editorInstance.replaceText
                    )
                },
                set: { newState in
                    let cursorPositions = newState.cursorPositions ?? []
                    if editorInstance.cursorPositions != cursorPositions {
                        editorInstance.cursorPositions = cursorPositions
                    }
                    if editorInstance.scrollPosition != newState.scrollPosition {
                        editorInstance.scrollPosition = newState.scrollPosition
                    }
                    if editorInstance.findText != newState.findText {
                        editorInstance.findText = newState.findText
                        editorInstance.findTextSubject.send(newState.findText)
                    }
                    if editorInstance.replaceText != newState.replaceText {
                        editorInstance.replaceText = newState.replaceText
                        editorInstance.replaceTextSubject.send(newState.replaceText)
                    }
                }
            ),
            highlightProviders: [
                codeFile.languageServerObjects.highlightProvider,
                session.treeSitterClient
            ],
            undoManager: undoRegistration.manager(forFile: editorInstance.file),
            coordinators: coordinators(for: session),
            completionDelegate: codeFile.languageServerObjects.completionDelegate,
            jumpToDefinitionDelegate: codeFile.languageServerObjects.jumpToDefinitionDelegate
        )
        // This view needs to refresh when the codefile changes. The file URL is too stable.
        .id(session.identity)
        .colorScheme(theme.appearance == .dark ? .dark : .light)
        // minHeight zero fixes a bug where the app would freeze if the contents of the file are empty.
        .frame(minHeight: .zero, maxHeight: .infinity)
        .onChange(of: settingsFont) { _, newFontSetting in
            font = newFontSetting.current
        }
    }

    /// Determines the style of bracket emphasis based on the `bracketEmphasis` setting and the current theme.
    /// - Returns: The emphasis style to use for bracket pair emphasis.
    private func getBracketPairEmphasis(for theme: Theme) -> BracketPairEmphasis? {
        let color = if Settings[\.textEditing].bracketEmphasis.useCustomColor {
            Settings[\.textEditing].bracketEmphasis.color.nsColor
        } else {
            theme.editor.text.nsColor.withAlphaComponent(0.8)
        }

        switch Settings[\.textEditing].bracketEmphasis.highlightType {
        case .disabled:
            return nil
        case .flash:
            return .flash
        case .bordered:
            return .bordered(color: color)
        case .underline:
            return .underline(color: color)
        }
    }
}

// This extension is kept here because it should not be used elsewhere in the app and may cause confusion
// due to the similar type name from the CETV module.
private extension SettingsData.TextEditingSettings.IndentOption {
    func textViewOption() -> IndentOption {
        switch self.indentType {
        case .spaces:
            return IndentOption.spaces(count: spaceCount)
        case .tab:
            return IndentOption.tab
        }
    }
}

private extension SettingsData.TextEditingSettings.InvisibleCharactersConfig {
    func textViewOption() -> InvisibleCharactersConfiguration {
        guard self.enabled else { return .empty }
        var config = InvisibleCharactersConfiguration(
            showSpaces: self.showSpaces,
            showTabs: self.showTabs,
            showLineEndings: self.showLineEndings
        )

        config.spaceReplacement = self.spaceReplacement
        config.tabReplacement = self.tabReplacement
        config.carriageReturnReplacement = self.carriageReturnReplacement
        config.lineFeedReplacement = self.lineFeedReplacement
        config.paragraphSeparatorReplacement = self.paragraphSeparatorReplacement
        config.lineSeparatorReplacement = self.lineSeparatorReplacement

        return config
    }
}
