import AppKit
import CodeEditTextView
import SwiftUI

struct FoldPlaceholderStyle {
    let font: NSFont
    let background: NSColor
    let foreground: NSColor
    let selectedBackground: NSColor
    let selectedForeground: NSColor

    static func make(font: NSFont, invisibles: NSColor) -> FoldPlaceholderStyle {
        FoldPlaceholderStyle(
            font: font,
            background: invisibles.withAlphaComponent(0.35),
            foreground: NSColor(Islands.editorForeground),
            selectedBackground: NSColor(Islands.selection),
            selectedForeground: NSColor(Islands.foreground)
        )
    }
}

final class FoldPlaceholderAttachment: TextAttachment {
    static let ellipsis = "…"
    static let horizontalPadding: CGFloat = 6
    static let margin: CGFloat = 2
    static let verticalInset: CGFloat = 2
    static let cornerRadius: CGFloat = 4

    let region: FoldRegion
    var isSelected = false
    private let style: FoldPlaceholderStyle
    private let textWidth: CGFloat
    private let ascent: CGFloat
    private let descent: CGFloat

    init(region: FoldRegion, style: FoldPlaceholderStyle) {
        self.region = region
        self.style = style
        let measured = Self.makeLine(style: style, color: style.foreground)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        textWidth = CGFloat(CTLineGetTypographicBounds(measured, &ascent, &descent, nil))
        self.ascent = ascent
        self.descent = descent
    }

    var width: CGFloat {
        ceil(textWidth) + Self.horizontalPadding * 2 + Self.margin * 2
    }

    func draw(in context: CGContext, rect: NSRect) {
        let pill = NSRect(
            x: rect.minX + Self.margin,
            y: rect.minY + Self.verticalInset,
            width: rect.width - Self.margin * 2,
            height: rect.height - Self.verticalInset * 2
        )
        let background = isSelected ? style.selectedBackground : style.background
        let foreground = isSelected ? style.selectedForeground : style.foreground
        context.saveGState()
        context.addPath(
            CGPath(roundedRect: pill, cornerWidth: Self.cornerRadius, cornerHeight: Self.cornerRadius, transform: nil)
        )
        context.setFillColor(background.cgColor)
        context.fillPath()
        context.textPosition = CGPoint(
            x: pill.minX + Self.horizontalPadding,
            y: pill.midY + (ascent - descent) / 2
        )
        CTLineDraw(Self.makeLine(style: style, color: foreground), context)
        context.restoreGState()
    }

    func attachmentAction() -> TextAttachmentAction {
        .discard
    }

    private static func makeLine(style: FoldPlaceholderStyle, color: NSColor) -> CTLine {
        CTLineCreateWithAttributedString(
            NSAttributedString(
                string: ellipsis,
                attributes: [.font: style.font, .foregroundColor: color]
            )
        )
    }
}
