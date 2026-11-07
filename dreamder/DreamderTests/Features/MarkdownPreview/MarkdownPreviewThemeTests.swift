import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized)
struct MarkdownPreviewThemeTests {
    @Test
    func swiftUIColorsRoundTripThroughThePreviewColor() {
        let color = MarkdownPreviewColor(Color(.sRGB, red: 0.2, green: 0.4, blue: 0.6, opacity: 0.5))

        #expect(color.red == 51)
        #expect(color.green == 102)
        #expect(color.blue == 153)
        #expect(abs(color.alpha - 0.5) < 0.01)

        let back = color.nsColor.usingColorSpace(.sRGB)
        #expect(back.map { abs($0.redComponent - 0.2) < 0.01 } == true)
        #expect(back.map { abs($0.blueComponent - 0.6) < 0.01 } == true)
    }

    @Test
    func islandsAccentsFollowTheIslandsTokens() {
        let accents = MarkdownPreviewAccents.islands

        #expect(accents.link == MarkdownPreviewColor(Islands.link))
        #expect(accents.separator == MarkdownPreviewColor(Islands.separator))
        #expect(accents.warning == MarkdownPreviewColor(Islands.warningForeground))
    }

    @Test
    func currentPaletteUsesTheSelectedThemeAndTheEditorFontSize() throws {
        try withTempDir { directory in
            let settings = Dreamder.Settings(baseURL: directory)
            let themeModel = ThemeModel.shared
            let theme = try #require(themeModel.selectedTheme ?? themeModel.themes.first)
            let expectedBackground = try #require(MarkdownPreviewColor(hex: theme.editor.background.color))
            let expectedForeground = try #require(MarkdownPreviewColor(hex: theme.editor.text.color))

            let palette = MarkdownPreviewPalette.current(settings: settings, themeModel: themeModel)

            #expect(palette.background == expectedBackground)
            #expect(palette.foreground == expectedForeground)
            #expect(palette.fontSize == Int(settings.preferences.textEditing.font.size.rounded()))
            #expect(palette.link == MarkdownPreviewAccents.islands.link)
        }
    }

    @Test
    func currentPaletteHonorsAnExplicitPreviewFontSize() throws {
        try withTempDir { directory in
            let settings = Dreamder.Settings(baseURL: directory)
            settings.preferences.markdownPreview.fontSize = 22

            let palette = MarkdownPreviewPalette.current(settings: settings, themeModel: ThemeModel.shared)

            #expect(palette.fontSize == 22)
        }
    }
}
