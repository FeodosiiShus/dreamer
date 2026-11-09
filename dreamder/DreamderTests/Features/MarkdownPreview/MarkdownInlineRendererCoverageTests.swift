import Foundation
import Testing
@testable import Dreamder

private struct InlineCase {
    let markdown: String
    let html: String
}

private func expectInlineCases(_ cases: [InlineCase], context: MarkdownInlineContext = .empty) {
    for entry in cases {
        let html = MarkdownInlineRenderer.render(entry.markdown, context: context)
        #expect(html == entry.html, "\(entry.markdown.debugDescription)")
    }
}

@Suite
struct MarkdownInlineRendererCoverageTests {
    @Test
    func defaultContextAllowsLinksAndHasNoReferences() {
        #expect(MarkdownInlineContext.empty.allowsLinks)
        #expect(MarkdownInlineContext.empty.references.isEmpty)
        #expect(MarkdownInlineContext(allowsLinks: false).allowsLinks == false)
        #expect(MarkdownInlineRenderer.render("plain *em*") == "plain <em>em</em>")
    }

    @Test
    func unescapeLiteralResolvesEscapesAndEntities() {
        #expect(MarkdownInlineRenderer.unescapeLiteral("plain") == "plain")
        #expect(MarkdownInlineRenderer.unescapeLiteral("a\\*b") == "a*b")
        #expect(MarkdownInlineRenderer.unescapeLiteral("a\\qb") == "a\\qb")
        #expect(MarkdownInlineRenderer.unescapeLiteral("a\\") == "a\\")
        #expect(MarkdownInlineRenderer.unescapeLiteral("&amp;x") == "&x")
        #expect(MarkdownInlineRenderer.unescapeLiteral("&zzzz; & x") == "&zzzz; & x")
    }

    @Test
    func codeSpanStripsOneSurroundingSpace() {
        expectInlineCases([
            InlineCase(markdown: "` a `", html: "<code>a</code>"),
            InlineCase(markdown: "`  `", html: "<code>  </code>"),
            InlineCase(markdown: "`` ` ``", html: "<code>`</code>"),
            InlineCase(markdown: "` a", html: "` a"),
            InlineCase(markdown: "``a`", html: "``a`"),
            InlineCase(markdown: "`abc", html: "`abc")
        ])
    }

    @Test
    func underscoreWordBoundaries() {
        expectInlineCases([
            InlineCase(markdown: "1_2", html: "1_2"),
            InlineCase(markdown: "_a", html: "_a"),
            InlineCase(markdown: "a_", html: "a_"),
            InlineCase(markdown: "x_ y", html: "x_ y"),
            InlineCase(markdown: "_1_", html: "<em>1</em>")
        ])
    }

    @Test
    func unresolvedLinksStayLiteral() {
        expectInlineCases([
            InlineCase(markdown: "[a", html: "[a"),
            InlineCase(markdown: "![a", html: "![a"),
            InlineCase(markdown: "[[a]", html: "[[a]"),
            InlineCase(markdown: "[a](<b", html: "[a](&lt;b"),
            InlineCase(markdown: "[a](b \"t)", html: "[a](b &quot;t)"),
            InlineCase(markdown: "[a](b c)", html: "[a](b c)"),
            InlineCase(markdown: "[a][b]", html: "[a][b]"),
            InlineCase(markdown: "[a][b", html: "[a][b")
        ])
    }

    @Test
    func inlineLinkDestinationsAndTitles() {
        expectInlineCases([
            InlineCase(markdown: "[a](b(c)d)", html: "<a href=\"b(c)d\">a</a>"),
            InlineCase(markdown: "[a](b (t))", html: "<a href=\"b\" title=\"t\">a</a>"),
            InlineCase(markdown: "[a\\]b](u)", html: "<a href=\"u\">a]b</a>")
        ])
    }

    @Test
    func referenceLinksResolveThroughContext() {
        let context = MarkdownInlineContext(references: ["a": MarkdownLinkReference(destination: "/u", title: nil)])
        expectInlineCases([
            InlineCase(markdown: "[a][]", html: "<a href=\"/u\">a</a>"),
            InlineCase(markdown: "[x][a]", html: "<a href=\"/u\">x</a>"),
            InlineCase(markdown: "[a]", html: "<a href=\"/u\">a</a>"),
            InlineCase(markdown: "![a]", html: "<img src=\"/u\" alt=\"a\" />")
        ], context: context)
    }

    @Test
    func linksAreIgnoredInsideLinkLabels() {
        let context = MarkdownInlineContext(allowsLinks: false)
        expectInlineCases([
            InlineCase(markdown: "<http://x.y>", html: "&lt;http://x.y&gt;"),
            InlineCase(markdown: "http://x.y", html: "http://x.y"),
            InlineCase(markdown: "[a](b)", html: "[a](b)")
        ], context: context)
    }

    @Test
    func angleBracketsThatAreNotAutolinksStayText() {
        expectInlineCases([
            InlineCase(markdown: "<a:b>", html: "&lt;a:b&gt;"),
            InlineCase(markdown: "<1ab:c>", html: "&lt;1ab:c&gt;"),
            InlineCase(markdown: "<ab_c:d>", html: "&lt;ab_c:d&gt;"),
            InlineCase(markdown: "<a@b@c>", html: "&lt;a@b@c&gt;"),
            InlineCase(markdown: "<@b>", html: "&lt;@b&gt;"),
            InlineCase(markdown: "<a@>", html: "&lt;a@&gt;"),
            InlineCase(markdown: "<a(b@c.d>", html: "&lt;a(b@c.d&gt;"),
            InlineCase(markdown: "<\u{E9}@b.c>", html: "&lt;\u{E9}@b.c&gt;"),
            InlineCase(markdown: "<a@b..c>", html: "&lt;a@b..c&gt;"),
            InlineCase(markdown: "<a@-b.c>", html: "&lt;a@-b.c&gt;"),
            InlineCase(markdown: "<a@b_c.d>", html: "&lt;a@b_c.d&gt;")
        ])
        let longScheme = String(repeating: "a", count: 33)
        let longSchemeHTML = MarkdownInlineRenderer.render("<\(longScheme):x>")
        #expect(!longSchemeHTML.contains("<a href"))
        let longLabel = String(repeating: "a", count: 64)
        let longLabelHTML = MarkdownInlineRenderer.render("<a@\(longLabel).c>")
        #expect(!longLabelHTML.contains("<a href"))
    }

    @Test
    func validAngleAutolinks() {
        expectInlineCases([
            InlineCase(markdown: "<a+b.c-d:x>", html: "<a href=\"a+b.c-d:x\">a+b.c-d:x</a>"),
            InlineCase(markdown: "<a+b@c.d>", html: "<a href=\"mailto:a+b@c.d\">a+b@c.d</a>")
        ])
    }

    @Test
    func bareAutolinkBoundaries() {
        expectInlineCases([
            InlineCase(
                markdown: "http://x.y/a&amp;.",
                html: "<a href=\"http://x.y/a\">http://x.y/a</a>&amp;."
            ),
            InlineCase(
                markdown: "http://x.y/a&b1;",
                html: "<a href=\"http://x.y/a\">http://x.y/a</a>&amp;b1;"
            ),
            InlineCase(markdown: "www./x", html: "www./x"),
            InlineCase(markdown: "http:///x", html: "http:///x"),
            InlineCase(markdown: "www.a..b", html: "www.a..b"),
            InlineCase(markdown: "www.ex@mple.com", html: "www.ex@mple.com")
        ])
    }

    @Test
    func emphasisRuleOfThree() {
        expectInlineCases([
            InlineCase(markdown: "*foo**bar*", html: "<em>foo**bar</em>"),
            InlineCase(markdown: "foo***bar***baz", html: "foo<em><strong>bar</strong></em>baz")
        ])
    }

    @Test
    func delimiterRunThatClosesAndOpensEmitsClosingBeforeOpening() {
        expectInlineCases([
            InlineCase(markdown: "*a***b**", html: "<em>a</em><strong>b</strong>")
        ])
    }
}
