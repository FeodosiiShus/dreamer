import Foundation
import Testing
@testable import Dreamder

private func tableCoverageText(_ lines: String...) -> String {
    lines.joined(separator: "\n")
}

private func tableCoverageString(_ units: [UInt16]) -> String {
    String(decoding: units, as: UTF16.self)
}

struct MarkdownTableCharacterWidthCoverageTests {
    @Test(arguments: [("\u{301}", 0), ("\u{200B}", 0), ("\u{20DD}", 0), ("\u{E9}", 1), ("\u{1}", 0)])
    func standaloneMarksAndNarrowLettersMeasureTheirColumns(text: String, width: Int) {
        #expect(MarkdownTable.displayWidth(of: text) == width)
    }
}

struct MarkdownTableLayoutCoverageTests {
    private func insideListItem(_ markup: String) throws -> Bool {
        let document = MarkdownDocument(markup)
        let offset = document.text.lines[document.text.lines.count - 1].start
        let layout = try #require(MarkdownTableLayout.find(in: document, containing: offset))
        return layout.isInsideListItem(document: document)
    }

    @Test
    func initializerRejectsInconsistentInput() {
        let text = MarkdownText("| a |\n|---|")

        #expect(MarkdownTableLayout(text: text, lines: 0..<1, prefixLengths: [0]) == nil)
        #expect(MarkdownTableLayout(text: text, lines: 0..<2, prefixLengths: [0]) == nil)
        #expect(MarkdownTableLayout(text: text, lines: 0..<3, prefixLengths: [0, 0, 0]) == nil)
        #expect(MarkdownTableLayout(text: text, lines: 0..<2, prefixLengths: [99, 0]) == nil)
        #expect(MarkdownTableLayout(text: text, lines: 0..<2, prefixLengths: [0, 0]) != nil)
    }

    @Test
    func rowPositionIsNilOutsideOfTheTable() throws {
        let text = MarkdownText("| a |\n|---|")
        let layout = try #require(MarkdownTableLayout(text: text, lines: 0..<2, prefixLengths: [0, 0]))

        #expect(layout.rowPosition(ofLine: 0) == 0)
        #expect(layout.rowPosition(ofLine: 1) == 1)
        #expect(layout.rowPosition(ofLine: 2) == nil)
        #expect(layout.rowPosition(ofLine: -1) == nil)
    }

    @Test
    func tableAfterAQuoteIsNotInsideAListItem() throws {
        let markup = tableCoverageText("> quoted", "  | a | b |", "  |---|---|")

        #expect(try !insideListItem(markup))
    }

    @Test
    func tableAfterAnUnindentedParagraphIsNotInsideAListItem() throws {
        let markup = tableCoverageText("text", "  | a | b |", "  |---|---|")

        #expect(try !insideListItem(markup))
    }

    @Test
    func tableAfterAnIndentedContinuationBelongsToTheListItem() throws {
        let markup = tableCoverageText("- item", "  cont", "  | a | b |", "  |---|---|")

        #expect(try insideListItem(markup))
    }

    @Test
    func tableAfterABlankLineBelongsToTheListItem() throws {
        let markup = tableCoverageText("- item", "", "  | a | b |", "  |---|---|")

        #expect(try insideListItem(markup))
    }

    @Test
    func tableLessIndentedThanTheItemContentIsNotInsideIt() throws {
        let markup = tableCoverageText("-   item", "  | a | b |", "  |---|---|")

        #expect(try !insideListItem(markup))
    }

    @Test
    func indentedTableAtTheDocumentStartIsNotInsideAListItem() throws {
        let markup = tableCoverageText("  | a | b |", "  |---|---|")

        #expect(try !insideListItem(markup))
    }

    @Test
    func unindentedTableIsNotInsideAListItem() throws {
        let markup = tableCoverageText("- item", "| a | b |", "|---|---|")

        #expect(try !insideListItem(markup))
    }
}

struct MarkdownTableInsertCoverageTests {
    @Test
    func insertingAfterTextInAQuoteKeepsTheQuotePrefixOfTheCaretLine() {
        let result = MarkdownTable.insertEmptyTable(text: "> abc", caret: 5, contentRows: 1, columns: 2)

        let rendered = MarkdownActionCaretMarkup.render(result.text, result.selections)

        #expect(rendered == "> abc|<caret>   |   |\n> |---|---|\n> |   |   |\n")
    }
}

struct MarkdownTableFormatterCoverageTests {
    private func format(
        _ text: String,
        preventExpand: Bool,
        selections: [NSRange] = []
    ) -> MarkdownActionResult? {
        MarkdownTableFormatter(style: .aligned, tabSize: 4, trimToMaxContent: true, preventExpand: preventExpand)
            .format(text: text, selections: selections, onlyTablesTouchedBySelections: false)
    }

    @Test
    func preventExpandKeepsNarrowCellsAndSeparators() {
        let text = tableCoverageText("| a | bbb |", "|---|---|", "| c | d |")

        #expect(format(text, preventExpand: true) == nil)
        #expect(format(text, preventExpand: false)?.text == tableCoverageText("| a | bbb |", "|---|-----|", "| c | d   |"))
    }

    @Test
    func preventExpandStillShrinksWideCellsAndSeparators() {
        let text = tableCoverageText("| a      | b |", "|--------|---|", "| c | d |")

        let result = format(text, preventExpand: true)

        #expect(result?.text == tableCoverageText("| a | b |", "|---|---|", "| c | d |"))
    }

    @Test
    func caretInsideAShrunkSeparatorCollapsesToTheChangedStart() {
        let text = tableCoverageText("|a|", "|-----|", "|c|")

        let result = MarkdownTable.format(
            text: text,
            selections: [NSRange(location: 9, length: 0)],
            style: .tight
        )

        #expect(result?.text == tableCoverageText("|a|", "|---|", "|c|"))
        #expect(result?.selections == [NSRange(location: 8, length: 0)])
    }
}

struct MarkdownTableCellContentCoverageTests {
    private func aligned(_ content: String, width: Int, alignment: MarkdownTableAlignment) -> String {
        tableCoverageString(
            MarkdownTableCellContent.realigned(
                content: Array(content.utf16),
                width: width,
                alignment: alignment,
                style: .aligned
            )
        )
    }

    @Test
    func tabbedCenterCellPicksTheMostBalancedPadding() {
        #expect(aligned("a\tb", width: 12, alignment: .center) == "   a\tb   ")
    }

    @Test
    func tabbedRightCellPicksTheWidestLeftPadding() {
        #expect(aligned("a\tb", width: 12, alignment: .right) == "      a\tb   ")
    }

    @Test
    func tabbedLeftCellKeepsOneLeadingSpace() {
        #expect(aligned("a\tb", width: 10, alignment: .left) == " a\tb     ")
    }

    @Test
    func tabbedCellThatCannotFitFallsBackToOneSpaceOnEachSide() {
        #expect(aligned("a\tb", width: 2, alignment: .right) == " a\tb ")
    }
}

struct MarkdownTableNavigationCoverageTests {
    @Test
    func shiftEnterOutsideTheTextBoundsIsLeftToTheEditor() {
        let text = tableCoverageText("| a |", "|---|", "| b |")

        #expect(MarkdownTable.shiftEnter(text: text, caret: 0) == nil)
        #expect(MarkdownTable.shiftEnter(text: text, caret: 999) == nil)
    }

    @Test
    func shiftEnterBetweenCarriageReturnAndLineFeedIsLeftToTheEditor() {
        let text = "| a |\r\n|---|\r\n| b |"

        #expect(MarkdownTable.shiftEnter(text: text, caret: 6) == nil)
    }

    @Test
    func shiftEnterBeforeTrailingSpacesAddsARowAfterTheLine() throws {
        let text = tableCoverageText("| a | b |", "|---|---|", "| c | d |   ")

        let result = try #require(MarkdownTable.shiftEnter(text: text, caret: 29))

        #expect(result.text == text + "\n|   |   |")
        #expect(result.selections == [NSRange(location: 35, length: 0)])
    }

    @Test
    func tabFromTheHeaderIntoAnEmptyRowStaysAtTheHeaderEnd() {
        let text = tableCoverageText("| a |", "|---|", "|")

        let forward = MarkdownTable.navigate(text: text, caret: 2, forward: true)
        let backward = MarkdownTable.navigate(text: text, caret: 2, forward: false)

        #expect(forward == MarkdownTableNavigation(caret: 5))
        #expect(backward == nil)
    }
}

struct MarkdownTableOfContentsCoverageTests {
    private func toc(_ lines: String...) -> String {
        (["<!-- TOC -->"] + lines + ["<!-- TOC -->"]).joined(separator: "\n")
    }

    private var emptyToc: String {
        "<!-- TOC -->\n<!-- TOC -->"
    }

    @Test(arguments: [
        ("  <!-- omit in toc -->  ", true),
        ("\t<!--   OMIT\tfrom   TOC-->\n", true),
        ("<!-- omit foo toc -->", false),
        ("<!-- omit in toc", false),
        ("<!-- omit in toc --> x", false),
        ("<!-- omit", false),
        ("", false)
    ])
    func omitMarkerMatching(text: String, expected: Bool) {
        #expect(MarkdownTableOfContents.isOmitMarker(text) == expected)
    }

    @Test
    func headersWithoutAnchorTextAreSkipped() {
        #expect(MarkdownTableOfContents.build(text: "#\n\n# Real") == toc("* [Real](#real)"))
    }

    @Test
    func omitMarkerFollowedByAnotherInlineNodeHidesTheHeader() {
        #expect(MarkdownTableOfContents.build(text: "## A <!-- omit in toc --> `c`") == emptyToc)
    }

    @Test
    func omitMarkerFollowedByADistantTagHidesTheHeader() {
        #expect(MarkdownTableOfContents.build(text: "## A <!-- omit in toc --> mid <!-- x -->") == emptyToc)
    }

    @Test
    func indentedHeaderAtTheDocumentStartIsTopLevel() {
        #expect(MarkdownTableOfContents.build(text: " # Indented") == toc("* [Indented](#indented)"))
    }

    @Test
    func headerInsideAListItemContentIsNotTopLevel() {
        #expect(MarkdownTableOfContents.build(text: "- item\n\n  # Nested") == emptyToc)
    }

    @Test
    func headerLessIndentedThanTheItemContentIsTopLevel() {
        #expect(MarkdownTableOfContents.build(text: "1. item\n\n # Edge") == toc("* [Edge](#edge)"))
    }

    @Test
    func headerSearchContinuesPastNestedItemsToTheOuterItem() {
        #expect(MarkdownTableOfContents.build(text: "- a\n  - b\n\n # H") == toc("* [H](#h)"))
    }

    @Test
    func headerAfterAnUnindentedParagraphIsTopLevel() {
        #expect(MarkdownTableOfContents.build(text: "text\n\n # H") == toc("* [H](#h)"))
    }

    @Test
    func headerAfterAQuoteIsTopLevel() {
        #expect(MarkdownTableOfContents.build(text: "> quote\n\n # H") == toc("* [H](#h)"))
    }

    @Test
    func headerAfterATabIndentedCodeBlockIsTopLevel() {
        #expect(MarkdownTableOfContents.build(text: "\tcode\n\n # H") == toc("* [H](#h)"))
    }
}
