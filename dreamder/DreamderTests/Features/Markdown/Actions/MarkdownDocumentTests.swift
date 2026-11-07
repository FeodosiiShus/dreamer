import Foundation
import Testing
@testable import Dreamder

struct MarkdownTextTests {
    @Test
    func trailingNewlineProducesFinalEmptyLine() {
        let text = MarkdownText("a\nb\n")

        #expect(text.lines.count == 3)
        #expect(text.lines[2] == MarkdownText.Line(start: 4, contentEnd: 4, end: 4))
    }

    @Test
    func crlfAndLoneCarriageReturnEndLines() {
        let text = MarkdownText("a\r\nb\rc")

        let contents = text.lines.map { text.string($0.contentRange) }
        let ends = text.lines.map(\.end)

        #expect(contents == ["a", "b", "c"])
        #expect(ends == [3, 5, 6])
    }

    @Test(arguments: [(0, 0), (2, 0), (3, 1), (5, 1), (6, 2), (8, 2)])
    func lineIndexContainingOffset(offset: Int, expected: Int) {
        let text = MarkdownText("ab\ncd\nef")

        #expect(text.lineIndex(containing: offset) == expected)
    }

    @Test
    func trimmedRangeDropsSpacesAndTabsOnly() {
        let text = MarkdownText("  \tab c \t ")

        let range = text.trimmedRange(0..<text.length)

        #expect(text.string(range) == "ab c")
    }

    @Test(arguments: [(UInt16(0x20), true), (UInt16(0x09), true), (UInt16(0xA0), false), (UInt16(0x41), false)])
    func javaWhitespaceFollowsJavaDefinition(unit: UInt16, expected: Bool) {
        #expect(MarkdownText.isJavaWhitespace(unit) == expected)
    }

    @Test(arguments: [("a", true), ("7", true), ("한", true), ("-", false), ("_", false)])
    func letterOrDigitClassification(character: String, expected: Bool) {
        let unit = Array(character.utf16)[0]

        #expect(MarkdownText.isLetterOrDigit(unit) == expected)
    }
}

struct MarkdownActionResultTests {
    @Test
    func minimalEditCoversOnlyTheChangedSpan() {
        let edit = MarkdownActionResult.minimalEdit(
            from: Array("hello world".utf16),
            to: Array("hello brave world".utf16)
        )

        #expect(edit == MarkdownTextEdit(range: NSRange(location: 6, length: 0), replacement: "brave "))
    }

    @Test
    func identicalTextsHaveNoEdit() {
        let units = Array("same".utf16)

        #expect(MarkdownActionResult.minimalEdit(from: units, to: units) == nil)
    }

    @Test
    func minimalEditNeverSplitsSurrogatePairs() {
        let edit = MarkdownActionResult.minimalEdit(from: Array("a😀b".utf16), to: Array("a😁b".utf16))

        #expect(edit == MarkdownTextEdit(range: NSRange(location: 1, length: 2), replacement: "😁"))
    }

    @Test
    func appliedEditsReproduceTheUpdatedText() {
        let original = "one two three"
        let result = MarkdownActionResult(
            original: Array(original.utf16),
            updated: Array("one 2 three!".utf16),
            selections: []
        )

        #expect(result.applied(to: original) == "one 2 three!")
        #expect(result.text == "one 2 three!")
    }
}

struct MarkdownEditBufferTests {
    @Test
    func insertionBeforeSettledSelectionShiftsIt() {
        var buffer = MarkdownEditBuffer("abcdef")
        buffer.settle(NSRange(location: 4, length: 2))

        buffer.insert("**", at: 1)

        #expect(buffer.settled == [NSRange(location: 6, length: 2)])
        #expect(String(decoding: buffer.units, as: UTF16.self) == "a**bcdef")
    }

    @Test
    func insertionAtSettledStartMovesTheSelection() {
        var buffer = MarkdownEditBuffer("abcdef")
        buffer.settle(NSRange(location: 3, length: 2))

        buffer.insert("_", at: 3)

        #expect(buffer.settled == [NSRange(location: 4, length: 2)])
    }

    @Test
    func deletionBeforeSettledSelectionShiftsItBack() {
        var buffer = MarkdownEditBuffer("**abc**")
        buffer.settle(NSRange(location: 2, length: 3))

        buffer.delete(0..<2)

        #expect(buffer.settled == [NSRange(location: 0, length: 3)])
    }

    @Test
    func editAfterSettledSelectionLeavesItUntouched() {
        var buffer = MarkdownEditBuffer("abcdef")
        buffer.settle(NSRange(location: 0, length: 2))

        buffer.replace(4..<6, with: "XYZ")

        #expect(buffer.settled == [NSRange(location: 0, length: 2)])
        #expect(String(decoding: buffer.units, as: UTF16.self) == "abcdXYZ")
    }

    @Test
    func resultCarriesTheMinimalEditAndGivenSelections() {
        var buffer = MarkdownEditBuffer("abc")
        buffer.insert("!", at: 3)

        let result = buffer.result(selections: [NSRange(location: 4, length: 0)])

        #expect(result.text == "abc!")
        #expect(result.edits == [MarkdownTextEdit(range: NSRange(location: 3, length: 0), replacement: "!")])
        #expect(result.selections == [NSRange(location: 4, length: 0)])
    }
}

struct MarkdownDocumentTests {
    private func kinds(_ markdown: String) -> [MarkdownBlock.Kind] {
        MarkdownDocument(markdown).blocks.map(\.kind)
    }

    @Test
    func frontMatterOnlyAtDocumentStart() {
        #expect(kinds("---\ntitle: x\n---\ntext") == [.frontMatter, .paragraph])
        #expect(kinds("text\n\n---\ntitle: x\n---") == [.paragraph, .thematicBreak, .setextHeading(level: 2)])
    }

    @Test(arguments: [("# one", 1), ("## two", 2), ("###### six", 6), ("### closed ###", 3)])
    func atxHeadingLevels(markdown: String, level: Int) {
        #expect(kinds(markdown) == [.atxHeading(level: level)])
    }

    @Test(arguments: ["#nospace", "####### seven"])
    func notAtxHeadings(markdown: String) {
        #expect(kinds(markdown) == [.paragraph])
    }

    @Test
    func atxContentRangeDropsClosingSequence() {
        let document = MarkdownDocument("## Title ##  ")

        let range = document.atxContentRange(line: 0)

        #expect(range.map { document.text.string($0) } == "Title")
    }

    @Test
    func atxContentRangeOfEmptyHeadingIsEmpty() {
        let document = MarkdownDocument("#")

        let range = document.atxContentRange(line: 0)

        #expect(range?.isEmpty == true)
    }

    @Test
    func setextHeadingIncludesUnderlineLine() {
        let document = MarkdownDocument("first\nsecond\n===\nnext")

        #expect(document.blocks.map(\.kind) == [.setextHeading(level: 1), .paragraph])
        #expect(document.blocks[0].lines == 0..<3)
        #expect(document.blocks[0].contentLines == 0..<2)
    }

    @Test
    func dashesAfterBlankLineAreThematicBreak() {
        #expect(kinds("text\n\n---") == [.paragraph, .thematicBreak])
        #expect(kinds("text\n---") == [.setextHeading(level: 2)])
    }

    @Test
    func fencedCodeRunsToMatchingFence() {
        let document = MarkdownDocument("```swift\nlet a = 1\n```\ntext")

        #expect(document.blocks.map(\.kind) == [.fencedCode, .paragraph])
        #expect(document.blocks[0].lines == 0..<3)
    }

    @Test
    func longerClosingFenceClosesAndShorterDoesNot() {
        let document = MarkdownDocument("````\n```\ninner\n````\nafter")

        #expect(document.blocks.map(\.kind) == [.fencedCode, .paragraph])
        #expect(document.blocks[0].lines == 0..<4)
    }

    @Test
    func unterminatedFenceRunsToDocumentEnd() {
        let document = MarkdownDocument("```\ncode\nmore")

        #expect(document.blocks.map(\.kind) == [.fencedCode])
        #expect(document.blocks[0].lines == 0..<3)
    }

    @Test
    func tildeFenceAndBacktickInfoStringRule() {
        #expect(kinds("~~~\nx\n~~~") == [.fencedCode])
        #expect(kinds("``` a`b\nx") == [.paragraph])
    }

    @Test
    func isInFencedCodeOnlyInsideTheFence() {
        let document = MarkdownDocument("text\n```\ncode\n```\nafter")

        #expect(document.isInFencedCode(7))
        #expect(document.isInFencedCode(0) == false)
        #expect(document.isInFencedCode(19) == false)
    }

    @Test
    func indentedCodeOnlyOutsideParagraphsAndLists() {
        #expect(kinds("    code") == [.indentedCode])
        #expect(kinds("para\n    still para") == [.paragraph])
        #expect(kinds("- item\n\n    continuation") == [.paragraph, .paragraph])
    }

    @Test
    func htmlCommentBlockEndsAtItsTerminator() {
        let document = MarkdownDocument("<!-- TOC -->\ntext")

        #expect(document.blocks.map(\.kind) == [.htmlBlock, .paragraph])
        #expect(document.blocks[0].lines == 0..<1)
    }

    @Test
    func multilineHtmlCommentSpansLines() {
        let document = MarkdownDocument("<!--\nnote\n-->\ntext")

        #expect(document.blocks.map(\.kind) == [.htmlBlock, .paragraph])
        #expect(document.blocks[0].lines == 0..<3)
    }

    @Test
    func htmlBlockTagRunsToBlankLine() {
        let document = MarkdownDocument("<div>\nhello\n</div>\n\ntext")

        #expect(document.blocks.map(\.kind) == [.htmlBlock, .paragraph])
        #expect(document.blocks[0].lines == 0..<3)
    }

    @Test
    func inlineHtmlTagStartsParagraph() {
        #expect(kinds("<span>text</span> more") == [.paragraph])
    }

    @Test
    func standaloneAutolinkLineIsParagraphWhileStandaloneTagIsHtml() {
        #expect(kinds("<http://example.com>") == [.paragraph])
        #expect(kinds("<custom-tag attr=\"1\">") == [.htmlBlock])
    }

    @Test
    func tableNeedsSeparatorRowWithMatchingColumns() {
        #expect(kinds("| a | b |\n|---|---|\n| 1 | 2 |") == [.table])
        #expect(kinds("| a | b |\n|---|\n| 1 | 2 |") == [.paragraph])
        #expect(kinds("a | b\n- | -\n1 | 2") == [.table])
    }

    @Test
    func tableEndsAtBlankLineAndRowsWithoutPipes() {
        let document = MarkdownDocument("| a |\n|---|\n| 1 |\n\nafter\n")

        #expect(document.blocks.map(\.kind) == [.table, .paragraph])
        #expect(document.blocks[0].lines == 0..<3)
    }

    @Test
    func tableInsideBlockQuote() {
        let document = MarkdownDocument("> | a |\n> |---|\n> | 1 |")

        #expect(document.blocks.map(\.kind) == [.table])
        #expect(document.infos[0].quoteDepth == 1)
    }

    @Test
    func listItemStartsNewParagraphAndKeepsMarkerInfo() {
        let document = MarkdownDocument("* first\n* ### Second\n  more")

        #expect(document.blocks.map(\.kind) == [.paragraph, .atxHeading(level: 3), .paragraph])
        #expect(document.infos[1].listItem?.markerText == "*")
        #expect(document.infos[1].bodyStart == 10)
    }

    @Test
    func blockQuoteMarkersAreCountedAndStripped() {
        let document = MarkdownDocument("> > deep")

        #expect(document.infos[0].quoteDepth == 2)
        #expect(document.infos[0].bodyStart == 4)
    }

    @Test
    func blockLookupByOffsetSkipsBlankLines() {
        let document = MarkdownDocument("one\n\ntwo")

        #expect(document.blockIndex(containing: 0) == 0)
        #expect(document.blockIndex(containing: 4) == nil)
        #expect(document.blockIndex(containing: 5) == 1)
    }

    @Test
    func inlineRegionMasksQuotePrefixAndListMarker() {
        let document = MarkdownDocument("> - *a*\n> b")

        let region = document.inlineRegion(ofBlock: 0)

        #expect(region?.base == 0)
        #expect(region.map { String(decoding: $0.units, as: UTF16.self) } == "    *a*\n  b")
    }

    @Test
    func inlineRegionOfHeadingsCoversOnlyTheContent() {
        let document = MarkdownDocument("## Hi *there* ##")

        let region = document.inlineRegion(ofBlock: 0)

        #expect(region.map { String(decoding: $0.units, as: UTF16.self) } == "   Hi *there*")
    }

    @Test
    func inlineRegionOfSetextHeadingExcludesUnderline() {
        let document = MarkdownDocument("Title *x*\n=====")

        let region = document.inlineRegion(ofBlock: 0)

        #expect(region.map { String(decoding: $0.units, as: UTF16.self) } == "Title *x*")
    }

    @Test
    func codeBlocksHaveNoInlineRegion() {
        let document = MarkdownDocument("```\n*a*\n```")

        #expect(document.inlineRegion(ofBlock: 0) == nil)
    }
}

struct MarkdownTableRowSplitterTests {
    private func split(_ row: String) -> (cells: [String], leading: Bool, trailing: Bool) {
        let text = MarkdownText(row)
        let result = MarkdownTableRowSplitter.split(text.units, body: 0..<text.length)
        return (result.cells.map { text.string($0) }, result.hasLeadingPipe, result.hasTrailingPipe)
    }

    @Test
    func borderedRowYieldsCellsBetweenPipes() {
        let result = split("| a |b| c |")

        #expect(result.cells == [" a ", "b", " c "])
        #expect(result.leading)
        #expect(result.trailing)
    }

    @Test
    func emptyCellsBetweenAdjacentPipes() {
        let result = split("||||")

        #expect(result.cells == ["", "", ""])
    }

    @Test
    func rowWithoutBordersHasFlagsOff() {
        let result = split("a | b")

        #expect(result.cells == ["a ", " b"])
        #expect(result.leading == false)
        #expect(result.trailing == false)
    }

    @Test
    func escapedPipeDoesNotSplit() {
        let result = split("| a \\| b | c |")

        #expect(result.cells == [" a \\| b ", " c "])
    }

    @Test
    func missingTrailingPipeKeepsTheTailCell() {
        let result = split("| a | b")

        #expect(result.cells == [" a ", " b"])
        #expect(result.trailing == false)
    }

    @Test
    func lonePipeHasNoCells() {
        let result = split("|")

        #expect(result.cells.isEmpty)
        #expect(result.leading)
        #expect(result.trailing == false)
    }
}
