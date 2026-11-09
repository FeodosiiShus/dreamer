import Foundation
import Testing
@testable import Dreamder

@Suite
struct MarkdownHTMLRendererCoverageTests {
    @Test
    func documentWithoutBaseURLHasNoBaseTag() {
        let html = MarkdownHTMLRenderer.documentHTML(
            body: "<p>x</p>",
            baseURL: nil,
            palette: MarkdownPreviewFixtures.darkPalette
        )
        #expect(!html.contains("<base"))
        #expect(html.contains("<body>\n<p>x</p>\n</body>"))
        #expect(html.contains(MarkdownPreviewStyles.stylesheet(palette: MarkdownPreviewFixtures.darkPalette)))
    }

    @Test
    func baseURLGetsTrailingSlash() throws {
        let directory = try #require(URL(string: "file:///tmp/notes"))
        let html = MarkdownHTMLRenderer.documentHTML(
            body: "",
            baseURL: directory,
            palette: MarkdownPreviewFixtures.darkPalette
        )
        #expect(html.contains("<base href=\"file:///tmp/notes/\">"))
    }

    @Test
    func baseURLWithTrailingSlashIsKept() throws {
        let directory = try #require(URL(string: "file:///tmp/notes/"))
        let html = MarkdownHTMLRenderer.documentHTML(
            body: "",
            baseURL: directory,
            palette: MarkdownPreviewFixtures.darkPalette
        )
        #expect(html.contains("<base href=\"file:///tmp/notes/\">"))
        #expect(!html.contains("notes//"))
    }

    @Test
    func bodyHTMLHonoursSourcePositionSwitch() {
        #expect(MarkdownHTMLRenderer.bodyHTML(from: "# a").contains("md-src-pos"))
        #expect(!MarkdownHTMLRenderer.bodyHTML(from: "# a", includesSourcePositions: false).contains("md-src-pos"))
    }
}
