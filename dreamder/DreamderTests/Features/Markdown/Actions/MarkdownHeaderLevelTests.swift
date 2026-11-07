import Foundation
import Testing

@testable import Dreamder

struct MarkdownHeaderLevelTests {
    private func rendered(_ result: MarkdownActionResult?) -> String? {
        result.map { MarkdownActionCaretMarkup.render($0.text, $0.selections) }
    }

    private func set(_ level: Int, _ markup: String) -> String? {
        let parsed = MarkdownActionCaretMarkup(markup)
        return rendered(MarkdownHeaderLevel.set(level: level, text: parsed.text, selections: parsed.selections))
    }

    private func up(_ markup: String) -> String? {
        let parsed = MarkdownActionCaretMarkup(markup)
        return rendered(MarkdownHeaderLevel.headerUp(text: parsed.text, selections: parsed.selections))
    }

    private func down(_ markup: String) -> String? {
        let parsed = MarkdownActionCaretMarkup(markup)
        return rendered(MarkdownHeaderLevel.headerDown(text: parsed.text, selections: parsed.selections))
    }

    @Test func headerWithSelectionAtFileEnd() {
        let result = set(1, "Some first<selection> level header</selection>")
        #expect(result == "# Some first<selection> level header</selection>")
    }

    @Test func consistencyBetweenNormalAndHeader() {
        let header = "# Some first<selection> level header</selection>"
        let plain = "Some first<selection> level header</selection>"
        let toPlain = set(0, header)
        let backToHeader = set(1, plain)
        #expect(toPlain == plain)
        #expect(backToHeader == header)
    }

    @Test func headerFromSingleLineInMultilineParagraph() {
        let content = """
        Lorem ipsum dolor sit amet, consectetur adipiscing elit.
        <selection>Phasellus posuere fermentum elit placerat dapibus.</selection>
        Donec blandit dolor a mauris lacinia, ut facilisis quam vulputate.
        """
        let expected = """
        Lorem ipsum dolor sit amet, consectetur adipiscing elit.

        ## <selection>Phasellus posuere fermentum elit placerat dapibus.</selection>

        Donec blandit dolor a mauris lacinia, ut facilisis quam vulputate.
        """
        #expect(set(2, content) == expected)
    }

    @Test func inList() {
        let content = """
        * First item
        * <selection>Second item</selection>
        * Third item
        """
        let expected = """
        * First item
        * ### <selection>Second item</selection>
        * Third item
        """
        #expect(set(3, content) == expected)
    }

    @Test func inSublist() {
        let content = """
        * First outer item
          * First inner item
          * <selection>Second inner item</selection>
          * Third inner item
        * Third outer item
        """
        let expected = """
        * First outer item
          * First inner item
          * ### <selection>Second inner item</selection>
          * Third inner item
        * Third outer item
        """
        #expect(set(3, content) == expected)
    }

    @Test func appliesHeaderLevelToMultipleCarets() {
        let content = "First line\n\nSecond line"
        let selections = [NSRange(location: 0, length: 10), NSRange(location: 12, length: 11)]
        let result = MarkdownHeaderLevel.set(level: 1, text: content, selections: selections)
        #expect(result?.text == "# First line\n\n# Second line")
        #expect(result?.selections == [NSRange(location: 2, length: 10), NSRange(location: 16, length: 11)])
    }

    @Test func removesHeaderLevelFromMultipleCarets() {
        let content = "# First line\n\n# Second line"
        let selections = [NSRange(location: 2, length: 10), NSRange(location: 16, length: 11)]
        let result = MarkdownHeaderLevel.set(level: 0, text: content, selections: selections)
        #expect(result?.text == "First line\n\nSecond line")
        #expect(result?.selections == [NSRange(location: 0, length: 10), NSRange(location: 12, length: 11)])
    }

    @Test func changesExistingHeaderLevelAndDropsClosingHashes() {
        #expect(set(3, "# Ti<caret>tle #") == "### Ti<caret>tle")
        #expect(set(1, "###   Ti<caret>tle") == "# Ti<caret>tle")
    }

    @Test func settingSameLevelDoesNothing() {
        #expect(set(2, "## Ti<caret>tle") == nil)
        #expect(set(0, "Ti<caret>tle") == nil)
    }

    @Test func plainParagraphToHeaderKeepsCaret() {
        #expect(set(2, "Ti<caret>tle") == "## Ti<caret>tle")
    }

    @Test func setLevelClampsToSix() {
        #expect(set(9, "Ti<caret>tle") == "###### Ti<caret>tle")
    }

    @Test func setLevelInBlockQuoteKeepsQuoteMarker() {
        #expect(set(2, "> Ti<caret>tle") == "> ## Ti<caret>tle")
        #expect(set(0, "> ## Ti<caret>tle") == "> Ti<caret>tle")
    }

    @Test func setLevelInListKeepsMarkerAndCheckbox() {
        #expect(set(2, "- [ ] Ti<caret>tle") == "- [ ] ## Ti<caret>tle")
        #expect(set(1, "1. Ti<caret>tle") == "1. # Ti<caret>tle")
    }

    @Test func rawLineInQuotedParagraphKeepsQuoteOnSeparators() {
        let content = "> one\n> <caret>two\n> three"
        let expected = "> one\n>\n> ## <caret>two\n>\n> three"
        #expect(set(2, content) == expected)
    }

    @Test func rawLineWithBlankNeighboursAddsNoLines() {
        let content = "para\nline<caret>"
        #expect(set(1, content) == "para\n\n# line<caret>")
        let first = "li<caret>ne\nnext"
        #expect(set(1, first) == "# li<caret>ne\n\nnext")
    }

    @Test func rawLineSetToPlainDoesNothing() {
        #expect(set(0, "one\nt<caret>wo\nthree") == nil)
    }

    @Test func setextHeaderToAtx() {
        let content = "Ti<caret>tle\n====\nnext"
        #expect(set(2, content) == "## Ti<caret>tle\nnext")
        #expect(set(0, content) == "Ti<caret>tle\nnext")
    }

    @Test func headerDownOnParagraphCreatesLevelOne() {
        #expect(down("Ti<caret>tle") == "# Ti<caret>tle")
    }

    @Test func headerDownIncreasesLevel() {
        #expect(down("## Ti<caret>tle ##") == "### Ti<caret>tle")
    }

    @Test func headerUpDecreasesLevel() {
        #expect(up("### Ti<caret>tle") == "## Ti<caret>tle")
    }

    @Test func headerUpFromLevelOneProducesPlainText() {
        #expect(up("# Ti<caret>tle") == "Ti<caret>tle")
    }

    @Test func headerDownAtLevelSixChangesNothing() {
        #expect(down("###### Ti<caret>tle") == nil)
    }

    @Test func headerUpOnParagraphChangesNothing() {
        #expect(up("Ti<caret>tle") == nil)
    }

    @Test func headerDownSwitchesSetextOneToTwoKeepingUnderlineLength() {
        let content = "Ti<caret>tle\n=====\n"
        #expect(down(content) == "Ti<caret>tle\n-----\n")
    }

    @Test func headerUpSwitchesSetextTwoToOneKeepingUnderlineLength() {
        let content = "Ti<caret>tle\n---\n"
        #expect(up(content) == "Ti<caret>tle\n===\n")
    }

    @Test func headerUpOnSetextOneProducesPlainText() {
        #expect(up("Ti<caret>tle\n=====\nnext") == "Ti<caret>tle\nnext")
    }

    @Test func headerDownOnSetextTwoProducesAtxLevelThree() {
        #expect(down("Ti<caret>tle\n-----\nnext") == "### Ti<caret>tle\nnext")
    }

    @Test func headerActionsOnMultipleCarets() {
        let content = "# One\n\n## Two"
        let selections = [NSRange(location: 2, length: 0), NSRange(location: 10, length: 0)]
        let result = MarkdownHeaderLevel.headerDown(text: content, selections: selections)
        #expect(result?.text == "## One\n\n### Two")
        #expect(result?.selections == [NSRange(location: 3, length: 0), NSRange(location: 12, length: 0)])
    }

    @Test func isSelectedMatchesHeaderLevel() {
        let parsed = MarkdownActionCaretMarkup("## Ti<caret>tle")
        let level2 = MarkdownHeaderLevel.isSelected(level: 2, text: parsed.text, selections: parsed.selections)
        let level1 = MarkdownHeaderLevel.isSelected(level: 1, text: parsed.text, selections: parsed.selections)
        let level0 = MarkdownHeaderLevel.isSelected(level: 0, text: parsed.text, selections: parsed.selections)
        #expect(level2)
        #expect(!level1)
        #expect(!level0)
    }

    @Test func isSelectedOnPlainTextMatchesNormalOnly() {
        let parsed = MarkdownActionCaretMarkup("Ti<caret>tle")
        let normal = MarkdownHeaderLevel.isSelected(level: 0, text: parsed.text, selections: parsed.selections)
        let title = MarkdownHeaderLevel.isSelected(level: 1, text: parsed.text, selections: parsed.selections)
        #expect(normal)
        #expect(!title)
    }

    @Test func isSelectedRequiresAllCarets() {
        let content = "# One\n\n## Two"
        let selections = [NSRange(location: 2, length: 0), NSRange(location: 10, length: 0)]
        let level1 = MarkdownHeaderLevel.isSelected(level: 1, text: content, selections: selections)
        #expect(!level1)
    }

    @Test func setextHeaderLevelIsSelected() {
        let parsed = MarkdownActionCaretMarkup("Ti<caret>tle\n---")
        let level2 = MarkdownHeaderLevel.isSelected(level: 2, text: parsed.text, selections: parsed.selections)
        #expect(level2)
    }

    @Test func enabledStateOfHeaderActions() {
        struct Row {
            let markup: String
            let up: Bool
            let down: Bool
        }
        let rows = [
            Row(markup: "# Ti<caret>tle", up: true, down: true),
            Row(markup: "###### Ti<caret>tle", up: true, down: false),
            Row(markup: "Ti<caret>tle", up: false, down: true),
            Row(markup: "one\nt<caret>wo\nthree", up: false, down: false),
            Row(markup: "Ti<caret>tle\n---", up: true, down: true),
        ]
        for row in rows {
            let parsed = MarkdownActionCaretMarkup(row.markup)
            let upEnabled = MarkdownHeaderLevel.isHeaderUpEnabled(text: parsed.text, selections: parsed.selections)
            let downEnabled = MarkdownHeaderLevel.isHeaderDownEnabled(text: parsed.text, selections: parsed.selections)
            #expect(upEnabled == row.up)
            #expect(downEnabled == row.down)
        }
    }
}
