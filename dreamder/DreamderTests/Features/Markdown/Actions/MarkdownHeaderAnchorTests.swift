import Testing

@testable import Dreamder

struct MarkdownHeaderAnchorTests {
    private func anchor(ofFirstHeaderIn markdown: String) -> String? {
        let document = MarkdownDocument(markdown)
        guard let index = document.blocks.firstIndex(where: { $0.isHeading }),
              let content = document.headerContent(ofBlock: index) else { return nil }
        return MarkdownHeaderAnchor.rawAnchor(forHeaderContent: content)
    }

    @Test(arguments: [
        ("# Some header text", "some-header-text"),
        ("Some header text\n---", "some-header-text"),
        ("Some header text\n===", "some-header-text"),
        ("Some header [Some link text](https://jetbrains.com) suffix\n---", "some-header-some-link-text-suffix"),
        ("# Some header [Some link text](https://jetbrains.com) suffix", "some-header-some-link-text-suffix"),
        ("# Some header ![Some image text](https://jetbrains.com) suffix", "some-header--suffix"),
        ("# Some header ![Some image text](https://jetbrains.com)", "some-header-"),
        ("# ![Some image text](https://jetbrains.com) Some header", "-some-header"),
        (
            "# Some header [![Some image text](https://jetbrains.com)](https://example.com) suffix",
            "some-header--suffix"
        ),
        (
            "# Some header [Some link ![Some image text](https://jetbrains.com) text](https://example.com) suffix",
            "some-header-some-link--text-suffix"
        ),
        ("# -  ^Foo* ?baR <baz", "--foo-bar-baz"),
        ("# This header has Unicode in it 한글", "this-header-has-unicode-in-it-한글"),
        ("# This header has 3.5 in it (and parentheses)", "this-header-has-35-in-it-and-parentheses"),
        ("# This header has 3.5 in it [and brackets]", "this-header-has-35-in-it-and-brackets"),
    ])
    func headerAnchorText(markdown: String, expected: String) {
        #expect(anchor(ofFirstHeaderIn: markdown) == expected)
    }

    @Test func htmlCommentIsDroppedAndTrailingSpaceTrimmed() {
        let result = anchor(ofFirstHeaderIn: "## Title <!-- omit from toc -->")
        #expect(result == "title")
    }

    @Test func htmlCommentInMiddleKeepsSurroundingSpaces() {
        let result = anchor(ofFirstHeaderIn: "## Title <!-- note --> tail")
        #expect(result == "title--tail")
    }

    @Test func closingHashesAreNotPartOfAnchor() {
        let result = anchor(ofFirstHeaderIn: "## Title ##")
        #expect(result == "title")
    }

    @Test func emptyHeaderHasNoAnchor() {
        let result = anchor(ofFirstHeaderIn: "#")
        #expect(result == nil)
    }

    @Test(arguments: [
        ("# a &amp; b", "a--b"),
        ("# caf&#233;", "café"),
        ("# caf&#xE9;", "café"),
        ("# x&unknown;y", "xampunknowny"),
        ("# a&nbsp;b", "ab"),
    ])
    func entitiesAreDecodedBeforeCleaning(markdown: String, expected: String) {
        #expect(anchor(ofFirstHeaderIn: markdown) == expected)
    }

    @Test(arguments: [
        ("a &amp; b", "a & b"),
        ("&lt;&gt;&quot;", "<>\""),
        ("&#65;&#x42;", "AB"),
        ("&bogus;", "&amp;bogus;"),
        ("&#123456789;", "&#123456789;"),
        ("a & b", "a & b"),
    ])
    func replaceEntities(input: String, expected: String) {
        #expect(MarkdownHeaderAnchor.replaceEntities(input) == expected)
    }

    @Test func duplicatesGetNumberedSuffixes() {
        let result = MarkdownHeaderAnchor.uniqueAnchors(forRawAnchors: ["a", "b", "a", "a", "b"])
        #expect(result == ["a", "b", "a-1", "a-2", "b-1"])
    }

    @Test func visibleTextReplacesLinksByTheirTextAndDropsHtmlTags() {
        let content = "Some [link *text*](https://x.y) <b>bold</b> <!-- c -->"
        let result = MarkdownHeaderAnchor.visibleText(forHeaderContent: content)
        #expect(result == "Some link *text* bold")
    }

    @Test func visibleTextKeepsImagesAsIs() {
        let result = MarkdownHeaderAnchor.visibleText(forHeaderContent: "![alt](https://x.y/i.png) Title")
        #expect(result == "![alt](https://x.y/i.png) Title")
    }

    @Test func visibleTextOfEmptyContentIsNil() {
        let result = MarkdownHeaderAnchor.visibleText(forHeaderContent: "   ")
        #expect(result == nil)
    }
}
