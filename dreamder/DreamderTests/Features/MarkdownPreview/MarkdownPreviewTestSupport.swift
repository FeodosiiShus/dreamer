import Foundation
@testable import Dreamder

enum MarkdownPreviewTestSupport {
    struct PositionedElement: Equatable {
        let tag: String
        let from: Int
        let to: Int
    }

    private static let sourcePositionPattern = #" md-src-pos="[^"]*""#
    private static let identifierPattern = #" id="[^"]*""#
    private static let betweenTagsPattern = #">\s+<"#

    static func stripped(_ html: String) -> String {
        [sourcePositionPattern, identifierPattern].reduce(html) { current, pattern in
            replacing(pattern, in: current, with: "")
        }
    }

    static func plainHTML(_ markdown: String) -> String {
        stripped(MarkdownHTMLRenderer.bodyHTML(from: markdown))
    }

    static func normalized(_ html: String) -> String {
        replacing(betweenTagsPattern, in: stripped(html), with: "><")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func positions(in html: String) -> [PositionedElement] {
        let pattern = #"<([A-Za-z0-9]+)[^>]*? md-src-pos="(\d+)\.\.(\d+)""#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsHTML = html as NSString
        return expression.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)).compactMap { match in
            guard let from = Int(nsHTML.substring(with: match.range(at: 2))),
                  let to = Int(nsHTML.substring(with: match.range(at: 3))) else { return nil }
            return PositionedElement(tag: nsHTML.substring(with: match.range(at: 1)), from: from, to: to)
        }
    }

    static func replacing(_ pattern: String, in text: String, with template: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return text }
        return expression.stringByReplacingMatches(
            in: text,
            range: NSRange(location: 0, length: (text as NSString).length),
            withTemplate: template
        )
    }

    static func slice(_ markdown: String, _ element: PositionedElement) -> String {
        let units = Array(markdown.utf16)
        return String(decoding: units[element.from..<element.to], as: UTF16.self)
    }
}

enum MarkdownPreviewFixtures {
    static func color(_ hex: String) -> MarkdownPreviewColor {
        MarkdownPreviewColor(hex: hex) ?? MarkdownPreviewColor(red: 0, green: 0, blue: 0)
    }

    static let accents = MarkdownPreviewAccents(
        link: color("#71A1FE"),
        accent: color("#3871E1"),
        info: color("#8C8F96"),
        separator: color("#33353B"),
        warning: color("#F2C55C")
    )

    static var darkPalette: MarkdownPreviewPalette {
        MarkdownPreviewPalette(
            isDark: true,
            fontSize: 13,
            background: color("#191A1C"),
            foreground: color("#BCBEC4"),
            selection: color("#2E436E"),
            accents: accents
        )
    }

    static func themeJSON(background: String, text: String, selection: String, type: String) -> String {
        let editorKeys = [
            "text", "insertionPoint", "invisibles", "background", "lineHighlight", "selection", "keywords",
            "commands", "types", "attributes", "variables", "values", "numbers", "strings", "characters", "comments"
        ]
        let terminalKeys = [
            "text", "boldText", "cursor", "background", "selection", "black", "red", "green", "yellow", "blue",
            "magenta", "cyan", "white", "brightBlack", "brightRed", "brightGreen", "brightYellow", "brightBlue",
            "brightMagenta", "brightCyan", "brightWhite"
        ]
        let overrides = ["text": text, "background": background, "selection": selection]
        func section(_ keys: [String], overriding: [String: String]) -> String {
            let entries = keys.map { key in
                "\"\(key)\":{\"color\":\"\(overriding[key] ?? "#123456")\"}"
            }
            return "{" + entries.joined(separator: ",") + "}"
        }
        return """
        {"author":"A","license":"MIT","description":"d","distributionURL":"https://example.com",\
        "name":"fixture-\(type)","displayName":"Fixture","version":"1","type":"\(type)",\
        "editor":\(section(editorKeys, overriding: overrides)),\
        "terminal":\(section(terminalKeys, overriding: [:]))}
        """
    }

    static func theme(background: String, text: String, selection: String, type: String) throws -> Theme {
        let json = themeJSON(background: background, text: text, selection: selection, type: type)
        return try JSONDecoder().decode(Theme.self, from: Data(json.utf8))
    }

    static func darkTheme() throws -> Theme {
        try theme(background: "#191A1C", text: "#BCBEC4", selection: "#2E436E", type: "dark")
    }

    static func lightTheme() throws -> Theme {
        try theme(background: "#FFFFFF", text: "#080808", selection: "#A6D2FF", type: "light")
    }
}
