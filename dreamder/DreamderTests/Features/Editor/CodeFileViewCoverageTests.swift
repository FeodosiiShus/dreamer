import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct CodeFileViewCoverageTests {
    private typealias BracketSettings = SettingsData.TextEditingSettings.BracketPairEmphasis

    private func makeEditor(_ name: String = "file.swift") -> EditorInstance {
        EditorInstance(workspace: nil, file: CEWorkspaceFile(url: URL(filePath: "/fake/dir/\(name)")))
    }

    @Test
    func openOptionsMoveTheStoredCursorsToTheEditorInstanceExactlyOnce() {
        let editor = makeEditor()
        let document = CodeFileDocument()
        let positions = [CursorPosition(line: 3, column: 2), CursorPosition(line: 5, column: 1)]
        document.openOptions = CodeFileDocument.OpenOptions(cursorPositions: positions)

        _ = CodeFileView(editorInstance: editor, codeFile: document)

        #expect(editor.cursorPositions == positions)
        #expect(document.openOptions == nil)

        editor.cursorPositions = []
        _ = CodeFileView(editorInstance: editor, codeFile: document)
        #expect(editor.cursorPositions.isEmpty)
    }

    @Test
    func withoutAnyThemeTheViewRendersNothing() async throws {
        try await withTempDir { directory in
            let url = directory.appending(path: "a.txt")
            let document = try FileViewsCoverageFixtures.textDocument(at: url, contents: "text\n")
            let editor = EditorInstance(workspace: nil, file: CEWorkspaceFile(url: url))
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            let themes = ThemeModel(
                baseURL: directory,
                bundledThemesURL: nil,
                preferencesStore: Dreamder.Settings(baseURL: directory)
            )
            #expect(themes.selectedTheme == nil)
            #expect(themes.themes.isEmpty)

            let hosted = try HostedViewFixture.hostInWorkspace(workspace) {
                CodeFileView(editorInstance: editor, codeFile: document, themeModel: themes)
            }
            defer { hosted.close() }
            try await hosted.settle()

            #expect(hosted.views(of: TextView.self).isEmpty)
        }
    }

    @Test
    func aDocumentWithoutContentStillHostsAnEmptyEditor() async throws {
        try await withTempDir { directory in
            let url = directory.appending(path: "blank.dat")
            try FileViewsCoverageFixtures.writeBlob(to: url)
            let document = try FileViewsCoverageFixtures.nonTextDocument(at: url, type: FileViewsCoverageFixtures.dataType)
            #expect(document.content == nil)
            let editor = EditorInstance(workspace: nil, file: CEWorkspaceFile(url: url))
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }

            let hosted = try HostedViewFixture.hostInWorkspace(workspace) {
                CodeFileView(editorInstance: editor, codeFile: document)
            }
            defer { hosted.close() }

            try await eventually(timeout: .seconds(30)) { !hosted.views(of: TextView.self).isEmpty }
        }
    }

    @Test
    func adoptingEditorStateCopiesEveryChangedField() {
        let editor = makeEditor()
        let positions = [CursorPosition(line: 2, column: 4)]
        let state = SourceEditorState(
            cursorPositions: positions,
            scrollPosition: CGPoint(x: 1, y: 20),
            findText: "needle",
            replaceText: "thread"
        )

        CodeFileView.adopt(state, into: editor)

        #expect(editor.cursorPositions == positions)
        #expect(editor.scrollPosition == CGPoint(x: 1, y: 20))
        #expect(editor.findText == "needle")
        #expect(editor.replaceText == "thread")
    }

    @Test
    func adoptingAnEmptyStateClearsTheEditorInstance() {
        let editor = makeEditor()
        editor.cursorPositions = [CursorPosition(line: 1, column: 1)]
        editor.scrollPosition = CGPoint(x: 0, y: 9)
        editor.findText = "a"
        editor.replaceText = "b"

        CodeFileView.adopt(SourceEditorState(), into: editor)

        #expect(editor.cursorPositions.isEmpty)
        #expect(editor.scrollPosition == nil)
        #expect(editor.findText == nil)
        #expect(editor.replaceText == nil)
    }

    @Test
    func bracketEmphasisFollowsTheHighlightTypeAndColorSource() {
        let theme = ThemeSettingsCoverageThemes.make(name: "brackets")
        let themeColor = theme.editor.text.nsColor.withAlphaComponent(0.8)
        let customAttributes = Theme.Attributes(color: "#ff0000")
        let customColor = customAttributes.nsColor

        func emphasis(_ type: BracketSettings.HighlightType, custom: Bool) -> BracketPairEmphasis? {
            var settings = BracketSettings()
            settings.highlightType = type
            settings.useCustomColor = custom
            settings.color = customAttributes
            return CodeFileView.bracketPairEmphasis(for: settings, theme: theme)
        }

        #expect(emphasis(.disabled, custom: false) == nil)
        #expect(emphasis(.flash, custom: true) == .flash)
        #expect(emphasis(.bordered, custom: false) == .bordered(color: themeColor))
        #expect(emphasis(.bordered, custom: true) == .bordered(color: customColor))
        #expect(emphasis(.underline, custom: false) == .underline(color: themeColor))
        #expect(emphasis(.underline, custom: true) == .underline(color: customColor))
    }

    @Test
    func disabledInvisibleCharactersProduceTheEmptyConfiguration() {
        var config = SettingsData.TextEditingSettings.InvisibleCharactersConfig.default
        config.enabled = false

        #expect(config.textViewOption() == .empty)
    }

    @Test
    func enabledInvisibleCharactersCarryTheVisibilityFlagsAndReplacements() {
        var config = SettingsData.TextEditingSettings.InvisibleCharactersConfig(
            enabled: true,
            showSpaces: true,
            showTabs: false,
            showLineEndings: true
        )
        config.spaceReplacement = "s"
        config.tabReplacement = "t"
        config.carriageReturnReplacement = "c"
        config.lineFeedReplacement = "l"
        config.paragraphSeparatorReplacement = "p"
        config.lineSeparatorReplacement = "e"

        let option = config.textViewOption()

        #expect(option.showSpaces)
        #expect(!option.showTabs)
        #expect(option.showLineEndings)
        #expect(option.spaceReplacement == "s")
        #expect(option.tabReplacement == "t")
        #expect(option.carriageReturnReplacement == "c")
        #expect(option.lineFeedReplacement == "l")
        #expect(option.paragraphSeparatorReplacement == "p")
        #expect(option.lineSeparatorReplacement == "e")
    }
}
