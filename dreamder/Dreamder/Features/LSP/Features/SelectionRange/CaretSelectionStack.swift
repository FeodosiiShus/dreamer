import Foundation
import LanguageServerProtocol

nonisolated struct CaretSelectionStack: Equatable, Sendable {
    let requestOffset: Int
    let anchors: [Int]
    private(set) var current: NSRange
    private(set) var history: [NSRange] = []
    var serverChain: [NSRange]?

    init(selection: NSRange) {
        requestOffset = selection.location
        anchors = selection.length == 0 ? [selection.location] : [selection.location, NSMaxRange(selection)]
        current = selection
    }

    mutating func expand(in text: NSString) -> Bool {
        let chained = serverChain?.first { SelectionLadder.strictlyContains($0, current) }
        guard let next = chained ?? SelectionLadder.next(in: text, anchors: anchors, selection: current) else {
            return false
        }
        history.append(current)
        current = next
        return true
    }

    mutating func shrink(in text: NSString) -> Bool {
        if let previous = history.popLast() {
            current = previous
            return true
        }
        let shrunk = SelectionLadder.previous(in: text, anchors: anchors, selection: current)
        guard shrunk != current else { return false }
        current = shrunk
        return true
    }
}

nonisolated enum SelectionRangeChain {
    static func ranges(from innermost: SelectionRange, convert: (LSPRange) -> NSRange?) -> [NSRange] {
        var result: [NSRange] = []
        var node: SelectionRange? = innermost
        while let element = node {
            if let range = convert(element.range), isNested(range, around: result.last) {
                result.append(range)
            }
            node = element.parent
        }
        return result
    }

    private static func isNested(_ range: NSRange, around previous: NSRange?) -> Bool {
        guard let previous else { return true }
        return SelectionLadder.strictlyContains(range, previous)
    }
}
