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

/// CodeFileView is just a wrapper of the `CodeEditor` dependency
struct CodeFileView: View {
    private let editorInstance: EditorInstance
    private let codeFile: CodeFileDocument

    @State private var sessionStore = CodeFileViewSessionStore()

    /// Any coordinators passed to the view.
    private var textViewCoordinators: [TextViewCoordinator]

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

    @Environment(UndoManagerRegistration.self) private var undoRegistration

    private let themeModel: ThemeModel

    private let isEditable: Bool

    init(
        editorInstance: EditorInstance,
        codeFile: CodeFileDocument,
        textViewCoordinators: [TextViewCoordinator] = [],
        isEditable: Bool = true,
        themeModel: ThemeModel = .shared
    ) {
        self.editorInstance = editorInstance
        self.codeFile = codeFile

        self.textViewCoordinators = textViewCoordinators
        self.isEditable = isEditable
        self.themeModel = themeModel

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
            VStack(spacing: 0) {
                if let error = codeFile.readError {
                    CodeFileReadErrorView(error: error)
                } else {
                    if let notice = codeFile.notice {
                        CodeFileNoticeBanner(notice: notice)
                    }
                    sourceEditor(
                        theme: theme,
                        session: sessionStore.session(editorInstance: editorInstance, codeFile: codeFile)
                    )
                }
            }
        } else {
            Color.clear
        }
    }

    private var isIntelligenceDisabled: Bool {
        codeFile.isTooLargeForIntelligence || codeFile.isBinary
    }

    private var editorLanguage: CodeLanguage {
        isIntelligenceDisabled ? .default : codeFile.getLanguage()
    }

    private func coordinators(for session: CodeFileViewSession) -> [TextViewCoordinator] {
        var coordinators = textViewCoordinators
        coordinators.append(editorInstance.rangeTranslator)
        coordinators.append(codeFile.contentCoordinator)
        coordinators.append(codeFile.textViewBinder)
        coordinators.append(codeFile.languageServerObjects.textCoordinator)
        coordinators.append(contentsOf: session.coordinators)
        return coordinators
    }

    private var isMarkdown: Bool {
        MarkdownPreviewLayoutStore.isMarkdownFile(codeFile.fileURL)
    }

    private var wrapsLines: Bool {
        editorInstance.wrapLinesOverride ?? (isMarkdown ? (codeFile.wrapLines ?? true) : wrapLinesToEditorWidth)
    }

    private func highlightProviders(for session: CodeFileViewSession) -> [HighlightProviding] {
        guard !isIntelligenceDisabled else { return [] }
        var providers: [HighlightProviding] = [
            codeFile.languageServerObjects.highlightProvider,
            session.treeSitterClient
        ]
        if let markdownProvider = session.markdownHighlightProvider {
            providers.append(markdownProvider)
        }
        return providers
    }

    private var editorState: SourceEditorState {
        SourceEditorState(
            cursorPositions: editorInstance.cursorPositions,
            scrollPosition: editorInstance.requestedScrollPosition,
            findText: editorInstance.findText,
            replaceText: editorInstance.replaceText
        )
    }

    private func consumeScrollRequest(_ request: CGPoint?) {
        guard request != nil else { return }
        Task { @MainActor in
            if editorInstance.requestedScrollPosition == request {
                editorInstance.requestedScrollPosition = nil
            }
        }
    }

    private var textStorage: NSTextStorage {
        if let content = codeFile.content {
            return content
        }
        return CodeTextStorage()
    }

    private func sourceEditor(theme: Theme, session: CodeFileViewSession) -> some View {
        _ = editorState
        let triggerCharacters = session.completionTriggerCharacters(
            requested: codeFile.languageServerObjects.completionDelegate?.completionTriggerCharacters() ?? []
        )
        return SourceEditor(
            textStorage,
            language: editorLanguage,
            configuration: SourceEditorConfiguration(
                appearance: .init(
                    theme: editorTheme(for: theme),
                    useThemeBackground: useThemeBackground,
                    font: font,
                    lineHeightMultiple: lineHeightMultiple,
                    letterSpacing: letterSpacing,
                    wrapLines: wrapsLines,
                    useSystemCursor: useSystemCursor,
                    tabWidth: codeFile.effectiveTabWidth,
                    bracketPairEmphasis: getBracketPairEmphasis(for: theme)
                ),
                behavior: .init(
                    isEditable: isEditable && !codeFile.isReadOnly,
                    indentOption: codeFile.effectiveIndentOption.textViewOption(),
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
                get: { editorState },
                set: { Self.adopt($0, into: editorInstance) }
            ),
            highlightProviders: highlightProviders(for: session),
            undoManager: undoRegistration.manager(forFile: editorInstance.file),
            coordinators: coordinators(for: session),
            completionDelegate: isIntelligenceDisabled ? nil : codeFile.languageServerObjects.completionDelegate,
            jumpToDefinitionDelegate: isIntelligenceDisabled
                ? nil
                : codeFile.languageServerObjects.jumpToDefinitionDelegate
        )
        // This view needs to refresh when the codefile changes. The file URL is too stable.
        .id(session.identity)
        .colorScheme(theme.appearance == .dark ? .dark : .light)
        // minHeight zero fixes a bug where the app would freeze if the contents of the file are empty.
        .frame(minHeight: .zero, maxHeight: .infinity)
        .onChange(of: editorInstance.requestedScrollPosition, initial: true) { _, request in
            consumeScrollRequest(request)
        }
        .onChange(of: settingsFont, initial: true) { _, newFontSetting in
            font = newFontSetting.current
        }
    }

    static func adopt(_ newState: SourceEditorState, into editorInstance: EditorInstance) {
        let cursorPositions = newState.cursorPositions ?? []
        if editorInstance.cursorPositions != cursorPositions {
            editorInstance.cursorPositions = cursorPositions
        }
        if editorInstance.scrollPosition != newState.scrollPosition {
            editorInstance.scrollPosition = newState.scrollPosition
        }
        if editorInstance.findText != newState.findText {
            editorInstance.findText = newState.findText
        }
        if editorInstance.replaceText != newState.replaceText {
            editorInstance.replaceText = newState.replaceText
        }
    }

    private func getBracketPairEmphasis(for theme: Theme) -> BracketPairEmphasis? {
        Self.bracketPairEmphasis(for: Settings[\.textEditing].bracketEmphasis, theme: theme)
    }

    static func bracketPairEmphasis(
        for settings: SettingsData.TextEditingSettings.BracketPairEmphasis,
        theme: Theme
    ) -> BracketPairEmphasis? {
        let color = if settings.useCustomColor {
            settings.color.nsColor
        } else {
            theme.editor.text.nsColor.withAlphaComponent(0.8)
        }

        switch settings.highlightType {
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

struct CodeFileNoticeBanner: View {
    let notice: CodeFileNotice

    var body: some View {
        Text(notice.message)
            .font(Islands.smallFont)
            .foregroundStyle(Islands.foreground)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Islands.islandRaised)
    }
}

struct CodeFileReadErrorView: View {
    let error: CodeFileReadError

    var body: some View {
        VStack(spacing: 6) {
            Text(error.title)
                .font(Islands.headerTitleFont)
                .foregroundStyle(Islands.errorForeground)
            Text(error.detail)
                .font(Islands.uiFont)
                .foregroundStyle(Islands.secondaryForeground)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// This extension is kept here because it should not be used elsewhere in the app and may cause confusion
// due to the similar type name from the CETV module.
extension SettingsData.TextEditingSettings.IndentOption {
    func textViewOption() -> IndentOption {
        switch self.indentType {
        case .spaces:
            return IndentOption.spaces(count: spaceCount)
        case .tab:
            return IndentOption.tab
        }
    }
}

extension SettingsData.TextEditingSettings.InvisibleCharactersConfig {
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
