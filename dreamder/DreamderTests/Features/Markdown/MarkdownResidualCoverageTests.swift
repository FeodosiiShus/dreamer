import Foundation
import Testing
@testable import Dreamder

struct MarkdownResidualCoverageTests {
    private func blockTexts(_ kind: MarkdownTokenKind, _ text: String) -> [String] {
        MarkdownLexerSupport.texts(of: kind, in: text)
    }

    @Test
    func aSetextHeaderInsideAQuoteRecordsItsContainerPath() {
        let header = MarkdownBlockLexer.scan("> foo\n> ---").headers.first

        #expect(header?.isSetext == true)
        #expect(header?.containerPath.count == 1)
    }

    @Test
    func aSelfClosingBlockTagInterruptsAParagraph() {
        let text = "para\n<div/>\nfoo"

        #expect(blockTexts(.htmlTagName, text) == ["div"])
        #expect(blockTexts(.htmlCode, text) == ["foo"])
    }

    @Test
    func anUnterminatedCustomTagAtTheStartOfALineIsPlainText() {
        #expect(MarkdownLexerSupport.samples("<span class").isEmpty)
    }

    @Test
    func aBlockTagNameAtTheEndOfTheTextStartsABlock() {
        #expect(blockTexts(.htmlTagName, "para\n<div") == ["div"])
    }

    @Test
    func delimiterRunsOfThreeAroundTheSameWordPairUp() {
        let kinds = MarkdownInlineLexer.tokens(in: "foo***bar***baz").map(\.kind)

        #expect(kinds.contains(.bold))
        #expect(kinds.contains(.italic))
    }

    @Test
    func theActionParserPairsDelimiterRunsOfThree() {
        let nodes = MarkdownInlineParser.parse(Array("foo***bar***baz".utf16), base: 0).map(\.kind)

        #expect(nodes.contains(.emphasis))
        #expect(nodes.contains(.strong))
    }

    @Test
    func anAutolinkSchemeMayContainDigits() {
        let nodes = MarkdownInlineParser.parse(Array("<a1b:c>".utf16), base: 0).map(\.kind)

        #expect(nodes == [.autolink])
    }

    @Test
    func boldIsNotSelectedInsideNestedEmphasisOfTheOtherKind() {
        let parsed = MarkdownActionCaretMarkup("_*<selection>a b</selection>*_")

        let selected = MarkdownEmphasisToggle.isSelected(.bold, text: parsed.text, selections: parsed.selections)

        #expect(!selected)
    }

    @Test(arguments: ["<a _b>", "<a :b>"])
    func attributeNamesMayStartWithAnUnderscoreOrAColon(tag: String) {
        let units = Array(tag.utf16)

        #expect(MarkdownHTMLScanner.tagEnd(in: units, from: 0, to: units.count) == units.count)
    }

    @Test
    func lowercaseHexadecimalEntitiesAreDecodedInAnchors() {
        #expect(MarkdownHeaderAnchor.replaceEntities("&#x2a;") == "*")
    }

    @Test
    func applyingAResultReplacesTheChangedRange() {
        let result = MarkdownActionResult(
            original: Array("abcdef".utf16),
            updated: Array("abXYef".utf16),
            selections: []
        )

        #expect(result.applied(to: "abcdef") == "abXYef")
    }

    @Test
    func theLastLineOfAListIsTheLastLineOfItsLastItem() {
        let structure = MarkdownListStructure("- a\n- b\n  c\n")

        #expect(structure.lastLine(ofList: 0) == 2)
    }

    @Test
    func aZeroNumericEntityDecodesToTheReplacementCharacter() {
        let characters = Array("&#0;")

        #expect(MarkdownHTMLEntities.decode(characters, at: 0)?.text == "\u{FFFD}")
        #expect(MarkdownHTMLEntities.decode(Array("&#38;"), at: 0)?.text == "&")
    }
}
