import CodeEditSourceEditor
import Foundation
import Testing
@testable import Dreamder

struct MarkdownHighlightingAnnotatorTests {
    private func runs(_ text: String) -> [HighlightRange] {
        let whole = NSRange(location: 0, length: (text as NSString).length)
        let result = MarkdownHighlightProvider.highlights(text: text, in: whole)
        var previousEnd = 0
        for run in result {
            #expect(run.range.length > 0)
            #expect(run.range.location >= previousEnd)
            previousEnd = run.range.location + run.range.length
        }
        return result
    }

    private func captures(of fragment: String, occurrence: Int = 0, in text: String) -> [CaptureName?] {
        let start = MarkdownLexerSupport.offset(of: fragment, in: text, occurrence: occurrence)
        guard start != NSNotFound else { return [] }
        let highlights = runs(text)
        return (start..<(start + (fragment as NSString).length)).map { offset in
            highlights.first { NSLocationInRange(offset, $0.range) }?.capture
        }
    }

    private func uniform(_ capture: CaptureName?, count: Int) -> [CaptureName?] {
        Array(repeating: capture, count: count)
    }

    private func intersectsAny(_ range: NSRange, kinds: [MarkdownTokenKind], in text: String) -> Bool {
        MarkdownLexerSupport.tokens(text).contains { token in
            kinds.contains(token.kind) && NSIntersectionRange(token.range, range).length > 0
        }
    }

    private func headerContentKinds() -> [MarkdownTokenKind] {
        (1...6).map { MarkdownTokenKind.headerContent(level: $0) }
    }

    @Test func headersKeepLevelHighlighting() {
        let text = "# Strong **Header**\n\nSetext Header\n==="
        #expect(MarkdownLexerSupport.kinds(of: "Strong", in: text).contains(.headerContent(level: 1)))
        #expect(MarkdownLexerSupport.kinds(of: "Header", in: text).contains(.headerContent(level: 1)))
        #expect(MarkdownLexerSupport.kinds(of: "Header", in: text).contains(.bold))
        #expect(MarkdownLexerSupport.kinds(of: "Setext Header", in: text).contains(.headerContent(level: 1)))
        let headerTexts = MarkdownLexerSupport.texts(of: .headerContent(level: 1), in: text)
        #expect(headerTexts == ["Strong **Header**", "Setext Header"])
    }

    @Test(arguments: ["#", "##", "==="])
    func containerMarkersKeepMarkerHighlighting(marker: String) {
        let text = "# Heading Level 1\n## Heading Level 2\n\nSetext Header\n===\n\n> Blockquote"
        let exact = MarkdownLexerSupport.exactKinds(of: marker, in: text)
        #expect(exact == [.headerMarker])
        let markerRange = NSRange(location: MarkdownLexerSupport.offset(of: marker, in: text), length: marker.count)
        #expect(!intersectsAny(markerRange, kinds: headerContentKinds(), in: text))
    }

    @Test func blockQuoteMarkerKeepsMarkerHighlighting() {
        let text = "# Heading Level 1\n## Heading Level 2\n\nSetext Header\n===\n\n> Blockquote"
        let exact = MarkdownLexerSupport.exactKinds(of: ">", in: text)
        #expect(exact == [.blockQuoteMarker])
        let quote = MarkdownLexerSupport.texts(of: .blockQuote, in: text)
        #expect(quote == ["> Blockquote"])
    }

    @Test func blockQuoteLinesAreHighlightedUpToTheirLineBreaks() {
        let text = "- > a [link](x) `code`\n  > > b\n\ntail"
        let lines = MarkdownLexerSupport.texts(of: .blockQuote, in: text)
        #expect(lines == ["> a [link](x) `code`\n", "> > b", "\n"])
        #expect(MarkdownLexerSupport.exactKinds(of: "link", in: text).isEmpty)
        #expect(MarkdownLexerSupport.kinds(of: "link", in: text).contains(.linkText))
        let codeSpans = MarkdownLexerSupport.texts(of: .codeSpan, in: text)
        #expect(codeSpans == ["`code`"])
    }

    @Test func inlineFormattingAndLinksKeepInheritedHighlighting() {
        let text = "A **bold** and *italic* [link](target.md)"
        #expect(MarkdownLexerSupport.kinds(of: "bold", in: text).contains(.bold))
        #expect(MarkdownLexerSupport.kinds(of: "italic", in: text).contains(.italic))
        #expect(MarkdownLexerSupport.kinds(of: "link", in: text).contains(.linkText))
        #expect(MarkdownLexerSupport.exactKinds(of: "target.md", in: text) == [.linkDestination])
    }

    @Test func highlightCoversTextAndMarkers() {
        let text = "A ==marked **bold**== text"
        #expect(MarkdownLexerSupport.kinds(of: "marked", in: text).contains(.highlight))
        let boldKinds = MarkdownLexerSupport.kinds(of: "bold", in: text)
        #expect(boldKinds.contains(.highlight))
        #expect(boldKinds.contains(.bold))
        #expect(MarkdownLexerSupport.kinds(of: "==", in: text, occurrence: 0) == [.highlight])
        #expect(MarkdownLexerSupport.kinds(of: "==", in: text, occurrence: 1) == [.highlight])
        #expect(!MarkdownLexerSupport.kinds(of: "text", in: text).contains(.highlight))
        let highlighted = MarkdownLexerSupport.texts(of: .highlight, in: text)
        #expect(highlighted == ["==marked **bold**=="])
    }

    @Test(arguments: ["A =one= and ===three===", "=x=", "===x==="])
    func singleAndTripleEqualsAreNotHighlighted(text: String) {
        let highlighted = MarkdownLexerSupport.texts(of: .highlight, in: text)
        #expect(highlighted.isEmpty)
    }

    @Test func indentedFenceUsesFenceHighlighting() {
        let text = "World\n\n    ```java\n    class C {}\n    ```"
        #expect(MarkdownLexerSupport.exactKinds(of: "```", in: text, occurrence: 0) == [.codeFenceMarker])
        #expect(MarkdownLexerSupport.exactKinds(of: "```", in: text, occurrence: 1) == [.codeFenceMarker])
        #expect(MarkdownLexerSupport.exactKinds(of: "java", in: text) == [.codeFenceLanguage])
        let codeBlocks = MarkdownLexerSupport.ranges(of: .codeBlock, in: text)
        #expect(codeBlocks.isEmpty)
        let classKinds = MarkdownLexerSupport.kinds(of: "class C {}", in: text)
        #expect(classKinds == [.codeFenceContent(hasLanguage: true)])
    }

    @Test func emptyIndentedFenceUsesFenceHighlighting() {
        let text = "    ```java\n    ```"
        #expect(MarkdownLexerSupport.exactKinds(of: "```", in: text, occurrence: 0) == [.codeFenceMarker])
        #expect(MarkdownLexerSupport.exactKinds(of: "```", in: text, occurrence: 1) == [.codeFenceMarker])
        #expect(MarkdownLexerSupport.exactKinds(of: "java", in: text) == [.codeFenceLanguage])
        let codeBlocks = MarkdownLexerSupport.ranges(of: .codeBlock, in: text)
        #expect(codeBlocks.isEmpty)
    }

    @Test func codeSpansKeepCodeSpanHighlightingInsideHeaders() {
        let text = "`Standalone`\n#### Header `Code`"
        #expect(MarkdownLexerSupport.kinds(of: "Standalone", in: text).contains(.codeSpan))
        let codeKinds = MarkdownLexerSupport.kinds(of: "Code", in: text)
        #expect(codeKinds.contains(.codeSpan))
        #expect(codeKinds.contains(.headerContent(level: 4)))
        let spans = MarkdownLexerSupport.texts(of: .codeSpan, in: text)
        #expect(spans == ["`Standalone`", "`Code`"])
        let markers = MarkdownLexerSupport.texts(of: .codeSpanMarker, in: text)
        #expect(markers == ["`", "`", "`", "`"])
    }

    @Test(arguments: [
        ("# Header `Code`", MarkdownTokenKind.headerContent(level: 1)),
        ("## Header `Code`", MarkdownTokenKind.headerContent(level: 2)),
        ("### Header `Code`", MarkdownTokenKind.headerContent(level: 3)),
        ("#### Header `Code`", MarkdownTokenKind.headerContent(level: 4)),
        ("##### Header `Code`", MarkdownTokenKind.headerContent(level: 5)),
        ("###### Header `Code`", MarkdownTokenKind.headerContent(level: 6)),
        ("**Bold `Code`**", MarkdownTokenKind.bold),
        ("*Italic `Code`*", MarkdownTokenKind.italic)
    ])
    func codeSpansKeepContainerHighlightingInDifferentContexts(text: String, container: MarkdownTokenKind) {
        let codeKinds = MarkdownLexerSupport.kinds(of: "Code", in: text)
        #expect(codeKinds.contains(.codeSpan))
        #expect(codeKinds.contains(container))
        let spans = MarkdownLexerSupport.texts(of: .codeSpan, in: text)
        #expect(spans == ["`Code`"])
    }

    @Test(arguments: [
        "- Item `Code`",
        "`First` and `Code`",
        "[Link](target.md) and `Code`"
    ])
    func codeSpansKeepCodeSpanHighlightingWithoutInheritedContainer(text: String) {
        let codeKinds = MarkdownLexerSupport.kinds(of: "Code", in: text)
        #expect(codeKinds.contains(.codeSpan))
        let spans = MarkdownLexerSupport.texts(of: .codeSpan, in: text)
        #expect(spans.last == "`Code`")
    }

    @Test func codeSpansKeepBoldAndItalicHighlighting() {
        let text = "_**Some `code`**_"
        let someKinds = MarkdownLexerSupport.kinds(of: "Some", in: text)
        #expect(someKinds.contains(.bold))
        #expect(someKinds.contains(.italic))
        let codeKinds = MarkdownLexerSupport.kinds(of: "code", in: text)
        #expect(codeKinds.contains(.bold))
        #expect(codeKinds.contains(.italic))
        #expect(codeKinds.contains(.codeSpan))
    }

    @Test func codeSpansKeepHeadingAndEmphasisHighlighting() {
        let text = "Setext ~~**`Header`**~~\n==="
        let kinds = MarkdownLexerSupport.kinds(of: "Header", in: text)
        #expect(kinds.contains(.strikethrough))
        #expect(kinds.contains(.bold))
        #expect(kinds.contains(.codeSpan))
        #expect(kinds.contains(.headerContent(level: 1)))
        let markers = MarkdownLexerSupport.exactKinds(of: "===", in: text)
        #expect(markers == [.headerMarker])
    }

    @Test func codeSpansKeepStrikethroughHighlighting() {
        let text = "~~_**Some `code`**_~~"
        let someKinds = MarkdownLexerSupport.kinds(of: "Some", in: text)
        #expect(someKinds.contains(.strikethrough))
        let codeKinds = MarkdownLexerSupport.kinds(of: "code", in: text)
        #expect(codeKinds.contains(.strikethrough))
        #expect(codeKinds.contains(.codeSpan))
        let strikes = MarkdownLexerSupport.texts(of: .strikethrough, in: text)
        #expect(strikes == ["~~_**Some `code`**_~~"])
    }

    @Test(arguments: 0..<4)
    func imagesKeepImageHighlightingInDifferentContexts(index: Int) {
        let text = "# Markdown WYSIWYG Demo\n\n![logo](../../imgs/unnamed.png)\n\n"
            + "![logo](../../imgs/unnamed.png)\n![logo](../../imgs/unnamed.png)\n\n"
            + "# Markdown WYSIWYG Demo\n\n\n![logo](../../imgs/unnamed.png)"
        let imageText = "![logo](../../imgs/unnamed.png)"
        let images = MarkdownLexerSupport.texts(of: .image, in: text)
        #expect(images == Array(repeating: imageText, count: 4))
        #expect(MarkdownLexerSupport.kinds(of: "!", in: text, occurrence: index) == [.image])
        let logoKinds = MarkdownLexerSupport.kinds(of: "logo", in: text, occurrence: index)
        #expect(logoKinds.contains(.linkText))
        #expect(logoKinds.contains(.image))
        let destinations = MarkdownLexerSupport.exactKinds(of: "../../imgs/unnamed.png", in: text, occurrence: index)
        #expect(destinations == [.linkDestination])
    }

    @Test func headerTextAndMarkerGetDifferentColors() {
        let text = "#### Header `Code`"
        #expect(captures(of: "####", in: text) == uniform(.keyword, count: 4))
        #expect(captures(of: " ", in: text) == uniform(nil, count: 1))
        #expect(captures(of: "Header ", in: text) == uniform(.variable, count: 7))
    }

    @Test func codeSpanInsideHeaderWinsOverHeaderColorAndBackticksKeepMarkerColor() {
        let text = "#### Header `Code`"
        #expect(captures(of: "`", occurrence: 0, in: text) == uniform(.keyword, count: 1))
        #expect(captures(of: "Code", in: text) == uniform(.string, count: 4))
        #expect(captures(of: "`", occurrence: 1, in: text) == uniform(.keyword, count: 1))
    }

    @Test func blockQuoteMarkerIsCommentAndTextIsUncolored() {
        let text = "> quote"
        #expect(captures(of: ">", in: text) == uniform(.comment, count: 1))
        #expect(captures(of: "quote", in: text) == uniform(nil, count: 5))
    }

    @Test func highlightSpanIsTypeAlternateIncludingMarkers() {
        let text = "==x=="
        #expect(captures(of: "==x==", in: text) == uniform(.typeAlternate, count: 5))
    }

    @Test func linkPartsGetTheirOwnColors() {
        let text = "[t](d \"x\")"
        #expect(captures(of: "[t]", in: text) == uniform(.number, count: 3))
        #expect(captures(of: "(", in: text) == uniform(.string, count: 1))
        #expect(captures(of: "d", in: text) == uniform(.number, count: 1))
        #expect(captures(of: "\"x\"", in: text) == uniform(.string, count: 3))
        #expect(captures(of: ")", in: text) == uniform(.string, count: 1))
    }

    @Test func boldMarkersInsideHeaderKeepMarkerColorWhileTextKeepsHeaderColor() {
        let text = "# Strong **Header**"
        #expect(captures(of: "Strong ", in: text) == uniform(.variable, count: 7))
        #expect(captures(of: "**", occurrence: 0, in: text) == uniform(.keyword, count: 2))
        #expect(captures(of: "Header", in: text) == uniform(.variable, count: 6))
        #expect(captures(of: "**", occurrence: 1, in: text) == uniform(.keyword, count: 2))
    }

    @Test func requestedRangeClipsTheRuns() {
        let text = "==x=="
        let clipped = MarkdownHighlightProvider.highlights(text: text, in: NSRange(location: 1, length: 3))
        #expect(clipped.count == 1)
        #expect(clipped.first?.range == NSRange(location: 1, length: 3))
        #expect(clipped.first?.capture == .typeAlternate)
    }

    @Test func textWithoutColoredTokensProducesNoRuns() {
        let text = "plain A =one= text"
        let whole = NSRange(location: 0, length: (text as NSString).length)
        let result = MarkdownHighlightProvider.highlights(text: text, in: whole)
        #expect(result.isEmpty)
    }
}
