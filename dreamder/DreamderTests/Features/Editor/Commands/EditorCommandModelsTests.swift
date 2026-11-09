import Foundation
import Testing
@testable import Dreamder

struct EditorCommandModelsTests {
    private let mixed = EditorLineIndex(NSString(string: "a\nbb\r\nccc\rd"))

    @Test
    func linesSplitOnEveryTerminatorKind() {
        #expect(mixed.count == 4)
        #expect(mixed.length == 11)
        #expect(mixed.lines[0] == EditorLine(index: 0, start: 0, contentEnd: 1, end: 2))
        #expect(mixed.lines[1] == EditorLine(index: 1, start: 2, contentEnd: 4, end: 6))
        #expect(mixed.lines[2] == EditorLine(index: 2, start: 6, contentEnd: 9, end: 10))
        #expect(mixed.lines[3] == EditorLine(index: 3, start: 10, contentEnd: 11, end: 11))
    }

    @Test
    func lineGeometryDescribesContentAndTerminator() {
        let line = mixed.lines[1]
        #expect(line.contentRange == NSRange(location: 2, length: 2))
        #expect(line.fullRange == NSRange(location: 2, length: 4))
        #expect(line.contentLength == 2)
        #expect(line.hasTerminator)
        #expect(!mixed.lines[3].hasTerminator)
    }

    @Test
    func trailingTerminatorLeavesAnEmptyLastLine() {
        let index = EditorLineIndex(NSString(string: "a\n"))
        #expect(index.count == 2)
        #expect(index.lines[1] == EditorLine(index: 1, start: 2, contentEnd: 2, end: 2))
    }

    @Test
    func emptyTextHasOneEmptyLine() {
        let index = EditorLineIndex(NSString(string: ""))
        #expect(index.count == 1)
        #expect(index.lines[0].contentLength == 0)
    }

    @Test
    func lineLookupClampsOffsets() {
        #expect(mixed.lineIndex(containing: 1) == 0)
        #expect(mixed.lineIndex(containing: 2) == 1)
        #expect(mixed.lineIndex(containing: 5) == 1)
        #expect(mixed.lineIndex(containing: 6) == 2)
        #expect(mixed.lineIndex(containing: 10) == 3)
        #expect(mixed.lineIndex(containing: 11) == 3)
        #expect(mixed.lineIndex(containing: -4) == 0)
        #expect(mixed.lineIndex(containing: 99) == 3)
        #expect(mixed.line(containing: 7) == mixed.lines[2])
    }

    @Test
    func touchedLinesExcludeALineOnlyTouchedAtItsStart() {
        #expect(mixed.touchedLines(by: NSRange(location: 7, length: 0)) == 2...2)
        #expect(mixed.touchedLines(by: NSRange(location: 0, length: 2)) == 0...0)
        #expect(mixed.touchedLines(by: NSRange(location: 1, length: 6)) == 0...2)
        #expect(mixed.touchedLines(by: NSRange(location: 2, length: 4)) == 1...1)
        #expect(mixed.touchedLines(by: NSRange(location: 6, length: 0)) == 2...2)
    }

    @Test
    func touchedLineBlocksMergeOverlapsAndOptionallyAdjacentLines() {
        let carets = [NSRange(location: 10, length: 0), NSRange(location: 0, length: 0), NSRange(location: 2, length: 0)]
        #expect(mixed.touchedLineBlocks(by: carets, mergingAdjacent: false) == [0...0, 1...1, 3...3])
        #expect(mixed.touchedLineBlocks(by: carets, mergingAdjacent: true) == [0...1, 3...3])
        let overlapping = [NSRange(location: 1, length: 6), NSRange(location: 6, length: 0)]
        #expect(mixed.touchedLineBlocks(by: overlapping, mergingAdjacent: false) == [0...2])
    }

    @Test
    func rangesAndColumnsFollowLineBoundaries() {
        #expect(mixed.fullRange(of: 0...1) == NSRange(location: 0, length: 6))
        #expect(mixed.column(of: 8) == 2)
    }

    @Test
    func resultDeltaSumsEveryEdit() {
        let result = EditorCommandResult(
            edits: [
                EditorTextEdit(range: NSRange(location: 0, length: 3), replacement: "x"),
                EditorTextEdit(range: NSRange(location: 9, length: 0), replacement: "yz")
            ],
            selections: []
        )
        #expect(result.resultingLengthDelta == 0)
    }
}
