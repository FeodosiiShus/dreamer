import Foundation

enum MarkdownHTMLRenderer {
    static func bodyHTML(from markdown: String) -> String {
        MarkdownBlockRenderer.render(markdown)
    }

    static func documentHTML(body: String, baseURL: URL?) -> String {
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
        \(stylesheet)
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    static let stylesheet = """
    :root {
        color-scheme: dark;
        background: #191A1C;
    }
    html, body {
        margin: 0;
        padding: 0;
        background: #191A1C;
        color: #BCBEC4;
    }
    body {
        font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
        font-size: 13px;
        line-height: 1.6;
        padding: 20px 24px 48px 24px;
        overflow-wrap: break-word;
        -webkit-font-smoothing: antialiased;
    }
    h1, h2, h3, h4, h5, h6 {
        color: #D1D3D9;
        font-weight: 600;
        line-height: 1.25;
        margin: 1.4em 0 0.5em 0;
    }
    h1 { font-size: 24px; border-bottom: 1px solid #33353B; padding-bottom: 6px; }
    h2 { font-size: 19px; border-bottom: 1px solid #33353B; padding-bottom: 4px; }
    h3 { font-size: 16px; }
    h4 { font-size: 14px; }
    h5 { font-size: 13px; }
    h6 { font-size: 12px; color: #8C8F96; }
    h1:first-child, h2:first-child, h3:first-child { margin-top: 0; }
    p, ul, ol, blockquote, table, pre, hr { margin: 0 0 12px 0; }
    a { color: #71A1FE; text-decoration: none; }
    a:hover { text-decoration: underline; }
    ul, ol { padding-left: 24px; }
    ul ul, ul ol, ol ul, ol ol { margin-bottom: 0; }
    li { margin: 2px 0; }
    li > p { margin: 0 0 8px 0; }
    blockquote {
        border-left: 3px solid #40434A;
        padding: 0 0 0 12px;
        color: #8C8F96;
    }
    blockquote > :last-child { margin-bottom: 0; }
    hr {
        border: none;
        border-top: 1px solid #33353B;
        height: 0;
    }
    code, pre, kbd, samp {
        font-family: "JetBrains Mono", monospace;
        font-size: 12px;
    }
    code {
        background: #2B2D30;
        border-radius: 4px;
        padding: 1px 4px;
    }
    pre {
        background: #2B2D30;
        border-radius: 6px;
        padding: 12px 14px;
        overflow-x: auto;
    }
    pre code {
        background: transparent;
        border-radius: 0;
        padding: 0;
        font-size: 12px;
    }
    table {
        border-collapse: collapse;
        font-size: 12px;
    }
    th, td {
        border: 1px solid #33353B;
        padding: 5px 10px;
        text-align: left;
    }
    th {
        background: #1F2024;
        color: #D1D3D9;
        font-weight: 600;
    }
    tbody tr:nth-child(even) td { background: #1F2024; }
    img { max-width: 100%; }
    input[type="checkbox"] {
        margin: 0 6px 0 0;
        vertical-align: middle;
        accent-color: #3871E1;
    }
    ::selection { background: #2E436E; }
    """
}
