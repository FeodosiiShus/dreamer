import CoreGraphics
import Testing
@testable import Dreamder

@Suite
struct ErrorStripeLayoutTests {
    private typealias Segment = ErrorStripeLayout.Segment

    private func layout(
        _ marks: [ErrorStripeMark],
        lineCount: Int,
        trackHeight: CGFloat = 200,
        minimumHeight: CGFloat = ErrorStripeLayout.defaultMinimumHeight
    ) -> [Segment] {
        ErrorStripeLayout.segments(
            marks: marks,
            lineCount: lineCount,
            trackHeight: trackHeight,
            minimumHeight: minimumHeight
        )
    }

    private func error(_ line: Int) -> ErrorStripeMark { ErrorStripeMark(line: line, severity: .error) }
    private func warning(_ line: Int) -> ErrorStripeMark { ErrorStripeMark(line: line, severity: .warning) }
    private func information(_ line: Int) -> ErrorStripeMark { ErrorStripeMark(line: line, severity: .information) }
    private func hint(_ line: Int) -> ErrorStripeMark { ErrorStripeMark(line: line, severity: .hint) }

    @Test(arguments: [
        (10, [0, 5, 9], [0.0, 100.0, 180.0], 20.0),
        (100, [0, 50, 99], [0.0, 100.0, 198.0], 2.0),
        (1000, [0, 500, 999], [0.0, 100.0, 198.0], 2.0),
    ] as [(Int, [Int], [Double], Double)])
    func proportionalPositions(lineCount: Int, lines: [Int], ys: [Double], height: Double) {
        let segments = layout(lines.map(error), lineCount: lineCount)
        #expect(segments.map { Double($0.y) } == ys)
        #expect(segments.allSatisfy { Double($0.height) == height })
        #expect(segments.map(\.firstLine) == lines)
    }

    @Test
    func customMinimumHeightClampsAndStaysInsideTrack() {
        let segments = layout([error(500), error(999)], lineCount: 1000, minimumHeight: 5)
        #expect(segments.map(\.y) == [100, 195])
        #expect(segments.map(\.height) == [5, 5])
    }

    @Test
    func heightNeverExceedsTrack() {
        let segments = layout([error(0)], lineCount: 1, trackHeight: 1)
        #expect(segments == [Segment(y: 0, height: 1, severity: .error, lines: [0])])
    }

    @Test
    func adjacentMarksMerge() {
        let segments = layout([warning(26), error(25)], lineCount: 100)
        #expect(segments == [Segment(y: 50, height: 4, severity: .error, lines: [25, 26])])
        #expect(segments[0].firstLine == 25)
        #expect(segments[0].lastLine == 26)
        #expect(segments[0].maxY == 54)
    }

    @Test
    func overlappingMarksMergeAndSameLineIsDeduplicated() {
        let segments = layout([warning(3), warning(3), warning(4)], lineCount: 10)
        #expect(segments == [Segment(y: 60, height: 40, severity: .warning, lines: [3, 4])])
    }

    @Test
    func distantMarksStaySeparateAndSorted() {
        let segments = layout([information(75), error(25)], lineCount: 100)
        #expect(segments == [
            Segment(y: 50, height: 2, severity: .error, lines: [25]),
            Segment(y: 150, height: 2, severity: .information, lines: [75]),
        ])
    }

    @Test
    func mixedSeveritiesTakeTheHighest() {
        #expect(layout([information(10), warning(11)], lineCount: 100).map(\.severity) == [.warning])
        #expect(layout([information(10), warning(11), error(12)], lineCount: 100).map(\.severity) == [.error])
        #expect(layout([error(10), information(11)], lineCount: 100).map(\.severity) == [.error])
    }

    @Test
    func hintsAreNotDrawn() {
        #expect(layout([hint(5)], lineCount: 10).isEmpty)
        #expect(layout([hint(5), warning(5)], lineCount: 10).map(\.severity) == [.warning])
    }

    @Test
    func degenerateInputsYieldNothing() {
        #expect(layout([], lineCount: 10).isEmpty)
        #expect(layout([error(0)], lineCount: 0).isEmpty)
        #expect(layout([error(0)], lineCount: -4).isEmpty)
        #expect(layout([error(0)], lineCount: 10, trackHeight: 0).isEmpty)
        #expect(layout([error(0)], lineCount: 10, trackHeight: -5).isEmpty)
    }

    @Test
    func outOfRangeLinesAreClampedIntoTheDocument() {
        let segments = layout([error(-3), error(500)], lineCount: 10)
        #expect(segments.map(\.lines) == [[0], [9]])
        #expect(segments.map(\.y) == [0, 180])
    }

    @Test
    func hitOnSegmentSlopAndMiss() {
        let segments = layout([error(25), warning(75)], lineCount: 100)
        func line(_ y: CGFloat) -> Int? {
            ErrorStripeLayout.line(atY: y, trackHeight: 200, lineCount: 100, segments: segments)
        }
        #expect(line(51) == 25)
        #expect(line(47) == 25)
        #expect(line(46) == nil)
        #expect(line(55) == 25)
        #expect(line(56) == nil)
        #expect(line(100) == nil)
        #expect(line(151) == 75)
    }

    @Test
    func hitPrefersTheNearestOfTwoSegmentsWithinSlop() {
        let segments = layout([error(25), warning(27)], lineCount: 100)
        func line(_ y: CGFloat) -> Int? {
            ErrorStripeLayout.line(atY: y, trackHeight: 200, lineCount: 100, segments: segments)
        }
        #expect(line(52.5) == 25)
        #expect(line(53.5) == 27)
    }

    @Test
    func hitOnMergedSegmentPicksTheLineNearestToTheClick() {
        let segments = layout([error(3), error(4), error(5)], lineCount: 10)
        #expect(segments.count == 1)
        func line(_ y: CGFloat) -> Int? {
            ErrorStripeLayout.line(atY: y, trackHeight: 200, lineCount: 10, segments: segments)
        }
        #expect(line(65) == 3)
        #expect(line(90) == 4)
        #expect(line(119) == 5)
        #expect(line(122) == 5)
        #expect(line(125) == nil)
    }

    @Test
    func hitWithDegenerateGeometryIsNil() {
        let segments = layout([error(0)], lineCount: 10)
        #expect(ErrorStripeLayout.line(atY: 1, trackHeight: 200, lineCount: 0, segments: segments) == nil)
        #expect(ErrorStripeLayout.line(atY: 1, trackHeight: 0, lineCount: 10, segments: segments) == nil)
        #expect(ErrorStripeLayout.line(atY: 1, trackHeight: 200, lineCount: 10, segments: []) == nil)
    }

    @Test
    func emptySegmentFallsBackToLineZero() {
        let empty = Segment(y: 0, height: 1, severity: .error, lines: [])
        #expect(empty.firstLine == 0)
        #expect(empty.lastLine == 0)
    }
}
