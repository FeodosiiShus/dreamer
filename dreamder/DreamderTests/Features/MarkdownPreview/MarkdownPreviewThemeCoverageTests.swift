import AppKit
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct MarkdownPreviewThemeCoverageTests {
    @Test
    func paletteFallsBackToTheIslandsColorsWithoutATheme() throws {
        try withTempDir { directory in
            let settings = Dreamder.Settings(baseURL: directory)

            let palette = MarkdownPreviewPalette.palette(for: nil, settings: settings)

            #expect(palette.isDark)
            #expect(palette.background == MarkdownPreviewColor(Islands.island))
            #expect(palette.foreground == MarkdownPreviewColor(Islands.editorForeground))
            #expect(palette.selection == MarkdownPreviewColor(Islands.selection))
            #expect(palette.link == MarkdownPreviewAccents.islands.link)
            #expect(palette.fontSize == Int(settings.preferences.textEditing.font.size.rounded()))
        }
    }

    @Test
    func paletteFallsBackToTheIslandsColorsWhenTheThemeColorsCannotBeParsed() throws {
        try withTempDir { directory in
            let settings = Dreamder.Settings(baseURL: directory)
            let theme = try MarkdownPreviewFixtures.theme(
                background: "not-a-color",
                text: "#BCBEC4",
                selection: "#2E436E",
                type: "light"
            )

            let palette = MarkdownPreviewPalette.palette(for: theme, settings: settings)

            #expect(palette.isDark)
            #expect(palette.background == MarkdownPreviewColor(Islands.island))
        }
    }

    @Test
    func paletteUsesTheColorsOfAValidTheme() throws {
        try withTempDir { directory in
            let settings = Dreamder.Settings(baseURL: directory)
            settings.preferences.markdownPreview.fontSize = 17

            let dark = MarkdownPreviewPalette.palette(for: try MarkdownPreviewFixtures.darkTheme(), settings: settings)
            let light = MarkdownPreviewPalette.palette(
                for: try MarkdownPreviewFixtures.lightTheme(),
                settings: settings
            )

            #expect(dark.isDark)
            #expect(dark.background == MarkdownPreviewFixtures.color("#191A1C"))
            #expect(dark.fontSize == 17)
            #expect(light.isDark == false)
            #expect(light.background == MarkdownPreviewFixtures.color("#FFFFFF"))
            #expect(light.foreground == MarkdownPreviewFixtures.color("#080808"))
        }
    }

    @Test
    func theCurrentPaletteFollowsTheSelectedThemeThenTheFirstThemeThenTheIslandsFallback() throws {
        try withTempDir { directory in
            let settings = Dreamder.Settings(baseURL: directory)
            let model = ThemeModel(baseURL: directory, bundledThemesURL: nil, preferencesStore: settings)
            let dark = try MarkdownPreviewFixtures.darkTheme()
            let light = try MarkdownPreviewFixtures.lightTheme()
            model.themes = [light, dark]

            model.selectedTheme = dark
            let selected = MarkdownPreviewPalette.current(settings: settings, themeModel: model)
            model.selectedTheme = nil
            let first = MarkdownPreviewPalette.current(settings: settings, themeModel: model)
            model.themes = []
            let fallback = MarkdownPreviewPalette.current(settings: settings, themeModel: model)

            #expect(selected.background == MarkdownPreviewFixtures.color("#191A1C"))
            #expect(first.background == MarkdownPreviewFixtures.color("#FFFFFF"))
            #expect(fallback.background == MarkdownPreviewColor(Islands.island))
        }
    }
}
