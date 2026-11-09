import Foundation
import Testing
@testable import Dreamder

private struct EmphasisCase: Sendable, CustomTestStringConvertible {
    let name: String
    let kind: MarkdownEmphasisKind
    let style: MarkdownEmphasisStyle
    let before: String
    let after: String

    init(
        _ name: String,
        _ kind: MarkdownEmphasisKind,
        style: MarkdownEmphasisStyle = .asterisks,
        _ before: String,
        _ after: String
    ) {
        self.name = name
        self.kind = kind
        self.style = style
        self.before = before
        self.after = after
    }

    var testDescription: String { name }
}

private struct DisabledCase: Sendable, CustomTestStringConvertible {
    let name: String
    let kind: MarkdownEmphasisKind
    let markup: String

    init(_ name: String, _ kind: MarkdownEmphasisKind, _ markup: String) {
        self.name = name
        self.kind = kind
        self.markup = markup
    }

    var testDescription: String { name }
}

private func toggled(
    _ kind: MarkdownEmphasisKind,
    _ markup: String,
    style: MarkdownEmphasisStyle = .asterisks
) -> String? {
    let parsed = MarkdownActionCaretMarkup(markup)
    guard let result = MarkdownEmphasisToggle.toggle(
        kind,
        text: parsed.text,
        selections: parsed.selections,
        style: style
    ) else { return nil }
    return MarkdownActionCaretMarkup.render(result.text, result.selections)
}

private func selected(_ kind: MarkdownEmphasisKind, _ markup: String) -> Bool {
    let parsed = MarkdownActionCaretMarkup(markup)
    return MarkdownEmphasisToggle.isSelected(kind, text: parsed.text, selections: parsed.selections)
}

private func enabled(_ kind: MarkdownEmphasisKind, _ markup: String) -> Bool {
    let parsed = MarkdownActionCaretMarkup(markup)
    return MarkdownEmphasisToggle.isEnabled(kind, text: parsed.text, selections: parsed.selections)
}

private let tableHeader = "| Feature | Markdown | MDX |\n|---------|----------|-----|\n"
private let tableFooter = "\n| React | no | yes |"

private func tableRow(_ row: String) -> String {
    tableHeader + "<selection>" + row + "</selection>" + tableFooter
}

private func plainTableRow(_ row: String) -> String {
    tableHeader + row + tableFooter
}

@Suite("MarkdownEmphasisToggle")
struct MarkdownEmphasisToggleTests {
    private static let addCases: [EmphasisCase] = [
        EmphasisCase("bold on empty caret", .bold, "<caret>", "**<caret>**"),
        EmphasisCase("bold underscores on empty caret", .bold, style: .underscores, "<caret>", "__<caret>__"),
        EmphasisCase(
            "bold simple selection",
            .bold,
            "Simple <selection>test</selection> text",
            "Simple **<selection>test</selection>** text"
        ),
        EmphasisCase(
            "bold trims surrounding whitespace",
            .bold,
            "a<selection> test </selection>b",
            "a<selection> **test** </selection>b"
        ),
        EmphasisCase(
            "bold whitespace only selection wraps as is",
            .bold,
            "a<selection>  </selection>b",
            "a**<selection>  </selection>**b"
        ),
        EmphasisCase("italic on empty caret", .italic, "<caret>", "*<caret>*"),
        EmphasisCase("italic underscores on empty caret", .italic, style: .underscores, "<caret>", "_<caret>_"),
        EmphasisCase(
            "italic simple selection",
            .italic,
            "Simple <selection>test</selection> text",
            "Simple *<selection>test</selection>* text"
        ),
        EmphasisCase(
            "italic underscores whole word",
            .italic,
            style: .underscores,
            "Simple <selection>test</selection> text",
            "Simple _<selection>test</selection>_ text"
        ),
        EmphasisCase(
            "italic part of word keeps asterisks",
            .italic,
            "fo<selection>ob</selection>ar",
            "fo*<selection>ob</selection>*ar"
        ),
        EmphasisCase(
            "italic underscores part of word falls back to asterisks",
            .italic,
            style: .underscores,
            "fo<selection>ob</selection>ar",
            "fo*<selection>ob</selection>*ar"
        ),
        EmphasisCase(
            "italic underscores caret inside word falls back to asterisks",
            .italic,
            style: .underscores,
            "fo<caret>bar",
            "fo*<caret>*bar"
        ),
        EmphasisCase("strikethrough on empty caret", .strikethrough, "<caret>", "~~<caret>~~"),
        EmphasisCase(
            "strikethrough selection",
            .strikethrough,
            "some <selection>text</selection> here",
            "some ~~<selection>text</selection>~~ here"
        ),
        EmphasisCase("code span on empty caret", .codeSpan, "<caret>", "`<caret>`"),
        EmphasisCase(
            "code span selection",
            .codeSpan,
            "foo <selection>bar</selection> baz",
            "foo `<selection>bar</selection>` baz"
        ),
        EmphasisCase(
            "code span does not trim whitespace",
            .codeSpan,
            "a<selection> b </selection>c",
            "a`<selection> b </selection>`c"
        ),
        EmphasisCase(
            "code span around single backticks uses double fence",
            .codeSpan,
            "<selection>a`b</selection>",
            "``<selection>a`b</selection>``"
        ),
        EmphasisCase(
            "code span around double backticks uses triple fence",
            .codeSpan,
            "x <selection>a``b</selection> y",
            "x ```<selection>a``b</selection>``` y"
        ),
        EmphasisCase(
            "code span uses longest of separate backtick runs",
            .codeSpan,
            "x <selection>a`b```c</selection> y",
            "x ````<selection>a`b```c</selection>```` y"
        ),
        EmphasisCase(
            "bold inside a paragraph word",
            .bold,
            "one <caret>two",
            "one **<caret>**two"
        ),
        EmphasisCase(
            "bold in heading",
            .bold,
            "# Head <selection>line</selection>",
            "# Head **<selection>line</selection>**"
        ),
        EmphasisCase(
            "bold in indented code simply wraps",
            .bold,
            "para\n\n    <selection>code</selection>",
            "para\n\n    **<selection>code</selection>**"
        )
    ]

    private static let removeCases: [EmphasisCase] = [
        EmphasisCase(
            "bold content selection removes markers",
            .bold,
            "a **<selection>foo</selection>** b",
            "a <selection>foo</selection> b"
        ),
        EmphasisCase(
            "bold selection with markers removes markers",
            .bold,
            "a <selection>**foo**</selection> b",
            "a <selection>foo</selection> b"
        ),
        EmphasisCase(
            "bold underscores content selection",
            .bold,
            "a __<selection>foo</selection>__ b",
            "a <selection>foo</selection> b"
        ),
        EmphasisCase(
            "bold partial selection splits",
            .bold,
            "**aaa <selection>bbb</selection> ccc**",
            "**aaa** <selection>bbb</selection> **ccc**"
        ),
        EmphasisCase(
            "bold partial selection at start",
            .bold,
            "**<selection>aaa</selection> bbb**",
            "<selection>aaa</selection> **bbb**"
        ),
        EmphasisCase(
            "bold partial selection at end",
            .bold,
            "**aaa <selection>bbb</selection>**",
            "**aaa** <selection>bbb</selection>"
        ),
        EmphasisCase(
            "italic simple off",
            .italic,
            "Simple *<selection>test</selection>* text",
            "Simple <selection>test</selection> text"
        ),
        EmphasisCase(
            "italic underscores off",
            .italic,
            style: .underscores,
            "Simple _<selection>test</selection>_ text",
            "Simple <selection>test</selection> text"
        ),
        EmphasisCase(
            "italic partially off",
            .italic,
            "*aaa <selection>bbb</selection> ccc*",
            "*aaa* <selection>bbb</selection> *ccc*"
        ),
        EmphasisCase(
            "strikethrough off",
            .strikethrough,
            "some ~~<selection>text</selection>~~ here",
            "some <selection>text</selection> here"
        ),
        EmphasisCase(
            "strikethrough partially off",
            .strikethrough,
            "~~aaa <selection>bbb</selection> ccc~~",
            "~~aaa~~ <selection>bbb</selection> ~~ccc~~"
        ),
        EmphasisCase(
            "code span cancel",
            .codeSpan,
            "foo `<selection>bar</selection>` baz",
            "foo <selection>bar</selection> baz"
        ),
        EmphasisCase(
            "code span cancel with double fence",
            .codeSpan,
            "``<selection>a`b</selection>``",
            "<selection>a`b</selection>"
        ),
        EmphasisCase(
            "code span cancel selecting whole span",
            .codeSpan,
            "foo <selection>`bar`</selection> baz",
            "foo <selection>bar</selection> baz"
        )
    ]

    private static let disabledCases: [DisabledCase] = [
        DisabledCase("bold inside fenced code", .bold, "```\n<caret>code\n```"),
        DisabledCase("code span inside fenced code", .codeSpan, "```swift\nlet <selection>a</selection> = 1\n```"),
        DisabledCase("italic inside fence info line", .italic, "```sw<caret>ift\nx\n```"),
        DisabledCase("bold inside code span", .bold, "`co<caret>de`"),
        DisabledCase("italic selection inside code span", .italic, "`<selection>co</selection>de`"),
        DisabledCase("bold inside link text", .bold, "[li<caret>nk](http://example.com)"),
        DisabledCase(
            "strikethrough selection inside link text",
            .strikethrough,
            "[<selection>link</selection>](http://example.com)"
        ),
        DisabledCase("bold inside link destination", .bold, "[link](http://exa<caret>mple.com)"),
        DisabledCase("bold inside autolink", .bold, "see <http://exa<caret>mple.com> now"),
        DisabledCase("bold inside bare url", .bold, "see http://exa<caret>mple.com now"),
        DisabledCase("code span inside link text", .codeSpan, "[li<caret>nk](http://example.com)"),
        DisabledCase("mixed formatted and plain carets", .bold, "**a<caret>** b <caret>c"),
        DisabledCase("mixed plain and formatted carets", .italic, "a <caret>b *c<caret>*")
    ]

    @Test(arguments: addCases)
    private func addsEmphasis(_ testCase: EmphasisCase) {
        let result = toggled(testCase.kind, testCase.before, style: testCase.style)
        #expect(result == testCase.after)
    }

    @Test(arguments: removeCases)
    private func removesEmphasis(_ testCase: EmphasisCase) {
        let result = toggled(testCase.kind, testCase.before, style: testCase.style)
        #expect(result == testCase.after)
    }

    @Test(arguments: disabledCases)
    private func disabledInProhibitedElements(_ testCase: DisabledCase) {
        let isEnabled = enabled(testCase.kind, testCase.markup)
        let result = toggled(testCase.kind, testCase.markup)
        #expect(isEnabled == false)
        #expect(result == nil)
    }

    @Test(arguments: [
        ("caret inside bold", MarkdownEmphasisKind.bold, "**fo<caret>o**", true),
        ("caret at the start of bold", .bold, "<caret>**foo** bar", true),
        ("caret after bold at end of file", .bold, "**foo**<caret>", true),
        ("caret after bold before text", .bold, "**foo**<caret> bar", false),
        ("caret outside bold", .bold, "fo<caret>o **bar**", false),
        ("bold is not italic", .italic, "**fo<caret>o**", false),
        ("selection of bold content", .bold, "**<selection>foo</selection>**", true),
        ("selection of bold including markers", .bold, "<selection>**foo**</selection>", true),
        ("partial selection of bold", .bold, "**f<selection>o</selection>o**", true),
        ("selection of text and bold", .bold, "<selection>a **foo**</selection>", false),
        ("italic caret", .italic, "*a<caret>b*", true),
        ("underscore italic caret", .italic, "_a<caret>b_", true),
        ("strikethrough caret", .strikethrough, "~~a<caret>b~~", true),
        ("code span caret", .codeSpan, "`a<caret>b`", true),
        ("plain text", .strikethrough, "a<caret>b", false),
        ("bold inside highlight is selected", .bold, "==**a<caret>b**==", true)
    ])
    private func reportsSelectedState(
        _ name: String,
        _ kind: MarkdownEmphasisKind,
        _ markup: String,
        _ expected: Bool
    ) {
        let result = selected(kind, markup)
        #expect(result == expected, Comment(rawValue: name))
    }

    @Test
    func enabledOutsideProhibitedElements() {
        let result = enabled(.bold, "plain <caret>text")
        #expect(result)
    }

    @Test
    func caretInsideBoldIsEnabled() {
        let result = enabled(.bold, "**fo<caret>o**")
        #expect(result)
    }

    @Test
    func codeSpanIsEnabledInsideCodeSpan() {
        let result = enabled(.codeSpan, "`co<caret>de`")
        #expect(result)
    }

    @Test
    func multiCaretWordsOn() {
        let result = toggled(.italic, "<selection>one</selection> two <selection>three</selection>")
        #expect(result == "*<selection>one</selection>* two *<selection>three</selection>*")
    }

    @Test
    func multiCaretWordsOff() {
        let result = toggled(.italic, "*<selection>one</selection>* two *<selection>three</selection>*")
        #expect(result == "<selection>one</selection> two <selection>three</selection>")
    }

    @Test
    func multiCaretEmptyCaretsInsertPairsAtEveryCaret() {
        let result = toggled(.bold, "<caret>a <caret>b")
        #expect(result == "**<caret>**a **<caret>**b")
    }

    @Test
    func multiCaretSelectionsComeBackInDocumentOrder() {
        let parsed = MarkdownActionCaretMarkup("<selection>one</selection> two <selection>three</selection>")
        let reversed = Array(parsed.selections.reversed())
        let result = MarkdownEmphasisToggle.toggle(.bold, text: parsed.text, selections: reversed)
        let selections = result?.selections
        #expect(selections == [NSRange(location: 2, length: 3), NSRange(location: 14, length: 5)])
        #expect(result?.text == "**one** two **three**")
    }

    @Test
    func multiCaretWordsOnUnderscores() {
        let result = toggled(
            .italic,
            "<selection>one</selection> t<selection>w</selection>o",
            style: .underscores
        )
        #expect(result == "_<selection>one</selection>_ t*<selection>w</selection>*o")
    }

    @Test
    func multiCaretMixedStateIsDisabled() {
        let markup = "*<selection>one</selection>* two <selection>three</selection>"
        let isEnabled = enabled(.italic, markup)
        #expect(isEnabled == false)
    }

    @Test
    func multiCaretCodeSpanUsesPerCaretFence() {
        let result = toggled(.codeSpan, "<selection>a`b</selection> and <selection>c</selection>")
        #expect(result == "``<selection>a`b</selection>`` and `<selection>c</selection>`")
    }

    @Test
    func resultEditsReproduceText() {
        let parsed = MarkdownActionCaretMarkup("Simple <selection>test</selection> text")
        let result = MarkdownEmphasisToggle.toggle(.bold, text: parsed.text, selections: parsed.selections)
        let applied = result?.applied(to: parsed.text)
        #expect(applied == "Simple **test** text")
        #expect(result?.edit != nil)
    }

    @Test
    func disabledToggleLeavesTextUntouched() {
        let parsed = MarkdownActionCaretMarkup("```\n<caret>code\n```")
        let result = MarkdownEmphasisToggle.toggle(.bold, text: parsed.text, selections: parsed.selections)
        #expect(result == nil)
    }

    @Test
    func emptySelectionListIsDisabled() {
        let result = MarkdownEmphasisToggle.toggle(.bold, text: "text", selections: [])
        let isEnabled = MarkdownEmphasisToggle.isEnabled(.bold, text: "text", selections: [])
        #expect(result == nil)
        #expect(isEnabled == false)
    }

    @Test
    func boldInsideItalicWrapsContent() {
        let result = toggled(.bold, "*a <selection>b</selection> c*")
        #expect(result == "*a **<selection>b</selection>** c*")
    }

    @Test
    func italicSelectionCoveringBoldContentOfMixedMarkup() {
        let result = toggled(.italic, "<selection>***foo***</selection>")
        #expect(result == "<selection>**foo**</selection>")
    }

    @Test
    func tableRowSelectionCanToggleBoldAfterItalic() {
        let row = "| Headings | yes | yes |"
        let afterBold = toggled(.bold, tableRow(row))
        #expect(afterBold == tableRow("| **Headings** | **yes** | **yes** |"))
        let afterItalic = afterBold.flatMap { toggled(.italic, $0) }
        #expect(afterItalic == tableRow("| ***Headings*** | ***yes*** | ***yes*** |"))
        let afterSecondBold = afterItalic.flatMap { toggled(.bold, $0) }
        #expect(afterSecondBold == tableRow("| *Headings* | *yes* | *yes* |"))
    }

    @Test
    func tableRowSelectionFinalText() {
        let row = "| Headings | yes | yes |"
        let afterBold = toggled(.bold, tableRow(row))
        let afterItalic = afterBold.flatMap { toggled(.italic, $0) }
        let afterSecondBold = afterItalic.flatMap { toggled(.bold, $0) }
        let parsed = afterSecondBold.map { MarkdownActionCaretMarkup($0) }
        #expect(parsed?.text == plainTableRow("| *Headings* | *yes* | *yes* |"))
    }

    @Test
    func tableRowSelectionCanToggleBoldAfterHighlight() {
        let before = tableRow("| ==**Headings**== | ==**yes**== | ==**yes**== |")
        let after = toggled(.bold, before)
        #expect(after == tableRow("| ==Headings== | ==yes== | ==yes== |"))
    }

    @Test
    func tableRowSelectionDoesNotIncludePadding() {
        let after = toggled(.codeSpan, tableRow("| Headings | yes | yes |"))
        #expect(after == tableRow("| `Headings` | `yes` | `yes` |"))
    }

    @Test
    func tableRowSelectionTogglesCodeSpanOff() {
        let after = toggled(.codeSpan, tableRow("| `Headings` | `yes` | `yes` |"))
        #expect(after == tableRow("| Headings | yes | yes |"))
    }

    @Test
    func tableRowSelectionOnlyFormatsUnformattedCellsWhenMixed() {
        let after = toggled(.bold, tableRow("| **Headings** | yes | yes |"))
        #expect(after == tableRow("| **Headings** | **yes** | **yes** |"))
    }

    @Test
    func tableRowSelectionIsSelectedWhenEveryCellHasParent() {
        let markup = tableRow("| **Headings** | **yes** | **yes** |")
        let isSelected = selected(.bold, markup)
        #expect(isSelected)
    }

    @Test
    func tableRowSelectionIsNotSelectedWhenOneCellLacksParent() {
        let markup = tableRow("| **Headings** | yes | **yes** |")
        let isSelected = selected(.bold, markup)
        let isEnabled = enabled(.bold, markup)
        #expect(isSelected == false)
        #expect(isEnabled)
    }

    @Test
    func tableRowSelectionIsEnabledInsideCodeSpanCell() {
        let markup = tableRow("| `Headings` | yes | yes |")
        let isEnabled = enabled(.bold, markup)
        #expect(isEnabled)
    }

    @Test
    func tableCaretInsideCellWrapsOnlyAtCaret() {
        let result = toggled(.bold, plainTableRow("| Head<caret>ings | yes | yes |"))
        #expect(result == plainTableRow("| Head**<caret>**ings | yes | yes |"))
    }

    @Test
    func tablePartialCellSelectionWrapsOnlyThatPart() {
        let markup = tableHeader + "| Head<selection>in</selection>gs | yes | yes |" + tableFooter
        let result = toggled(.bold, markup)
        let expected = tableHeader + "| Head**<selection>in</selection>**gs | yes | yes |" + tableFooter
        #expect(result == expected)
    }
}
