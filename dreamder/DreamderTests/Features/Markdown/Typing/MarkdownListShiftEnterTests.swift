import Foundation
import Testing
@testable import Dreamder

@Suite
struct MarkdownListShiftEnterTests {
    static let continuationCases: [MarkdownTypingCase] = [
        .init("continues the current item", "- item 1\n  1. item 2<caret>", "- item 1\n  1. item 2\n     <caret>"),
        .init("keeps the block quote prefix", "- item\n  > quote<caret>", "- item\n  > quote\n  > <caret>"),
        .init("bullet", "- item<caret>", "- item\n  <caret>"),
        .init("ordered with two digits", "10. item<caret>", "10. item\n    <caret>"),
        .init("indent equals marker width on the first line", "1. one<caret>", "1. one\n   <caret>"),
        .init("continuation line keeps its own indent", "- a\n  b<caret>", "- a\n  b\n  <caret>"),
        .init("appends at the end of the line", "- ab<caret>cd", "- abcd\n  <caret>"),
        .init("list inside block quote", "> - a<caret>", "> - a\n>   <caret>"),
        .init("checkbox does not widen the indent", "- [ ] task<caret>", "- [ ] task\n  <caret>")
    ]

    @Test(arguments: continuationCases)
    func startsContinuationLine(_ scenario: MarkdownTypingCase) {
        #expect(MarkdownTypingHarness.enter(scenario.before, shift: true) == scenario.after)
    }

    static let defaultCases: [String] = [
        "- <caret>",
        "plain<caret>",
        "- item\n  ```python\n  x = 1<caret>\n  ```",
        "<caret>",
        "# Title<caret>"
    ]

    @Test(arguments: defaultCases)
    func leavesEditorDefault(_ marked: String) {
        #expect(MarkdownTypingHarness.rawEnterEdit(marked, shift: true) == nil)
    }

    @Test
    func disabledSmartEnterLeavesShiftEnterToEditor() {
        let settings = MarkdownTypingSettings(smartEnterAndBackspace: false)
        #expect(MarkdownTypingHarness.rawEnterEdit("- item<caret>", shift: true, settings: settings) == nil)
    }

    @Test
    func shiftEnterDoesNotCreateAnItem() {
        let result = MarkdownTypingHarness.enter("1. one<caret>", shift: true)
        #expect(!result.contains("2."))
    }
}
