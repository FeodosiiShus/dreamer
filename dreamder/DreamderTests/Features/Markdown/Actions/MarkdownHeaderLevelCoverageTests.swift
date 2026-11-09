import Foundation
import Testing
@testable import Dreamder

struct MarkdownHeaderLevelCoverage {
    private func set(_ level: Int, _ markup: String) -> String? {
        let parsed = MarkdownActionCaretMarkup(markup)
        return MarkdownHeaderLevel.set(level: level, text: parsed.text, selections: parsed.selections)
            .map { MarkdownActionCaretMarkup.render($0.text, $0.selections) }
    }

    @Test
    func selectionStartingAtTheEndOfALineBelongsToTheNextLine() {
        let selections = [NSRange(location: 3, length: 7)]

        let level2 = MarkdownHeaderLevel.isSelected(level: 2, text: "one\n## two", selections: selections)
        let up = MarkdownHeaderLevel.isHeaderUpEnabled(text: "one\n## two", selections: selections)

        #expect(level2)
        #expect(up)
    }

    @Test
    func selectionEndingAtTheStartOfALineBelongsToThePreviousLine() {
        let selections = [NSRange(location: 0, length: 7)]

        let level2 = MarkdownHeaderLevel.isSelected(level: 2, text: "## one\ntwo", selections: selections)
        let up = MarkdownHeaderLevel.isHeaderUpEnabled(text: "## one\ntwo", selections: selections)

        #expect(level2)
        #expect(up)
    }

    @Test
    func selectionSpanningSeveralBlocksIsOnlyNormalText() {
        let text = "# a\n\nb"
        let selections = [NSRange(location: 0, length: 6)]

        let normal = MarkdownHeaderLevel.isSelected(level: 0, text: text, selections: selections)
        let level1 = MarkdownHeaderLevel.isSelected(level: 1, text: text, selections: selections)
        let up = MarkdownHeaderLevel.isHeaderUpEnabled(text: text, selections: selections)
        let down = MarkdownHeaderLevel.isHeaderDownEnabled(text: text, selections: selections)

        #expect(normal)
        #expect(!level1)
        #expect(!up)
        #expect(!down)
        #expect(MarkdownHeaderLevel.set(level: 1, text: text, selections: selections) == nil)
    }

    @Test
    func selectionOnABlankLineHasNoTarget() {
        let selections = [NSRange(location: 4, length: 0)]

        #expect(MarkdownHeaderLevel.set(level: 1, text: "# a\n\nb", selections: selections) == nil)
        #expect(MarkdownHeaderLevel.headerDown(text: "# a\n\nb", selections: selections) == nil)
    }

    @Test
    func selectionOutsideTheTextHasNoTarget() {
        let selections = [NSRange(location: 100, length: 0)]

        let normal = MarkdownHeaderLevel.isSelected(level: 0, text: "text", selections: selections)

        #expect(normal)
        #expect(MarkdownHeaderLevel.set(level: 1, text: "text", selections: selections) == nil)
    }

    @Test
    func codeBlocksCannotBecomeHeaders() {
        #expect(set(1, "```\nco<caret>de\n```") == nil)
        #expect(set(0, "    co<caret>de") == nil)
    }

    @Test
    func setextHeaderWithTrailingSpacesLosesThemWhenConvertedToAtx() {
        #expect(set(2, "Ti<caret>tle  \n===\nnext") == "## Ti<caret>tle\nnext")
    }
}
