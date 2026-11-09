import Foundation
import Testing
@testable import Dreamder

@Suite
struct SelectionRangeLadderTests {
    private func text(_ string: String) -> NSString {
        NSString(string: string)
    }

    private func range(_ location: Int, _ length: Int) -> NSRange {
        NSRange(location: location, length: length)
    }

    @Test
    func wordPartsFollowJavaIdentifierPartCategories() {
        for character in ["a", "Z", "7", "_", "$", "\u{E9}", "\u{20AC}", "\u{0301}", "\u{2160}", "\u{0903}"] {
            #expect(SelectionLadder.isWordPart(character.utf16.first ?? 0), "\(character)")
        }
        for character in [" ", "-", ".", "\n", "\"", "("] {
            #expect(!SelectionLadder.isWordPart(character.utf16.first ?? 0), "\(character)")
        }
        #expect(!SelectionLadder.isWordPart(0xD83D))
    }

    @Test
    func surrogatePairsAreNeitherWhitespaceNorTrimmedAway() {
        let emoji = text("\u{1F600}")

        #expect(SelectionLadder.ranges(in: emoji, at: 0) == [range(0, 2), range(0, 2)])
        #expect(SelectionLadder.blankRange(in: text("\u{1F600} x"), at: 2) == nil)
    }

    @Test
    func strictContainmentExcludesEqualAndDisjointRanges() {
        #expect(SelectionLadder.strictlyContains(range(0, 10), range(2, 3)))
        #expect(SelectionLadder.strictlyContains(range(2, 8), range(2, 3)))
        #expect(SelectionLadder.strictlyContains(range(0, 5), range(2, 3)))
        #expect(SelectionLadder.strictlyContains(range(0, 3), range(3, 0)))
        #expect(!SelectionLadder.strictlyContains(range(2, 3), range(2, 3)))
        #expect(!SelectionLadder.strictlyContains(range(3, 2), range(2, 3)))
        #expect(!SelectionLadder.strictlyContains(range(2, 2), range(2, 3)))
        #expect(!SelectionLadder.strictlyContains(range(8, 2), range(2, 3)))
    }

    @Test
    func wordRangeCoversTheIdentifierAroundTheOffset() {
        let source = text("let alpha_1 = beta$2")
        #expect(SelectionLadder.wordRange(in: source, at: 6) == range(4, 7))
        #expect(SelectionLadder.wordRange(in: source, at: 4) == range(4, 7))
        #expect(SelectionLadder.wordRange(in: source, at: 11) == range(4, 7))
        #expect(SelectionLadder.wordRange(in: source, at: 0) == range(0, 3))
        #expect(SelectionLadder.wordRange(in: source, at: 20) == range(14, 6))
        #expect(SelectionLadder.wordRange(in: source, at: 18) == range(14, 6))
    }

    @Test
    func wordRangeIsNilOutsideIdentifiers() {
        #expect(SelectionLadder.wordRange(in: text(""), at: 0) == nil)
        #expect(SelectionLadder.wordRange(in: text("a  b"), at: -1) == nil)
        #expect(SelectionLadder.wordRange(in: text("a  b"), at: 5) == nil)
        #expect(SelectionLadder.wordRange(in: text("a  b"), at: 2) == nil)
        #expect(SelectionLadder.wordRange(in: text("ab  "), at: 4) == nil)
        #expect(SelectionLadder.wordRange(in: text("  ab"), at: 0) == nil)
    }

    @Test
    func blankRangeCoversWhitespaceRunsAfterWhitespace() {
        #expect(SelectionLadder.blankRange(in: text("a  \t b"), at: 2) == range(1, 4))
        #expect(SelectionLadder.blankRange(in: text("  x"), at: 0) == range(0, 2))
        #expect(SelectionLadder.blankRange(in: text("a\n  b"), at: 2) == range(2, 2))
        #expect(SelectionLadder.blankRange(in: text("a  b"), at: 1) == nil)
        #expect(SelectionLadder.blankRange(in: text("a  b"), at: 3) == nil)
        #expect(SelectionLadder.blankRange(in: text("a  "), at: 3) == nil)
        #expect(SelectionLadder.blankRange(in: text("a  b"), at: -1) == nil)
    }

    @Test
    func rangesAtAnOffsetListWordBlankTrimmedAndWholeLine() {
        let source = text("  foo bar  \nnext")
        #expect(SelectionLadder.ranges(in: source, at: 3) == [range(2, 3), range(2, 7), range(0, 11)])
        #expect(SelectionLadder.ranges(in: source, at: 0) == [range(0, 2), range(2, 7), range(0, 11)])
        #expect(SelectionLadder.ranges(in: source, at: 12) == [range(12, 4), range(12, 4), range(12, 4)])
        #expect(SelectionLadder.ranges(in: text("   "), at: 1) == [range(0, 3), range(0, 3)])
        #expect(SelectionLadder.ranges(in: source, at: -1).isEmpty)
        #expect(SelectionLadder.ranges(in: source, at: 99).isEmpty)
    }

    @Test
    func coveringLinesStartAtTheFirstLineAndEndAtTheLastLineContent() {
        let source = text("  one two\nthree\r\nfour")
        #expect(SelectionLadder.lines(in: source, covering: range(4, 3)) == range(0, 9))
        #expect(SelectionLadder.lines(in: source, covering: range(4, 8)) == range(0, 15))
        #expect(SelectionLadder.lines(in: source, covering: range(4, 6)) == range(0, 10))
        #expect(SelectionLadder.lines(in: source, covering: range(10, 4)) == range(10, 5))
        #expect(SelectionLadder.lines(in: source, covering: range(15, 0)) == range(10, 5))
        #expect(SelectionLadder.lines(in: source, covering: range(16, 0)) == range(10, 6))
        #expect(SelectionLadder.lines(in: source, covering: range(0, 0)) == range(0, 9))
    }

    @Test
    func coveringLinesRejectsSelectionsOutsideTheText() {
        #expect(SelectionLadder.lines(in: text("abc"), covering: range(-1, 1)) == nil)
        #expect(SelectionLadder.lines(in: text("abc"), covering: range(2, 5)) == nil)
        #expect(SelectionLadder.lines(in: text("abc"), covering: range(3, 0)) == range(0, 3))
    }

    @Test
    func nextPicksTheSmallestStrictlyLargerCandidate() {
        let source = text("  foo bar  \nnext")
        #expect(SelectionLadder.next(in: source, anchors: [3], selection: range(3, 0)) == range(2, 3))
        #expect(SelectionLadder.next(in: source, anchors: [3], selection: range(2, 3)) == range(2, 7))
        #expect(SelectionLadder.next(in: source, anchors: [3], selection: range(2, 7)) == range(0, 11))
        #expect(SelectionLadder.next(in: source, anchors: [3], selection: range(0, 11)) == range(0, 16))
        #expect(SelectionLadder.next(in: source, anchors: [3], selection: range(0, 16)) == nil)
    }

    @Test
    func nextExtendsAMultiLineSelectionToWholeLinesBeforeTheDocument() {
        let source = text("one two\nthree four\nfive six")
        #expect(SelectionLadder.next(in: source, anchors: [4, 14], selection: range(4, 10)) == range(0, 18))
        #expect(SelectionLadder.next(in: source, anchors: [4, 14], selection: range(0, 18)) == range(0, 27))
    }

    @Test
    func nextIsNilForInvalidSelectionsAndEmptyText() {
        #expect(SelectionLadder.next(in: text("abc"), anchors: [0], selection: range(2, 9)) == nil)
        #expect(SelectionLadder.next(in: text(""), anchors: [0], selection: range(0, 0)) == nil)
        #expect(SelectionLadder.next(in: text("abc"), anchors: [99, -3], selection: range(1, 0)) == range(0, 3))
    }

    @Test
    func nextOnTheTrailingEmptyLineJumpsToTheDocument() {
        let source = text("a\n")
        #expect(SelectionLadder.next(in: source, anchors: [2], selection: range(2, 0)) == range(0, 2))
    }

    @Test
    func previousShrinksToTheLargestCandidateAroundTheCaret() {
        let source = text("ab cd\nef")
        #expect(SelectionLadder.previous(in: source, anchors: [0], selection: range(0, 8)) == range(0, 5))
        #expect(SelectionLadder.previous(in: source, anchors: [0, 8], selection: range(0, 8)) == range(6, 2))
        #expect(SelectionLadder.previous(in: text("foo bar"), anchors: [0, 7], selection: range(0, 7)) == range(4, 3))
    }

    @Test
    func previousCollapsesToTheCaretWhenNothingSmallerContainsIt() {
        #expect(SelectionLadder.previous(in: text("foo"), anchors: [0, 3], selection: range(0, 3)) == range(3, 0))
        #expect(SelectionLadder.previous(in: text("foo"), anchors: [], selection: range(0, 3)) == range(3, 0))
    }

    @Test
    func previousLeavesEmptyAndInvalidSelectionsAlone() {
        #expect(SelectionLadder.previous(in: text("foo"), anchors: [1], selection: range(1, 0)) == range(1, 0))
        #expect(SelectionLadder.previous(in: text("foo"), anchors: [1], selection: range(2, 9)) == range(2, 9))
        #expect(SelectionLadder.previous(in: text("foo"), anchors: [1], selection: range(-1, 2)) == range(-1, 2))
    }

    private func expandedSelections(markup: SelectionRangeFixtureMarkup) throws -> [NSRange] {
        let caret = try #require(markup.caret)
        var stack = CaretSelectionStack(selection: NSRange(location: caret, length: 0))
        let source = NSString(string: markup.text)
        var selections: [NSRange] = []
        while stack.expand(in: source) {
            selections.append(stack.current)
        }
        return selections
    }

    private func shrunkSelections(markup: SelectionRangeFixtureMarkup, steps: Int) throws -> [NSRange] {
        let caret = try #require(markup.caret)
        var stack = CaretSelectionStack(selection: NSRange(location: caret, length: 0))
        let source = NSString(string: markup.text)
        for _ in 0..<steps {
            let expanded = stack.expand(in: source)
            #expect(expanded)
        }
        var selections: [NSRange] = []
        while stack.shrink(in: source) {
            selections.append(stack.current)
        }
        return selections
    }

    @Test
    func selectWordWithoutPSITestTest1() throws {
        let before = try SelectionRangeFixtureMarkup.intelliJ("selectWordWithoutPSIAction/test1/before")
        let afters = try SelectionRangeFixtureMarkup.afterFiles(in: "selectWordWithoutPSIAction/test1")
        try #require(afters.count == 3)
        for after in afters {
            #expect(after.text == before.text)
            #expect(after.caret == before.caret)
        }
        let expanded = try expandedSelections(markup: before)
        #expect(expanded == afters.compactMap(\.selection))
    }

    @Test
    func selectWordWithoutPSITestCamelHumpsWithoutCamelStepAddsOnlyTheTrimmedLine() throws {
        let before = try SelectionRangeFixtureMarkup.intelliJ("selectWordWithoutPSIAction/camelHumps/before")
        let afters = try SelectionRangeFixtureMarkup.afterFiles(in: "selectWordWithoutPSIAction/camelHumps")
        try #require(afters.count == 4)
        let word = try #require(afters[1].selection)
        let line = try #require(afters[2].selection)
        let document = try #require(afters[3].selection)
        let trimmed = NSRange(location: line.location + 2, length: line.length - 2)
        let expanded = try expandedSelections(markup: before)
        #expect(expanded == [word, trimmed, line, document])
        let hump = try #require(afters[0].selection)
        let caret = try #require(before.caret)
        #expect(hump == NSRange(location: 29, length: 4))
        #expect(NSLocationInRange(caret, hump))
    }

    @Test
    func plainTextSelectWordTestInnerWhitespace() throws {
        let before = try SelectionRangeFixtureMarkup.intelliJ("selectWordAction/innerWhitespace/before.txt")
        let afters = try SelectionRangeFixtureMarkup.afterFiles(in: "selectWordAction/innerWhitespace", suffix: ".txt")
        try #require(afters.count == 1)
        let expanded = try expandedSelections(markup: before)
        #expect(expanded.first == afters.first?.selection)
    }

    @Test
    func plainTextSelectWordTestLeadingWhitespace() throws {
        let before = try SelectionRangeFixtureMarkup.intelliJ("selectWordAction/leadingWhitespace/before.txt")
        let afters = try SelectionRangeFixtureMarkup.afterFiles(in: "selectWordAction/leadingWhitespace", suffix: ".txt")
        try #require(afters.count == 1)
        let expanded = try expandedSelections(markup: before)
        #expect(expanded.first == afters.first?.selection)
    }

    @Test
    func plainTextSelectWordTestPlainTextEmptyLine() throws {
        let before = try SelectionRangeFixtureMarkup.intelliJ("selectWordAction/plainTextEmptyLine/before.txt")
        let afters = try SelectionRangeFixtureMarkup.afterFiles(in: "selectWordAction/plainTextEmptyLine", suffix: ".txt")
        try #require(afters.count == 1)
        let expanded = try expandedSelections(markup: before)
        #expect(expanded == afters.compactMap(\.selection))
    }

    @Test
    func unselectWalksTheSelectWordFixturesBackToTheCaret() throws {
        let before = try SelectionRangeFixtureMarkup.intelliJ("selectWordWithoutPSIAction/test1/before")
        let afters = try SelectionRangeFixtureMarkup.afterFiles(in: "selectWordWithoutPSIAction/test1")
        let caret = try #require(before.caret)
        let expected = afters.dropLast().reversed().compactMap(\.selection) + [NSRange(location: caret, length: 0)]
        let shrunk = try shrunkSelections(markup: before, steps: afters.count)
        #expect(shrunk == expected)
    }
}
