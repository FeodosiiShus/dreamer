import Foundation
import Testing
@testable import Dreamder

struct MarkdownDocumentBlocksCoverage {
    private func kinds(_ markdown: String) -> [MarkdownBlock.Kind] {
        MarkdownDocument(markdown).blocks.map(\.kind)
    }

    private func lines(_ markdown: String) -> [Range<Int>] {
        MarkdownDocument(markdown).blocks.map(\.lines)
    }

    @Test
    func plusFrontMatterIsRecognizedAtDocumentStart() {
        #expect(kinds("+++\ntitle = 1\n+++\ntext") == [.frontMatter, .paragraph])
        #expect(lines("+++\ntitle = 1\n+++\ntext") == [0..<3, 3..<4])
    }

    @Test
    func dotsTerminateDashFrontMatter() {
        #expect(kinds("---\ntitle: x\n...\ntext") == [.frontMatter, .paragraph])
    }

    @Test
    func unterminatedFrontMatterFallsBackToThematicBreak() {
        #expect(kinds("---\ntitle: x") == [.thematicBreak, .paragraph])
    }

    @Test
    func orderedListItemInterruptsParagraphOnlyWhenItStartsAtOne() {
        #expect(kinds("para\n1. one") == [.paragraph, .paragraph])
        #expect(lines("para\n1. one") == [0..<1, 1..<2])
        #expect(kinds("para\n2. two") == [.paragraph])
        #expect(lines("para\n2. two") == [0..<2])
    }

    @Test
    func bulletListItemInterruptsParagraph() {
        #expect(lines("para\n- item") == [0..<1, 1..<2])
    }

    @Test
    func leadingTabsMakeIndentedCode() {
        #expect(kinds("\tcode") == [.indentedCode])
        #expect(kinds("  \tcode") == [.indentedCode])
    }

    @Test
    func indentedCodeSpansBlankLinesBetweenCodeLinesButNotTrailingOnes() {
        #expect(kinds("    a\n\n    b\n    c\nafter") == [.indentedCode, .paragraph])
        #expect(lines("    a\n\n    b\n    c\nafter") == [0..<4, 4..<5])
        #expect(lines("    a\n\nafter") == [0..<1, 2..<3])
    }

    @Test
    func indentedCodeStopsAtListItem() {
        #expect(kinds("    a\n- item") == [.indentedCode, .paragraph])
        #expect(lines("    a\n- item") == [0..<1, 1..<2])
    }

    @Test
    func processingInstructionBlockEndsAtItsTerminator() {
        #expect(kinds("<?php echo 1 ?>\ntext") == [.htmlBlock, .paragraph])
        #expect(lines("<?php echo 1 ?>\ntext") == [0..<1, 1..<2])
    }

    @Test
    func cdataBlockSpansLinesUntilItsTerminator() {
        #expect(kinds("<![CDATA[\nx\n]]>\ntext") == [.htmlBlock, .paragraph])
        #expect(lines("<![CDATA[\nx\n]]>\ntext") == [0..<3, 3..<4])
    }

    @Test
    func declarationBlockEndsAtClosingBracket() {
        #expect(kinds("<!DOCTYPE html>\ntext") == [.htmlBlock, .paragraph])
        #expect(lines("<!DOCTYPE html>\ntext") == [0..<1, 1..<2])
    }

    @Test
    func rawTextTagBlockIncludesBlankLinesUntilClosingTag() {
        #expect(lines("<pre>\ncode\n\nmore\n</pre>\nafter") == [0..<5, 5..<6])
        #expect(kinds("<pre>\ncode\n\nmore\n</pre>\nafter") == [.htmlBlock, .paragraph])
    }

    @Test
    func rawTextTagClosingIsCaseInsensitive() {
        #expect(lines("<SCRIPT>\nx\n</Script>\nafter") == [0..<3, 3..<4])
    }

    @Test
    func unterminatedRawTextTagRunsToDocumentEnd() {
        #expect(lines("<pre>\ncode\n\nmore") == [0..<4])
        #expect(kinds("<!-- never closed\ntext") == [.htmlBlock])
        #expect(lines("<!-- never closed\ntext") == [0..<2])
    }
}

struct MarkdownDocumentAtxAndSetextCoverage {
    @Test(arguments: ["plain text", "####### seven", "#nospace"])
    func atxContentRangeIsNilForNonHeadingLines(markdown: String) {
        #expect(MarkdownDocument(markdown).atxContentRange(line: 0) == nil)
    }
}
