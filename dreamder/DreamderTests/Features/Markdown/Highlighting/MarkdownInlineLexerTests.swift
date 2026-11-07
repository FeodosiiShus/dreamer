import Foundation
import Testing
@testable import Dreamder

struct MarkdownInlineLexerTests {
    private func inline(_ text: String) -> [MarkdownTokenSample] {
        MarkdownInlineLexer.tokens(in: text).map {
            MarkdownTokenSample($0.kind, (text as NSString).substring(with: $0.range))
        }
    }

    private func inlineTexts(_ kind: MarkdownTokenKind, _ text: String) -> [String] {
        inline(text).filter { $0.kind == kind }.map(\.text)
    }

    private func inlineKinds(_ text: String) -> [MarkdownTokenKind] {
        inline(text).map(\.kind)
    }

    private func s(_ kind: MarkdownTokenKind, _ text: String) -> MarkdownTokenSample {
        MarkdownTokenSample(kind, text)
    }

    @Test(arguments: [
        ("*a*", MarkdownTokenKind.italic, MarkdownTokenKind.italicMarker, "*"),
        ("_a_", MarkdownTokenKind.italic, MarkdownTokenKind.italicMarker, "_"),
        ("**a**", MarkdownTokenKind.bold, MarkdownTokenKind.boldMarker, "**"),
        ("__a__", MarkdownTokenKind.bold, MarkdownTokenKind.boldMarker, "__")
    ])
    func emphasisProducesCompositeAndTwoMarkers(text: String, kind: MarkdownTokenKind, marker: MarkdownTokenKind, delimiter: String) {
        let actual = inline(text)
        #expect(actual == [s(kind, text), s(marker, delimiter), s(marker, delimiter)])
        let markerLocations = MarkdownInlineLexer.tokens(in: text).filter { $0.kind == marker }.map(\.range.location)
        #expect(markerLocations == [0, text.utf16.count - delimiter.utf16.count])
    }

    @Test
    func tripleDelimiterIsItalicOuterAndBoldInner() {
        let actual = inline("***x***")
        let expected = [
            s(.italic, "***x***"),
            s(.italicMarker, "*"),
            s(.bold, "**x**"),
            s(.boldMarker, "**"),
            s(.boldMarker, "**"),
            s(.italicMarker, "*")
        ]
        #expect(actual == expected)
        let locations = MarkdownInlineLexer.tokens(in: "***x***").map(\.range.location)
        #expect(locations == [0, 0, 1, 1, 4, 6])
    }

    @Test
    func ruleOfThreeNestsBoldInsideItalic() {
        let actual = inline("*foo**bar**baz*")
        let expected = [
            s(.italic, "*foo**bar**baz*"),
            s(.italicMarker, "*"),
            s(.bold, "**bar**"),
            s(.boldMarker, "**"),
            s(.boldMarker, "**"),
            s(.italicMarker, "*")
        ]
        #expect(actual == expected)
    }

    @Test
    func nestedBoldInsideItalic() {
        let actual = inline("*a **b** c*")
        let expected = [
            s(.italic, "*a **b** c*"),
            s(.italicMarker, "*"),
            s(.bold, "**b**"),
            s(.boldMarker, "**"),
            s(.boldMarker, "**"),
            s(.italicMarker, "*")
        ]
        #expect(actual == expected)
    }

    @Test(arguments: ["snake_case_word", "a__b__", "**unclosed", "a * not emphasis * b", "a ** b ** c"])
    func nonEmphasisInputsProduceNoTokens(text: String) {
        let actual = inline(text)
        #expect(actual.isEmpty)
    }

    @Test
    func asteriskIsEmphasisInsideWord() {
        let actual = inline("intra*word*")
        #expect(actual == [s(.italic, "*word*"), s(.italicMarker, "*"), s(.italicMarker, "*")])
        let digits = inline("2*3*4")
        #expect(digits == [s(.italic, "*3*"), s(.italicMarker, "*"), s(.italicMarker, "*")])
    }

    @Test
    func unmatchedLeadingBoldDelimiterLeavesInnerItalic() {
        let actual = inline("**a*")
        #expect(actual == [s(.italic, "*a*"), s(.italicMarker, "*"), s(.italicMarker, "*")])
    }

    @Test
    func codeSpanWithSingleBacktickRun() {
        let actual = inline("`a`")
        #expect(actual == [s(.codeSpan, "`a`"), s(.codeSpanMarker, "`"), s(.codeSpanMarker, "`")])
    }

    @Test
    func doubleBacktickRunMayContainSingleBacktick() {
        let actual = inline("``a`b``")
        #expect(actual == [s(.codeSpan, "``a`b``"), s(.codeSpanMarker, "``"), s(.codeSpanMarker, "``")])
    }

    @Test
    func unmatchedBacktickRunIsLiteral() {
        let actual = inline("`unmatched")
        #expect(actual.isEmpty)
        let mismatched = inline("``a`")
        #expect(mismatched.isEmpty)
    }

    @Test
    func codeSpanAcrossTwoParagraphLinesGivesTokenPerLine() {
        let text = "one `a\nb` two"
        let actual = MarkdownLexerSupport.samples(text)
        let expected = [
            s(.codeSpan, "`a"),
            s(.codeSpanMarker, "`"),
            s(.codeSpan, "b`"),
            s(.codeSpanMarker, "`")
        ]
        #expect(actual == expected)
        #expect(MarkdownLexerSupport.ranges(of: .codeSpan, in: text) == [NSRange(location: 4, length: 2), NSRange(location: 7, length: 2)])
    }

    @Test
    func emphasisInsideCodeSpanIsIgnored() {
        let actual = inline("*a `*b*` c*")
        let expected = [
            s(.italic, "*a `*b*` c*"),
            s(.italicMarker, "*"),
            s(.codeSpan, "`*b*`"),
            s(.codeSpanMarker, "`"),
            s(.codeSpanMarker, "`"),
            s(.italicMarker, "*")
        ]
        #expect(actual == expected)
        let onlySpan = inline("`*b*`")
        #expect(onlySpan == [s(.codeSpan, "`*b*`"), s(.codeSpanMarker, "`"), s(.codeSpanMarker, "`")])
    }

    @Test
    func backslashDoesNotEscapeInsideCodeSpan() {
        let actual = inline("`a\\*b`")
        #expect(actual == [s(.codeSpan, "`a\\*b`"), s(.codeSpanMarker, "`"), s(.codeSpanMarker, "`")])
    }

    @Test
    func inlineLinkWithDestinationAndTitle() {
        let actual = inline("[text](dest \"title\")")
        let expected = [
            s(.inlineLink, "[text](dest \"title\")"),
            s(.linkText, "[text]"),
            s(.linkDestination, "dest"),
            s(.linkTitle, "\"title\"")
        ]
        #expect(actual == expected)
    }

    @Test
    func angleBracketDestinationKeepsBracketsAndAllowsSpaces() {
        let actual = inline("[a](<d e> \"t\")")
        let expected = [
            s(.inlineLink, "[a](<d e> \"t\")"),
            s(.linkText, "[a]"),
            s(.linkDestination, "<d e>"),
            s(.linkTitle, "\"t\"")
        ]
        #expect(actual == expected)
    }

    @Test
    func balancedParenthesesInDestination() {
        let actual = inline("[a](a(b)c)")
        #expect(actual == [s(.inlineLink, "[a](a(b)c)"), s(.linkText, "[a]"), s(.linkDestination, "a(b)c")])
    }

    @Test
    func emptyDestinationHasNoDestinationToken() {
        let actual = inline("[a]()")
        #expect(actual == [s(.inlineLink, "[a]()"), s(.linkText, "[a]")])
    }

    @Test(arguments: [
        ("[a](x 't')", "'t'"),
        ("[a](x (t))", "(t)"),
        ("[a](b \"t\\\"q\")", "\"t\\\"q\"")
    ])
    func linkTitleSupportsQuoteAndParenthesisForms(text: String, title: String) {
        #expect(inlineTexts(.linkTitle, text) == [title])
        #expect(inlineTexts(.inlineLink, text) == [text])
    }

    @Test
    func emphasisInsideLinkTextIsLexed() {
        let actual = inline("[*e* b](x)")
        let expected = [
            s(.inlineLink, "[*e* b](x)"),
            s(.linkText, "[*e* b]"),
            s(.italic, "*e*"),
            s(.italicMarker, "*"),
            s(.italicMarker, "*"),
            s(.linkDestination, "x")
        ]
        #expect(actual == expected)
    }

    @Test
    func linkIsNotNestedInsideLink() {
        let actual = inline("[a [b](c) d](e)")
        #expect(actual == [s(.inlineLink, "[b](c)"), s(.linkText, "[b]"), s(.linkDestination, "c")])
    }

    @Test
    func escapedBracketDoesNotCloseLinkText() {
        let actual = inline("[a\\]b](c)")
        #expect(inlineTexts(.linkText, "[a\\]b](c)") == ["[a\\]b]"])
        #expect(actual.contains(s(.escape, "\\]")))
    }

    @Test
    func textAfterLinkIsNotPartOfIt() {
        let actual = inline("[a](b)(c)")
        #expect(actual == [s(.inlineLink, "[a](b)"), s(.linkText, "[a]"), s(.linkDestination, "b")])
    }

    @Test
    func fullReferenceLinkHasTextAndLabel() {
        let actual = inline("[a][b]")
        #expect(actual == [s(.linkText, "[a]"), s(.linkLabel, "[b]")])
    }

    @Test
    func collapsedReferenceLinkHasEmptyLabel() {
        let actual = inline("[a][]")
        #expect(actual == [s(.linkText, "[a]"), s(.linkLabel, "[]")])
    }

    @Test
    func shortReferenceIsAlwaysLinkLabel() {
        let actual = inline("[a]")
        #expect(actual == [s(.linkLabel, "[a]")])
    }

    @Test
    func bracketedWhitespaceIsNotALink() {
        let actual = inline("[ ]")
        #expect(actual.isEmpty)
    }

    @Test
    func imageIncludesBangAndWrapsInlineLink() {
        let text = "![alt](src)"
        let actual = inline(text)
        let expected = [
            s(.image, "![alt](src)"),
            s(.inlineLink, "[alt](src)"),
            s(.linkText, "[alt]"),
            s(.linkDestination, "src")
        ]
        #expect(actual == expected)
        let locations = MarkdownInlineLexer.tokens(in: text).map(\.range.location)
        #expect(locations == [0, 1, 1, 7])
    }

    @Test
    func imageReferenceHasTextAndLabel() {
        let actual = inline("![alt][ref]")
        #expect(actual == [s(.image, "![alt][ref]"), s(.linkText, "[alt]"), s(.linkLabel, "[ref]")])
    }

    @Test
    func shortImageReferenceUsesLabel() {
        let actual = inline("![alt]")
        #expect(actual == [s(.image, "![alt]"), s(.linkLabel, "[alt]")])
    }

    @Test(arguments: [
        ("<http://x.y>", "http://x.y", 1),
        ("<a@b.co>", "a@b.co", 1),
        ("<https://a.b/c?d=1>", "https://a.b/c?d=1", 1)
    ])
    func angleAutolinkCoversOnlyInside(text: String, inside: String, start: Int) {
        let tokens = MarkdownInlineLexer.tokens(in: text)
        #expect(tokens.map(\.kind) == [.autolink])
        #expect(tokens.map(\.range) == [NSRange(location: start, length: inside.utf16.count)])
        #expect(inline(text) == [s(.autolink, inside)])
    }

    @Test(arguments: [
        ("see http://foo.bar/baz.", "http://foo.bar/baz"),
        ("www.x.com", "www.x.com"),
        ("(http://x.com/a_(b))", "http://x.com/a_(b)"),
        ("foo. www.a.com/x, ok", "www.a.com/x")
    ])
    func bareGfmAutolinkTrimsTrailingPunctuationAndKeepsBalancedParentheses(text: String, link: String) {
        #expect(inline(text) == [s(.autolink, link)])
    }

    @Test
    func bareAutolinkNotInsideWord() {
        let actual = inline("xhttp://a.b")
        #expect(actual.isEmpty)
    }

    @Test
    func doubleTildeIsStrikethrough() {
        let actual = inline("~~x~~")
        #expect(actual == [s(.strikethrough, "~~x~~")])
    }

    @Test(arguments: ["~x~", "~~~x~~~"])
    func singleAndTripleTildeAreNotStrikethrough(text: String) {
        let actual = inline(text)
        #expect(actual.isEmpty)
    }

    @Test
    func doubleEqualsIsHighlight() {
        let actual = inline("==x==")
        #expect(actual == [s(.highlight, "==x==")])
    }

    @Test
    func singleAndTripleEqualsAreNotHighlighted() {
        let actual = inline("A =one= and ===three===")
        #expect(actual.isEmpty)
    }

    @Test
    func highlightContainsNestedBold() {
        let actual = inline("A ==marked **bold**== text")
        let expected = [
            s(.highlight, "==marked **bold**=="),
            s(.bold, "**bold**"),
            s(.boldMarker, "**"),
            s(.boldMarker, "**")
        ]
        #expect(actual == expected)
    }

    @Test
    func openingTagHasTagAndNameTokens() {
        let actual = inline("<b>")
        #expect(actual == [s(.inlineHtml, "<b>"), s(.htmlTag, "<"), s(.htmlTagName, "b"), s(.htmlTag, ">")])
    }

    @Test
    func closingTagUsesSlashOpener() {
        let actual = inline("</b>")
        #expect(actual == [s(.inlineHtml, "</b>"), s(.htmlTag, "</"), s(.htmlTagName, "b"), s(.htmlTag, ">")])
    }

    @Test
    func selfClosingTagUsesSlashCloser() {
        let actual = inline("<br/>")
        #expect(actual == [s(.inlineHtml, "<br/>"), s(.htmlTag, "<"), s(.htmlTagName, "br"), s(.htmlTag, "/>")])
    }

    @Test
    func attributesSplitIntoNameEqualsAndValue() {
        let actual = inline("<a href=\"x\" disabled>")
        let expected = [
            s(.inlineHtml, "<a href=\"x\" disabled>"),
            s(.htmlTag, "<"),
            s(.htmlTagName, "a"),
            s(.htmlAttributeName, "href"),
            s(.htmlAttributeValue, "="),
            s(.htmlAttributeValue, "\"x\""),
            s(.htmlAttributeName, "disabled"),
            s(.htmlTag, ">")
        ]
        #expect(actual == expected)
    }

    @Test
    func inlineCommentIsInlineHtmlAndHtmlComment() {
        let actual = inline("x <!-- c --> y")
        #expect(actual == [s(.inlineHtml, "<!-- c -->"), s(.htmlComment, "<!-- c -->")])
    }

    @Test(arguments: ["<3", "a < b"])
    func lessThanThatIsNotATagIsPlainText(text: String) {
        let actual = inline(text)
        #expect(actual.isEmpty)
    }

    @Test
    func twoTrailingSpacesBeforeNewlineIsHardBreak() {
        let text = "a  \nb"
        let actual = inline(text)
        #expect(actual == [s(.hardBreak, "  ")])
        #expect(MarkdownInlineLexer.tokens(in: text).map(\.range) == [NSRange(location: 1, length: 2)])
    }

    @Test
    func backslashBeforeNewlineIsHardBreak() {
        let text = "a\\\nb"
        let actual = inline(text)
        #expect(actual == [s(.hardBreak, "\\")])
        #expect(MarkdownInlineLexer.tokens(in: text).map(\.range) == [NSRange(location: 1, length: 1)])
    }

    @Test
    func trailingSpacesAtEndOfParagraphAreNotHardBreak() {
        let actual = inline("a  ")
        #expect(actual.isEmpty)
        let block = MarkdownLexerSupport.samples("a  \n\nb")
        #expect(block.isEmpty)
    }

    @Test(arguments: ["\\*", "\\["])
    func escapeCoversBackslashAndCharacter(text: String) {
        let tokens = MarkdownInlineLexer.tokens(in: text)
        #expect(tokens.map(\.kind) == [.escape])
        #expect(tokens.map(\.range) == [NSRange(location: 0, length: 2)])
    }

    @Test
    func escapedDelimitersDoNotStartEmphasis() {
        let text = "x \\*a\\* y"
        let actual = inline(text)
        #expect(actual == [s(.escape, "\\*"), s(.escape, "\\*")])
    }

    @Test
    func escapedFirstDelimiterLeavesFollowingEmphasis() {
        let actual = inline("\\*a*")
        #expect(actual == [s(.escape, "\\*")])
    }

    @Test
    func escapedClosingDelimiterPreventsBold() {
        let text = "**a\\**"
        #expect(inlineTexts(.bold, text).isEmpty)
        #expect(inlineTexts(.escape, text) == ["\\*"])
    }

    @Test
    func blockLexerLexesParagraphInlineContent() {
        let text = "a **b** `c` d"
        let actual = MarkdownLexerSupport.samples(text)
        let expected = [
            s(.bold, "**b**"),
            s(.boldMarker, "**"),
            s(.boldMarker, "**"),
            s(.codeSpan, "`c`"),
            s(.codeSpanMarker, "`"),
            s(.codeSpanMarker, "`")
        ]
        #expect(actual == expected)
    }

    @Test
    func listItemTextIsLexedInline() {
        let text = "- *a* [l](u)"
        let kinds = MarkdownLexerSupport.tokens(text).map(\.kind)
        #expect(kinds.first == .listMarker)
        #expect(MarkdownLexerSupport.texts(of: .italic, in: text) == ["*a*"])
        #expect(MarkdownLexerSupport.texts(of: .inlineLink, in: text) == ["[l](u)"])
    }

    @Test
    func headerContentIsLexedInline() {
        let text = "# **b** end"
        #expect(MarkdownLexerSupport.texts(of: .bold, in: text) == ["**b**"])
        #expect(MarkdownLexerSupport.texts(of: .headerContent(level: 1), in: text) == ["**b** end"])
    }

    static let orderingCorpus: [String] = [
        "***x***",
        "*foo**bar**baz*",
        "[a [b](c) d](e)",
        "![alt](src \"t\") and [r][l] ![i]",
        "`a` **b** ~~c~~ ==d== <b>e</b>",
        "<http://x.y> http://foo.bar/baz. www.x.com",
        "\\*esc\\* \\[x\\]",
        "# H *a* `c`\n\n> q **b**\n\n- [x] i ~~s~~",
        "| a | `b` |\n| - | - |\n| c *d* | e |",
        "```swift\ncode\n```\ntext",
        "<div>\n<!-- c\nd -->\n</div>",
        "one `a\nb` two  \nthree\\\nfour",
        "A ==marked **bold**== text",
        "😀 é *a* [l](u) ~~s~~",
        "[a]: http://x \"t\"\n[b][a]"
    ]

    @Test(arguments: orderingCorpus)
    func blockTokensAreSortedOuterFirstAndWithinBounds(text: String) {
        let scan = MarkdownBlockLexer.scan(text)
        let sorted = scan.tokens.sortedOuterFirst()
        #expect(scan.tokens == sorted)
        let length = (text as NSString).length
        let outOfBounds = scan.tokens.filter { $0.range.location < 0 || $0.range.length < 0 || NSMaxRange($0.range) > length }
        #expect(outOfBounds.isEmpty)
        let empty = scan.tokens.filter { $0.range.length == 0 }
        #expect(empty.isEmpty)
    }

    @Test(arguments: orderingCorpus)
    func inlineTokensAreSortedOuterFirstAndWithinBounds(text: String) {
        let tokens = MarkdownInlineLexer.tokens(in: text)
        #expect(tokens == tokens.sortedOuterFirst())
        let length = (text as NSString).length
        let outOfBounds = tokens.filter { $0.range.location < 0 || $0.range.length < 0 || NSMaxRange($0.range) > length }
        #expect(outOfBounds.isEmpty)
    }
}
