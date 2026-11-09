import Foundation
import Testing
@testable import Dreamder

private func md(_ lines: String...) -> String {
    lines.joined(separator: "\n")
}

struct MarkdownTableFormatCase: Sendable, CustomTestStringConvertible {
    let name: String
    let before: String
    let after: String

    var testDescription: String { name }
}

private func formatted(
    _ markup: String,
    style: MarkdownTableStyle = .aligned,
    tabSize: Int = 4,
    trimToMaxContent: Bool = true
) -> String {
    let parsed = MarkdownActionCaretMarkup(markup)
    let result = MarkdownTable.format(
        text: parsed.text,
        selections: parsed.selections,
        style: style,
        tabSize: tabSize,
        trimToMaxContent: trimToMaxContent
    )
    guard let result else {
        return MarkdownActionCaretMarkup.render(parsed.text, parsed.selections)
    }
    return MarkdownActionCaretMarkup.render(result.text, result.selections)
}

private let familyEmoji = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
private let darkThumbsUp = "\u{1F44D}\u{1F3FF}"
private let usFlag = "\u{1F1FA}\u{1F1F8}"

struct MarkdownTableFormatTypingTests {
    private static let cases: [MarkdownTableFormatCase] = [
        MarkdownTableFormatCase(
            name: "typing in a non-last column",
            before: md("| a |malformed| c |", "|---|---|---|", "| 1x<caret> |y| 2 |"),
            after: md("| a  | malformed | c |", "|----|-----------|---|", "| 1x<caret> | y         | 2 |")
        ),
        MarkdownTableFormatCase(
            name: "typing in the last column",
            before: md("| a |malformed| c |", "|---|---|---|", "| 1 |y| 2x<caret> |"),
            after: md("| a | malformed | c  |", "|---|-----------|----|", "| 1 | y         | 2x<caret> |")
        ),
        MarkdownTableFormatCase(
            name: "right after cell content",
            before: md("| none | none |", "|------|------|", "| a    <caret> | asd  |"),
            after: md("| none  | none |", "|-------|------|", "| a    <caret> | asd  |")
        ),
        MarkdownTableFormatCase(
            name: "between spaces on the right side",
            before: md("| none | none |", "|------|------|", "|  a    <caret>   | asd  |"),
            after: md("| none  | none |", "|-------|------|", "| a    <caret> | asd  |")
        ),
        MarkdownTableFormatCase(
            name: "just before the right pipe",
            before: md("| none | none |", "|------|------|", "|  a    <caret>| asd  |"),
            after: md("| none  | none |", "|-------|------|", "| a    <caret> | asd  |")
        ),
        MarkdownTableFormatCase(
            name: "typing a dash in the separator",
            before: md("| none | none |", "|---<caret>----|------|", "|  a   | asd  |"),
            after: md("| none  | none |", "|---<caret>----|------|", "| a     | asd  |")
        ),
        MarkdownTableFormatCase(
            name: "typing a colon in the separator",
            before: md("| none | none |", "|:<caret>------|------|", "| a    | asd  |"),
            after: md("| none  | none |", "|:<caret>------|------|", "| a     | asd  |")
        ),
        MarkdownTableFormatCase(
            name: "right aligned column",
            before: md("|  right <caret>    |", "| ---:  |", "| some    |"),
            after: md("| right <caret> |", "|-------:|", "|   some |")
        ),
        MarkdownTableFormatCase(
            name: "typing in a right aligned column",
            before: md("| right |", "|------:|", "| some<caret>      |"),
            after: md("| right |", "|------:|", "|  some<caret> |")
        ),
        MarkdownTableFormatCase(
            name: "typing a long text in a right aligned column",
            before: md("| right |", "|------:|", "| some content<caret>      |"),
            after: md("|        right |", "|-------------:|", "| some content<caret> |")
        ),
        MarkdownTableFormatCase(
            name: "typing in a right aligned column with a short header",
            before: md("| left |", "|-----:|", "|   some<caret>   |"),
            after: md("| left |", "|-----:|", "| some<caret> |")
        ),
        MarkdownTableFormatCase(
            name: "typing a long text in a right aligned column with a short header",
            before: md("| left |", "|-----:|", "|   some content<caret>   |"),
            after: md("|         left |", "|-------------:|", "| some content<caret> |")
        ),
        MarkdownTableFormatCase(
            name: "center aligned column",
            before: md("| center |", "|:------:|", "| some<caret>   |"),
            after: md("| center |", "|:------:|", "|  some<caret>  |")
        ),
        MarkdownTableFormatCase(
            name: "center aligned column with trailing space typed",
            before: md("| center |", "|:------:|", "| ssome <caret>   |"),
            after: md("| center |", "|:------:|", "| ssome <caret> |")
        ),
        MarkdownTableFormatCase(
            name: "typing in an empty cell",
            before: md("||", "|-|", "|some<caret>|"),
            after: md("|      |", "|------|", "| some<caret> |")
        ),
        MarkdownTableFormatCase(
            name: "typing a space in a cell with two spaces",
            before: md("|  |", "|--|", "|  <caret> |"),
            after: md("|   |", "|---|", "|  <caret> |")
        ),
        MarkdownTableFormatCase(
            name: "pasting text",
            before: md("| a | b |", "|---|---|", "| onexyz<caret> | 2 |"),
            after: md("| a      | b |", "|--------|---|", "| onexyz<caret> | 2 |")
        )
    ]

    @Test(arguments: cases)
    func reformatsTypedState(_ testCase: MarkdownTableFormatCase) {
        #expect(formatted(testCase.before) == testCase.after)
    }

    @Test(arguments: cases)
    func reformattedTypedStateIsStable(_ testCase: MarkdownTableFormatCase) {
        #expect(formatted(testCase.after) == testCase.after)
    }

    @Test
    func compactTypedState() {
        let before = md("| a |malformed| c |", "|---|---|---|", "| 1x<caret> |y| 2 |")
        let after = md("| a | malformed | c |", "| --- | --- | --- |", "| 1x<caret> | y | 2 |")
        #expect(formatted(before, style: .compact) == after)
    }

    @Test
    func compactEmptyCellKeepsOnePaddingSpaceBeforeCaret() {
        let before = md("| a |", "| --- |", "| <caret> |")
        let after = md("| a |", "| --- |", "| <caret>|")
        #expect(formatted(before, style: .compact) == after)
    }

    @Test
    func tightTypedState() {
        let before = md("| a |malformed| c |", "|---|---|---|", "| 1x<caret> |y| 2 |")
        let after = md("|a|malformed|c|", "|---|---|---|", "|1x<caret>|y|2|")
        #expect(formatted(before, style: .tight) == after)
    }
}

struct MarkdownTableFormatSingleColumnTests {
    private static let cases: [MarkdownTableFormatCase] = [
        MarkdownTableFormatCase(
            name: "single column center alignment",
            before: md("|       none |", "| :---:  |", "| some |"),
            after: md("|    none    |", "|:----------:|", "|    some    |")
        ),
        MarkdownTableFormatCase(
            name: "single column center alignment with caret",
            before: md("|       none<caret> |", "| :---:  |", "| some |"),
            after: md("|    none<caret>    |", "|:----------:|", "|    some    |")
        ),
        MarkdownTableFormatCase(
            name: "single column center alignment with several carets",
            before: md("|       none<caret> |", "| :---:  |", "| <caret>so<caret>me |"),
            after: md("|    none<caret>    |", "|:----------:|", "|    <caret>so<caret>me    |")
        ),
        MarkdownTableFormatCase(
            name: "several columns with right alignment and several carets",
            before: md("|  right<caret>    |    none |", "| ---:  | ----  |", "| <caret>so<caret>me    |    some |"),
            after: md(
                "|     right<caret> | none    |",
                "|----------:|---------|",
                "|      <caret>so<caret>me | some    |"
            )
        ),
        MarkdownTableFormatCase(
            name: "escaped pipe does not split the cell",
            before: md("| none |", "| :---:  |", "| A\\|B<caret> |"),
            after: md("| none |", "|:----:|", "| A\\|B<caret> |")
        ),
        MarkdownTableFormatCase(
            name: "escaped pipes in several columns",
            before: md("| none |    A\\|B |", "| :---:  |  ---: |", "| A\\|B<caret> | A\\|B\\|\\|\\|B<caret> |"),
            after: md("| none |        A\\|B |", "|:----:|------------:|", "| A\\|B<caret> | A\\|B\\|\\|\\|B<caret> |")
        ),
        MarkdownTableFormatCase(
            name: "escaped pipe inside a code span",
            before: md("| none |", "| :---:  |", "| `A\\|B`<caret> |"),
            after: md("|  none  |", "|:------:|", "| `A\\|B`<caret> |")
        )
    ]

    @Test(arguments: cases)
    func keepsRawWidthWhenNotTrimmingToContent(_ testCase: MarkdownTableFormatCase) {
        #expect(formatted(testCase.before, trimToMaxContent: false) == testCase.after)
    }

    @Test
    func trimsToContentWithoutAlignment() {
        let before = md("|       none |", "| ---  |", "| some   |")
        let after = md("| none |", "|------|", "| some |")
        #expect(formatted(before) == after)
    }

    @Test
    func addsPaddingToTightCells() {
        let before = md("|none|", "|--- |", "|some|")
        let after = md("| none |", "|------|", "| some |")
        #expect(formatted(before) == after)
    }

    @Test
    func largeSingleColumnTable() {
        var beforeLines = ["|header|", "|---|"]
        var afterLines = ["| header    |", "|-----------|"]
        for index in 0..<101 {
            if index == 100 {
                beforeLines.append("|value <caret>\(index)|")
                afterLines.append("| value <caret>\(index) |")
            } else {
                let content = "value \(index)"
                beforeLines.append("|\(content)|")
                afterLines.append("| " + content.padding(toLength: 10, withPad: " ", startingAt: 0) + "|")
            }
        }
        let before = beforeLines.joined(separator: "\n")
        let after = afterLines.joined(separator: "\n")
        #expect(formatted(before) == after)
    }
}

struct MarkdownTableFormatStyleTests {
    private static let aligned = md(
        "| Character | Meaning |",
        "|-----------|---------|",
        "| Y         | Yes     |",
        "| N         | No      |"
    )
    private static let compact = md(
        "| Character | Meaning |",
        "| --- | --- |",
        "| Y | Yes |",
        "| N | No |"
    )
    private static let tight = md(
        "|Character|Meaning|",
        "|---|---|",
        "|Y|Yes|",
        "|N|No|"
    )
    private static let tightSource = md(
        "|Character|Meaning|",
        "|---------|-------|",
        "|Y|Yes|",
        "|N|No|"
    )

    @Test
    func malformedTableBecomesAligned() {
        let before = md("| a |malformed| c |", "|---|---|---|", "| 1x |y| 2 |")
        let after = md("| a  | malformed | c |", "|----|-----------|---|", "| 1x | y         | 2 |")
        #expect(formatted(before) == after)
    }

    @Test
    func malformedTableBecomesCompact() {
        let before = md("| a |malformed| c |", "|---|---|---|", "| 1x |y| 2 |")
        let after = md("| a | malformed | c |", "| --- | --- | --- |", "| 1x | y | 2 |")
        #expect(formatted(before, style: .compact) == after)
    }

    @Test
    func malformedTableBecomesTight() {
        let before = md("| a |malformed| c |", "|---|---|---|", "| 1x |y| 2 |")
        let after = md("|a|malformed|c|", "|---|---|---|", "|1x|y|2|")
        #expect(formatted(before, style: .tight) == after)
    }

    @Test
    func tightSourceBecomesCompact() {
        #expect(formatted(Self.tightSource, style: .compact) == Self.compact)
    }

    @Test
    func compactSourceBecomesTight() {
        #expect(formatted(Self.compact, style: .tight) == Self.tight)
    }

    @Test
    func compactSourceBecomesAligned() {
        #expect(formatted(Self.compact, style: .aligned) == Self.aligned)
    }

    @Test(arguments: MarkdownTableStyle.allCases)
    func formattingIsIdempotent(_ style: MarkdownTableStyle) {
        let once = MarkdownTable.formatAllTables(text: Self.compact, style: style)?.text ?? Self.compact
        let twice = MarkdownTable.formatAllTables(text: once, style: style)
        #expect(twice == nil)
    }

    @Test
    func alignmentIsPreservedFromTheSeparator() {
        let wide = md("| left | right | center | none |", "|:--|--:|:-:|---|", "| 1 | 2 | 3 | 4 |")
        let wideAfter = md(
            "| left | right | center | none |",
            "|:-----|------:|:------:|------|",
            "| 1    |     2 |   3    | 4    |"
        )
        #expect(MarkdownTable.formatAllTables(text: wide)?.text == wideAfter)
    }

    @Test
    func caretKeepsTrackedPositionInCompactStyle() {
        let before = md("| a |", "| --- |", "|   x<caret>   |")
        let after = md("| a |", "| --- |", "| x<caret> |")
        #expect(formatted(before, style: .compact) == after)
    }
}

struct MarkdownTableFormatWidthTests {
    private static let cases: [MarkdownTableFormatCase] = [
        MarkdownTableFormatCase(
            name: "chinese table",
            before: md("|名字|年龄|", "|-|-|", "|张三|25|"),
            after: md("| 名字 | 年龄 |", "|------|------|", "| 张三 | 25   |")
        ),
        MarkdownTableFormatCase(
            name: "chinese table with different widths",
            before: md("| 名字 | 年龄 |", "|---|---|", "| 张三丰 | 5 |", "| Bob | 100 |"),
            after: md(
                "| 名字   | 年龄 |",
                "|--------|------|",
                "| 张三丰 | 5    |",
                "| Bob    | 100  |"
            )
        ),
        MarkdownTableFormatCase(
            name: "emoji table",
            before: md("|a|b|", "|-|-|", "|\u{1F600}|x|"),
            after: md("| a  | b |", "|----|---|", "| \u{1F600} | x |")
        ),
        MarkdownTableFormatCase(
            name: "colored boxes",
            before: md("|a|b|", "|-|-|", "|\u{1F7E5}|\u{1F7E9}|"),
            after: md("| a  | b  |", "|----|----|", "| \u{1F7E5} | \u{1F7E9} |")
        ),
        MarkdownTableFormatCase(
            name: "emoji sequences count as one glyph",
            before: md("|a|b|c|", "|-|-|-|", "|\(familyEmoji)|\(darkThumbsUp)|\(usFlag)|"),
            after: md("| a  | b  | c  |", "|----|----|----|", "| \(familyEmoji) | \(darkThumbsUp) | \(usFlag) |")
        ),
        MarkdownTableFormatCase(
            name: "combining marks have no width",
            before: md("|a|b|", "|-|-|", "|e\u{301}|x|"),
            after: md("| a | b |", "|---|---|", "| e\u{301} | x |")
        )
    ]

    @Test(arguments: cases)
    func alignsByDisplayWidth(_ testCase: MarkdownTableFormatCase) {
        #expect(formatted(testCase.before) == testCase.after)
    }

    @Test(arguments: cases)
    func displayWidthFormattingIsStable(_ testCase: MarkdownTableFormatCase) {
        #expect(formatted(testCase.after) == testCase.after)
    }

    @Test(arguments: [2, 4, 8])
    func tabsInCodeSpansPreserveAlignment(_ tabSize: Int) {
        let leftContent = " `a\tb`" + String(repeating: " ", count: tabSize == 2 ? 7 : 5)
        let rightContent = tabSize == 8 ? "    `a\tb`     " : "        `a\tb` "
        let separators: [(separator: String, content: String)] = [
            (":-------------", leftContent),
            ("-------------:", rightContent),
            (":------------:", "    `a\tb`     ")
        ]
        for (separator, content) in separators {
            let before = "| abcdefghijkl | x |\n|\(separator)|---|\n| `a\tb` | y |"
            let after = "| abcdefghijkl | x |\n|\(separator)|---|\n|\(content)| y |"
            #expect(formatted(before, tabSize: tabSize) == after)
            #expect(formatted(after, tabSize: tabSize) == after)
        }
    }

    @Test
    func tabInsideCellTextAdvancesToTabStop() {
        let before = md("| a\tb | c |", "|---|---|", "| x | y |")
        let expected = md("| a\tb | c |", "|-----|---|", "| x   | y |")
        let result = MarkdownTable.formatAllTables(text: before, tabSize: 4)
        #expect(result?.text == expected)
        #expect(MarkdownTable.formatAllTables(text: expected, tabSize: 4) == nil)
    }
}

struct MarkdownTableFormatContextTests {
    @Test
    func tableInsideBlockQuoteKeepsItsPrefix() {
        let before = md("> |a|b|", "> |-|-|", "> |long|x|")
        let after = md("> | a    | b |", "> |------|---|", "> | long | x |")
        #expect(MarkdownTable.formatAllTables(text: before)?.text == after)
    }

    @Test
    func tableInsideListItemKeepsItsIndent() {
        let before = md("- item", "", "  |a|b|", "  |-|-|", "  |long|x|")
        let after = md("- item", "", "  | a    | b |", "  |------|---|", "  | long | x |")
        #expect(MarkdownTable.formatAllTables(text: before)?.text == after)
    }

    @Test
    func multipleTablesAreFormattedIndependently() {
        let before = md("|a|b|", "|-|-|", "|long|x|", "", "text", "", "|c|", "|-|", "|wider|")
        let after = md(
            "| a    | b |",
            "|------|---|",
            "| long | x |",
            "",
            "text",
            "",
            "| c     |",
            "|-------|",
            "| wider |"
        )
        #expect(MarkdownTable.formatAllTables(text: before)?.text == after)
    }

    @Test
    func tableWithoutTrailingNewlineIsFormatted() {
        let before = md("|a|b|", "|-|-|", "|long|x|")
        let result = MarkdownTable.formatAllTables(text: before)
        #expect(result?.text == md("| a    | b |", "|------|---|", "| long | x |"))
    }

    @Test
    func tableWithTrailingNewlineKeepsIt() {
        let before = md("|a|b|", "|-|-|", "|long|x|", "")
        let result = MarkdownTable.formatAllTables(text: before)
        #expect(result?.text == md("| a    | b |", "|------|---|", "| long | x |", ""))
    }

    @Test
    func onlyTablesTouchedBySelectionsAreFormatted() {
        let markup = md("|a|b|", "|-|-|", "|long|x|", "", "|c|", "|-|", "|wi<caret>der|")
        let after = md("|a|b|", "|-|-|", "|long|x|", "", "| c     |", "|-------|", "| wi<caret>der |")
        #expect(formatted(markup) == after)
    }

    @Test
    func tablesWithoutBordersAreNotFormatted() {
        let withoutBorders = md("a | b", "--|--", "1 | 2")
        let withoutTrailingBorder = md("| a | b", "|---|---", "| 1 | 2")
        #expect(MarkdownTable.formatAllTables(text: withoutBorders) == nil)
        #expect(MarkdownTable.formatAllTables(text: withoutTrailingBorder) == nil)
    }

    @Test
    func tableInsideFencedCodeIsNotFormatted() {
        let text = md("```", "|a|b|", "|-|-|", "|long|x|", "```")
        #expect(MarkdownTable.formatAllTables(text: text) == nil)
    }

    @Test
    func rowsWithMoreCellsThanTheHeaderKeepTheExtraCells() {
        let before = md("|a|b|", "|-|-|", "|long|x|extra|")
        let after = md("| a    | b |", "|------|---|", "| long | x |extra|")
        #expect(MarkdownTable.formatAllTables(text: before)?.text == after)
    }

    @Test
    func resultCarriesTheMinimalEditAndAppliesToTheOriginal() {
        let before = md("|a|b|", "|-|-|", "|long|x|")
        let result = MarkdownTable.formatAllTables(text: before)
        #expect(result?.applied(to: before) == result?.text)
        #expect(result?.edit != nil)
    }

    @Test
    func selectionRangeKeepsItsLengthThroughTheRewrite() {
        let markup = md("|a|b|", "|-|-|", "|<selection>long</selection>|x|")
        let parsed = MarkdownActionCaretMarkup(markup)
        let result = MarkdownTable.format(text: parsed.text, selections: parsed.selections)
        let rendered = result.map { MarkdownActionCaretMarkup.render($0.text, $0.selections) }
        #expect(rendered == md("| a    | b |", "|------|---|", "| <selection>long</selection> | x |"))
    }
}
