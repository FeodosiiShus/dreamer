import Foundation
import Testing
@testable import Dreamder

private func lexerCoverageSample(_ kind: MarkdownTokenKind, _ text: String) -> MarkdownTokenSample {
    MarkdownTokenSample(kind, text)
}

private func lexerCoverageInline(_ text: String) -> [MarkdownTokenSample] {
    MarkdownInlineLexer.tokens(in: text).map { token in
        MarkdownTokenSample(token.kind, (text as NSString).substring(with: token.range))
    }
}

private func lexerCoverageScanLines(_ lines: [String], emitsText: Bool = true) -> [[MarkdownTokenSample]] {
    var scanner = MarkdownHTMLScanner(emitsText: emitsText)
    return lines.map { line in
        let units = Array(line.utf16)
        var tokens: [MarkdownToken] = []
        scanner.scan(units, from: 0, to: units.count, into: &tokens)
        return tokens.map { token in
            MarkdownTokenSample(token.kind, (line as NSString).substring(with: token.range))
        }
    }
}

private func lexerCoverageTagEnd(_ text: String) -> Int? {
    let units = Array(text.utf16)
    return MarkdownHTMLScanner.tagEnd(in: units, from: 0, to: units.count)
}

@Suite("Markdown block lexer coverage")
struct MarkdownBlockLexerCoverageTests {
    private func texts(_ kind: MarkdownTokenKind, _ text: String) -> [String] {
        MarkdownLexerSupport.texts(of: kind, in: text)
    }

    @Test
    func nsStringScanMatchesStringScan() {
        let text = "# Title\n\n*em* `code`"
        let fromString = MarkdownBlockLexer.scan(text)
        let fromNSString = MarkdownBlockLexer.scan(NSString(string: text))
        #expect(!fromString.tokens.isEmpty)
        #expect(fromNSString.tokens == fromString.tokens)
        #expect(fromNSString.headers == fromString.headers)
    }

    @Test
    func frontMatterOpeningMayHaveTrailingSpaces() {
        let text = "---  \ntitle: x\n---\nbody"
        #expect(texts(.frontMatterDelimiter, text) == ["---", "---"])
        #expect(texts(.frontMatterContent, text) == ["title: x"])
    }

    @Test
    func unterminatedFrontMatterIsAnOrdinaryRule() {
        let text = "---\nfoo\n"
        #expect(texts(.frontMatterDelimiter, text).isEmpty)
        #expect(texts(.horizontalRule, text) == ["---"])
    }

    @Test
    func quoteContinuationAcceptsLeadingSpacesBeforeTheMarker() {
        let text = "> a\n  > b"
        #expect(texts(.blockQuoteMarker, text) == [">", ">"])
    }

    @Test
    func leadingTabIsFourColumnsOfIndentedCode() {
        #expect(MarkdownLexerSupport.samples("\tcode") == [lexerCoverageSample(.codeBlock, "code")])
    }

    @Test
    func tabIndentedLineContinuesAQuoteParagraphLazily() {
        let text = "> a\n\tb"
        #expect(texts(.blockQuoteMarker, text) == [">"])
        #expect(texts(.codeBlock, text).isEmpty)
    }

    @Test
    func blockStartInterruptsAnOpenTable() {
        let text = "| a |\n| - |\n# H"
        #expect(texts(.headerContent(level: 1), text) == ["H"])
        #expect(texts(.tableSeparator, text).contains("| - |"))
    }

    @Test
    func tableDelimiterRowTrailingWhitespaceIsNotPartOfTheSeparator() {
        let text = "| a |\n| - |   "
        let separators = texts(.tableSeparator, text)
        #expect(separators.contains("| - |"))
        #expect(!separators.contains("| - |   "))
    }

    @Test
    func quoteNestedInANewListItemStartsANewQuoteTracker() {
        let text = "> a\n- > b"
        #expect(texts(.blockQuoteMarker, text) == [">", ">"])
        #expect(texts(.listMarker, text) == ["-"])
        let quotes = texts(.blockQuote, text)
        #expect(quotes.contains("> a"))
        #expect(quotes.contains("> b"))
    }

    @Test
    func setextUnderlineDropsTrailingSpacesOfTheParagraph() {
        let text = "foo  \n---"
        #expect(texts(.headerContent(level: 2), text) == ["foo"])
        #expect(MarkdownBlockLexer.scan(text).headers.first?.isSetext == true)
    }

    @Test
    func listMarkerFollowedByFiveSpacesStartsIndentedCode() {
        let text = "-     code"
        #expect(texts(.listMarker, text) == ["-"])
        #expect(texts(.codeBlock, text) == ["code"])
    }

    @Test
    func cdataBlockRunsUntilItsTerminator() {
        let text = "<![CDATA[\nfoo\n]]>\nafter"
        #expect(texts(.htmlTag, text) == ["<![CDATA[", "foo", "]]>"])
    }

    @Test
    func declarationBlockEndsOnTheFirstClosingAngle() {
        let text = "<!DOCTYPE html>\nnext"
        #expect(texts(.htmlTag, text) == ["<!DOCTYPE html>"])
    }

    @Test
    func bangFollowedByADigitIsNotAnHTMLBlock() {
        #expect(MarkdownLexerSupport.samples("<!1 x>").isEmpty)
    }

    @Test
    func standaloneCustomTagStartsATypeSevenBlock() {
        let text = "<span>\nfoo"
        #expect(texts(.htmlTagName, text) == ["span"])
        #expect(texts(.htmlCode, text) == ["foo"])
    }

    @Test
    func typeSixBlockContinuesUntilABlankLine() {
        let text = "<div>\nfoo\n\nbar"
        #expect(texts(.htmlTagName, text) == ["div"])
        #expect(texts(.htmlCode, text) == ["foo"])
    }
}

@Suite("Markdown inline lexer coverage")
struct MarkdownInlineLexerCoverageTests {
    private func sample(_ kind: MarkdownTokenKind, _ text: String) -> MarkdownTokenSample {
        lexerCoverageSample(kind, text)
    }

    @Test
    func nsStringRangeOverloadMatchesStringOverload() {
        let text = "*a* b"
        let fromRange = MarkdownInlineLexer.tokens(in: NSString(string: text), range: NSRange(location: 0, length: 5))
        #expect(!fromRange.isEmpty)
        #expect(fromRange == MarkdownInlineLexer.tokens(in: text))
    }

    @Test
    func backslashBeforeALetterIsNotAnEscape() {
        #expect(lexerCoverageInline("a\\b").isEmpty)
    }

    @Test
    func referenceLabelMayContainAnEscapedBracket() {
        #expect(lexerCoverageInline("[x][a\\]b]") == [sample(.linkText, "[x]"), sample(.linkLabel, "[a\\]b]")])
    }

    @Test
    func referenceLabelWithANestedBracketFallsBackToACollapsedLabel() {
        #expect(lexerCoverageInline("[x][a[b]").contains(sample(.linkLabel, "[x]")))
    }

    @Test
    func unterminatedReferenceLabelFallsBackToACollapsedLabel() {
        #expect(lexerCoverageInline("[x][abc") == [sample(.linkLabel, "[x]")])
    }

    @Test
    func angleBracketDestinationMayContainAnEscapedBracket() {
        let text = "[a](<b\\>c>)"
        #expect(
            lexerCoverageInline(text) == [
                sample(.inlineLink, text),
                sample(.linkText, "[a]"),
                sample(.linkDestination, "<b\\>c>")
            ]
        )
    }

    @Test
    func bareDestinationMayContainAnEscapedParenthesis() {
        let text = "[a](b\\)c)"
        #expect(
            lexerCoverageInline(text) == [
                sample(.inlineLink, text),
                sample(.linkText, "[a]"),
                sample(.linkDestination, "b\\)c")
            ]
        )
    }

    @Test
    func unterminatedSchemeAutolinkIsNotAToken() {
        #expect(lexerCoverageInline("<http://x").isEmpty)
    }

    @Test(arguments: ["<![CDATA[x]]>", "<!DOCTYPE html>", "<?php echo ?>"])
    func declarationLikeInlineHTMLIsATag(text: String) {
        #expect(lexerCoverageInline(text) == [sample(.inlineHtml, text), sample(.htmlTag, text)])
    }

    @Test(arguments: ["<!a b>", "<?php", "<![CDATA[x"])
    func malformedDeclarationLikeInlineHTMLIsPlainText(text: String) {
        #expect(lexerCoverageInline(text).isEmpty)
    }

    @Test
    func bareURLThatTrimsToNothingIsNotAnAutolink() {
        #expect(lexerCoverageInline("see http://... now").isEmpty)
    }
}

@Suite("Markdown HTML scanner coverage")
struct MarkdownHTMLScannerCoverageTests {
    private func sample(_ kind: MarkdownTokenKind, _ text: String) -> MarkdownTokenSample {
        lexerCoverageSample(kind, text)
    }

    @Test
    func attributeWithoutValueIsFollowedByWhitespaceAndAnotherAttribute() {
        #expect(
            lexerCoverageScanLines(["<a b c>"]) == [[
                sample(.htmlTag, "<"),
                sample(.htmlTagName, "a"),
                sample(.htmlAttributeName, "b"),
                sample(.htmlAttributeName, "c"),
                sample(.htmlTag, ">")
            ]]
        )
    }

    @Test
    func trailingWhitespaceAfterAnAttributeNameEndsTheLine() {
        #expect(
            lexerCoverageScanLines(["<a b   "]) == [[
                sample(.htmlTag, "<"),
                sample(.htmlTagName, "a"),
                sample(.htmlAttributeName, "b")
            ]]
        )
    }

    @Test
    func quotedValueSpansLines() {
        #expect(
            lexerCoverageScanLines(["<a href=\"foo", "bar", "baz\" c>"]) == [
                [
                    sample(.htmlTag, "<"),
                    sample(.htmlTagName, "a"),
                    sample(.htmlAttributeName, "href"),
                    sample(.htmlAttributeValue, "="),
                    sample(.htmlAttributeValue, "\"foo")
                ],
                [sample(.htmlAttributeValue, "bar")],
                [
                    sample(.htmlAttributeValue, "baz\""),
                    sample(.htmlAttributeName, "c"),
                    sample(.htmlTag, ">")
                ]
            ]
        )
    }

    @Test
    func whitespaceAroundTheEqualsSignIsSkipped() {
        #expect(
            lexerCoverageScanLines(["<a b = \"x\">"]) == [[
                sample(.htmlTag, "<"),
                sample(.htmlTagName, "a"),
                sample(.htmlAttributeName, "b"),
                sample(.htmlAttributeValue, "="),
                sample(.htmlAttributeValue, "\"x\""),
                sample(.htmlTag, ">")
            ]]
        )
    }

    @Test
    func equalsSignDirectlyBeforeTheClosingAngleHasNoValue() {
        #expect(
            lexerCoverageScanLines(["<a b=>"]) == [[
                sample(.htmlTag, "<"),
                sample(.htmlTagName, "a"),
                sample(.htmlAttributeName, "b"),
                sample(.htmlAttributeValue, "="),
                sample(.htmlTag, ">")
            ]]
        )
    }

    @Test
    func unterminatedQuoteOnTheSameLineStaysOpen() {
        #expect(
            lexerCoverageScanLines(["<a b=\"x"]) == [[
                sample(.htmlTag, "<"),
                sample(.htmlTagName, "a"),
                sample(.htmlAttributeName, "b"),
                sample(.htmlAttributeValue, "="),
                sample(.htmlAttributeValue, "\"x")
            ]]
        )
    }

    @Test
    func textAroundTagsIsTrimmed() {
        #expect(
            lexerCoverageScanLines(["hello <b>world </b>"]) == [[
                sample(.htmlCode, "hello"),
                sample(.htmlTag, "<"),
                sample(.htmlTagName, "b"),
                sample(.htmlTag, ">"),
                sample(.htmlCode, "world"),
                sample(.htmlTag, "</"),
                sample(.htmlTagName, "b"),
                sample(.htmlTag, ">")
            ]]
        )
    }

    @Test(arguments: ["1 < 2 <3", "a </3 b"])
    func angleBracketsThatStartNoTagStayText(text: String) {
        #expect(lexerCoverageScanLines([text]) == [[sample(.htmlCode, text)]])
    }

    @Test
    func tagEndAcceptsUnquotedAttributeValues() {
        let text = "<a b=c d=e>"
        #expect(lexerCoverageTagEnd(text) == text.utf16.count)
    }

    @Test(arguments: ["<a b=c", "<a b==>", "<a", "<a "])
    func tagEndRejectsIncompleteTags(text: String) {
        #expect(lexerCoverageTagEnd(text) == nil)
    }
}

@Suite("Markdown character classes coverage")
struct MarkdownCharCoverageTests {
    @Test(arguments: [0x2003, 0x3000, 0x2002])
    func unicodeSpaceSeparatorsAreWhitespace(unit: Int) {
        #expect(MarkdownChar.isWhitespace(UInt16(unit)))
    }

    @Test(arguments: [0x00E9, 0x4E2D, 0xD800])
    func otherNonASCIIUnitsAreNotWhitespace(unit: Int) {
        #expect(!MarkdownChar.isWhitespace(UInt16(unit)))
    }

    @Test(arguments: [0x00AB, 0x2014, 0x20AC, 0x00A9, 0x00B4, 0x2212, 0x203F])
    func nonASCIIPunctuationAndSymbols(unit: Int) {
        #expect(MarkdownChar.isPunctuation(UInt16(unit)))
    }

    @Test(arguments: [0x00E9, 0x4E2D, 0xD800])
    func nonASCIILettersAndLoneSurrogatesAreNotPunctuation(unit: Int) {
        #expect(!MarkdownChar.isPunctuation(UInt16(unit)))
    }
}
