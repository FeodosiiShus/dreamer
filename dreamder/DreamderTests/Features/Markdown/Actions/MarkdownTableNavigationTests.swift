import Foundation
import Testing
@testable import Dreamder

private func md(_ lines: String...) -> String {
    lines.joined(separator: "\n")
}

private func tab(_ markup: String, count: Int = 1, forward: Bool = true) -> String {
    let parsed = MarkdownActionCaretMarkup(markup)
    var caret = parsed.selections.first?.location ?? 0
    for _ in 0..<count {
        guard let navigation = MarkdownTable.navigate(text: parsed.text, caret: caret, forward: forward) else { break }
        caret = navigation.caret
    }
    return MarkdownActionCaretMarkup.render(parsed.text, [NSRange(location: caret, length: 0)])
}

private func navigation(_ markup: String, forward: Bool = true) -> MarkdownTableNavigation? {
    let parsed = MarkdownActionCaretMarkup(markup)
    let caret = parsed.selections.first?.location ?? 0
    return MarkdownTable.navigate(text: parsed.text, caret: caret, forward: forward)
}

struct MarkdownTableTabTests {
    @Test
    func singleTabForward() {
        let before = md("| none | none |", "|------|------|", "| some<caret> | some |")
        let after = md("| none | none |", "|------|------|", "| some | <caret>some |")
        #expect(tab(before) == after)
    }

    @Test
    func multipleTabsForward() {
        let before = md("| none | none | none |", "|------|------|------|", "| some<caret> | some | some |")
        let after = md("| none | none | none |", "|------|------|------|", "| some | some | <caret>some |")
        #expect(tab(before, count: 2) == after)
    }

    @Test
    func multipleTabsForwardToNextRow() {
        let before = md(
            "| none | none | none |",
            "|------|------|------|",
            "| some<caret> | some | some |",
            "| some | some | some |"
        )
        let after = md(
            "| none | none | none |",
            "|------|------|------|",
            "| some | some | some |",
            "| some | some | <caret>some |"
        )
        #expect(tab(before, count: 5) == after)
    }

    @Test
    func singleTabBackward() {
        let before = md("| none | none |", "|------|------|", "| some | some<caret> |")
        let after = md("| none | none |", "|------|------|", "| some<caret> | some |")
        #expect(tab(before, forward: false) == after)
    }

    @Test
    func multipleTabsBackward() {
        let before = md("| none | none | none |", "|------|------|------|", "| some | some | some<caret> |")
        let after = md("| none | none | none |", "|------|------|------|", "| some<caret> | some | some |")
        #expect(tab(before, count: 2, forward: false) == after)
    }

    @Test
    func multipleTabsBackwardToPreviousRow() {
        let before = md(
            "| none | none | none |",
            "|------|------|------|",
            "| some | some | some |",
            "| some | some | some<caret> |"
        )
        let after = md(
            "| none | none | none |",
            "|------|------|------|",
            "| some<caret> | some | some |",
            "| some | some | some |"
        )
        #expect(tab(before, count: 5, forward: false) == after)
    }

    @Test
    func multipleTabsForwardInEmptyCells() {
        let before = md("||||", "|-|-|-|", "|<caret>|||")
        let after = md("||||", "|-|-|-|", "|||<caret>|")
        #expect(tab(before, count: 2) == after)
    }

    @Test
    func tabFromHeaderJumpsOverTheSeparatorRow() {
        let before = md("| a | b<caret> |", "|---|---|", "| c | d |")
        let after = md("| a | b |", "|---|---|", "| <caret>c | d |")
        #expect(tab(before) == after)
    }

    @Test
    func shiftTabFromFirstBodyCellJumpsOverTheSeparatorRow() {
        let before = md("| a | b |", "|---|---|", "| <caret>c | d |")
        let after = md("| a | b<caret> |", "|---|---|", "| c | d |")
        #expect(tab(before, forward: false) == after)
    }

    @Test
    func tabAtTheLastCellOfTheLastRowMovesToTheRowEnd() {
        let before = md("| a | b |", "|---|---|", "| c | d<caret> |")
        let after = md("| a | b |", "|---|---|", "| c | d |<caret>")
        #expect(tab(before) == after)
    }

    @Test
    func tabAtTheLastCellOfTheLastRowIgnoresTrailingSpaces() {
        let before = md("| a |", "|---|", "| c<caret> |   ")
        let after = md("| a |", "|---|", "| c |<caret>   ")
        #expect(tab(before) == after)
    }

    @Test
    func tabGoesToTheFirstNonSpaceOfTheNextCell() {
        let before = md("| a<caret> |   b |", "|---|---|", "| c | d |")
        let after = md("| a |   <caret>b |", "|---|---|", "| c | d |")
        #expect(tab(before) == after)
    }

    @Test
    func tabIntoAnEmptyCellStaysInsideTheCell() {
        let before = md("| a<caret> |  |", "|---|--|", "| c | d |")
        let after = md("| a |<caret>  |", "|---|--|", "| c | d |")
        #expect(tab(before) == after)
    }

    @Test
    func shiftTabIntoAnEmptyCellDoesNotJumpPastThePipe() {
        let before = md("|a|b|", "|-|-|", "||<caret>x|")
        let after = md("|a|b|", "|-|-|", "|<caret>|x|")
        #expect(tab(before, forward: false) == after)
    }

    @Test
    func shiftTabAtTheFirstCellOfTheTableIsLeftToTheDefaultAction() {
        let result = navigation(md("| <caret>a | b |", "|---|---|", "| c | d |"), forward: false)
        #expect(result == nil)
    }

    @Test
    func caretInSeparatorRowIsLeftToTheDefaultAction() {
        let result = navigation(md("| a | b |", "|--<caret>-|---|", "| c | d |"))
        #expect(result == nil)
    }

    @Test
    func caretOutsideOfTablesIsLeftToTheDefaultAction() {
        #expect(navigation("some <caret>text | with pipe") == nil)
        #expect(navigation(md("| a | b |", "|---|---|", "| c | d |", "", "text<caret>")) == nil)
    }

    @Test
    func caretAfterTheLastPipeIsLeftToTheDefaultAction() {
        let result = navigation(md("| a | b |", "|---|---|", "| c | d |<caret>"))
        #expect(result == nil)
    }

    @Test
    func caretBeforeTheFirstPipeIsLeftToTheDefaultAction() {
        let result = navigation(md("| a | b |", "|---|---|", "<caret>| c | d |"))
        #expect(result == nil)
    }

    @Test
    func tableInsideListItemIsLeftToTheDefaultAction() {
        let before = md("- item", "", "  | a<caret> | b |", "  |---|---|", "  | c | d |")
        #expect(navigation(before) == nil)
    }

    @Test
    func tableInsideBlockQuoteIsNavigated() {
        let before = md("> | a<caret> | b |", "> |---|---|", "> | c | d |")
        let after = md("> | a | <caret>b |", "> |---|---|", "> | c | d |")
        #expect(tab(before) == after)
    }

    @Test
    func indentedTableOutsideOfListItemIsNavigated() {
        let before = md("text", "", "  | a<caret> | b |", "  |---|---|", "  | c | d |")
        let after = md("text", "", "  | a | <caret>b |", "  |---|---|", "  | c | d |")
        #expect(tab(before) == after)
    }
}

struct MarkdownTableIsInsideTests {
    @Test
    func insideHeaderAndBodyCells() {
        let text = md("| a | b |", "|---|---|", "| c | d |")
        #expect(MarkdownTable.isInsideTable(text: text, caret: 3))
        #expect(MarkdownTable.isInsideTable(text: text, caret: 22))
    }

    @Test
    func notInsideTheSeparatorRowOrAtTheRowEnd() {
        let text = md("| a | b |", "|---|---|", "| c | d |")
        #expect(!MarkdownTable.isInsideTable(text: text, caret: 14))
        #expect(!MarkdownTable.isInsideTable(text: text, caret: text.utf16.count))
        #expect(!MarkdownTable.isInsideTable(text: text, caret: 0))
    }

    @Test
    func notInsideParagraphsWithPipes() {
        #expect(!MarkdownTable.isInsideTable(text: "a | b | c", caret: 4))
    }
}

struct MarkdownTableEnterTests {
    private struct Step {
        let text: String
        let caret: Int
        let previousBreakCaret: Int?
    }

    private func start(_ markup: String) -> Step {
        let parsed = MarkdownActionCaretMarkup(markup)
        return Step(text: parsed.text, caret: parsed.selections.first?.location ?? 0, previousBreakCaret: nil)
    }

    private func enter(_ step: Step) -> Step? {
        guard let result = MarkdownTable.enterInCell(
            text: step.text,
            caret: step.caret,
            previousBreakCaret: step.previousBreakCaret
        ) else {
            return nil
        }
        return Step(
            text: result.action.text,
            caret: result.action.selections.first?.location ?? 0,
            previousBreakCaret: result.previousBreakCaret
        )
    }

    private func render(_ step: Step?) -> String? {
        step.map { MarkdownActionCaretMarkup.render($0.text, [NSRange(location: $0.caret, length: 0)]) }
    }

    @Test
    func singleEnterInsideCellInsertsLineBreakTag() {
        let before = md("| none | none |", "|------|------|", "| some<caret> | some |")
        let after = md("| none | none |", "|------|------|", "| some<br/><caret> | some |")
        #expect(render(enter(start(before))) == after)
    }

    @Test
    func singleEnterRemembersTheCaretAfterTheTag() {
        let before = md("| none | none |", "|------|------|", "| some<caret> | some |")
        let step = enter(start(before))
        let tagEnd = (before.replacingOccurrences(of: "<caret>", with: "") as NSString).range(of: " | some |").location
        #expect(step?.previousBreakCaret == tagEnd + 5)
    }

    @Test
    func doubleEnterInsideCellSplitsTheRowAndRemovesTheTag() {
        let before = md("| none | none |", "|------|------|", "| some<caret> | some |")
        let first = enter(start(before))
        let second = first.flatMap { enter($0) }
        let after = md("| none | none |", "|------|------|", "| some", "<caret>| some |")
        #expect(render(second) == after)
        #expect(second?.previousBreakCaret == nil)
    }

    @Test
    func enterAtTheRowEndIsLeftToTheDefaultAction() {
        let before = md("| none | none |", "|------|------|", "| some | some |<caret>")
        #expect(enter(start(before)) == nil)
    }

    @Test
    func enterOutsideOfTablesIsLeftToTheDefaultAction() {
        #expect(enter(start("plain <caret>text")) == nil)
    }

    @Test
    func enterInSeparatorRowIsLeftToTheDefaultAction() {
        let before = md("| none | none |", "|------<caret>|------|", "| some | some |")
        #expect(enter(start(before)) == nil)
    }

    @Test
    func secondEnterAtAnotherCaretInsertsAnotherTag() {
        let before = md("| a | b |", "|---|---|", "| c<caret> | d |")
        let first = enter(start(before))
        let moved = first.map { Step(text: $0.text, caret: $0.caret - 6, previousBreakCaret: $0.previousBreakCaret) }
        let second = moved.flatMap { enter($0) }
        #expect(second?.text == md("| a | b |", "|---|---|", "| <br/>c<br/> | d |"))
    }

    @Test
    func enterRightAfterTagWithoutTagBeforeCaretIsLeftToTheDefaultAction() {
        let before = md("| a | b |", "|---|---|", "| cc<caret> | d |")
        let parsed = MarkdownActionCaretMarkup(before)
        let caret = parsed.selections.first?.location ?? 0
        let result = MarkdownTable.enterInCell(text: parsed.text, caret: caret, previousBreakCaret: caret)
        #expect(result == nil)
    }

    @Test
    func doubleEnterInsideBlockQuoteKeepsThePrefix() {
        let before = md("> | a | b |", "> |---|---|", "> | c<caret> | d |")
        let first = enter(start(before))
        let second = first.flatMap { enter($0) }
        let after = md("> | a | b |", "> |---|---|", "> | c", "> <caret>| d |")
        #expect(render(second) == after)
    }
}

struct MarkdownTableShiftEnterTests {
    private func shiftEnter(_ markup: String, style: MarkdownTableStyle = .aligned) -> String? {
        let parsed = MarkdownActionCaretMarkup(markup)
        let caret = parsed.selections.first?.location ?? 0
        guard let result = MarkdownTable.shiftEnter(text: parsed.text, caret: caret, style: style) else { return nil }
        return MarkdownActionCaretMarkup.render(result.text, result.selections)
    }

    @Test
    func atTheRowEnd() {
        let before = md("| none | none |", "|------|------|", "| some | some |<caret>")
        let after = md("| none | none |", "|------|------|", "| some | some |", "| <caret>     |      |")
        #expect(shiftEnter(before) == after)
    }

    @Test
    func atTheRowEndInsideListItem() {
        let before = "- item  \n\n  | none | none |\n  |------|------|\n  | some | some |<caret>"
        let after = "- item  \n\n  | none | none |\n  |------|------|\n  | some | some |\n  | <caret>     |      |"
        #expect(shiftEnter(before) == after)
    }

    @Test
    func atTheRowEndInCompactTable() {
        let before = md("| a | b |", "| --- | --- |", "| some | some |<caret>")
        let after = md("| a | b |", "| --- | --- |", "| some | some |", "| <caret>| |")
        #expect(shiftEnter(before, style: .compact) == after)
    }

    @Test
    func atTheRowEndInTightTable() {
        let before = md("|a|b|", "|---|---|", "|some|some|<caret>")
        let after = md("|a|b|", "|---|---|", "|some|some|", "|<caret>||")
        #expect(shiftEnter(before, style: .tight) == after)
    }

    @Test
    func atTheRowEndWithCjkHeader() {
        let before = md("| 名字 | 年龄 |", "|------|------|", "| 张三 | 25   |<caret>")
        let after = md("| 名字 | 年龄 |", "|------|------|", "| 张三 | 25   |", "| <caret>     |      |")
        #expect(shiftEnter(before) == after)
    }

    @Test
    func atTheSeparatorRowEnd() {
        let before = md("| none | none |", "|------|------|<caret>", "| some | some |")
        let after = md("| none | none |", "|------|------|", "| <caret>     |      |", "| some | some |")
        #expect(shiftEnter(before) == after)
    }

    @Test
    func atTheHeaderRowEndIsLeftToTheDefaultAction() {
        let before = md("| none | none |<caret>", "|------|------|", "| some | some |")
        #expect(shiftEnter(before) == nil)
    }

    @Test
    func insideAHeaderCellIsLeftToTheDefaultAction() {
        let before = md("| no<caret>ne | none |", "|------|------|", "| some | some |")
        #expect(shiftEnter(before) == nil)
    }

    @Test
    func insideABodyCellInsertsTheRowAfterTheCurrentLine() {
        let before = md("| none | none |", "|------|------|", "| so<caret>me | some |", "| last | last |")
        let after = md(
            "| none | none |",
            "|------|------|",
            "| some | some |",
            "| <caret>     |      |",
            "| last | last |"
        )
        #expect(shiftEnter(before) == after)
    }

    @Test
    func insideBlockQuoteKeepsThePrefix() {
        let before = md("> | a | b |", "> |---|---|", "> | c | d |<caret>")
        let after = md("> | a | b |", "> |---|---|", "> | c | d |", "> | <caret>  |   |")
        #expect(shiftEnter(before) == after)
    }

    @Test
    func outsideOfTablesIsLeftToTheDefaultAction() {
        #expect(shiftEnter("plain text<caret>") == nil)
        #expect(shiftEnter(md("| a | b |", "|---|---|", "| c | d |", "", "text<caret>")) == nil)
    }

    @Test
    func resultEditAppliesToTheOriginalText() {
        let original = md("| a | b |", "|---|---|", "| c | d |")
        let caret = original.utf16.count
        let result = MarkdownTable.shiftEnter(text: original, caret: caret)
        #expect(result?.applied(to: original) == result?.text)
    }
}
