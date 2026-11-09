import Foundation
import Testing
@testable import Dreamder

@Suite
struct MarkdownPreviewStylesTests {
    private func color(_ hex: String) -> MarkdownPreviewColor {
        MarkdownPreviewFixtures.color(hex)
    }

    private func darkPalette(fontSize: Int = 13) throws -> MarkdownPreviewPalette {
        try #require(
            MarkdownPreviewPalette(
                theme: MarkdownPreviewFixtures.darkTheme(),
                fontSize: fontSize,
                islandsAccents: MarkdownPreviewFixtures.accents
            )
        )
    }

    private func lightPalette(fontSize: Int = 14) throws -> MarkdownPreviewPalette {
        try #require(
            MarkdownPreviewPalette(
                theme: MarkdownPreviewFixtures.lightTheme(),
                fontSize: fontSize,
                islandsAccents: MarkdownPreviewFixtures.accents
            )
        )
    }

    @Test
    func hexParsingAcceptsSixAndEightDigits() {
        #expect(MarkdownPreviewColor(hex: "#191A1C") == MarkdownPreviewColor(red: 25, green: 26, blue: 28))
        #expect(MarkdownPreviewColor(hex: "bcbec4") == MarkdownPreviewColor(red: 188, green: 190, blue: 196))
        #expect(MarkdownPreviewColor(hex: "#FF000080")?.alpha == 128.0 / 255.0)
        #expect(MarkdownPreviewColor(hex: "#12345") == nil)
        #expect(MarkdownPreviewColor(hex: "not a color") == nil)
    }

    @Test
    func cssAndHexFormatting() {
        #expect(color("#191A1C").css == "rgba(25, 26, 28, 1)")
        #expect(color("#191A1C").withAlpha(0.1).css == "rgba(25, 26, 28, 0.1)")
        #expect(color("#191A1C").withAlpha(0.25).css == "rgba(25, 26, 28, 0.25)")
        #expect(color("#71a1fe").hex == "#71A1FE")
    }

    @Test
    func luminanceAndContrastFollowWCAG() {
        let black = color("#000000")
        let white = color("#FFFFFF")
        #expect(black.luminance == 0)
        #expect(abs(white.luminance - 1) < 1e-9)
        #expect(abs(black.contrast(with: white) - 21) < 1e-9)
        #expect(black.contrast(with: white) == white.contrast(with: black))
        #expect(black.contrast(with: black) == 1)
    }

    @Test
    func brightnessTonesMultiplyByTenPercent() {
        let grey = color("#808080")
        #expect(grey.brighter(tones: 0) == grey)
        #expect(grey.brighter(tones: 1).hex == "#8D8D8D")
        #expect(grey.darker(tones: 1).hex == "#747474")
        #expect(color("#FFFFFF").brighter(tones: 5) == color("#FFFFFF"))
        #expect(color("#000000").brighter(tones: 5) == color("#000000"))
    }

    @Test
    func brightnessTonesKeepHueAndSaturation() {
        let blue = color("#3871E1").brighter(tones: 1)
        #expect(blue.blue > color("#3871E1").blue || blue.blue == 255)
        #expect(blue.red >= color("#3871E1").red)
    }

    @Test
    func ensuringContrastShiftsTowardTheBrighterSideForDarkBackgrounds() {
        let background = color("#191A1C")
        let base = color("#33353B")
        let adjusted = base.ensuringContrast(against: background, atLeast: 3)
        #expect(adjusted.contrast(with: background) >= 3)
        #expect(adjusted.luminance > base.luminance)
        #expect(base.brighter(tones: 1).contrast(with: background) < 3 || adjusted == base.brighter(tones: 1))
    }

    @Test
    func ensuringContrastUsesTheMinimalNumberOfTones() {
        let background = color("#191A1C")
        let base = color("#33353B")
        var tones = 0
        var shifted = base
        while shifted.contrast(with: background) < 3 {
            tones += 1
            shifted = base.brighter(tones: tones)
        }
        #expect(base.ensuringContrast(against: background, atLeast: 3) == shifted)
        if tones > 1 {
            #expect(base.brighter(tones: tones - 1).contrast(with: background) < 3)
        }
    }

    @Test
    func ensuringContrastKeepsAnAlreadyContrastingColor() {
        let background = color("#191A1C")
        let strong = color("#FFFFFF")
        #expect(strong.ensuringContrast(against: background, atLeast: 3) == strong)
    }

    @Test
    func ensuringContrastDarkensAgainstLightBackgrounds() {
        let background = color("#FFFFFF")
        let faint = color("#EEEEEE")
        let adjusted = faint.ensuringContrast(against: background, atLeast: 3)
        #expect(adjusted.contrast(with: background) >= 3)
        #expect(adjusted.luminance < faint.luminance)
    }

    @Test
    func darkPaletteTakesBackgroundForegroundAndSelectionFromTheTheme() throws {
        let palette = try darkPalette()
        #expect(palette.isDark)
        #expect(palette.background == color("#191A1C"))
        #expect(palette.foreground == color("#BCBEC4"))
        #expect(palette.selection == color("#2E436E"))
        #expect(palette.link == MarkdownPreviewFixtures.accents.link)
        #expect(palette.info == MarkdownPreviewFixtures.accents.info)
        #expect(palette.fontSize == 13)
    }

    @Test
    func darkPaletteSeparatorHasAtLeastThreeToOneContrast() throws {
        let palette = try darkPalette()
        #expect(palette.separator.contrast(with: palette.background) >= MarkdownPreviewPalette.minimumBorderContrast)
        #expect(palette.separator != MarkdownPreviewFixtures.accents.separator)
        #expect(
            palette.separator == MarkdownPreviewFixtures.accents.separator
                .ensuringContrast(against: palette.background, atLeast: 3)
        )
    }

    @Test
    func lightPaletteDerivesInfoAndSeparatorFromTheTheme() throws {
        let palette = try lightPalette()
        #expect(!palette.isDark)
        #expect(palette.background == color("#FFFFFF"))
        #expect(palette.foreground == color("#080808"))
        #expect(palette.link == MarkdownPreviewFixtures.accents.accent)
        #expect(palette.info == color("#080808").contrasted(by: 0.6))
        #expect(palette.separator.contrast(with: palette.background) >= 3)
        #expect(palette.fontSize == 14)
    }

    @Test
    func fenceAndHighlightBackgroundsDependOnTheAppearance() throws {
        let dark = try darkPalette()
        let light = try lightPalette()
        #expect(dark.fenceBackground.css == "rgba(212, 222, 231, 0.1)")
        #expect(light.fenceBackground.css == "rgba(212, 222, 231, 0.25)")
        #expect(dark.highlightBackground.css == "rgba(242, 197, 92, 0.3)")
        #expect(light.highlightBackground.css == "rgba(242, 197, 92, 0.35)")
    }

    @Test
    func contrastedByScalesDistanceFromMidGrey() {
        #expect(color("#BCBEC4").contrasted(by: 0.1).hex == "#868686")
        #expect(color("#808080").contrasted(by: 0.5) == color("#808080"))
        #expect(color("#FFFFFF").contrasted(by: 2) == color("#FFFFFF"))
    }

    @Test
    func mixingBlendsChannelsLinearly() {
        #expect(color("#000000").mixed(with: color("#FFFFFF"), fraction: 0.5).hex == "#808080")
        #expect(color("#102030").mixed(with: color("#102030"), fraction: 0.7) == color("#102030"))
    }

    @Test
    func themeStylesheetUsesTheThemeColors() throws {
        let palette = try darkPalette()
        let css = MarkdownPreviewStyles.themeStylesheet(palette: palette)
        #expect(css.contains("color-scheme: dark;"))
        #expect(css.contains("--default-font-size: 13px;"))
        #expect(css.contains("background-color: rgba(25, 26, 28, 1);"))
        #expect(css.contains("body, p, blockquote, ul, ol, dl, table, pre, code, tr  {\n    color: rgba(188, 190, 196, 1);"))
        #expect(css.contains("a {\n    color: rgba(113, 161, 254, 1);"))
        #expect(css.contains("table td, table th {\n  border: 1px solid \(palette.separator.css);"))
        #expect(css.contains("hr {\n  background-color: \(palette.separator.css);"))
        #expect(css.contains("h6 {\n    color: rgba(140, 143, 150, 1);"))
        #expect(css.contains("blockquote {\n  border-left: 2px solid rgba(113, 161, 254, 0.4);"))
        #expect(css.contains("blockquote, code, pre {\n  background-color: rgba(212, 222, 231, 0.1);"))
        #expect(css.contains("mark {\n  background-color: rgba(242, 197, 92, 0.3);\n  color: inherit;"))
        #expect(css.contains("::selection {\n  background-color: rgba(46, 67, 110, 1);"))
        #expect(css.contains("font-size: var(--default-font-size) !important;"))
    }

    @Test
    func themeStylesheetFollowsALightTheme() throws {
        let palette = try lightPalette(fontSize: 18)
        let css = MarkdownPreviewStyles.themeStylesheet(palette: palette)
        #expect(css.contains("color-scheme: light;"))
        #expect(css.contains("--default-font-size: 18px;"))
        #expect(css.contains("background-color: rgba(255, 255, 255, 1);"))
        #expect(css.contains("color: rgba(8, 8, 8, 1);"))
        #expect(css.contains("rgba(212, 222, 231, 0.25)"))
        #expect(!css.contains("rgba(25, 26, 28, 1)"))
    }

    @Test
    func stylesheetContainsNoHardcodedHexColors() throws {
        let css = MarkdownPreviewStyles.stylesheet(palette: try darkPalette())
        #expect(!css.contains("#"))
    }

    @Test
    func themeRulesComeAfterTheBaseRulesSoTheyOverrideThem() throws {
        let css = MarkdownPreviewStyles.stylesheet(palette: try darkPalette())
        let base = try #require(css.range(of: "-webkit-text-size-adjust: 100%;"))
        let theme = try #require(css.range(of: "--default-font-size: 13px;"))
        #expect(base.lowerBound < theme.lowerBound)
    }

    @Test
    func baseStylesheetPortsIntelliJDefaultCSSMetrics() {
        let css = MarkdownPreviewStyles.baseStylesheet
        let expectedFragments = [
            "font-size: 14px;\n  line-height: 1.6;",
            "margin: 0 2em;",
            "h1 {\n  font-size: 2.2em;",
            "h2 {\n  font-size: 1.8em;",
            "h3 {\n  font-size: 1.3em;",
            "margin-top: 16px;\n  margin-bottom: 16px;",
            "padding: 10px 10px 10px 16px;\n  border-left: 2px solid;\n  border-radius: 0 3px 3px 0;",
            "padding: 6px 13px;",
            "font: 0.9em \"JetBrains Mono\"",
            "font: 0.85em \"JetBrains Mono\"",
            "padding: 16px;",
            ".task-list-item {\n  list-style-type: none;",
            "del {\n  text-decoration: line-through;"
        ]
        for fragment in expectedFragments {
            #expect(css.contains(fragment), "missing \(fragment)")
        }
    }

    @Test
    func differentThemesProduceDifferentStylesheets() throws {
        let dark = MarkdownPreviewStyles.stylesheet(palette: try darkPalette())
        let light = MarkdownPreviewStyles.stylesheet(palette: try lightPalette())
        #expect(dark != light)
    }

    @Test
    func themeWithInvalidColorsYieldsNoPalette() throws {
        let theme = try MarkdownPreviewFixtures.theme(
            background: "not-a-color",
            text: "#BCBEC4",
            selection: "#2E436E",
            type: "dark"
        )
        #expect(
            MarkdownPreviewPalette(theme: theme, fontSize: 13, islandsAccents: MarkdownPreviewFixtures.accents) == nil
        )
    }
}

@MainActor
@Suite(.uiGate)
struct MarkdownPreviewSettingsTests {
    @Test
    func defaultsMatchIntelliJ() {
        let settings = SettingsData().markdownPreview
        #expect(settings.isVerticalSplit)
        #expect(settings.isAutoScrollEnabled)
        #expect(settings.lastLayout == .editorAndPreview)
        #expect(settings.fontSize == nil)
    }

    @Test
    func previewFontSizeDefaultsToTheEditorFontSize() {
        var settings = SettingsData.MarkdownPreviewSettings()
        #expect(settings.resolvedFontSize(editorFontSize: 13) == 13)
        #expect(settings.resolvedFontSize(editorFontSize: 12.6) == 13)
        settings.fontSize = 20
        #expect(settings.resolvedFontSize(editorFontSize: 13) == 20)
    }

    @Test
    func fontSizeOptionsMatchIntelliJ() {
        #expect(SettingsData.MarkdownPreviewSettings.fontSizeOptions == [
            8, 9, 10, 11, 12, 14, 16, 18, 20, 22, 24, 26, 28, 36, 48, 72
        ])
    }

    @Test
    func missingKeysDecodeToDefaults() throws {
        let decoded = try JSONDecoder().decode(
            SettingsData.MarkdownPreviewSettings.self,
            from: Data("{}".utf8)
        )
        #expect(decoded == SettingsData.MarkdownPreviewSettings())
        let legacy = try JSONDecoder().decode(SettingsData.self, from: Data("{}".utf8))
        #expect(legacy.markdownPreview == SettingsData.MarkdownPreviewSettings())
    }

    @Test
    func valuesRoundTripThroughJSON() throws {
        var settings = SettingsData.MarkdownPreviewSettings()
        settings.isVerticalSplit = false
        settings.isAutoScrollEnabled = false
        settings.lastLayout = .previewOnly
        settings.fontSize = 16
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(SettingsData.MarkdownPreviewSettings.self, from: data)
        #expect(decoded == settings)
        #expect(String(decoding: data, as: UTF8.self).contains("\"lastLayout\":\"previewOnly\""))
    }
}
