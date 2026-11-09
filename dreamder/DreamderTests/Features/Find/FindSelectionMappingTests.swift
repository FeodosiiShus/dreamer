import Foundation
import Testing
@testable import Dreamder

@Suite
struct FindSelectionMappingTests {
    private let edits = [
        FindReplaceEdit(range: NSRange(location: 3, length: 3), replacement: "quux"),
        FindReplaceEdit(range: NSRange(location: 10, length: 3), replacement: "x")
    ]

    @Test
    func rangesBeforeBetweenAndAfterTheEditsShiftByTheEditsBeforeThem() {
        #expect(FindReplaceEngine.mapped(NSRange(location: 1, length: 1), through: edits) == NSRange(location: 1, length: 1))
        #expect(FindReplaceEngine.mapped(NSRange(location: 8, length: 0), through: edits) == NSRange(location: 9, length: 0))
        #expect(FindReplaceEngine.mapped(NSRange(location: 16, length: 0), through: edits) == NSRange(location: 15, length: 0))
    }

    @Test
    func offsetsAtTheBoundariesOfAReplacedMatchStayOutsideOfIt() {
        #expect(FindReplaceEngine.mapped(NSRange(location: 3, length: 0), through: edits) == NSRange(location: 3, length: 0))
        #expect(FindReplaceEngine.mapped(NSRange(location: 6, length: 0), through: edits) == NSRange(location: 7, length: 0))
    }

    @Test
    func offsetsInsideAReplacedMatchMoveToTheEndOfTheReplacement() {
        #expect(FindReplaceEngine.mapped(NSRange(location: 4, length: 0), through: edits) == NSRange(location: 7, length: 0))
        #expect(FindReplaceEngine.mapped(NSRange(location: 11, length: 0), through: edits) == NSRange(location: 12, length: 0))
    }

    @Test
    func selectionsSpanningAMatchGrowOrShrinkWithIt() {
        #expect(FindReplaceEngine.mapped(NSRange(location: 2, length: 5), through: edits) == NSRange(location: 2, length: 6))
        #expect(FindReplaceEngine.mapped(NSRange(location: 2, length: 12), through: edits) == NSRange(location: 2, length: 11))
    }
}
