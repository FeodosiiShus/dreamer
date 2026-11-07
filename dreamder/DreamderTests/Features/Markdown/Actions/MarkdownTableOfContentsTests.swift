import Foundation
import Testing

@testable import Dreamder

struct MarkdownTableOfContentsTests {
    private func toc(_ lines: String...) -> String {
        (["<!-- TOC -->"] + lines + ["<!-- TOC -->"]).joined(separator: "\n")
    }

    @Test func buildsNestedEntriesWithTwoSpaceIndent() {
        let text = "# Title\n\n## Sub\n\n### Deep\n\n## Other"
        let expected = toc("* [Title](#title)", "  * [Sub](#sub)", "    * [Deep](#deep)", "  * [Other](#other)")
        #expect(MarkdownTableOfContents.build(text: text) == expected)
    }

    @Test func buildsWithCustomIndentSize() {
        let text = "# A\n## B\n### C"
        let expected = toc("* [A](#a)", "    * [B](#b)", "        * [C](#c)")
        #expect(MarkdownTableOfContents.build(text: text, indentSize: 4) == expected)
    }

    @Test func documentWithoutHeadersBuildsEmptyBlock() {
        #expect(MarkdownTableOfContents.build(text: "just text") == "<!-- TOC -->\n<!-- TOC -->")
    }

    @Test func setextHeadersAreListed() {
        let text = "Title\n=====\n\nSub\n---"
        let expected = toc("* [Title](#title)", "  * [Sub](#sub)")
        #expect(MarkdownTableOfContents.build(text: text) == expected)
    }

    @Test func headerLinkContributesItsTextOnly() {
        let text = "# See [docs](https://example.com) now"
        #expect(MarkdownTableOfContents.build(text: text) == toc("* [See docs now](#see-docs-now)"))
    }

    @Test func headerImageIsKeptInTextAndDroppedFromAnchor() {
        let text = "# Logo ![alt](i.png)"
        #expect(MarkdownTableOfContents.build(text: text) == toc("* [Logo ![alt](i.png)](#logo-)"))
    }

    @Test func sameTextHeadersGetNumberedAnchors() {
        let text = "# Same\n\n## Same\n\n## Same"
        let expected = toc("* [Same](#same)", "  * [Same](#same-1)", "  * [Same](#same-2)")
        #expect(MarkdownTableOfContents.build(text: text) == expected)
    }

    @Test func headerCommentIsNotPartOfTextOrAnchor() {
        let text = "## Title <!-- note -->"
        #expect(MarkdownTableOfContents.build(text: text) == toc("  * [Title](#title)"))
    }

    @Test func headerHtmlTagsAreDroppedFromText() {
        let text = "# Hello <b>world</b>"
        #expect(MarkdownTableOfContents.build(text: text) == toc("* [Hello world](#hello-bworldb)"))
    }

    @Test func inlineOmitMarkerHidesHeaderButKeepsItsAnchorNumber() {
        let text = "# A\n\n## A <!-- omit in toc -->\n\n## A"
        let expected = toc("* [A](#a)", "  * [A](#a-2)")
        #expect(MarkdownTableOfContents.build(text: text) == expected)
    }

    @Test func omitMarkerAboveHidesHeader() {
        let text = "<!-- OMIT   from TOC -->\n## Hidden\n\n## Shown"
        #expect(MarkdownTableOfContents.build(text: text) == toc("  * [Shown](#shown)"))
    }

    @Test func omitMarkerSeparatedByBlankLineDoesNotHideHeader() {
        let text = "<!-- omit from toc -->\n\n## Visible"
        #expect(MarkdownTableOfContents.build(text: text) == toc("  * [Visible](#visible)"))
    }

    @Test func nestedHeadersAreNotListedButCountForAnchors() {
        let text = "# Same\n\n> # Same\n\n- # Same\n\n# Same"
        let expected = toc("* [Same](#same)", "* [Same](#same-3)")
        #expect(MarkdownTableOfContents.build(text: text) == expected)
    }

    @Test func frontMatterAndCodeFencesAreSkipped() {
        let text = "---\ntitle: x\n---\n\n# Real\n\n```\n# Not a header\n```"
        #expect(MarkdownTableOfContents.build(text: text) == toc("* [Real](#real)"))
    }

    @Test func existingRangesPairTopLevelDelimiters() {
        let text = "<!-- TOC -->\n# A\n<!-- TOC -->\n\n<!-- TOC -->"
        let ranges = MarkdownTableOfContents.existingRanges(in: text)
        #expect(ranges == [NSRange(location: 0, length: 29)])
    }

    @Test func existingRangesIgnoreNonDelimiterComments() {
        let text = "<!-- TOC -->\n\n<!-- other -->\n\n<!-- TOC -->"
        let ranges = MarkdownTableOfContents.existingRanges(in: text)
        #expect(ranges == [NSRange(location: 0, length: text.utf16.count)])
    }

    @Test func existingRangesIgnoreDelimitersInsideQuotes() {
        let ranges = MarkdownTableOfContents.existingRanges(in: "> <!-- TOC -->\n\n> <!-- TOC -->")
        #expect(ranges.isEmpty)
    }

    @Test func generatesAtCaretWhenNoTocExists() {
        let text = "# A\n\n"
        let result = MarkdownTableOfContents.generate(text: text, caret: 5)
        let block = toc("* [A](#a)")
        #expect(result.text == "# A\n\n" + block)
        #expect(result.selections == [NSRange(location: 5 + block.utf16.count, length: 0)])
    }

    @Test func replacesExistingTocAndIsIdempotent() {
        let text = "<!-- TOC -->\nold\n<!-- TOC -->\n\n# A\n\n## B"
        let first = MarkdownTableOfContents.generate(text: text, caret: 0)
        let expected = toc("* [A](#a)", "  * [B](#b)") + "\n\n# A\n\n## B"
        #expect(first.text == expected)
        let second = MarkdownTableOfContents.generate(text: first.text, caret: 0)
        #expect(second.text == expected)
        #expect(second.edits.isEmpty)
    }

    @Test func updatesEveryTocSection() {
        let text = "<!-- TOC -->\n<!-- TOC -->\n\n# A\n\n<!-- TOC -->\nx\n<!-- TOC -->"
        let result = MarkdownTableOfContents.generate(text: text, caret: 0)
        let block = toc("* [A](#a)")
        #expect(result.text == block + "\n\n# A\n\n" + block)
    }

    @Test func tocLinesDoNotChangeAnchorsOnRegeneration() {
        let text = "# A\n\n" + toc("* [stale](#stale)") + "\n\n# A"
        let result = MarkdownTableOfContents.generate(text: text, caret: 0)
        let block = toc("* [A](#a)", "* [A](#a-1)")
        #expect(result.text == "# A\n\n" + block + "\n\n# A")
    }

    @Test func caretAfterReplacedTocIsShifted() {
        let text = "<!-- TOC -->\n<!-- TOC -->\n\n# A\n"
        let caret = text.utf16.count
        let result = MarkdownTableOfContents.generate(text: text, caret: caret)
        let block = toc("* [A](#a)")
        #expect(result.selections == [NSRange(location: block.utf16.count + "\n\n# A\n".utf16.count, length: 0)])
    }
}
