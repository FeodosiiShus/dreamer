import AppKit

@MainActor
enum SignatureHelpMetrics {
    static let horizontalInset: CGFloat = 12
    static let verticalInset: CGFloat = 8
    static let rowInset: CGFloat = 6
    static let rowVerticalPadding: CGFloat = 4
    static let rowSpacing: CGFloat = 4
    static let lineSpacing: CGFloat = 2
    static let minimumWidth: CGFloat = 220
    static let maximumWidth: CGFloat = 640
    static let preferredDocumentationWidth: CGFloat = 420
    static let documentationLineLimit = 2

    static var labelFont: NSFont {
        Islands.codeNSFont
    }

    static var documentationFont: NSFont {
        NSFont.systemFont(ofSize: Islands.smallFontSize)
    }

    static func size(for rows: [SignatureHelpRow]) -> NSSize {
        let width = panelWidth(for: rows)
        let available = width - 2 * (horizontalInset + rowInset)
        var height = 2 * verticalInset
        for row in rows {
            height += rowHeight(for: row, availableWidth: available) + rowSpacing
        }
        height -= rowSpacing
        if rows.count > 1 {
            height += rowSpacing + lineHeight(of: documentationFont)
        }
        return NSSize(width: width, height: ceil(height))
    }

    static func panelWidth(for rows: [SignatureHelpRow]) -> CGFloat {
        var content: CGFloat = 0
        for row in rows {
            content = max(content, textWidth(row.label, font: labelFont))
            for documentation in documentations(of: row) {
                content = max(
                    content,
                    min(textWidth(documentation.text, font: documentationFont), preferredDocumentationWidth)
                )
            }
        }
        let width = content + 2 * (horizontalInset + rowInset)
        return min(max(ceil(width), minimumWidth), maximumWidth)
    }

    static func rowHeight(for row: SignatureHelpRow, availableWidth: CGFloat) -> CGFloat {
        var height = lineHeight(of: labelFont) + rowVerticalPadding
        for documentation in documentations(of: row) {
            let lines = documentationLines(documentation.text, availableWidth: availableWidth)
            height += lineSpacing + CGFloat(lines) * lineHeight(of: documentationFont)
        }
        return height
    }

    static func documentationLines(_ text: String, availableWidth: CGFloat) -> Int {
        let ratio = textWidth(text, font: documentationFont) / max(availableWidth, 1)
        return min(documentationLineLimit, max(1, Int(ceil(ratio))))
    }

    static func lineHeight(of font: NSFont) -> CGFloat {
        ceil(font.ascender - font.descender + font.leading) + 2
    }

    static func textWidth(_ text: String, font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private static func documentations(of row: SignatureHelpRow) -> [SignatureHelpDocumentation] {
        [row.documentation, row.parameterDocumentation].compactMap { $0 }
    }
}
