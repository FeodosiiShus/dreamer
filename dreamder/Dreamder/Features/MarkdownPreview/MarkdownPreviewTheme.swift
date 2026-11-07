import AppKit
import SwiftUI

extension MarkdownPreviewColor {
    init(_ color: Color) {
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.white
        self.init(
            red: Int((resolved.redComponent * 255).rounded()),
            green: Int((resolved.greenComponent * 255).rounded()),
            blue: Int((resolved.blueComponent * 255).rounded()),
            alpha: Double(resolved.alphaComponent)
        )
    }

    var nsColor: NSColor {
        NSColor(
            srgbRed: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: CGFloat(alpha)
        )
    }
}

extension MarkdownPreviewAccents {
    static var islands: MarkdownPreviewAccents {
        MarkdownPreviewAccents(
            link: MarkdownPreviewColor(Islands.link),
            accent: MarkdownPreviewColor(Islands.accent),
            info: MarkdownPreviewColor(Islands.secondaryForeground),
            separator: MarkdownPreviewColor(Islands.separator),
            warning: MarkdownPreviewColor(Islands.warningForeground)
        )
    }
}

extension MarkdownPreviewPalette {
    static func current(settings: Settings = .shared, themeModel: ThemeModel = .shared) -> MarkdownPreviewPalette {
        let preferences = settings.preferences
        let fontSize = preferences.markdownPreview.resolvedFontSize(editorFontSize: preferences.textEditing.font.size)
        if let theme = themeModel.selectedTheme ?? themeModel.themes.first,
           let palette = MarkdownPreviewPalette(theme: theme, fontSize: fontSize, islandsAccents: .islands) {
            return palette
        }
        return MarkdownPreviewPalette(
            isDark: true,
            fontSize: fontSize,
            background: MarkdownPreviewColor(Islands.island),
            foreground: MarkdownPreviewColor(Islands.editorForeground),
            selection: MarkdownPreviewColor(Islands.selection),
            accents: .islands
        )
    }
}
