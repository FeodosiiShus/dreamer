import Foundation
import Testing
@testable import Dreamder

private func sanitizerParsedTag(_ text: String) -> MarkdownHTMLTag.ParsedTag? {
    MarkdownHTMLTag.parse(Array(text), at: 0)
}

@Suite
struct MarkdownHTMLSanitizerCoverageTests {
    @Test
    func parseRejectsMalformedTags() {
        let malformed = [
            "<", "<!", "<!1>", "<!>", "<!-- x", "<![CDATA[ x", "<? x", "</div x>", "</div", "<a b=\"x", "<a b=",
            "<a b=  ", "<a href=>", "<a /x>", "<a", "<a b", "<1>", "<a\"b\">"
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
            "<br />", "</div >"
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
    func selfClosingScriptElementIsDropped() {
        #expect(MarkdownHTMLSanitizer.sanitize("a<script/>b") == "ab")
        #expect(MarkdownHTMLSanitizer.sanitize("a<script src=x />b") == "ab")
        #expect(MarkdownHTMLSanitizer.sanitize("a<script>abc") == "a")
        #expect(MarkdownHTMLSanitizer.sanitize("a</script>b") == "a</script>b")
    }

    @Test
    func eventHandlersWithUnquotedAndSpacedValuesAreRemoved() {
        #expect(MarkdownHTMLSanitizer.sanitize("<div onclick=x() id=a>") == "<div id=a>")
        #expect(MarkdownHTMLSanitizer.sanitize("<div onclick = 'x()' id=a>") == "<div id=a>")
        #expect(MarkdownHTMLSanitizer.sanitize("<div ONCLICK=\"x\" class=\"c\">") == "<div class=\"c\">")
    }

    @Test
    func strippingHandlesIncompleteTagText() {
        #expect(MarkdownHTMLSanitizer.strippingEventHandlers(from: "<div ") == "<div ")
        #expect(MarkdownHTMLSanitizer.strippingEventHandlers(from: "<div !>") == "<div !>")
        #expect(MarkdownHTMLSanitizer.strippingEventHandlers(from: "<!-- x -->") == "<!-- x -->")
        #expect(MarkdownHTMLSanitizer.strippingEventHandlers(from: "</div>") == "</div>")
        #expect(MarkdownHTMLSanitizer.strippingEventHandlers(from: "<div onclick='x>") == "<div")
        #expect(MarkdownHTMLSanitizer.strippingEventHandlers(from: "<") == "<")
    }
}
