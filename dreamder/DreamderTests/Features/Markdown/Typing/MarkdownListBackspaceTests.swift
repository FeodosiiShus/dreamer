import Foundation
import Testing
@testable import Dreamder

@Suite
struct MarkdownListBackspaceTests {
    static let markerCases: [MarkdownTypingCase] = [
        .init("bullet", "- <caret>item", "<caret>item"),
        .init("ordered", "1. <caret>item", "<caret>item"),
        .init("two digit ordered", "10. <caret>item", "<caret>item"),
        .init("caret between marker and space removes the whole marker", "-<caret> item", "<caret>item"),
        .init("caret inside ordered marker", "1<caret>. item", "<caret>item"),
        .init("marker without content", "- <caret>", "<caret>"),
        .init("keeps the checkbox", "- <caret>[ ] item", "<caret>[ ] item"),
        .init("nested item keeps its indent", "- a\n  - <caret>b", "- a\n  <caret>b"),
        .init("in block quote", "> - <caret>a", "> <caret>a"),
        .init("second item", "- a\n- <caret>b", "- a\n<caret>b"),
        .init("number delimiter", "1) <caret>item", "<caret>item")
    ]

    @Test(arguments: markerCases)
    func deletesWholeMarker(_ scenario: MarkdownTypingCase) {
        #expect(MarkdownTypingHarness.backspace(scenario.before) == scenario.after)
    }

    static let editorDefaultCases: [String] = [
        "- ite<caret>m",
        "- [ ] <caret>item",
        "- item<caret>",
        "plain<caret> text",
        "```\n- <caret>x\n```",
        "<caret>- item",
        "text\n  <caret>x"
    ]

    @Test(arguments: editorDefaultCases)
    func leavesEditorDefault(_ marked: String) {
        #expect(MarkdownTypingHarness.rawBackspaceEdit(marked) == nil)
    }

    @Test
    func renumbersFollowingItemsWhenEnabled() {
        let settings = MarkdownTypingSettings(renumberListsOnType: true)
        let result = MarkdownTypingHarness.backspace("1. a\n2. <caret>b\n3. c", settings: settings)
        #expect(result == "1. a\n<caret>b\n2. c")
    }

    @Test
    func keepsFollowingNumbersWhenRenumberingIsOff() {
        let result = MarkdownTypingHarness.backspace("1. a\n2. <caret>b\n3. c")
        #expect(result == "1. a\n<caret>b\n3. c")
    }

    @Test
    func doesNotRenumberWhenTheListWouldBeSplit() {
        let settings = MarkdownTypingSettings(renumberListsOnType: true)
        let result = MarkdownTypingHarness.backspace("1. a\n2. <caret>\n\n3. c", settings: settings)
        #expect(result == "1. a\n<caret>\n\n3. c")
    }

    @Test
    func disabledSmartBackspaceKeepsTheMarkerDeletionToTheEditor() {
        let settings = MarkdownTypingSettings(smartEnterAndBackspace: false)
        #expect(MarkdownTypingHarness.rawBackspaceEdit("- <caret>item", settings: settings) == nil)
    }

    static let indentCases: [MarkdownTypingCase] = [
        .init("nested item moves to the parent indent", "- a\n  <caret>- b", "- a\n<caret>- b"),
        .init("top level item loses its leading spaces", "intro\n\n <caret>- a", "intro\n\n<caret>- a"),
        .init("children move with the item", "- a\n  <caret>- b\n    - c", "- a\n<caret>- b\n  - c"),
        .init(
            "deep item goes to the parent indent",
            "- a\n  - b\n    <caret>- c",
            "- a\n  - b\n  <caret>- c"
        ),
        .init("nested ordered item", "1. a\n   <caret>1. b", "1. a\n<caret>1. b"),
        .init("item inside block quote", "> - a\n>   <caret>- b", "> - a\n> <caret>- b"),
        .init("continuation line goes to the item indent", "- a\n  - b\n    <caret>c", "- a\n  - b\n  <caret>c"),
        .init(
            "continuation line in block quote",
            "> - a\n>   - b\n>     <caret>c",
            "> - a\n>   - b\n>   <caret>c"
        ),
        .init(
            "continuation line after a blank line",
            "- a\n  - b\n\n    <caret>c",
            "- a\n  - b\n\n  <caret>c"
        )
    ]

    @Test(arguments: indentCases)
    func unindentsInsideTheIndent(_ scenario: MarkdownTypingCase) {
        #expect(MarkdownTypingHarness.backspace(scenario.before) == scenario.after)
    }

    @Test
    func repeatedBackspaceIteratesThroughIndentLevels() {
        let before = "- a\n  - b\n    <caret>c"
        #expect(MarkdownTypingHarness.backspace(before, times: 1) == "- a\n  - b\n  <caret>c")
        #expect(MarkdownTypingHarness.backspace(before, times: 2) == "- a\n  - b\n<caret>c")
    }

    @Test
    func repeatedBackspaceIteratesThroughIndentLevelsInBlockQuote() {
        let before = "> - a\n>   - b\n>     <caret>c"
        #expect(MarkdownTypingHarness.backspace(before, times: 1) == "> - a\n>   - b\n>   <caret>c")
        #expect(MarkdownTypingHarness.backspace(before, times: 2) == "> - a\n>   - b\n> <caret>c")
    }

    @Test
    func disabledAdjustListIndentationLeavesIndentToTheEditor() {
        let settings = MarkdownTypingSettings(adjustListIndentation: false)
        #expect(MarkdownTypingHarness.rawBackspaceEdit("- a\n  <caret>- b", settings: settings) == nil)
    }

    @Test
    func backspaceOnFirstLineIndentIsLeftToTheEditor() {
        #expect(MarkdownTypingHarness.rawBackspaceEdit("  <caret>- a") == nil)
    }

    @Test
    func deletingTheMarkerReportsOneEdit() throws {
        let edit = try #require(MarkdownListEnter.edit(forBackspaceIn: "- a\n- b", caret: 6))
        #expect(edit.range == NSRange(location: 4, length: 2))
        #expect(edit.replacement.isEmpty)
        #expect(edit.caretOffset == 4)
    }

    @Test
    func unindentingOneSpaceWidensTheEditSoTheEditorsWhitespaceFilterIsNotTriggered() throws {
        let before = "intro\n\n <caret>- a"
        let markup = MarkdownCaretMarkup(before)
        let edit = try #require(MarkdownListEnter.edit(forBackspaceIn: markup.text, caret: markup.caret))
        #expect(!(edit.replacement.isEmpty && edit.range.length == 1))
        let result = edit.applied(to: markup.text)
        #expect(result.text == "intro\n\n- a")
        #expect(result.caret == 7)
    }
}
