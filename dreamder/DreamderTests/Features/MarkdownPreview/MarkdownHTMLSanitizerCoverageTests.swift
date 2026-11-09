import Foundation
import Testing
@testable import Dreamder

private func sanitizerParsedTag(_ text: String) -> MarkdownHTMLTag.ParsedTag? {
    MarkdownHTMLTag.parse(Array(text), at: 0)
}

private func expectSanitized(_ cases: [(input: String, output: String)]) {
    for entry in cases {
        #expect(MarkdownHTMLSanitizer.sanitize(entry.input) == entry.output, "\(entry.input.debugDescription)")
    }
}

@Suite
struct MarkdownHTMLSanitizerCoverageTests {
    @Test
    func parseRejectsMalformedTags() {
        let malformed = [
            "<", "<!", "<!1>", "<!>", "<!-- x", "<![CDATA[ x", "<? x", "</div x>", "</div", "<a b=\"x", "<a b=",
            "<a b=  ", "<a href=>", "<a /x>", "<a", "<a b", "<1>", "<a\"b\">", "<a ", "<a   ", "<a b "
        ]
        for text in malformed {
            #expect(sanitizerParsedTag(text) == nil, "\(text)")
        }
        #expect(MarkdownHTMLTag.parse(Array("x"), at: 0) == nil)
        #expect(MarkdownHTMLTag.parse(Array("<a>"), at: 3) == nil)
    }

    @Test
    func parseAcceptsAttributeForms() {
        let accepted = [
            "<a href = x>", "<a href=x>", "<a b =  x>", "<a href='x'>", "<a href=\"x\" b>", "<a/>", "<a b/>",
            "<br />", "</div >", "<a _x>", "<a :x>", "<a _x=1 :y='2'>"
        ]
        for text in accepted {
            let tag = sanitizerParsedTag(text)
            #expect(tag?.text == text, "\(text)")
            #expect(tag?.endIndex == text.count - 1, "\(text)")
        }
    }

    @Test
    func parseClassifiesSpecialTags() {
        #expect(sanitizerParsedTag("<!-- c -->")?.name == "#comment")
        #expect(sanitizerParsedTag("<![CDATA[x]]>")?.name == "#cdata")
        #expect(sanitizerParsedTag("<!DOCTYPE html>")?.name == "#declaration")
        #expect(sanitizerParsedTag("<?php ?>")?.name == "#instruction")
        #expect(sanitizerParsedTag("</div >")?.isClosing == true)
        #expect(sanitizerParsedTag("<div>")?.isClosing == false)
    }

    @Test
    func scriptAndStyleElementsAreRemovedWithTheirContent() {
        expectSanitized([
            ("a<script>x()</script>b", "ab"),
            ("a<SCRIPT>x()</SCRIPT>b", "ab"),
            ("<style>p { color: red }</style><p>t</p>", "<p>t</p>"),
            ("x<script>if (a<b) {} <p></p></script>y", "xy"),
            ("a<script/>b", "ab"),
            ("a<script src=x />b", "ab"),
            ("a<script>abc", "a"),
            ("a</script>b", "ab"),
            ("a</style>b", "ab")
        ])
    }

    @Test
    func eventHandlersWithUnquotedAndSpacedValuesAreRemoved() {
        expectSanitized([
            ("<div onclick=x() id=a>", "<div id=\"user-content-a\">"),
            ("<div onclick = 'x()' id=a>", "<div id=\"user-content-a\">"),
            ("<div ONCLICK=\"x\" class=\"c\">", "<div class=\"c\">")
        ])
    }

    @Test
    func elementsOutsideTheAllowlistLoseTheirTagsAndKeepTheirText() {
        expectSanitized([
            ("<iframe src=\"x\"></iframe>", ""),
            ("<object data=\"x\"></object>", ""),
            ("<embed src=\"x\">", ""),
            ("<form action=\"x\"><p>t</p></form>", "<p>t</p>"),
            ("<meta http-equiv=\"refresh\" content=\"0;url=file:///etc/hosts\">", ""),
            ("<base href=\"file:///\">", ""),
            ("<link rel=\"stylesheet\" href=\"https://evil.example/x.css\">", ""),
            ("<svg onload=\"x\"><circle/></svg>", ""),
            ("<math><mi>x</mi></math>", "x"),
            ("<textarea>t</textarea>", "t"),
            ("<button>b</button>", "b"),
            ("<video src=x></video>", ""),
            ("<custom-tag>t</custom-tag>", "t")
        ])
    }

    @Test
    func angleBracketsThatDoNotFormATagAreEscapedWhenABrowserCouldReadThemAsMarkup() {
        expectSanitized([
            ("<iframe src=x", "&lt;iframe src=x"),
            ("<a href=\"x", "&lt;a href=\"x"),
            ("<!x", "&lt;!x"),
            ("<?x", "&lt;?x"),
            ("</", "&lt;/"),
            ("a < b", "a < b"),
            ("1<2", "1<2"),
            ("tail<", "tail<"),
            ("<<b>", "<<b>")
        ])
    }

    @Test
    func commentsAreKeptOnlyWhenEveryBrowserEndsThemAtTheSamePlace() {
        expectSanitized([
            ("a<!-- note -->b", "a<!-- note -->b"),
            ("a<!---->b", "a<!---->b"),
            ("a<!--> <iframe src=x> -->b", "ab"),
            ("a<!--> <b> -->b", "ab"),
            ("a<!--->x<iframe src=x> -->b", "ab"),
            ("a<!-- x --!> <iframe src=x> -->b", "ab")
        ])
    }

    @Test
    func declarationsAndInstructionsAreKeptOnlyWhenTheyEndAtTheFirstAngleBracket() {
        expectSanitized([
            ("<!DOCTYPE html>", "<!DOCTYPE html>"),
            ("<?xml version=\"1.0\"?>", "<?xml version=\"1.0\"?>"),
            ("<? > <iframe src=x> ?>", ""),
            ("<![CDATA[raw]]>", "<![CDATA[raw]]>"),
            ("<![CDATA[ > <iframe src=x> ]]>", "")
        ])
    }

    @Test
    func attributesOutsideTheAllowlistAreRemovedAndTheRestKeepsItsSpelling() {
        expectSanitized([
            (
                "<div onclick=\"a()\" onmouseover=b() style=\"background:url(x)\" "
                    + "id=\"k\" class='c' data-x=1 title = \"t\">",
                "<div id=\"user-content-k\" class='c' title = \"t\">"
            ),
            ("<DIV ID=\"k\" CLASS=\"c\">", "<DIV id=\"user-content-k\" CLASS=\"c\">"),
            ("<details open>", "<details open>"),
            ("<p hidden>", "<p>"),
            ("<br/>", "<br/>"),
            ("<img src=\"a.png\" onerror=x />", "<img src=\"a.png\" />"),
            ("<p aria-label=\"x\" aria-hidden=true>", "<p aria-label=\"x\" aria-hidden=true>"),
            ("<div\nid=\"a\"\n>", "<div\nid=\"user-content-a\"\n>"),
            ("<a href=\"x\" src=\"y\" colspan=\"2\">t</a>", "<a href=\"x\">t</a>"),
            ("<td colspan=\"2\" nowrap>", "<td colspan=\"2\" nowrap>"),
            ("<div colspan=\"2\">", "<div>"),
            ("<img src=\"a.png\" href=\"b\" alt=\"c\">", "<img src=\"a.png\" alt=\"c\">"),
            ("<ol start=\"3\" type=\"a\" reversed>", "<ol start=\"3\" type=\"a\" reversed>"),
            ("<table border=\"1\" style=\"x\" target=\"_blank\" name=\"n\">", "<table border=\"1\">"),
            ("<a href target=\"_blank\" ping=\"https://evil.example\">", "<a href>")
        ])
    }

    @Test
    func inputsAreKeptOnlyAsCheckboxes() {
        expectSanitized([
            ("<input type=\"checkbox\" checked disabled>", "<input type=\"checkbox\" checked disabled>"),
            ("<input type=\"CHECKBOX\" disabled>", "<input type=\"CHECKBOX\" disabled>"),
            ("<input type=checkbox>", "<input type=checkbox>"),
            ("<input type=\"checkbox\" onclick=\"x\" name=\"n\">", "<input type=\"checkbox\">"),
            ("<input type=\"text\">", ""),
            ("<input type=\"image\" src=\"x\">", ""),
            ("<input>", "")
        ])
    }

    @Test
    func hyperlinkTargetsAreLimitedToWebMailAndRelativeAddresses() {
        let refused = [
            "javascript:alert(1)", "JaVaScRiPt:alert(1)", "  javascript:alert(1)", "java&#115;cript:alert(1)",
            "&#x6A;avascript:alert(1)", "jav&#x09;ascript:x", "java\tscript:x", "java\nscript:x",
            "javascript&colon;alert(1)", "&#106;avascript:x", "data:text/html,x", "vbscript:x", "file:///etc/passwd",
            "x-apple.systempreferences:x", "a:b", "\u{1}javascript:x", "ftp://example.com/x"
        ]
        for value in refused {
            #expect(
                MarkdownHTMLSanitizer.sanitize("<a href=\"\(value)\">t</a>") == "<a>t</a>",
                "\(value.debugDescription)"
            )
        }
        let kept = [
            "https://example.com/a?b=1&c=2", "HTTP://EXAMPLE.COM", "mailto:a@b.co", "a.md", "../a.md#h", "#anchor",
            "?q=1", "docs/a:b.md", "//example.com/x", ""
        ]
        for value in kept {
            let html = "<a href=\"\(value)\">t</a>"
            #expect(MarkdownHTMLSanitizer.sanitize(html) == html, "\(value.debugDescription)")
        }
    }

    @Test
    func imageSourcesAreLimitedToWebRelativeAndInlineImages() {
        let refused = [
            "javascript:x", "data:text/html;base64,AA", "mailto:a@b.co", "file:///etc/passwd", "ftp://x/a.png",
            "da&#116;a:text/html,x", "a&b.png"
        ]
        for value in refused {
            #expect(
                MarkdownHTMLSanitizer.sanitize("<img src=\"\(value)\">") == "<img>",
                "\(value.debugDescription)"
            )
        }
        let kept = [
            "https://x.y/a.png", "http://x.y/a.png", "a.png", "data:image/png;base64,AAAA",
            "DATA:IMAGE/PNG;base64,AA", "x.png?a=1&b=2"
        ]
        for value in kept {
            let html = "<img src=\"\(value)\">"
            #expect(MarkdownHTMLSanitizer.sanitize(html) == html, "\(value.debugDescription)")
        }
    }

    @Test
    func urlCheckDecodesEntitiesAndIgnoresControlCharactersBeforeLookingAtTheScheme() {
        let web = MarkdownHTMLSanitizer.linkSchemes
        #expect(MarkdownHTMLSanitizer.isSafeURL("https&#58;//x.y", schemes: web, allowsInlineImages: false))
        #expect(!MarkdownHTMLSanitizer.isSafeURL("&#x6A;avascript:1", schemes: web, allowsInlineImages: false))
        #expect(!MarkdownHTMLSanitizer.isSafeURL("a&b.png", schemes: web, allowsInlineImages: false))
        #expect(MarkdownHTMLSanitizer.isSafeURL("x.png?a=1&b=2", schemes: web, allowsInlineImages: false))
        #expect(!MarkdownHTMLSanitizer.isSafeURL("data:image/png;base64,AA", schemes: web, allowsInlineImages: false))
        #expect(MarkdownHTMLSanitizer.isSafeURL("data:image/png;base64,AA", schemes: web, allowsInlineImages: true))
    }
}
