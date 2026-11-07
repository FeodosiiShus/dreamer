import Foundation
import Testing
@testable import Dreamder

@Suite
struct MarkdownTextLinesTests {
    @Test
    func splitsLinesOnAllTerminators() {
        let lines = MarkdownTextLines("a\nb\r\nc\rd")
        #expect(lines.count == 4)
        #expect(lines.lines.map(\.start) == [0, 2, 5, 7])
        #expect(lines.lines.map(\.contentEnd) == [1, 3, 6, 8])
        #expect(lines.lineEnding == "\n")
    }

    @Test
    func detectsTheFirstLineEnding() {
        #expect(MarkdownTextLines("a\r\nb\nc").lineEnding == "\r\n")
        #expect(MarkdownTextLines("a\rb").lineEnding == "\r")
        #expect(MarkdownTextLines("single").lineEnding == "\n")
    }

    @Test
    func trailingTerminatorCreatesAnEmptyLastLine() {
        let lines = MarkdownTextLines("a\n")
        #expect(lines.count == 2)
        #expect(lines.lines[1].start == 2)
        #expect(lines.lines[1].contentEnd == 2)
    }

    @Test
    func findsTheLineContainingAnOffset() {
        let lines = MarkdownTextLines("ab\ncd\n\nef")
        #expect(lines.lineIndex(containing: 0) == 0)
        #expect(lines.lineIndex(containing: 2) == 0)
        #expect(lines.lineIndex(containing: 3) == 1)
        #expect(lines.lineIndex(containing: 6) == 2)
        #expect(lines.lineIndex(containing: 7) == 3)
        #expect(lines.lineIndex(containing: 9) == 3)
    }

    @Test
    func tabsInTheIndentExpandToTheTabWidth() {
        let lines = MarkdownTextLines("\t> x")
        #expect(String(decoding: lines.expandedIndent(0, tabWidth: 4), as: UTF16.self) == "    > ")
        #expect(MarkdownTextLines.innerSpaces(of: lines.expandedIndent(0, tabWidth: 4)) == 1)
    }

    @Test
    func blankDetectionTreatsQuoteOnlyLinesAsBlank() {
        let lines = MarkdownTextLines("  \n>\n> x\n\t")
        #expect(lines.isBlank(0))
        #expect(lines.isBlank(1))
        #expect(!lines.isBlank(2))
        #expect(lines.isWhitespaceOnly(0))
        #expect(!lines.isWhitespaceOnly(1))
        #expect(lines.isBlank(3))
    }
}

@Suite
struct MarkdownListStructureTests {
    @Test
    func nestsItemsByContentColumn() {
        let structure = MarkdownListStructure("- a\n  - b\n- c")
        #expect(structure.items.map(\.parent) == [nil, 0, nil])
        #expect(structure.itemAtLine == [0, 1, 2])
        #expect(structure.lists.count == 2)
        #expect(structure.lists[0].items == [0, 2])
        #expect(structure.lists[1].items == [1])
        #expect(structure.sublists(of: 0) == [1])
        #expect(structure.items[0].lastLine == 1)
    }

    @Test
    func orderedItemsNestUnderTheirMarkerWidth() {
        let structure = MarkdownListStructure("1. a\n   1. b\n  1. c")
        #expect(structure.items.map(\.parent) == [nil, 0, nil])
    }

    @Test
    func changingTheBulletStartsANewList() {
        let structure = MarkdownListStructure("- a\n* b\n+ c")
        #expect(structure.lists.count == 3)
    }

    @Test
    func changingTheNumberDelimiterStartsANewList() {
        let structure = MarkdownListStructure("1. a\n2) b")
        #expect(structure.lists.count == 2)
    }

    @Test
    func blankLinesBetweenItemsKeepTheList() {
        let structure = MarkdownListStructure("- a\n\n- b")
        #expect(structure.lists.count == 1)
        #expect(structure.itemAtLine == [0, nil, 1])
    }

    @Test
    func aParagraphBetweenItemsSplitsTheList() {
        let structure = MarkdownListStructure("- a\n\npara\n\n- b")
        #expect(structure.lists.count == 2)
        #expect(structure.itemAtLine == [0, nil, nil, nil, 1])
    }

    @Test
    func lazyContinuationBelongsToTheItem() {
        let structure = MarkdownListStructure("- a\nlazy")
        #expect(structure.itemAtLine == [0, 0])
        #expect(structure.items[0].lastLine == 1)
    }

    @Test
    func unindentedParagraphAfterBlankEndsTheItem() {
        let structure = MarkdownListStructure("- a\n\nb")
        #expect(structure.itemAtLine == [0, nil, nil])
    }

    @Test
    func indentedParagraphAfterBlankBelongsToTheItem() {
        let structure = MarkdownListStructure("- a\n\n  b")
        #expect(structure.itemAtLine == [0, nil, 0])
        #expect(structure.items[0].lastLine == 2)
    }

    @Test
    func headingInterruptsTheList() {
        let structure = MarkdownListStructure("- a\n# H\n- b")
        #expect(structure.itemAtLine == [0, nil, 1])
        #expect(structure.lists.count == 2)
    }

    @Test
    func thematicBreakInterruptsTheList() {
        let structure = MarkdownListStructure("- a\n***\nb")
        #expect(structure.itemAtLine[1] == nil)
    }

    @Test
    func emptyItemDetection() {
        let structure = MarkdownListStructure("- a\n- \n- [ ] \n-")
        #expect(structure.isEmpty(item: 0) == false)
        #expect(structure.isEmpty(item: 1))
        #expect(structure.isEmpty(item: 2))
        #expect(structure.isEmpty(item: 3))
    }

    @Test
    func itemWithContentOnTheNextLineIsNotEmpty() {
        let structure = MarkdownListStructure("-\n  text")
        #expect(structure.isEmpty(item: 0) == false)
        #expect(structure.itemAtLine == [0, 0])
    }

    @Test
    func unindentedTextAfterAnEmptyItemIsNotItsContent() {
        let structure = MarkdownListStructure("- \nfoo")
        #expect(structure.isEmpty(item: 0))
        #expect(structure.itemAtLine == [0, nil])
    }

    @Test
    func emptyItemWithNestedItemIsNotEmpty() {
        let structure = MarkdownListStructure("- \n  - b")
        #expect(structure.isEmpty(item: 0) == false)
    }

    @Test
    func listsInsideBlockQuotesNestByColumns() {
        let structure = MarkdownListStructure("> - a\n>   - b\n> - c")
        #expect(structure.items.map(\.parent) == [nil, 0, nil])
        #expect(structure.items.map(\.quoteCount) == [1, 1, 1])
        #expect(structure.items.map(\.innerIndent) == [1, 3, 1])
        #expect(structure.lists.count == 2)
    }

    @Test
    func leavingTheBlockQuoteEndsTheList() {
        let structure = MarkdownListStructure("> - a\n- b")
        #expect(structure.items.map(\.parent) == [nil, nil])
        #expect(structure.lists.count == 2)
        #expect(structure.itemAtLine == [0, 1])
    }

    @Test
    func aBlockQuoteInsideAnItemStaysInsideIt() {
        let structure = MarkdownListStructure("- a\n  > q")
        #expect(structure.itemAtLine == [0, 0])
    }

    @Test
    func aBlockQuoteAtTheMarginEndsTheItem() {
        let structure = MarkdownListStructure("- a\n> q")
        #expect(structure.itemAtLine == [0, nil])
    }

    @Test
    func indentedCodeIsNotAnItem() {
        let structure = MarkdownListStructure("para\n\n    - x")
        #expect(structure.items.isEmpty)
    }

    @Test
    func deeplyIndentedMarkerUnderAnItemIsItsChild() {
        let structure = MarkdownListStructure("- a\n    - b")
        #expect(structure.items.map(\.parent) == [nil, 0])
    }

    @Test
    func listMarkersInsideFencesAreText() {
        let structure = MarkdownListStructure("```\n- a\n1. b\n```\n- c")
        #expect(structure.items.map(\.line) == [4])
        #expect(structure.fenceAtLine == [0, 0, 0, 0, nil])
    }

    @Test
    func fenceRangesAndIndent() {
        let structure = MarkdownListStructure("- a\n  ```py\n  x\n  ```\n- b")
        #expect(structure.fences.count == 1)
        let fence = structure.fences[0]
        #expect(fence.openLine == 1)
        #expect(fence.closeLine == 3)
        #expect(String(decoding: fence.indent, as: UTF16.self) == "  ")
        #expect(structure.items.map(\.line) == [0, 4])
        #expect(structure.itemAtLine[2] == 0)
    }

    @Test
    func unclosedFenceRunsToTheEndOfTheDocument() throws {
        let structure = MarkdownListStructure("```\ncode\n\n- not an item")
        let fence = try #require(structure.fences.first)
        #expect(fence.closeLine == nil)
        #expect(fence.endOffset == "```\ncode\n\n- not an item".utf16.count)
        #expect(structure.items.isEmpty)
    }

    @Test
    func tildeFenceNeedsMatchingCloser() {
        let structure = MarkdownListStructure("~~~\n```\n- x\n~~~\n- y")
        #expect(structure.fences.count == 1)
        #expect(structure.items.map(\.line) == [4])
    }

    @Test
    func backtickLineWithBackticksInInfoIsNotAFence() {
        let structure = MarkdownListStructure("```code``` text\n- a")
        #expect(structure.fences.isEmpty)
        #expect(structure.items.map(\.line) == [1])
    }

    @Test
    func fenceIndentInsideQuoteKeepsQuoteMarkers() throws {
        let structure = MarkdownListStructure("> ```\n> x\n> ```")
        let fence = try #require(structure.fences.first)
        #expect(String(decoding: fence.indent, as: UTF16.self) == "> ")
    }

    @Test
    func fenceOnTheItemLineHasMarkerWidthIndent() throws {
        let structure = MarkdownListStructure("- ```py\n  x\n  ```")
        let fence = try #require(structure.fences.first)
        #expect(String(decoding: fence.indent, as: UTF16.self) == "  ")
        #expect(structure.itemAtLine == [0, 0, 0])
    }

    @Test
    func caretInsideFenceCoversOpeningAndClosingLines() {
        let text = "a\n```\nx\n```\nb"
        let structure = MarkdownListStructure(text)
        #expect(structure.fence(containingCaret: 2) == nil)
        #expect(structure.fence(containingCaret: 5) != nil)
        #expect(structure.fence(containingCaret: 11) != nil)
        #expect(structure.fence(containingCaret: 12) == nil)
    }

    @Test
    func quoteInsideItemIsDetectedOnContinuationAndItemLines() {
        let structure = MarkdownListStructure("- a\n  > q\n- > r")
        #expect(structure.quoteInsideItem(0, line: 1, caret: 9))
        #expect(!structure.quoteInsideItem(0, line: 0, caret: 3))
        #expect(structure.quoteInsideItem(1, line: 2, caret: 15))
    }

    @Test
    func descendantsFollowTheItemInsideTheSameList() {
        let structure = MarkdownListStructure("- a\n  - b\n- c\n\npara\n- d")
        let list = structure.items[0].list
        #expect(structure.descendantItems(after: 0, inList: list) == [1, 2])
    }

    @Test
    func outermostListOfNestedItem() {
        let structure = MarkdownListStructure("- a\n  - b\n    - c")
        #expect(structure.outermostList(of: 2) == structure.items[0].list)
    }
}

@Suite
struct MarkdownTypingListPrefixTests {
    @Test
    func parsesBullets() throws {
        let prefix = try #require(MarkdownListItemPrefix.parse(line: "- item"))
        #expect(prefix.marker == .bullet("-"))
        #expect(prefix.markerText == "-")
        #expect(prefix.contentStart == 2)
        #expect(prefix.hasContent)
        #expect(prefix.checkbox == nil)
        #expect(prefix.markerTokenEnd == 2)
        #expect(prefix.normalizedMarkerText == "- ")
    }

    @Test
    func parsesOrderedMarkers() throws {
        let prefix = try #require(MarkdownListItemPrefix.parse(line: "  10) item"))
        #expect(prefix.indent == "  ")
        #expect(prefix.marker == .ordered(number: 10, delimiter: ")"))
        #expect(prefix.number == 10)
        #expect(prefix.delimiter == ")")
        #expect(prefix.indentLength == 2)
        #expect(prefix.markerTokenEnd == 6)
        #expect(prefix.contentStart == 6)
    }

    @Test
    func indentIncludesQuoteMarkers() throws {
        let prefix = try #require(MarkdownListItemPrefix.parse(line: ">  > - item"))
        #expect(prefix.indent == ">  > ")
        #expect(prefix.indentLength == 5)
    }

    @Test
    func parsesCheckboxes() throws {
        let unchecked = try #require(MarkdownListItemPrefix.parse(line: "- [ ] task"))
        #expect(unchecked.checkbox == false)
        #expect(unchecked.contentStart == 6)
        #expect(unchecked.prefixEnd == 6)
        #expect(unchecked.checkboxText == "[ ] ")
        let checked = try #require(MarkdownListItemPrefix.parse(line: "- [X] task"))
        #expect(checked.checkbox == true)
        #expect(checked.checkboxText == "[x] ")
        let bare = try #require(MarkdownListItemPrefix.parse(line: "- [x]"))
        #expect(bare.checkbox == true)
        #expect(bare.contentStart == 5)
        #expect(!bare.hasContent)
        let notACheckbox = try #require(MarkdownListItemPrefix.parse(line: "- [x]y"))
        #expect(notACheckbox.checkbox == nil)
        #expect(notACheckbox.contentStart == 2)
    }

    @Test
    func emptyItemsHaveNoContent() throws {
        for line in ["-", "- ", "-   ", "1. ", "- [ ] ", "-     "] {
            let prefix = try #require(MarkdownListItemPrefix.parse(line: Substring(line)))
            #expect(!prefix.hasContent, "\(line.debugDescription)")
        }
    }

    @Test
    func markerWidthFollowsCommonMark() throws {
        #expect(try #require(MarkdownListItemPrefix.parse(line: "-   x")).markerWidth == 4)
        #expect(try #require(MarkdownListItemPrefix.parse(line: "-     x")).markerWidth == 2)
        #expect(try #require(MarkdownListItemPrefix.parse(line: "1.\tx")).markerWidth == 3)
        #expect(try #require(MarkdownListItemPrefix.parse(line: "-")).markerWidth == 2)
    }

    @Test
    func rejectsNonItems() {
        for line in ["-x", "1.x", "1234567890. x", "[ ] x", "text", "", "   ", "# - x", "1 . x", ">"] {
            #expect(MarkdownListItemPrefix.parse(line: Substring(line)) == nil, "\(line.debugDescription)")
        }
    }

    @Test
    func nextMarkerTextIncrementsOnlyOrderedMarkers() throws {
        #expect(try #require(MarkdownListItemPrefix.parse(line: "3. x")).nextMarkerText() == "4.")
        #expect(try #require(MarkdownListItemPrefix.parse(line: "3. x")).nextMarkerText(sequential: false) == "3.")
        #expect(try #require(MarkdownListItemPrefix.parse(line: "* x")).nextMarkerText() == "*")
    }

    @Test
    func sameListKindComparesBulletAndDelimiter() throws {
        let dash = try #require(MarkdownListItemPrefix.parse(line: "- a"))
        let star = try #require(MarkdownListItemPrefix.parse(line: "* a"))
        let dot = try #require(MarkdownListItemPrefix.parse(line: "1. a"))
        let paren = try #require(MarkdownListItemPrefix.parse(line: "1) a"))
        #expect(dash.isSameListKind(as: dash))
        #expect(!dash.isSameListKind(as: star))
        #expect(!dot.isSameListKind(as: paren))
        #expect(!dash.isSameListKind(as: dot))
    }

    @Test
    func offsetsAreUtf16Units() throws {
        let prefix = try #require(MarkdownListItemPrefix.parse(line: "- 😀 x"))
        #expect(prefix.contentStart == 2)
        #expect(prefix.lineLength == 6)
    }
}

@Suite
struct MarkdownCaretMarkupTests {
    @Test
    func parsesCaret() {
        let markup = MarkdownCaretMarkup("ab<caret>cd")
        #expect(markup.text == "abcd")
        #expect(markup.caret == 2)
        #expect(markup.selection == nil)
    }

    @Test
    func parsesSelection() {
        let markup = MarkdownCaretMarkup("a<selection>bc</selection>d")
        #expect(markup.text == "abcd")
        #expect(markup.selection == NSRange(location: 1, length: 2))
        #expect(markup.caret == 3)
    }

    @Test
    func countsUtf16Units() {
        let markup = MarkdownCaretMarkup("😀<caret>x")
        #expect(markup.caret == 2)
    }

    @Test
    func rendersBack() {
        #expect(MarkdownCaretMarkup.render("abcd", caret: 2) == "ab<caret>cd")
    }
}
