import Foundation
import Testing
@testable import Dreamder

@Suite
struct MarkdownPreviewHeadingIDTests {
    struct AnchorCase: Sendable, CustomTestStringConvertible {
        let markdown: String
        let expected: String

        var testDescription: String { markdown }
    }

    static let intelliJCases: [AnchorCase] = [
        AnchorCase(markdown: "# Some header text", expected: "some-header-text"),
        AnchorCase(markdown: "# Some header ![img](url) suffix", expected: "some-header--suffix"),
        AnchorCase(markdown: "# ![img](url) Some header", expected: "-some-header"),
        AnchorCase(markdown: "# -  ^Foo* ?baR <baz", expected: "--foo-bar-baz"),
        AnchorCase(markdown: "# This header has 3.5 in it (and parentheses)", expected: "this-header-has-35-in-it-and-parentheses")
    ]

    static let moreIntelliJCases: [AnchorCase] = [
        AnchorCase(markdown: "Some header text\n---", expected: "some-header-text"),
        AnchorCase(markdown: "Some header text\n===", expected: "some-header-text"),
        AnchorCase(
            markdown: "Some header [Some link text](https://jetbrains.com) suffix\n---",
            expected: "some-header-some-link-text-suffix"
        ),
        AnchorCase(
            markdown: "# Some header [Some link text](https://jetbrains.com) suffix",
            expected: "some-header-some-link-text-suffix"
        ),
        AnchorCase(markdown: "# Some header ![Some image text](https://jetbrains.com)", expected: "some-header-"),
        AnchorCase(
            markdown: "# Some header [![Some image text](https://jetbrains.com)](https://example.com) suffix",
            expected: "some-header--suffix"
        ),
        AnchorCase(
            markdown: "# Some header [Some link ![Some image text](https://jetbrains.com) text](https://example.com) suffix",
            expected: "some-header-some-link--text-suffix"
        ),
        AnchorCase(markdown: "# This header has Unicode in it 한글", expected: "this-header-has-unicode-in-it-한글"),
        AnchorCase(markdown: "# This header has 3.5 in it [and brackets]", expected: "this-header-has-35-in-it-and-brackets")
    ]

    private static func headingIDs(in markdown: String) -> [String] {
        let html = MarkdownHTMLRenderer.bodyHTML(from: markdown)
        let pattern = #"<h[1-6] id="([^"]*)""#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsHTML = html as NSString
        return expression.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)).map {
            nsHTML.substring(with: $0.range(at: 1))
        }
    }

    @Test(arguments: intelliJCases)
    func headerAnchorTextMatchesIntelliJ(_ example: AnchorCase) {
        #expect(Self.headingIDs(in: example.markdown) == [example.expected])
    }

    @Test(arguments: moreIntelliJCases)
    func headerAnchorTextMatchesRemainingIntelliJCases(_ example: AnchorCase) {
        #expect(Self.headingIDs(in: example.markdown) == [example.expected])
    }

    @Test
    func duplicateHeadersGetNumericSuffixesInDocumentOrder() {
        let markdown = "# Some header\n\n## Some header\n\ntext\n\nSome header\n---\n\n# Other\n\n# Some header"
        #expect(Self.headingIDs(in: markdown) == [
            "some-header", "some-header-1", "some-header-2", "other", "some-header-3"
        ])
    }

    @Test
    func duplicateCountingIsPerRawAnchor() {
        let markdown = "# A\n\n# B\n\n# A\n\n# B\n\n# A"
        #expect(Self.headingIDs(in: markdown) == ["a", "b", "a-1", "b-1", "a-2"])
    }

    @Test
    func headersInsideQuotesAndListsAreNumberedInDocumentOrder() {
        let markdown = "# Title\n\n> # Title\n\n- # Title"
        #expect(Self.headingIDs(in: markdown) == ["title", "title-1", "title-2"])
    }

    @Test
    func htmlBlockHeadersDoNotConsumeAnchors() {
        let markdown = "<h1>Title</h1>\n\n# Title"
        #expect(Self.headingIDs(in: markdown) == ["title"])
    }

    @Test
    func emptyHeaderHasNoIdentifier() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "#\n\n# Text")
        #expect(MarkdownPreviewTestSupport.stripped(html) == "<h1></h1>\n<h1>Text</h1>")
        #expect(Self.headingIDs(in: "#\n\n# Text") == ["text"])
    }

    @Test
    func entitiesAreDecodedBeforeSanitizing() {
        #expect(Self.headingIDs(in: "# Fish &amp; Chips &copy; 2024") == ["fish--chips--2024"])
        #expect(Self.headingIDs(in: "# Tom &#38; Jerry") == ["tom--jerry"])
    }

    @Test
    func underscoresAndDashesSurviveAndSpacesBecomeDashes() {
        #expect(Self.headingIDs(in: "# snake_case-name  and tab\tsplit") == ["snake_case-name-and-tab-split"])
    }

    @Test
    func headerLinksResolveToGeneratedIdentifiers() {
        let markdown = "# Table of Contents\n\n- [Motivation](#motivation)\n\n## Motivation"
        let html = MarkdownHTMLRenderer.bodyHTML(from: markdown)
        #expect(html.contains("<h2 id=\"motivation\""))
        #expect(html.contains("<a href=\"#motivation\">Motivation</a>"))
    }
}
