import Foundation
import Testing
@testable import Dreamder

@Suite
struct MarkdownInlineSyntaxTests {
    struct Example: Sendable, CustomTestStringConvertible {
        let markdown: String
        let html: String

        init(_ markdown: String, _ html: String) {
            self.markdown = markdown
            self.html = html
        }

        var testDescription: String { markdown }
    }

    private static func render(_ markdown: String) -> String {
        MarkdownPreviewTestSupport.plainHTML(markdown)
    }

    static let strikethrough: [Example] = [
        Example("~~a~~", "<p><del>a</del></p>"),
        Example("~a~ and ~~~c~~~", "<p>~a~ and ~~~c~~~</p>"),
        Example("**~~a~~**", "<p><strong><del>a</del></strong></p>"),
        Example("a ~~ b ~~ c", "<p>a ~~ b ~~ c</p>"),
        Example("~~a *b* c~~", "<p><del>a <em>b</em> c</del></p>")
    ]

    static let highlights: [Example] = [
        Example("Some ==marked== text", "<p>Some <mark>marked</mark> text</p>"),
        Example("==a *b* c==", "<p><mark>a <em>b</em> c</mark></p>"),
        Example("a == b == c", "<p>a == b == c</p>"),
        Example("=one= and ===three===", "<p>=one= and ===three===</p>")
    ]

    static let angleAutolinks: [Example] = [
        Example("<http://example.com>", "<p><a href=\"http://example.com\">http://example.com</a></p>"),
        Example("<mailto:a@b.co>", "<p><a href=\"mailto:a@b.co\">mailto:a@b.co</a></p>"),
        Example("<a@b.co>", "<p><a href=\"mailto:a@b.co\">a@b.co</a></p>")
    ]

    static let bareAutolinks: [Example] = [
        Example("see www.example.com now", "<p>see <a href=\"http://www.example.com\">www.example.com</a> now</p>"),
        Example(
            "see https://example.com/path?q=1&r=2#frag, ok",
            "<p>see <a href=\"https://example.com/path?q=1&amp;r=2#frag\">https://example.com/path?q=1&amp;r=2#frag</a>, ok</p>"
        ),
        Example("(www.example.com)", "<p>(<a href=\"http://www.example.com\">www.example.com</a>)</p>"),
        Example(
            "(https://example.com/a_(b))",
            "<p>(<a href=\"https://example.com/a_(b)\">https://example.com/a_(b)</a>)</p>"
        ),
        Example(
            "https://example.com/&amp; and https://example.com/a&copy;.",
            "<p><a href=\"https://example.com/\">https://example.com/</a>&amp; and "
                + "<a href=\"https://example.com/a\">https://example.com/a</a>©.</p>"
        ),
        Example(
            "**www.example.com**",
            "<p><strong><a href=\"http://www.example.com\">www.example.com</a></strong></p>"
        )
    ]

    static let notAutolinks: [Example] = [
        Example("foowww.example.com and xhttp://a.b", "<p>foowww.example.com and xhttp://a.b</p>"),
        Example("`www.example.com`", "<p><code>www.example.com</code></p>"),
        Example("[www.example.com](http://x.y)", "<p><a href=\"http://x.y\">www.example.com</a></p>"),
        Example("www. and http://", "<p>www. and http://</p>")
    ]

    @Test(arguments: strikethrough)
    func strikethroughRendersDel(_ example: Example) {
        #expect(Self.render(example.markdown) == example.html)
    }

    @Test(arguments: highlights)
    func highlightRendersMarkOnlyForDoubleEquals(_ example: Example) {
        #expect(Self.render(example.markdown) == example.html)
    }

    @Test
    func highlightIsRenderedAsMarkLikeIntelliJ() {
        let html = Self.render("Some ==marked== text, =one= and ===three===")
        #expect(html.contains(">marked</mark>"))
        #expect(html.components(separatedBy: "<mark").count - 1 == 1)
        let withoutTags = MarkdownPreviewTestSupport.replacing("<[^>]+>", in: html, with: "")
        #expect(withoutTags == "Some marked text, =one= and ===three===")
    }

    @Test(arguments: angleAutolinks)
    func angleBracketAutolinks(_ example: Example) {
        #expect(Self.render(example.markdown) == example.html)
    }

    @Test(arguments: bareAutolinks)
    func bareGFMAutolinks(_ example: Example) {
        #expect(Self.render(example.markdown) == example.html)
    }

    @Test(arguments: notAutolinks)
    func textThatIsNotAnAutolink(_ example: Example) {
        #expect(Self.render(example.markdown) == example.html)
    }

    @Test
    func entitiesAreDecodedInText() {
        #expect(Self.render("a &copy; b &amp; c &#35; &#x1F600;") == "<p>a © b &amp; c # 😀</p>")
        #expect(Self.render("&AElig; &Dcaron; &frac34; &HilbertSpace; &DifferentialD;") == "<p>Æ Ď ¾ ℋ ⅆ</p>")
        #expect(Self.render("&ClockwiseContourIntegral; &ngE;") == "<p>∲ ≧̸</p>")
        #expect(Self.render("&#X41; &lt;b&gt;") == "<p>A &lt;b&gt;</p>")
    }

    @Test
    func invalidEntitiesStayLiteralAndAreEscaped() {
        #expect(Self.render("&bogus; &amp &#12345678;") == "<p>&amp;bogus; &amp;amp &amp;#12345678;</p>")
    }

    @Test
    func invalidCodePointsBecomeReplacementCharacter() {
        #expect(Self.render("&#0; &#x110000; &#xD800; &#1234567;") == "<p>\u{FFFD} \u{FFFD} \u{FFFD} \u{FFFD}</p>")
    }

    @Test
    func entitiesInsideCodeAreLiteral() {
        #expect(Self.render("`&amp;`") == "<p><code>&amp;amp;</code></p>")
        #expect(Self.render("```\n&amp;\n```") == "<pre><code>&amp;amp;\n</code></pre>")
    }

    @Test
    func entitiesAndEscapesInLinkDestinationAndTitleAreDecoded() {
        #expect(
            Self.render("[a](/f&ouml;o \"t&amp;t\")") == "<p><a href=\"/föo\" title=\"t&amp;t\">a</a></p>"
        )
    }

    @Test
    func rawHTMLIsEscapedOrPassedThroughByTagShape() {
        #expect(Self.render("a < b & c > d \"q\"") == "<p>a &lt; b &amp; c &gt; d &quot;q&quot;</p>")
        #expect(Self.render("a <b>bold</b> &amp; <i>it</i>") == "<p>a <b>bold</b> &amp; <i>it</i></p>")
    }

    @Test
    func entityTableIsComplete() {
        #expect(MarkdownHTMLEntities.named.count > 2_000)
        #expect(MarkdownHTMLEntities.named["nbsp"] == "\u{A0}")
        #expect(MarkdownHTMLEntities.named["ngE"] == "\u{2267}\u{338}")
    }

    @Test
    func referenceLinksResolveByNormalizedLabel() {
        let markdown = "[foo]: /url \"title\"\n\n[FOO] and [foo][] and [x][FOO] and [nope]"
        #expect(
            Self.render(markdown) == "<p><a href=\"/url\" title=\"title\">FOO</a> and "
                + "<a href=\"/url\" title=\"title\">foo</a> and <a href=\"/url\" title=\"title\">x</a> and [nope]</p>"
        )
    }

    @Test
    func referenceDefinitionsMayFollowTheirUse() {
        #expect(
            Self.render("[foo]\n\n[foo]: /url (paren title)")
                == "<p><a href=\"/url\" title=\"paren title\">foo</a></p>"
        )
    }

    @Test
    func angleBracketDestinationAndSingleQuotedTitle() {
        #expect(
            Self.render("[foo]: <url with spaces> 'single'\n\n[foo]")
                == "<p><a href=\"url with spaces\" title=\"single\">foo</a></p>"
        )
    }

    @Test
    func firstDefinitionWins() {
        #expect(Self.render("[foo]: /one\n[foo]: /two\n\n[foo]") == "<p><a href=\"/one\">foo</a></p>")
    }

    @Test
    func definitionCannotInterruptParagraph() {
        #expect(Self.render("text\n[foo]: /url\n\n[foo]") == "<p>text\n[foo]: /url</p>\n<p>[foo]</p>")
    }

    @Test
    func definitionWithTrailingJunkIsPlainText() {
        #expect(
            Self.render("[foo]: /url \"title\" junk\n\n[foo]")
                == "<p>[foo]: /url &quot;title&quot; junk</p>\n<p>[foo]</p>"
        )
    }

    @Test
    func definitionsInsideContainersAreCollected() {
        #expect(Self.render("> [foo]: /url\n\n[foo]") == "<blockquote>\n</blockquote>\n<p><a href=\"/url\">foo</a></p>")
        #expect(Self.render("- [foo]: /url\n\n[foo]") == "<ul>\n<li></li>\n</ul>\n<p><a href=\"/url\">foo</a></p>")
    }

    @Test
    func imageReferenceUsesPlainTextAlt() {
        #expect(Self.render("![alt *em*][img]\n\n[img]: /i.png") == "<p><img src=\"/i.png\" alt=\"alt em\" /></p>")
    }

    @Test
    func linkTextMayContainBracketsAndImages() {
        #expect(Self.render("[link [nested]](u)") == "<p><a href=\"u\">link [nested]</a></p>")
        #expect(Self.render("[![img](a.png)](b)") == "<p><a href=\"b\"><img src=\"a.png\" alt=\"img\" /></a></p>")
    }

    @Test
    func tableCellPipesAreUnescapedBeforeInlineParsing() {
        let html = Self.render("| a |\n|---|\n| `x\\|y` \\| z |")
        #expect(html.contains("<td><code>x|y</code> | z</td>"))
    }
}
