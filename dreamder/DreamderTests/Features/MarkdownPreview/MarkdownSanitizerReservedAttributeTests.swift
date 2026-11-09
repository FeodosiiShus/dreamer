import Foundation
import Testing
@testable import Dreamder

@Suite
struct MarkdownSanitizerReservedAttributeTests {
    @Test
    func sourcePositionsInRawHTMLAreRemovedWhateverTheSpelling() {
        let cases: [(input: String, output: String)] = [
            ("<div md-src-pos=\"0..9\">x</div>", "<div>x</div>"),
            ("<div MD-SRC-POS=\"0..9\">x</div>", "<div>x</div>"),
            ("<div md-src-pos='0..100000000'>x</div>", "<div>x</div>"),
            ("<div md-src-pos=0..9>x</div>", "<div>x</div>"),
            ("<div md-src-pos>x</div>", "<div>x</div>"),
            ("<p class=\"c\" md-src-pos=\"1..2\" title=\"t\">x</p>", "<p class=\"c\" title=\"t\">x</p>"),
            ("<table md-src-pos=\"0..1\"><thead md-src-pos=\"0..1\"><tr md-src-pos=\"0..1\">", "<table><thead><tr>"),
            ("<li md-src-pos=\"0..1\"><ul md-src-pos=\"0..1\"><blockquote md-src-pos=\"0..1\">", "<li><ul><blockquote>")
        ]
        for entry in cases {
            #expect(MarkdownHTMLSanitizer.sanitize(entry.input) == entry.output, "\(entry.input)")
        }
    }

    @Test
    func theScriptsPositionAttributeIsNotInAnyAllowlist() {
        let position = MarkdownPreviewScripts.positionAttribute
        #expect(!MarkdownHTMLSanitizer.globalAttributes.contains(position))
        for (element, attributes) in MarkdownHTMLSanitizer.elementAttributes {
            #expect(!attributes.contains(position), "\(element)")
        }
    }

    @Test
    func identifiersInRawHTMLAreNamespacedInEverySpelling() {
        let prefix = MarkdownHTMLSanitizer.userIdentifierPrefix
        #expect(prefix == "user-content-")
        let cases: [(input: String, output: String)] = [
            ("<div id=\"dreamderPreview\"></div>", "<div id=\"\(prefix)dreamderPreview\"></div>"),
            ("<div id='dreamderPreview'></div>", "<div id=\"\(prefix)dreamderPreview\"></div>"),
            ("<div id=dreamderPreview></div>", "<div id=\"\(prefix)dreamderPreview\"></div>"),
            ("<div ID=\"dreamderPreview\"></div>", "<div id=\"\(prefix)dreamderPreview\"></div>"),
            ("<div id = \"a\"></div>", "<div id=\"\(prefix)a\"></div>"),
            ("<div id=\"\"></div>", "<div id=\"\(prefix)\"></div>"),
            ("<div id></div>", "<div id=\"\(prefix)\"></div>"),
            ("<div id='a\"b'></div>", "<div id=\"\(prefix)a&quot;b\"></div>"),
            ("<div id=\"a&amp;b\"></div>", "<div id=\"\(prefix)a&amp;b\"></div>"),
            (
                "<div id=\"a\" id=\"dreamderPreview\"></div>",
                "<div id=\"\(prefix)a\" id=\"\(prefix)dreamderPreview\"></div>"
            ),
            ("<span\n\tid=\"x\"\n>t</span>", "<span\n\tid=\"\(prefix)x\"\n>t</span>")
        ]
        for entry in cases {
            #expect(MarkdownHTMLSanitizer.sanitize(entry.input) == entry.output, "\(entry.input.debugDescription)")
        }
    }

    @Test
    func noSanitizedOutputCanCarryAnUnnamespacedIdentifier() {
        let hostile = [
            "<div id=\"dreamderPreview\">",
            "<div id=dreamderPreview>",
            "<h1 id=\"dreamderPreview\" md-src-pos=\"0..1\">t</h1>",
            "<a href=\"#x\" id='dreamderPreview'>t</a>",
            "<p aria-label=\"x\" id=\"body\">t</p>",
            "<img src=\"a.png\" id=\"scrollTo\">"
        ]
        for input in hostile {
            let output = MarkdownHTMLSanitizer.sanitize(input).lowercased()
            #expect(!output.contains("id=\"dreamder"), "\(input)")
            #expect(!output.contains("id=dreamder"), "\(input)")
            #expect(!output.contains("md-src-pos"), "\(input)")
            #expect(output.contains("id=\"user-content-"), "\(input)")
        }
    }

    @Test
    func attributesOtherThanIdentifiersKeepTheirSpelling() {
        let html = "<div class='c' title = \"t\" lang=en role=\"note\" aria-hidden=true>x</div>"
        #expect(MarkdownHTMLSanitizer.sanitize(html) == html)
    }

    @Test
    func rawHTMLBlocksNeverReachThePreviewWithReservedAttributes() throws {
        let markdown = "<div id=\"dreamderPreview\" md-src-pos=\"0..100000000\">x</div>\n\npara"
        let html = MarkdownHTMLRenderer.bodyHTML(from: markdown)
        #expect(html.contains("<div id=\"user-content-dreamderPreview\">x</div>"))
        #expect(!html.contains("100000000"))
        let positions = MarkdownPreviewTestSupport.positions(in: html)
        let paragraph = try #require(positions.first)
        #expect(positions.count == 1)
        #expect(paragraph.tag == "p")
        #expect(MarkdownPreviewTestSupport.slice(markdown, paragraph) == "para")
    }

    @Test
    func inlineRawHTMLNeverReachesThePreviewWithReservedAttributes() {
        let html = MarkdownHTMLRenderer.bodyHTML(
            from: "text <span id=\"dreamderPreview\" md-src-pos=\"0..100000000\">x</span> end"
        )
        #expect(html.contains("<span id=\"user-content-dreamderPreview\">x</span>"))
        #expect(!html.contains("100000000"))
        #expect(MarkdownPreviewTestSupport.positions(in: html).map(\.tag) == ["p"])
    }

    @Test
    func identifiersGeneratedByTheRendererStayUnprefixed() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "# Title\n\n## dreamderPreview")
        #expect(html.contains("<h1 id=\"title\" md-src-pos=\"0..7\">"))
        #expect(html.contains("<h2 id=\"dreamderpreview\""))
        #expect(!html.contains("user-content-"))
    }
}
