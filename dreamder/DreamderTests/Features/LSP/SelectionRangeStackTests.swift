import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@Suite
struct SelectionRangeStackTests {
    private let source = NSString(string: "let alpha = 1\nlet beta = 2")

    private func range(_ location: Int, _ length: Int) -> NSRange {
        NSRange(location: location, length: length)
    }

    private func lsp(_ line: Int, _ start: Int, _ end: Int) -> LSPRange {
        LSPRange(start: Position(line: line, character: start), end: Position(line: line, character: end))
    }

    private func flat(_ range: LSPRange) -> NSRange? {
        guard range.start.line == range.end.line else { return nil }
        return NSRange(location: range.start.character, length: range.end.character - range.start.character)
    }

    @Test
    func aCaretStackAnchorsAtTheCaret() {
        let stack = CaretSelectionStack(selection: range(6, 0))

        #expect(stack.anchors == [6])
        #expect(stack.requestOffset == 6)
        #expect(stack.current == range(6, 0))
        #expect(stack.history.isEmpty)
        #expect(stack.serverChain == nil)
    }

    @Test
    func aSelectionStackAnchorsAtBothEnds() {
        let stack = CaretSelectionStack(selection: range(2, 4))

        #expect(stack.anchors == [2, 6])
        #expect(stack.requestOffset == 2)
    }

    @Test
    func expandWalksTheServerChainAndThenTheLadder() {
        var stack = CaretSelectionStack(selection: range(6, 0))
        stack.serverChain = [range(4, 5), range(0, 13)]

        let first = stack.expand(in: source)
        #expect(first)
        #expect(stack.current == range(4, 5))
        let second = stack.expand(in: source)
        #expect(second)
        #expect(stack.current == range(0, 13))
        let third = stack.expand(in: source)
        #expect(third)
        #expect(stack.current == range(0, 26))
        let fourth = stack.expand(in: source)
        #expect(!fourth)
        #expect(stack.current == range(0, 26))
        #expect(stack.history == [range(6, 0), range(4, 5), range(0, 13)])
    }

    @Test
    func expandSkipsChainEntriesThatDoNotContainTheSelection() {
        var stack = CaretSelectionStack(selection: range(6, 0))
        stack.serverChain = [range(0, 3), range(10, 5)]

        let expanded = stack.expand(in: source)
        #expect(expanded)
        #expect(stack.current == range(4, 5))
    }

    @Test
    func expandUsesTheLadderWhenTheChainIsEmptyOrMissing() {
        var withoutChain = CaretSelectionStack(selection: range(6, 0))
        var emptyChain = CaretSelectionStack(selection: range(6, 0))
        emptyChain.serverChain = []

        let withoutChainExpanded = withoutChain.expand(in: source)
        let emptyChainExpanded = emptyChain.expand(in: source)
        #expect(withoutChainExpanded)
        #expect(emptyChainExpanded)
        #expect(withoutChain.current == range(4, 5))
        #expect(emptyChain.current == range(4, 5))
    }

    @Test
    func shrinkPopsTheHistoryBackToTheCaret() {
        var stack = CaretSelectionStack(selection: range(6, 0))
        stack.serverChain = [range(4, 5), range(0, 13)]
        _ = stack.expand(in: source)
        _ = stack.expand(in: source)

        let first = stack.shrink(in: source)
        #expect(first)
        #expect(stack.current == range(4, 5))
        let second = stack.shrink(in: source)
        #expect(second)
        #expect(stack.current == range(6, 0))
        let third = stack.shrink(in: source)
        #expect(!third)
        #expect(stack.current == range(6, 0))
    }

    @Test
    func shrinkWithoutHistoryWalksTheLadderDownAndCollapsesToTheCaret() {
        var stack = CaretSelectionStack(selection: range(0, 13))

        let first = stack.shrink(in: source)
        #expect(first)
        #expect(stack.current == range(12, 1))
        let second = stack.shrink(in: source)
        #expect(second)
        #expect(stack.current == range(13, 0))
        let third = stack.shrink(in: source)
        #expect(!third)
        let expanded = stack.expand(in: source)
        #expect(expanded)
        #expect(stack.history == [range(13, 0)])
    }

    @Test
    func chainRangesAreOrderedInnermostFirst() {
        let outer = SelectionRange(range: lsp(0, 0, 26), parent: nil)
        let middle = SelectionRange(range: lsp(0, 0, 13), parent: outer)
        let inner = SelectionRange(range: lsp(0, 4, 9), parent: middle)

        #expect(SelectionRangeChain.ranges(from: inner, convert: flat) == [range(4, 5), range(0, 13), range(0, 26)])
    }

    @Test
    func chainSkipsUnconvertibleDuplicateAndNonNestedRanges() {
        let top = SelectionRange(range: lsp(0, 0, 30), parent: nil)
        let multiLine = SelectionRange(range: LSPRange(start: Position(line: 0, character: 0), end: Position(line: 1, character: 2)), parent: top)
        let sideways = SelectionRange(range: lsp(0, 20, 25), parent: multiLine)
        let duplicate = SelectionRange(range: lsp(0, 4, 9), parent: sideways)
        let inner = SelectionRange(range: lsp(0, 4, 9), parent: duplicate)

        #expect(SelectionRangeChain.ranges(from: inner, convert: flat) == [range(4, 5), range(0, 30)])
    }

    @Test
    func chainOfASingleRangeIsThatRange() {
        let only = SelectionRange(range: lsp(0, 2, 3), parent: nil)

        #expect(SelectionRangeChain.ranges(from: only, convert: flat) == [range(2, 1)])
    }
}
