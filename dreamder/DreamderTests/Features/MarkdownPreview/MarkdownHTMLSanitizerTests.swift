import Foundation
import Testing
@testable import Dreamder

@Suite
struct MarkdownHTMLSanitizerTests {
    @Test
    func allowedElementsPassThroughWhileIdentifiersAreNamespacedAndPositionsDropped() {
        let html = "<h1 id=\"title\" md-src-pos=\"0..7\"><del>a</del> <mark>b</mark></h1>"
        let expected = "<h1 id=\"user-content-title\"><del>a</del> <mark>b</mark></h1>"
        #expect(MarkdownHTMLSanitizer.sanitize(html) == expected)
    }

    @Test
    func rawHTMLWithDelAndMarkIsKept() {
        let html = MarkdownPreviewTestSupport.plainHTML("<div><del>x</del><mark>y</mark></div>")
        #expect(html == "<div><del>x</del><mark>y</mark></div>")
    }

    @Test
    func eventHandlersAndPositionsAreRemovedWhileIdentifiersAreNamespaced() {
        let sanitized = MarkdownHTMLSanitizer.sanitize(
            "<h1 id=\"a\" onclick=\"x()\" md-src-pos=\"0..1\">t</h1>"
        )
        #expect(sanitized == "<h1 id=\"user-content-a\">t</h1>")
    }

    @Test
    func scriptElementsAreRemovedAndPositionsOfInjectedMarkupAreDropped() {
        let sanitized = MarkdownHTMLSanitizer.sanitize(
            "<p md-src-pos=\"0..5\">a</p><script>alert(1)</script><mark>b</mark>"
        )
        #expect(sanitized == "<p>a</p><mark>b</mark>")
    }

    @Test
    func rendererOutputWithoutHeadingsIsStableUnderSanitizing() {
        let markdown = "~~gone~~ ==marked== <https://x.y>\n\n- [x] done\n\n```swift\nlet a = 1\n```"
        let html = MarkdownHTMLRenderer.bodyHTML(from: markdown, includesSourcePositions: false)
        #expect(MarkdownHTMLSanitizer.sanitize(html) == html)
    }

    @Test
    func userSuppliedEventHandlersInBlocksAreStrippedButMarkdownPositionsAreNotInjected() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "<div onclick=\"evil()\">\nhi\n</div>")
        #expect(html == "<div>\nhi\n</div>")
    }

    @Test
    func dangerousRawHTMLNeverReachesTheRenderedBody() {
        let markdown = """
        <meta http-equiv="refresh" content="0;url=https://evil.example/">

        <iframe src="https://evil.example/"></iframe>

        <form action="https://evil.example/"><button>go</button></form>

        <a href="javascript:alert(1)">js</a> <a href="java&#115;cript:alert(2)">js2</a>

        <img src="x" onerror="alert(3)" srcset="https://evil.example/a.png 2x" \
        style="background:url(https://evil.example/b.png)">

        inline <object data="x"></object> and <embed src="x"> and <base href="file:///"> \
        and <link rel="stylesheet" href="x"> end

        <style>body { background: url(https://evil.example/c.png) }</style>

        <svg><script>alert(4)</script></svg>
        """

        let html = MarkdownHTMLRenderer.bodyHTML(from: markdown)

        for forbidden in [
            "<meta", "<iframe", "<form", "<button", "<object", "<embed", "<base", "<link", "<style", "<svg",
            "<script", "javascript:", "java&#115;", "onerror", "srcset", "style=", "evil.example/a.png",
            "evil.example/b.png", "evil.example/c.png", "http-equiv"
        ] {
            #expect(!html.contains(forbidden), "\(forbidden)")
        }
        #expect(html.contains("<img src=\"x\">"))
        #expect(html.contains("<a>js</a>"))
    }
}
