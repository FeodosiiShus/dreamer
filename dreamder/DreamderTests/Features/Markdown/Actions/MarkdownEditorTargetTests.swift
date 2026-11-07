import CodeEditSourceEditor
import Foundation
import Testing
@testable import Dreamder

struct MarkdownEditorTargetRangesTests {
    @Test
    func resolvedRangesAreKeptVerbatim() {
        let positions = [CursorPosition(range: NSRange(location: 3, length: 2))]

        let ranges = MarkdownEditorTarget.ranges(of: positions, in: "hello world")

        #expect(ranges == [NSRange(location: 3, length: 2)])
    }

    @Test
    func lineAndColumnPositionsBecomeOffsets() {
        let positions = [CursorPosition(line: 2, column: 3)]

        let ranges = MarkdownEditorTarget.ranges(of: positions, in: "first\nsecond\nthird")

        #expect(ranges == [NSRange(location: 8, length: 0)])
    }

    @Test
    func columnBeyondTheLineEndIsClampedToTheLineEnd() {
        let positions = [CursorPosition(line: 1, column: 50)]

        let ranges = MarkdownEditorTarget.ranges(of: positions, in: "abc\ndef")

        #expect(ranges == [NSRange(location: 3, length: 0)])
    }

    @Test
    func missingOrInvalidPositionsFallBackToTheDocumentStart() {
        let invalid = MarkdownEditorTarget.ranges(of: [CursorPosition(line: 9, column: 1)], in: "abc")
        let empty = MarkdownEditorTarget.ranges(of: [], in: "abc")

        #expect(invalid == [NSRange(location: 0, length: 0)])
        #expect(empty == [NSRange(location: 0, length: 0)])
    }

    @Test
    func multipleCaretsAreAllConverted() {
        let positions = [CursorPosition(line: 1, column: 2), CursorPosition(line: 2, column: 1)]

        let ranges = MarkdownEditorTarget.ranges(of: positions, in: "ab\ncd")

        #expect(ranges == [NSRange(location: 1, length: 0), NSRange(location: 3, length: 0)])
    }
}
