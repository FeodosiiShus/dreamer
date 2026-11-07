import Foundation
import Testing
@testable import Dreamder

private func md(_ lines: String...) -> String {
    lines.joined(separator: "\n")
}

struct MarkdownTableDisplayWidthTests {
    struct WidthCase: Sendable, CustomTestStringConvertible {
        let text: String
        let startColumn: Int
        let tabSize: Int
        let width: Int

        var testDescription: String { "\(text.debugDescription) @\(startColumn) tab \(tabSize) = \(width)" }
    }

    private static let cases: [WidthCase] = [
        WidthCase(text: "", startColumn: 0, tabSize: 4, width: 0),
        WidthCase(text: "abc", startColumn: 0, tabSize: 4, width: 3),
        WidthCase(text: "名字", startColumn: 0, tabSize: 4, width: 4),
        WidthCase(text: "a名", startColumn: 0, tabSize: 4, width: 3),
        WidthCase(text: "\u{1F600}", startColumn: 0, tabSize: 4, width: 2),
        WidthCase(text: "\u{1F7E5}\u{1F7E9}", startColumn: 0, tabSize: 4, width: 4),
        WidthCase(text: "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}", startColumn: 0, tabSize: 4, width: 2),
        WidthCase(text: "\u{1F44D}\u{1F3FF}", startColumn: 0, tabSize: 4, width: 2),
        WidthCase(text: "\u{1F1FA}\u{1F1F8}", startColumn: 0, tabSize: 4, width: 2),
        WidthCase(text: "e\u{301}", startColumn: 0, tabSize: 4, width: 1),
        WidthCase(text: "\u{FF21}", startColumn: 0, tabSize: 4, width: 2),
        WidthCase(text: "\u{D55C}\u{AE00}", startColumn: 0, tabSize: 4, width: 4),
        WidthCase(text: "a\tb", startColumn: 0, tabSize: 4, width: 5),
        WidthCase(text: "a\tb", startColumn: 2, tabSize: 4, width: 3),
        WidthCase(text: "\t", startColumn: 0, tabSize: 8, width: 8),
        WidthCase(text: "\t", startColumn: 3, tabSize: 8, width: 5),
        WidthCase(text: "\t\t", startColumn: 0, tabSize: 2, width: 4),
        WidthCase(text: "\t", startColumn: 0, tabSize: 0, width: 1)
    ]

    @Test(arguments: cases)
    func measuresDisplayColumns(_ testCase: WidthCase) {
        let width = MarkdownTable.displayWidth(
            of: testCase.text,
            startColumn: testCase.startColumn,
            tabSize: testCase.tabSize
        )
        #expect(width == testCase.width)
    }
}

struct MarkdownTableBuildTests {
    @Test
    func alignedEmptyTable() {
        let table = MarkdownTable.buildEmptyTable(contentRows: 1, columns: 2)
        #expect(table == "|   |   |\n|---|---|\n|   |   |\n")
    }

    @Test
    func alignedEmptyTableWithWiderCells() {
        let table = MarkdownTable.buildEmptyTable(contentRows: 2, columns: 1, cellWidth: 5)
        #expect(table == "|     |\n|-----|\n|     |\n|     |\n")
    }

    @Test
    func compactEmptyTable() {
        let table = MarkdownTable.buildEmptyTable(contentRows: 1, columns: 2, style: .compact)
        #expect(table == "| | |\n| --- | --- |\n| | |\n")
    }

    @Test
    func tightEmptyTable() {
        let table = MarkdownTable.buildEmptyTable(contentRows: 1, columns: 2, style: .tight)
        #expect(table == "|||\n|---|---|\n|||\n")
    }

    @Test
    func headerOnlyTable() {
        let table = MarkdownTable.buildEmptyTable(contentRows: 0, columns: 3)
        #expect(table == "|   |   |   |\n|---|---|---|\n")
    }

    @Test(arguments: MarkdownTableStyle.allCases)
    func builtTablesAreAlreadyFormatted(_ style: MarkdownTableStyle) {
        let table = MarkdownTable.buildEmptyTable(contentRows: 2, columns: 3, style: style)
        let result = MarkdownTable.formatAllTables(text: table, style: style)
        #expect(result == nil)
    }

    @Test
    func negativeCountsProduceNoRowsAndNoColumns() {
        let table = MarkdownTable.buildEmptyTable(contentRows: -1, columns: 0)
        #expect(table == "|\n|\n")
    }
}

struct MarkdownTableInsertTests {
    private func insert(_ markup: String, style: MarkdownTableStyle = .aligned) -> String {
        let parsed = MarkdownActionCaretMarkup(markup)
        let caret = parsed.selections.first?.location ?? 0
        let result = MarkdownTable.insertEmptyTable(
            text: parsed.text,
            caret: caret,
            contentRows: 1,
            columns: 2,
            style: style
        )
        return MarkdownActionCaretMarkup.render(result.text, result.selections)
    }

    @Test
    func insertsIntoEmptyDocument() {
        #expect(insert("<caret>") == "|<caret>   |   |\n|---|---|\n|   |   |\n")
    }

    @Test
    func insertsWithoutBlankLineAfterBlankLine() {
        let result = insert(md("text", "", "<caret>"))
        #expect(result == md("text", "", "|<caret>   |   |", "|---|---|", "|   |   |", ""))
    }

    @Test
    func insertsBlankLineAfterNonEmptyLine() {
        let result = insert(md("text", "<caret>"))
        #expect(result == md("text", "", "|<caret>   |   |", "|---|---|", "|   |   |", ""))
    }

    @Test
    func insideBlockQuote() {
        let result = insert("> <caret>")
        #expect(result == "> |<caret>   |   |\n> |---|---|\n> |   |   |\n")
    }

    @Test
    func afterBlockQuoteLine() {
        let result = insert("> previous\n> <caret>")
        #expect(result == "> previous\n> \n> |<caret>   |   |\n> |---|---|\n> |   |   |\n")
    }

    @Test
    func insideNestedBlockQuote() {
        let result = insert("> > <caret>")
        #expect(result == "> > |<caret>   |   |\n> > |---|---|\n> > |   |   |\n")
    }

    @Test
    func compactStyle() {
        let result = insert("<caret>", style: .compact)
        #expect(result == "|<caret> | |\n| --- | --- |\n| | |\n")
    }

    @Test
    func tightStyle() {
        let result = insert("<caret>", style: .tight)
        #expect(result == "|<caret>||\n|---|---|\n|||\n")
    }

    @Test
    func resultEditAppliesToTheOriginalText() {
        let original = "text\n"
        let result = MarkdownTable.insertEmptyTable(text: original, caret: 5, contentRows: 1, columns: 2)
        #expect(result.applied(to: original) == result.text)
    }
}

struct MarkdownTableAlignmentDetectionTests {
    struct AlignmentCase: Sendable, CustomTestStringConvertible {
        let name: String
        let table: String
        let expected: [MarkdownTableAlignment]

        var testDescription: String { name }
    }

    private static let cases: [AlignmentCase] = [
        AlignmentCase(
            name: "all none",
            table: md("| none | none |", "|------|------|", "|  a   | asd  |"),
            expected: [.none, .none]
        ),
        AlignmentCase(
            name: "first left",
            table: md("| left | none |", "|:-----|------|", "|  a   | asd  |"),
            expected: [.left, .none]
        ),
        AlignmentCase(
            name: "first left second right",
            table: md("| left | right |", "|:-----|------:|", "|  a   | asd   |"),
            expected: [.left, .right]
        ),
        AlignmentCase(
            name: "first center second left",
            table: md("| center | left |", "|:------:|:-----|", "|    a   | asd  |"),
            expected: [.center, .left]
        ),
        AlignmentCase(
            name: "all with spaces",
            table: md(
                "| none | left | right | center |",
                "| ---  | :--- | ---:  |  :---: |",
                "|  0   |   1  |   2   |    3   |"
            ),
            expected: [.none, .left, .right, .center]
        ),
        AlignmentCase(
            name: "many columns",
            table: md(
                "| center   | right  |  left |  center                                 | none   |",
                "|:---:|---:|:---|           :-------------------:    |  ---|",
                "|  cell content   |  cell content  | cell content | cell content | cell content |",
                "|  cell content   |  cell content  | cell content | cell content | cell content |"
            ),
            expected: [.center, .right, .left, .center, .none]
        )
    ]

    @Test(arguments: cases)
    func detectsSeparatorAlignment(_ testCase: AlignmentCase) {
        let alignments = MarkdownTable.columnAlignments(text: testCase.table, tableContaining: 0)
        #expect(alignments == testCase.expected)
    }

    @Test
    func noAlignmentsOutsideOfTables() {
        #expect(MarkdownTable.columnAlignments(text: "plain text", tableContaining: 0) == nil)
    }
}

struct MarkdownTableCellContentTests {
    private func text(_ units: [UInt16]) -> String {
        String(decoding: units, as: UTF16.self)
    }

    @Test
    func alignedSeparatorForms() {
        #expect(text(MarkdownTableCellContent.separator(alignment: .none, width: 5, style: .aligned)) == "-----")
        #expect(text(MarkdownTableCellContent.separator(alignment: .left, width: 5, style: .aligned)) == ":----")
        #expect(text(MarkdownTableCellContent.separator(alignment: .right, width: 5, style: .aligned)) == "----:")
        #expect(text(MarkdownTableCellContent.separator(alignment: .center, width: 5, style: .aligned)) == ":---:")
    }

    @Test
    func alignedSeparatorKeepsAtLeastOneDash() {
        #expect(text(MarkdownTableCellContent.separator(alignment: .left, width: 1, style: .aligned)) == ":-")
        #expect(text(MarkdownTableCellContent.separator(alignment: .right, width: 1, style: .aligned)) == "-:")
        #expect(text(MarkdownTableCellContent.separator(alignment: .center, width: 2, style: .aligned)) == ":-:")
    }

    @Test
    func compactAndTightSeparatorForms() {
        #expect(text(MarkdownTableCellContent.separator(alignment: .none, width: 9, style: .compact)) == " --- ")
        #expect(text(MarkdownTableCellContent.separator(alignment: .left, width: 9, style: .compact)) == " :--- ")
        #expect(text(MarkdownTableCellContent.separator(alignment: .right, width: 9, style: .tight)) == "---:")
        #expect(text(MarkdownTableCellContent.separator(alignment: .center, width: 9, style: .tight)) == ":---:")
    }

    @Test
    func alignedRealignment() {
        let content = Array("ab".utf16)
        func realigned(_ alignment: MarkdownTableAlignment, width: Int) -> String {
            text(
                MarkdownTableCellContent.realigned(
                    content: content,
                    width: width,
                    alignment: alignment,
                    style: .aligned
                )
            )
        }
        #expect(realigned(.none, width: 6) == " ab   ")
        #expect(realigned(.left, width: 6) == " ab   ")
        #expect(realigned(.right, width: 6) == "   ab ")
        #expect(realigned(.center, width: 6) == "  ab  ")
        #expect(realigned(.center, width: 7) == "  ab   ")
    }

    @Test
    func compactAndTightRealignment() {
        let content = Array("ab".utf16)
        let empty: [UInt16] = []
        #expect(
            text(
                MarkdownTableCellContent.realigned(content: content, width: 9, alignment: .right, style: .compact)
            ) == " ab "
        )
        #expect(
            text(
                MarkdownTableCellContent.realigned(content: empty, width: 9, alignment: .none, style: .compact)
            ) == " "
        )
        #expect(
            text(
                MarkdownTableCellContent.realigned(content: content, width: 9, alignment: .none, style: .tight)
            ) == "ab"
        )
    }
}
