import Foundation
import Testing
@testable import Dreamder

struct MarkdownTextStateCoverageTests {
    @Test
    func caretInsideAReplacedRangeCollapsesIntoTheReplacement() {
        var state = MarkdownTextState(text: "abcdef", caret: 3)

        state.apply([MarkdownReplacement(start: 1, end: 5, text: "X")])

        #expect(state.text == "aXf")
        #expect(state.caret == 2)
    }

    @Test
    func caretInsideALongerReplacementKeepsItsOffset() {
        var state = MarkdownTextState(text: "abcdef", caret: 3)

        state.apply([MarkdownReplacement(start: 1, end: 5, text: "WXYZ12")])

        #expect(state.text == "aWXYZ12f")
        #expect(state.caret == 3)
    }

    @Test
    func caretsBeforeAndAfterAReplacementAreShiftedOrKept() {
        let before = MarkdownTextState(text: "abcdef", caret: 1).applying([MarkdownReplacement(start: 2, end: 4, text: "")])
        let after = MarkdownTextState(text: "abcdef", caret: 5).applying([MarkdownReplacement(start: 2, end: 4, text: "")])

        #expect(before.caret == 1)
        #expect(after.caret == 3)
    }

    @Test
    func changedHighSurrogateWidensToTheWholePair() {
        let original = Array("a😀b".utf16)

        let edit = MarkdownTypingEdit.between(original, and: MarkdownTextState(text: "a😁b", caret: 3))

        #expect(edit.range == NSRange(location: 1, length: 2))
        #expect(edit.replacement == "😁")
        #expect(edit.caretOffset == 3)
        #expect(edit.applied(to: "a😀b").text == "a😁b")
    }

    @Test
    func changedLeadingSurrogateKeepsTheSharedTrailingSurrogateInsideTheEdit() {
        let original = Array("a😀b".utf16)

        let edit = MarkdownTypingEdit.between(original, and: MarkdownTextState(text: "a\u{1F200}b", caret: 3))

        #expect(edit.range == NSRange(location: 1, length: 2))
        #expect(edit.replacement == "\u{1F200}")
        #expect(edit.applied(to: "a😀b").text == "a\u{1F200}b")
    }

    @Test
    func insertingALoneNewlineIntoEmptyTextKeepsTheEditAsIs() {
        let edit = MarkdownTypingEdit.between([], and: MarkdownTextState(text: "\n", caret: 1))

        #expect(edit.range == NSRange(location: 0, length: 0))
        #expect(edit.replacement == "\n")
        #expect(edit.caretOffset == 1)
        #expect(!edit.isCaretOnly)
    }

    @Test
    func identicalTextIsACaretOnlyEdit() {
        let edit = MarkdownTypingEdit.between(Array("abc".utf16), and: MarkdownTextState(text: "abc", caret: 1))

        #expect(edit.isCaretOnly)
    }
}

struct MarkdownListItemPrefixCoverageTests {
    @Test
    func parsingASubstringMatchesParsingItsUnits() throws {
        let line = "10) text"

        let fromLine = try #require(MarkdownListItemPrefix.parse(line: Substring(line)))
        let fromUnits = try #require(MarkdownListItemPrefix.parse(units: ArraySlice(Array(line.utf16))))

        #expect(fromLine == fromUnits)
        #expect(fromLine.number == 10)
    }
}

struct MarkdownListStructureCoverageTests {
    @Test
    func textLinesSliceByUtf16Offsets() {
        let lines = MarkdownTextLines("hello\nworld")

        #expect(lines.string(from: 6, to: 11) == "world")
        #expect(lines.string(from: 0, to: 0).isEmpty)
    }

    @Test
    func closingFenceMayBeFollowedByBlanks() throws {
        let structure = MarkdownListStructure("```\ncode\n```  \nafter")

        let fence = try #require(structure.fences.first)

        #expect(structure.fences.count == 1)
        #expect(fence.closeLine == 2)
    }

    @Test
    func closingFenceFollowedByTextDoesNotClose() throws {
        let structure = MarkdownListStructure("```\ncode\n``` x\nmore\n```")

        let fence = try #require(structure.fences.first)

        #expect(structure.fences.count == 1)
        #expect(fence.closeLine == 4)
    }

    @Test
    func tabsAfterTheClosingFenceAreIgnored() throws {
        let structure = MarkdownListStructure("```\n```\t\ntext")

        let fence = try #require(structure.fences.first)

        #expect(fence.closeLine == 1)
    }

    @Test
    func tabIndentedQuoteInsideAnItemIsDetectedAfterTheCaret() {
        let structure = MarkdownListStructure("- a\n\t> q")

        #expect(structure.itemAtLine == [0, 0])
        #expect(structure.quoteInsideItem(0, line: 1, caret: 8))
        #expect(!structure.quoteInsideItem(0, line: 1, caret: 5))
    }

    @Test
    func quoteMarkersAfterTheItemContentOnTheItemLineAreDetected() {
        let structure = MarkdownListStructure("- > q")

        #expect(structure.quoteInsideItem(0, line: 0, caret: 5))
        #expect(!structure.quoteInsideItem(0, line: 0, caret: 2))
    }

    @Test
    func lineWithoutQuoteMarkerLeavesAQuotedItem() {
        let structure = MarkdownListStructure("> - a\nb")

        #expect(structure.itemAtLine == [0, nil])
    }

    @Test
    func headingWithTabAfterTheHashesEndsTheItem() {
        let structure = MarkdownListStructure("- a\n#\tb")

        #expect(structure.itemAtLine == [0, nil])
    }

    @Test
    func hashesWithoutSeparatorStayLazyContinuation() {
        let structure = MarkdownListStructure("- a\n#b")

        #expect(structure.itemAtLine == [0, 0])
    }

    @Test
    func tooShortBacktickRunIsNotAFence() {
        let structure = MarkdownListStructure("- a\n``x")

        #expect(structure.itemAtLine == [0, 0])
        #expect(structure.fences.isEmpty)
    }
}

struct MarkdownListEnterCoverageTests {
    @Test
    func outOfRangeCaretsProduceNoEdit() {
        #expect(MarkdownListEnter.edit(forEnterIn: "abc", caret: -1) == nil)
        #expect(MarkdownListEnter.edit(forEnterIn: "abc", caret: 4) == nil)
        #expect(MarkdownListEnter.edit(forBackspaceIn: "abc", caret: 0) == nil)
        #expect(MarkdownListEnter.edit(forBackspaceIn: "abc", caret: 4) == nil)
    }

    @Test
    func backspaceAtLineStartIsLeftToTheEditor() {
        #expect(MarkdownTypingHarness.rawBackspaceEdit("x\n<caret>y") == nil)
    }

    @Test
    func backspaceInTheIndentOfALazyContinuationBelowTheItemIndentIsLeftToTheEditor() {
        #expect(MarkdownTypingHarness.rawBackspaceEdit("  - a\n <caret>x") == nil)
    }

    @Test
    func backspaceCountsTabsAsTabWidthWhenUnindenting() {
        #expect(MarkdownTypingHarness.backspace("- a\n\t<caret>- b") == "- a\n  <caret>- b")
    }

    @Test
    func backspaceUnindentRenumbersTheListAndRestartsItsSublist() {
        let settings = MarkdownTypingSettings(renumberListsOnType: true)

        let result = MarkdownTypingHarness.backspace(
            "1. a\n   <caret>1. b\n      5. c\n      7. d",
            settings: settings
        )

        #expect(result == "1. a\n<caret>2. b\n   1. c\n   2. d")
    }

    @Test
    func backspaceUnindentRenumbersItemsWithoutSublists() {
        let settings = MarkdownTypingSettings(renumberListsOnType: true)

        let result = MarkdownTypingHarness.backspace("1. a\n   <caret>1. b", settings: settings)

        #expect(result == "1. a\n<caret>2. b")
    }

    @Test
    func backspaceUnindentKeepsNumbersWhenRenumberingIsOff() {
        let result = MarkdownTypingHarness.backspace("1. a\n   <caret>5. b\n      5. c")

        #expect(result == "1. a\n<caret>5. b\n   5. c")
    }

    @Test
    func enterOnEmptyNestedItemRenumbersAfterUnindenting() {
        let settings = MarkdownTypingSettings(renumberListsOnType: true)

        let result = MarkdownTypingHarness.enter("1. a\n   1. <caret>", settings: settings)

        #expect(result == "1. a\n2. <caret>")
    }
}
