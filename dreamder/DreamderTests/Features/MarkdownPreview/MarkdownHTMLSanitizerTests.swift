import Foundation
import Testing
@testable import Dreamder

@Suite
struct MarkdownHTMLSanitizerTests {
    @Test
    func generatedElementsAndAttributesPassThroughUntouched() {
        let html = "<h1 id=\"title\" md-src-pos=\"0..7\"><del>a</del> <mark>b</mark></h1>"
        #expect(MarkdownHTMLSanitizer.sanitize(html) == html)
    }

    @Test
    func rawHTMLWithDelAndMarkIsKept() {
        let html = MarkdownPreviewTestSupport.plainHTML("<div><del>x</del><mark>y</mark></div>")
        #expect(html == "<div><del>x</del><mark>y</mark></div>")
    }

    @Test
    func eventHandlersAreRemovedWhileIdentifiersAndPositionsStay() {
        let sanitized = MarkdownHTMLSanitizer.sanitize(
            "<h1 id=\"a\" onclick=\"x()\" md-src-pos=\"0..1\">t</h1>"
        )
        #expect(sanitized == "<h1 id=\"a\" md-src-pos=\"0..1\">t</h1>")
    }

    @Test
    func scriptElementsAreRemovedEvenNextToGeneratedMarkup() {
        let sanitized = MarkdownHTMLSanitizer.sanitize(
            "<p md-src-pos=\"0..5\">a</p><script>alert(1)</script><mark>b</mark>"
        )
        #expect(sanitized == "<p md-src-pos=\"0..5\">a</p><mark>b</mark>")
    }

    @Test
    func rendererOutputIsStableUnderSanitizing() {
        let markdown = "# Head\n\n~~gone~~ ==marked== <https://x.y>\n\n- [x] done\n\n```swift\nlet a = 1\n```"
        let html = MarkdownHTMLRenderer.bodyHTML(from: markdown)
        #expect(MarkdownHTMLSanitizer.sanitize(html) == html)
    }

    @Test
    func userSuppliedEventHandlersInBlocksAreStrippedButMarkdownPositionsAreNotInjected() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "<div onclick=\"evil()\">\nhi\n</div>")
        #expect(html == "<div>\nhi\n</div>")
    }
}
