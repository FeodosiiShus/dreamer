import Foundation

nonisolated enum MarkdownHTMLRenderer {
    static func bodyHTML(from markdown: String, includesSourcePositions: Bool = true) -> String {
        MarkdownBlockRenderer.render(markdown, includesSourcePositions: includesSourcePositions)
    }

    static func documentHTML(body: String, baseURL: URL?, palette: MarkdownPreviewPalette) -> String {
        var baseTag = ""
        if let baseURL {
            var href = baseURL.absoluteString
            if !href.hasSuffix("/") {
                href += "/"
            }
            baseTag = "<base href=\"\(MarkdownInlineRenderer.escape(href))\">\n"
        }

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        \(baseTag)<style>
        \(MarkdownPreviewStyles.stylesheet(palette: palette))
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }
}
