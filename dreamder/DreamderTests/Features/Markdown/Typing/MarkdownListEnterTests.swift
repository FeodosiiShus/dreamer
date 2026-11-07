import Foundation
import Testing
@testable import Dreamder

nonisolated struct MarkdownTypingCase: Sendable, CustomTestStringConvertible {
    let name: String
    let before: String
    let after: String

    init(_ name: String, _ before: String, _ after: String) {
        self.name = name
        self.before = before
        self.after = after
    }

    var testDescription: String {
        name
    }
}

@Suite
struct MarkdownListEnterTests {
    static let newItemCases: [MarkdownTypingCase] = [
        .init("bullet", "- item<caret>", "- item\n- <caret>"),
        .init("star bullet", "* item<caret>", "* item\n* <caret>"),
        .init("plus bullet", "+ item<caret>", "+ item\n+ <caret>"),
        .init("unchecked checkbox", "- [ ] item<caret>", "- [ ] item\n- [ ] <caret>"),
        .init("checked checkbox yields unchecked", "- [x] item<caret>", "- [x] item\n- [ ] <caret>"),
        .init("upper case checked checkbox", "- [X] item<caret>", "- [X] item\n- [ ] <caret>"),
        .init("checkbox in numbered list", "1. [ ] item<caret>", "1. [ ] item\n2. [ ] <caret>"),
        .init("checkbox in block quote", "> - [ ] item<caret>", "> - [ ] item\n> - [ ] <caret>"),
        .init("checkbox after extra spaces", "- [ ]   item<caret>", "- [ ]   item\n- [ ] <caret>"),
        .init("numbered without renumbering", "3. [ ] item<caret>", "3. [ ] item\n4. [ ] <caret>"),
        .init("number delimiter kept", "1) item<caret>", "1) item\n2) <caret>"),
        .init("two digit number", "9. item<caret>", "9. item\n10. <caret>"),
        .init("nested bullet", "- a\n  - b<caret>", "- a\n  - b\n  - <caret>"),
        .init("nested numbered", "1. one\n   1. sub<caret>", "1. one\n   1. sub\n   2. <caret>"),
        .init("block quote list", "> - a<caret>", "> - a\n> - <caret>"),
        .init("nested list in block quote", "> - a\n>   - b<caret>", "> - a\n>   - b\n>   - <caret>"),
        .init("continuation line of the item", "- a\n  b<caret>", "- a\n  b\n- <caret>"),
        .init("split inside text", "- ab<caret>cd", "- ab\n- <caret>cd"),
        .init("whitespace after caret is dropped", "- ab<caret> cd", "- ab\n- <caret>cd"),
        .init("split ordered item", "1. ab<caret>cd", "1. ab\n2. <caret>cd"),
        .init("indented top level item", "  - a<caret>", "  - a\n  - <caret>"),
        .init("tab in item indent becomes spaces", "- a\n\t- b<caret>", "- a\n\t- b\n    - <caret>"),
        .init("item followed by sibling", "- a<caret>\n- b", "- a\n- <caret>\n- b"),
        .init("sub list stays attached to the new item", "1. a<caret>\n   - sub", "1. a\n2. <caret>\n   - sub")
    ]

    @Test(arguments: newItemCases)
    func newItemIsInserted(_ scenario: MarkdownTypingCase) {
        #expect(MarkdownTypingHarness.enter(scenario.before) == scenario.after)
    }

    static let caretInsidePrefixCases: [MarkdownTypingCase] = [
        .init("between marker and checkbox", "- <caret>[ ] item", "- [ ] \n- [ ] <caret>item"),
        .init("inside checkbox", "- [<caret> ] item", "- [ ] \n- [ ] <caret>item"),
        .init("inside ordered marker", "1<caret>. item", "1. \n2. <caret>item"),
        .init("right after marker of bullet", "- <caret>item", "- \n- <caret>item")
    ]

    @Test(arguments: caretInsidePrefixCases)
    func caretInsidePrefixMovesToPrefixEnd(_ scenario: MarkdownTypingCase) {
        #expect(MarkdownTypingHarness.enter(scenario.before) == scenario.after)
    }

    static let defaultBehaviorCases: [MarkdownTypingCase] = [
        .init("hard line break", "- item 1  <caret>", "- item 1  \n<caret>"),
        .init("hard break with three spaces", "- item 1   <caret>", "- item 1   \n<caret>"),
        .init("caret before marker", "<caret>- item", "\n<caret>- item"),
        .init("caret in indent before marker", "  <caret>- item", "  \n<caret>- item"),
        .init("indent after blank line", "- a\n\n  <caret>b", "- a\n\n  \n<caret>b"),
        .init("plain paragraph", "just text<caret>", "just text\n<caret>"),
        .init("heading", "# Title<caret>", "# Title\n<caret>"),
        .init(
            "indented code line is not an item",
            "para\n\n      - not an item<caret>",
            "para\n\n      - not an item\n<caret>"
        ),
        .init("fence without indent keeps editor default", "```\ncode<caret>\n```", "```\ncode\n<caret>\n```"),
        .init("closing fence without indent", "```\ncode\n```<caret>", "```\ncode\n```\n<caret>"),
        .init("list marker inside fence", "```\n- item<caret>\n```", "```\n- item\n<caret>\n```")
    ]

    @Test(arguments: defaultBehaviorCases)
    func leavesEditorDefault(_ scenario: MarkdownTypingCase) {
        #expect(MarkdownTypingHarness.rawEnterEdit(scenario.before) == nil)
        #expect(MarkdownTypingHarness.enter(scenario.before) == scenario.after)
    }

    static let emptyItemCases: [MarkdownTypingCase] = [
        .init("top level bullet", "- a\n- <caret>", "- a\n<caret>"),
        .init("top level numbered", "1. a\n2. <caret>", "1. a\n<caret>"),
        .init("only item", "- <caret>", "<caret>"),
        .init("marker without space", "-<caret>", "<caret>"),
        .init("checked checkbox", "- [x] <caret>", "<caret>"),
        .init("unchecked checkbox", "- [ ] <caret>", "<caret>"),
        .init("indented top level keeps indent", "  - <caret>", "  <caret>"),
        .init("in block quote", "> - a\n> - <caret>", "> - a\n> <caret>"),
        .init("nested bullet unindents", "- a\n  - <caret>", "- a\n- <caret>"),
        .init("nested checkbox unindents and keeps the checkbox", "- a\n  - [ ] <caret>", "- a\n- [ ] <caret>"),
        .init("deeper nested goes to parent indent", "- a\n  - b\n    - <caret>", "- a\n  - b\n  - <caret>"),
        .init("nested ordered", "1. a\n   1. <caret>", "1. a\n1. <caret>"),
        .init("nested in block quote", "> - a\n>   - <caret>", "> - a\n> - <caret>")
    ]

    @Test(arguments: emptyItemCases)
    func emptyItemExitsOrUnindents(_ scenario: MarkdownTypingCase) {
        #expect(MarkdownTypingHarness.enter(scenario.before) == scenario.after)
    }

    @Test
    func enterTwiceOnCheckboxItemExitsList() {
        #expect(MarkdownTypingHarness.enter("- [ ] item<caret>", times: 2) == "- [ ] item\n<caret>")
    }

    @Test
    func enterTwiceOnNestedCheckboxItemUnindents() {
        let result = MarkdownTypingHarness.enter("- parent\n  - [ ] child<caret>", times: 2)
        #expect(result == "- parent\n  - [ ] child\n- [ ] <caret>")
    }

    @Test
    func enterThreeTimesOnNestedItemLeavesListWithBlankLine() {
        let result = MarkdownTypingHarness.enter("- parent\n  - child<caret>", times: 3)
        #expect(result == "- parent\n  - child\n<caret>")
    }

    @Test
    func enterOnBlankLineAfterLeavingListInsertsPlainNewline() {
        let result = MarkdownTypingHarness.enter("- item<caret>", times: 3)
        #expect(result == "- item\n\n<caret>")
    }

    static let inlineFenceCases: [MarkdownTypingCase] = [
        .init("inline fence", "```<caret>```", "```\n<caret>\n```"),
        .init("inline fence with indent", "  ```<caret>```", "  ```\n  <caret>\n  ```"),
        .init("inline fence with language after", "```<caret>```swift", "```\n<caret>\n```swift")
    ]

    @Test(arguments: inlineFenceCases)
    func inlineFenceSplitsIntoThreeLines(_ scenario: MarkdownTypingCase) {
        #expect(MarkdownTypingHarness.enter(scenario.before) == scenario.after)
    }

    static let fenceIndentCases: [MarkdownTypingCase] = [
        .init(
            "fence in list item",
            "- item\n  ```py\n  x = 1<caret>\n  ```",
            "- item\n  ```py\n  x = 1\n  <caret>\n  ```"
        ),
        .init(
            "opening fence on the item line",
            "- ```py<caret>\n  code\n  ```",
            "- ```py\n  <caret>\n  code\n  ```"
        ),
        .init(
            "indented fence",
            "  ```\n  code<caret>\n  ```",
            "  ```\n  code\n  <caret>\n  ```"
        ),
        .init(
            "fence in block quote",
            "> ```\n> code<caret>\n> ```",
            "> ```\n> code\n> <caret>\n> ```"
        ),
        .init(
            "code indentation beyond the fence indent is preserved",
            "  ```\n      deep<caret>\n  ```",
            "  ```\n      deep\n      <caret>\n  ```"
        ),
        .init(
            "caret at the end of an opening fence line",
            "  ```py<caret>\n  code\n  ```",
            "  ```py\n  <caret>\n  code\n  ```"
        )
    ]

    @Test(arguments: fenceIndentCases)
    func fenceReappliesItsIndent(_ scenario: MarkdownTypingCase) {
        #expect(MarkdownTypingHarness.enter(scenario.before) == scenario.after)
    }

    static let quoteCases: [MarkdownTypingCase] = [
        .init("simple quote", "> quote<caret>", "> quote\n> <caret>"),
        .init("quote without space", ">quote<caret>", ">quote\n> <caret>"),
        .init("nested quote", "> > nested<caret>", "> > nested\n> > <caret>"),
        .init("split inside quote", "> a<caret> b", "> a\n> <caret>b"),
        .init("empty quote line", "> <caret>", "> \n> <caret>"),
        .init("quote in list item", "- item\n  > quote<caret>", "- item\n  > quote\n  > <caret>"),
        .init("quote on the item line", "- > quote<caret>", "- > quote\n  > <caret>"),
        .init("quote after paragraph", "text\n> quote<caret>", "text\n> quote\n> <caret>"),
        .init("hard break in list inside quote", "> - item  <caret>", "> - item  \n> <caret>"),
        .init("indented quote", "  > quote<caret>", "  > quote\n  > <caret>")
    ]

    @Test(arguments: quoteCases)
    func quoteContinues(_ scenario: MarkdownTypingCase) {
        #expect(MarkdownTypingHarness.enter(scenario.before) == scenario.after)
    }

    @Test
    func caretBeforeQuoteMarkerIsLeftToEditor() {
        #expect(MarkdownTypingHarness.rawEnterEdit("<caret>> quote") == nil)
    }

    @Test
    func quoteHandlingDoesNotDependOnSmartEnterSetting() {
        let settings = MarkdownTypingSettings(smartEnterAndBackspace: false)
        #expect(MarkdownTypingHarness.enter("> quote<caret>", settings: settings) == "> quote\n> <caret>")
    }

    @Test
    func disabledSmartEnterLeavesListsToEditor() {
        let settings = MarkdownTypingSettings(smartEnterAndBackspace: false)
        #expect(MarkdownTypingHarness.rawEnterEdit("- item<caret>", settings: settings) == nil)
        #expect(MarkdownTypingHarness.rawEnterEdit("```<caret>```", settings: settings) == nil)
    }

    @Test
    func disabledAdjustListIndentationLeavesNestedEmptyItemToEditor() {
        let settings = MarkdownTypingSettings(adjustListIndentation: false)
        #expect(MarkdownTypingHarness.rawEnterEdit("- a\n  - <caret>", settings: settings) == nil)
    }

    @Test
    func windowsLineEndingsAreKept() throws {
        let edit = try #require(MarkdownListEnter.edit(forEnterIn: "- a\r\n- b", caret: 8))
        let result = edit.applied(to: "- a\r\n- b")
        #expect(result.text == "- a\r\n- b\r\n- ")
        #expect(result.caret == 12)
    }

    @Test
    func editReportsMinimalRangeAndCaret() throws {
        let edit = try #require(MarkdownListEnter.edit(forEnterIn: "- item", caret: 6))
        #expect(edit.range == NSRange(location: 6, length: 0))
        #expect(edit.replacement == "\n- ")
        #expect(edit.caretOffset == 9)
    }

    @Test
    func emptyTopLevelItemEditRemovesOnlyTheMarker() throws {
        let edit = try #require(MarkdownListEnter.edit(forEnterIn: "- a\n- [ ] ", caret: 10))
        #expect(edit.range == NSRange(location: 4, length: 6))
        #expect(edit.replacement.isEmpty)
        #expect(edit.caretOffset == 4)
    }

    @Test
    func surrogatePairsInsideTheItemSurviveTheEdit() throws {
        let markup = MarkdownCaretMarkup("- 😀 item<caret>")
        let edit = try #require(MarkdownListEnter.edit(forEnterIn: markup.text, caret: markup.caret))
        let result = edit.applied(to: markup.text)
        #expect(result.text == "- 😀 item\n- ")
        #expect(result.caret == (result.text as NSString).length)
    }

    @Test
    func splitBetweenEmojisKeepsRemainderIntact() {
        #expect(MarkdownTypingHarness.enter("- 😀<caret>🙂") == "- 😀\n- <caret>🙂")
    }
}
