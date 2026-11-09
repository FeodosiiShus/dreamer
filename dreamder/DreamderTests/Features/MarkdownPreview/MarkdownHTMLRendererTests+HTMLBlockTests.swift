import Foundation
import Testing
@testable import Dreamder

extension MarkdownHTMLRendererTests {
    @Test
    func htmlBlockKind1ScriptIsRemoved() {
        let markdown = "<script>\nvar a = 1;\n</script>\n\ntext"
        let html = plainHTML(markdown)
        #expect(html == "<p>text</p>")
    }

    @Test
    func htmlBlockKind1PreIsVerbatim() {
        let markdown = "<pre>\nkeep *raw*\n</pre>\n\ntext"
        let html = plainHTML(markdown)
        #expect(html == "<pre>\nkeep *raw*\n</pre>\n<p>text</p>")
    }

    @Test
    func htmlBlockKind1TextareaTagsAreDroppedAndStyleElementsAreRemoved() {
        let markdown = "<textarea>\n*raw*\n</textarea>\n\n<style>\nbody { color: red }\n</style>"
        let html = plainHTML(markdown)
        #expect(html.contains("*raw*"))
        #expect(!html.contains("<textarea"))
        #expect(!html.contains("color: red"))
    }

    @Test
    func htmlBlockKind2CommentIsVerbatim() {
        let markdown = "<!-- hidden -->\n\ntext"
        let html = plainHTML(markdown)
        #expect(html == "<!-- hidden -->\n<p>text</p>")
    }

    @Test
    func htmlBlockKind3InstructionIsVerbatim() {
        let markdown = "<?php echo 1; ?>\n\ntext"
        let html = plainHTML(markdown)
        #expect(html == "<?php echo 1; ?>\n<p>text</p>")
    }

    @Test
    func htmlBlockKind4DeclarationIsVerbatim() {
        let markdown = "<!DOCTYPE html>\n\ntext"
        let html = plainHTML(markdown)
        #expect(html == "<!DOCTYPE html>\n<p>text</p>")
    }

    @Test
    func htmlBlockKind5CDataIsVerbatimWhenItCannotEndEarly() {
        let markdown = "<![CDATA[raw]]>\n\ntext"
        let html = plainHTML(markdown)
        #expect(html == "<![CDATA[raw]]>\n<p>text</p>")
    }

    @Test
    func htmlBlockKind5CDataWithAnAngleBracketInsideIsDropped() {
        let markdown = "<![CDATA[raw <tag>]]>\n\ntext"
        let html = plainHTML(markdown)
        #expect(html == "<p>text</p>")
    }

    @Test
    func htmlBlockKind6BlockTagIsVerbatim() {
        let markdown = "<div class=\"x\">\ncontent *not em*\n</div>\n\ntext"
        let html = plainHTML(markdown)
        #expect(html == "<div class=\"x\">\ncontent *not em*\n</div>\n<p>text</p>")
    }

    @Test
    func htmlBlockKind7UnknownTagAloneOnLineIsDropped() {
        let markdown = "<custom-tag>\n\ntext"
        let html = plainHTML(markdown)
        #expect(html == "<p>text</p>")
    }

    @Test
    func htmlBlockKind6InterruptsParagraph() {
        let html = plainHTML("text\n<div>block</div>")
        #expect(html == "<p>text</p>\n<div>block</div>")
    }

    @Test
    func htmlBlockKind7DoesNotInterruptParagraphAndTheUnknownTagIsDropped() {
        let html = plainHTML("text\n<custom-tag>")
        #expect(html.hasPrefix("<p>text"))
        #expect(!html.contains("custom-tag"))
    }

    @Test
    func htmlBlockEventHandlerAndUnknownAttributesAreStripped() {
        let markdown = "<div onclick=\"evil()\" data-x=\"1\" class=\"k\">\nhi\n</div>"
        let html = plainHTML(markdown)
        #expect(html == "<div class=\"k\">\nhi\n</div>")
    }

    @Test
    func sanitizerRemovesScriptElementsAndEventHandlers() {
        let html = MarkdownHTMLSanitizer.sanitize(
            "<div onClick=\"a()\">hi</div><script type=\"text/javascript\">bad()</script><img src=\"x\" onload='b()'>"
        )
        #expect(html == "<div>hi</div><img src=\"x\">")
    }

    @Test
    func sanitizerKeepsPlainTextUnchanged() {
        let text = "a < b and a & b"
        #expect(MarkdownHTMLSanitizer.sanitize(text) == text)
    }
}
