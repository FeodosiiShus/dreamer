import Foundation
import Testing
@testable import Dreamder

@Suite
struct MarkdownSourcePositionTests {
    typealias Element = MarkdownPreviewTestSupport.PositionedElement

    private static let blocksDocument = """
    # H1

    para one
    line two

    ---

    > quote
    > more

    - a
    - b

    1. x

    ```swift
    code
    ```

        indented

    | a | b |
    |---|---|
    | 1 | 2 |
    """

    private static func element(_ tag: String, _ from: Int, _ to: Int) -> Element {
        Element(tag: tag, from: from, to: to)
    }

    private func positions(_ markdown: String) -> [Element] {
        MarkdownPreviewTestSupport.positions(in: MarkdownHTMLRenderer.bodyHTML(from: markdown))
    }

    @Test
    func everyBlockElementCarriesItsSourceRange() {
        let found = positions(Self.blocksDocument)
        let expected: [(String, String)] = [
            ("h1", "# H1"),
            ("p", "para one\nline two"),
            ("hr", "---"),
            ("blockquote", "> quote\n> more"),
            ("p", "quote\n> more"),
            ("ul", "- a\n- b"),
            ("li", "- a"),
            ("li", "- b"),
            ("ol", "1. x"),
            ("li", "1. x"),
            ("pre", "```swift\ncode\n```"),
            ("pre", "    indented"),
            ("table", "| a | b |\n|---|---|\n| 1 | 2 |"),
            ("tr", "| a | b |"),
            ("tr", "| 1 | 2 |")
        ]
        #expect(found.map(\.tag) == expected.map(\.0))
        #expect(found.map { MarkdownPreviewTestSupport.slice(Self.blocksDocument, $0) } == expected.map(\.1))
    }

    @Test
    func rangesUseUTF16Offsets() {
        let markdown = "😀 emoji\n\n# café 😀"
        #expect(positions(markdown) == [Self.element("p", 0, 8), Self.element("h1", 10, 19)])
    }

    @Test
    func rangesCountCarriageReturnLineFeedAsTwoUnits() {
        #expect(positions("a\r\nb\r\n\r\n# x") == [Self.element("p", 0, 4), Self.element("h1", 8, 11)])
    }

    @Test
    func rangesAreRelativeToTheWholeDocumentInsideContainers() {
        let markdown = "- a\n  - b\n  - c\n- d"
        #expect(positions(markdown) == [
            Self.element("ul", 0, 19),
            Self.element("li", 0, 15),
            Self.element("ul", 6, 15),
            Self.element("li", 6, 9),
            Self.element("li", 12, 15),
            Self.element("li", 16, 19)
        ])
    }

    @Test
    func setextHeadingCoversItsUnderline() {
        #expect(positions("Title\n=====\n\nSub\n---") == [Self.element("h1", 0, 11), Self.element("h2", 13, 20)])
    }

    @Test
    func taskItemsKeepTheirMarkerInTheRange() {
        let markdown = "- [ ] open\n- [x] done"
        let found = positions(markdown)
        #expect(found.map { MarkdownPreviewTestSupport.slice(markdown, $0) } == [
            markdown, "- [ ] open", "- [x] done"
        ])
    }

    @Test
    func unterminatedFenceRunsToTheEndOfTheDocument() {
        let markdown = "```\nunterminated\ncode"
        #expect(positions(markdown) == [Self.element("pre", 0, 21)])
    }

    @Test
    func leadingIndentIsExcludedAndTrailingWhitespaceIsTrimmed() {
        #expect(positions("  # indented heading  \n   > quote") == [
            Self.element("h1", 2, 20),
            Self.element("blockquote", 26, 33),
            Self.element("p", 28, 33)
        ])
    }

    @Test
    func looseListItemSpansItsBlankLines() {
        #expect(positions("- one\n\n  more\n- two") == [
            Self.element("ul", 0, 19),
            Self.element("li", 0, 13),
            Self.element("p", 2, 5),
            Self.element("p", 9, 13),
            Self.element("li", 14, 19),
            Self.element("p", 16, 19)
        ])
    }

    @Test
    func referenceDefinitionsProduceNoElementButKeepOffsets() {
        #expect(positions("[ref]: /u\n\ntext") == [Self.element("p", 11, 15)])
    }

    @Test
    func childRangesNestInsideTheirParents() {
        let found = positions(Self.blocksDocument)
        let quote = found.first { $0.tag == "blockquote" }
        let inner = found.first { $0.tag == "p" && ($0.from > (quote?.from ?? Int.max)) }
        #expect(quote != nil)
        #expect((inner?.from ?? 0) >= (quote?.from ?? 0))
        #expect((inner?.to ?? Int.max) <= (quote?.to ?? 0))
        #expect(found.map(\.from) == found.map(\.from).sorted())
    }

    @Test
    func sourcePositionsCanBeOmitted() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: Self.blocksDocument, includesSourcePositions: false)
        #expect(!html.contains("md-src-pos"))
        let withPositions = MarkdownHTMLRenderer.bodyHTML(from: Self.blocksDocument)
        #expect(html.contains("id=\"h1\""))
        #expect(MarkdownPreviewTestSupport.stripped(withPositions) == MarkdownPreviewTestSupport.stripped(html))
    }

    @Test
    func positionAttributeFormatIsFromDotDotTo() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "text")
        #expect(html == "<p md-src-pos=\"0..4\">text</p>")
    }

    @Test
    func headingIdentifierPrecedesTheSourcePosition() {
        #expect(MarkdownHTMLRenderer.bodyHTML(from: "# Hi") == "<h1 id=\"hi\" md-src-pos=\"0..4\">Hi</h1>")
    }

    @Test
    func sourceLinesSplitOnEveryLineEnding() {
        let lines = MarkdownSourceLine.split("a\nb\r\nc\rd")
        #expect(lines.map(\.text) == ["a", "b", "c", "d"])
        #expect(lines.map(\.offset) == [0, 2, 5, 7])
        #expect(MarkdownSourceLine.split("").map(\.text) == [""])
        #expect(MarkdownSourceLine.split("a\n").map(\.text) == ["a", ""])
    }
}
