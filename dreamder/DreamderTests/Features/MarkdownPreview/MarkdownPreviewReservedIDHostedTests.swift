import AppKit
import Testing
import WebKit
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct MarkdownPreviewReservedIDHostedTests {
    private static let timeout = Duration.seconds(20)

    @Test
    func rawHTMLWithThePreviewObjectNameDoesNotStopLaterUpdates() async throws {
        let harness = MarkdownPreviewWebViewCoverageHarness()
        defer { harness.close() }

        harness.show(MarkdownHTMLRenderer.bodyHTML(from: "<div id=\"dreamderPreview\">first</div>"))

        try await eventually(timeout: Self.timeout) {
            await harness.evaluate("typeof window.dreamderPreview.replaceBody") == "function"
        }
        harness.show(MarkdownHTMLRenderer.bodyHTML(from: "second"))
        try await eventually(timeout: Self.timeout) { await harness.bodyText() == "second" }
    }

    @Test
    func rawHTMLIdentifiersLiveInTheirOwnNamespaceInThePage() async throws {
        let harness = MarkdownPreviewWebViewCoverageHarness()
        defer { harness.close() }

        harness.show(MarkdownHTMLRenderer.bodyHTML(from: "<a id=\"custom\">anchor</a>\n\n# Title"))

        try await eventually(timeout: Self.timeout) {
            await harness.evaluate("typeof window.dreamderPreview.scrollToAnchor") == "function"
        }
        #expect(await harness.evaluate("document.getElementById('custom') === null ? 'none' : 'found'") == "none")
        #expect(
            await harness.evaluate("document.getElementById('user-content-custom') === null ? 'none' : 'found'")
                == "found"
        )
        #expect(await harness.evaluate("document.getElementById('title') === null ? 'none' : 'found'") == "found")
    }

    @Test
    func rawHTMLSourcePositionsDoNotPinTheScrollTarget() async throws {
        let harness = MarkdownPreviewWebViewCoverageHarness()
        defer { harness.close() }
        let markdown = "<div md-src-pos=\"0..100000000\">x</div>\n\npara"

        harness.show(MarkdownHTMLRenderer.bodyHTML(from: markdown))

        try await eventually(timeout: Self.timeout) {
            await harness.evaluate("typeof window.dreamderPreview.scrollToSourceOffset") == "function"
        }
        let positioned = await harness.evaluate(
            "Array.from(document.querySelectorAll('[md-src-pos]')).map(function (e) { return e.tagName; }).join(',')"
        )
        #expect(positioned == "P")
    }
}
