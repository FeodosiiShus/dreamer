import Foundation
import Testing
@testable import Dreamder

struct CommentTextBufferTests {
    struct TextCase: Sendable, CustomStringConvertible {
        let input: String
        let expected: String

        var description: String { input }
    }

    private func makeBuffer(_ text: String) -> CommentTextBuffer {
        CommentTextBuffer(units: Array(text.utf16))
    }

    private func text(of buffer: CommentTextBuffer) -> String {
        String(decoding: buffer.units, as: UTF16.self)
    }

    private func markedBuffer(_ text: String) -> (buffer: CommentTextBuffer, marker: Int) {
        var buffer = makeBuffer(text)
        let marker = buffer.addMarker(start: 0, end: buffer.length)
        return (buffer, marker)
    }

    @Test
    func unitsOfAnNSStringAreItsUtf16CodeUnits() {
        #expect(CommentTextBuffer.units(of: NSString(string: "aé😀")) == Array("aé😀".utf16))
        #expect(CommentTextBuffer.units(of: NSString(string: "")).isEmpty)
    }

    @Test
    func skipSetsContainTheExpectedWhitespace() {
        #expect(CommentTextBuffer.spaceAndTab == [0x20, 0x09])
        #expect(CommentTextBuffer.spaceTabAndNewline == [0x20, 0x09, 0x0A])
    }

    @Test
    func lineBreaksAreLineFeedAndCarriageReturn() {
        #expect(CommentTextBuffer.isLineBreak(0x0A))
        #expect(CommentTextBuffer.isLineBreak(0x0D))
        #expect(!CommentTextBuffer.isLineBreak(0x20))
        #expect(!CommentTextBuffer.isLineBreak(0x61))
    }

    @Test
    func lengthAndUnitAccessAreBoundsChecked() {
        let buffer = makeBuffer("ab")
        #expect(buffer.length == 2)
        #expect(buffer.unit(at: 0) == 0x61)
        #expect(buffer.unit(at: 1) == 0x62)
        #expect(buffer.unit(at: 2) == nil)
        #expect(buffer.unit(at: -1) == nil)
    }

    @Test
    func instanceMatchesComparesAStringAtAnOffset() {
        let buffer = makeBuffer("xabcx")
        #expect(buffer.matches("abc", at: 1))
        #expect(!buffer.matches("abc", at: 0))
        #expect(!buffer.matches("abc", at: 3))
        #expect(!buffer.matches("abc", at: -1))
        #expect(!buffer.matches("abc", at: 9))
        #expect(buffer.matches("x", at: 4))
    }

    @Test
    func staticMatchesComparesUnitArrays() {
        let haystack = Array("ab".utf16)
        #expect(CommentTextBuffer.matches(Array("b".utf16), in: haystack, at: 1))
        #expect(!CommentTextBuffer.matches(Array("b".utf16), in: haystack, at: 0))
        #expect(CommentTextBuffer.matches([], in: haystack, at: 2))
        #expect(!CommentTextBuffer.matches([], in: haystack, at: 3))
        #expect(!CommentTextBuffer.matches([], in: haystack, at: -1))
        #expect(!CommentTextBuffer.matches(Array("abc".utf16), in: haystack, at: 0))
    }

    @Test
    func indexOfFindsTheFirstOccurrenceFromAPosition() {
        let haystack = Array("abcabc".utf16)
        let needle = Array("bc".utf16)
        #expect(CommentTextBuffer.index(of: needle, in: haystack, from: 0) == 1)
        #expect(CommentTextBuffer.index(of: needle, in: haystack, from: 1) == 1)
        #expect(CommentTextBuffer.index(of: needle, in: haystack, from: 2) == 4)
        #expect(CommentTextBuffer.index(of: needle, in: haystack, from: 5) == 6)
        #expect(CommentTextBuffer.index(of: needle, in: haystack, from: -3) == 1)
        #expect(CommentTextBuffer.index(of: Array("zz".utf16), in: haystack, from: 0) == 6)
    }

    @Test
    func indexOfAnEmptyNeedleIsTheStartPositionOrTheEnd() {
        let haystack = Array("ab".utf16)
        #expect(CommentTextBuffer.index(of: [], in: haystack, from: 1) == 1)
        #expect(CommentTextBuffer.index(of: [], in: haystack, from: 5) == 2)
    }

    @Test
    func shiftForwardSkipsTheGivenUnits() {
        let spaced = makeBuffer("  \tab")
        #expect(spaced.shiftForward(0, skipping: CommentTextBuffer.spaceAndTab) == 3)
        #expect(spaced.shiftForward(3, skipping: CommentTextBuffer.spaceAndTab) == 3)
        #expect(spaced.shiftForward(5, skipping: CommentTextBuffer.spaceAndTab) == 5)
        let lines = makeBuffer(" \n\tx")
        #expect(lines.shiftForward(0, skipping: CommentTextBuffer.spaceAndTab) == 1)
        #expect(lines.shiftForward(0, skipping: CommentTextBuffer.spaceTabAndNewline) == 3)
    }

    @Test
    func shiftBackwardSkipsTheGivenUnitsAndStopsBeforeTheStart() {
        let buffer = makeBuffer("ab  c")
        #expect(buffer.shiftBackward(3, skipping: CommentTextBuffer.spaceAndTab) == 1)
        #expect(buffer.shiftBackward(4, skipping: CommentTextBuffer.spaceAndTab) == 4)
        #expect(buffer.shiftBackward(5, skipping: CommentTextBuffer.spaceAndTab) == 5)
        #expect(buffer.shiftBackward(9, skipping: CommentTextBuffer.spaceAndTab) == 9)
        let leading = makeBuffer("  a")
        #expect(leading.shiftBackward(1, skipping: CommentTextBuffer.spaceAndTab) == -1)
        #expect(leading.shiftBackward(-1, skipping: CommentTextBuffer.spaceAndTab) == -1)
    }

    @Test
    func lineStartAndLineEndRespectBothLineBreakKinds() {
        let buffer = makeBuffer("ab\ncd\r\nef")
        let starts = [0, 2, 3, 4, 5, 6, 7, 9].map { buffer.lineStart(containing: $0) }
        #expect(starts == [0, 0, 3, 3, 3, 6, 7, 7])
        let ends = [0, 2, 3, 6, 7, 9].map { buffer.lineEnd(from: $0) }
        #expect(ends == [2, 2, 5, 6, 9, 9])
        #expect(makeBuffer("a\rb").lineStart(containing: 2) == 2)
    }

    @Test
    func isBlankAcceptsSpacesTabsAndLineBreaksOnly() {
        let buffer = makeBuffer(" \t\n\r  a ")
        #expect(buffer.isBlank(0..<6))
        #expect(!buffer.isBlank(0..<7))
        #expect(buffer.isBlank(1..<1))
        #expect(!buffer.isBlank(6..<7))
    }

    @Test
    func stringInRangeDecodesTheUnits() {
        #expect(makeBuffer("hello").string(in: 1..<4) == "ell")
        #expect(makeBuffer("hello").string(in: 2..<2) == "")
    }

    @Test
    func indentWidthExpandsTabsToFourColumnStops() {
        #expect(CommentTextBuffer.indentWidth(of: Array("".utf16)) == 0)
        #expect(CommentTextBuffer.indentWidth(of: Array("   ".utf16)) == 3)
        #expect(CommentTextBuffer.indentWidth(of: Array("\t".utf16)) == 4)
        #expect(CommentTextBuffer.indentWidth(of: Array("\t ".utf16)) == 5)
        #expect(CommentTextBuffer.indentWidth(of: Array("  \t".utf16)) == 4)
        #expect(CommentTextBuffer.indentWidth(of: Array("\t\t".utf16)) == 8)
        #expect(CommentTextBuffer.indentWidth(of: Array("   \t\t ".utf16)) == 9)
        #expect(CommentTextBuffer.indentWidth(of: Array("ab  ".utf16)[2...]) == 2)
    }

    @Test
    func minIndentPicksTheShallowestNonEmptyLine() {
        let buffer = makeBuffer("    a\n  b\n\n      c")
        #expect(buffer.minIndent(firstLineStart: 0, lastLineStart: 11) == "  ")
    }

    @Test
    func minIndentKeepsTheFirstOfEquallyWideIndents() {
        let buffer = makeBuffer("\ta\n    b")
        #expect(buffer.minIndent(firstLineStart: 0, lastLineStart: 3) == "\t")
        #expect(buffer.minIndent(firstLineStart: 3, lastLineStart: 3) == "    ")
    }

    @Test
    func minIndentWalksPastCrLfAndLoneCrLineBreaks() {
        #expect(makeBuffer("  a\r\n b").minIndent(firstLineStart: 0, lastLineStart: 5) == " ")
        #expect(makeBuffer("  a\r b").minIndent(firstLineStart: 0, lastLineStart: 4) == " ")
    }

    @Test
    func minIndentOfOnlyEmptyLinesIsNilForARange() {
        #expect(makeBuffer("\n\n").minIndent(firstLineStart: 0, lastLineStart: 1) == nil)
    }

    @Test
    func minIndentOfASingleEmptyLineLooksAtTheFollowingLines() {
        #expect(makeBuffer("\n\n  x").minIndent(firstLineStart: 0, lastLineStart: 0) == "  ")
        #expect(makeBuffer("\r\n\r\n  x").minIndent(firstLineStart: 0, lastLineStart: 0) == "  ")
    }

    @Test
    func minIndentOfAWhitespaceOnlyLastLineIsThatWhitespace() {
        #expect(makeBuffer("  ").minIndent(firstLineStart: 0, lastLineStart: 0) == "  ")
        #expect(makeBuffer("a\n  ").minIndent(firstLineStart: 0, lastLineStart: 2) == "")
    }

    @Test
    func nonGreedyMarkersExcludeInsertionsAtTheirEdges() {
        let cases: [(offset: Int, expected: Range<Int>)] = [
            (0, 4..<7), (1, 4..<7), (2, 4..<7), (3, 2..<7), (5, 2..<5), (8, 2..<5),
        ]
        for testCase in cases {
            var buffer = makeBuffer("0123456789")
            let marker = buffer.addMarker(start: 2, end: 5)
            buffer.insert("XX", at: testCase.offset)
            #expect(buffer.markerRange(marker) == testCase.expected)
        }
    }

    @Test
    func greedyMarkersIncludeInsertionsAtTheirEdges() {
        let cases: [(offset: Int, expected: Range<Int>)] = [
            (0, 4..<7), (2, 2..<7), (3, 2..<7), (5, 2..<7), (8, 2..<5),
        ]
        for testCase in cases {
            var buffer = makeBuffer("0123456789")
            let marker = buffer.addMarker(start: 2, end: 5, greedy: true)
            buffer.insert("XX", at: testCase.offset)
            #expect(buffer.markerRange(marker) == testCase.expected)
        }
    }

    @Test
    func emptyMarkersFollowInsertionsAccordingToGreediness() {
        var buffer = makeBuffer("0123456789")
        let plain = buffer.addMarker(start: 3, end: 3)
        let greedy = buffer.addMarker(start: 3, end: 3, greedy: true)
        buffer.insert("XX", at: 3)
        #expect(buffer.markerRange(plain) == 5..<5)
        #expect(buffer.markerRange(greedy) == 3..<5)
    }

    @Test
    func markersAreClampedByReplacementsAndDeletions() {
        let cases: [(range: Range<Int>, replacement: String, expected: Range<Int>)] = [
            (0..<1, "", 1..<4),
            (1..<3, "Z", 1..<4),
            (4..<8, "", 2..<4),
            (0..<10, "ab", 0..<2),
            (2..<5, "x", 2..<3),
            (2..<5, "", 2..<2),
            (6..<8, "", 2..<5),
            (1..<9, "", 1..<1),
        ]
        for testCase in cases {
            var buffer = makeBuffer("0123456789")
            let marker = buffer.addMarker(start: 2, end: 5)
            buffer.replace(testCase.range, with: testCase.replacement)
            #expect(buffer.markerRange(marker) == testCase.expected)
        }
    }

    @Test
    func deleteRemovesTheRangeAndUpdatesMarkers() {
        var buffer = makeBuffer("0123456789")
        let marker = buffer.addMarker(start: 6, end: 8)
        buffer.delete(1..<3)
        #expect(text(of: buffer) == "03456789")
        #expect(buffer.markerRange(marker) == 4..<6)
    }

    @Test
    func releasedMarkersStopTracking() {
        var buffer = makeBuffer("0123456789")
        let released = buffer.addMarker(start: 2, end: 5)
        let active = buffer.addMarker(start: 2, end: 5)
        buffer.releaseMarker(released)
        buffer.insert("XX", at: 0)
        #expect(released == 0)
        #expect(active == 1)
        #expect(buffer.markerRange(released) == 2..<5)
        #expect(buffer.markerRange(active) == 4..<7)
    }

    @Test
    func movedMarkersTakeTheNewRange() {
        var buffer = makeBuffer("0123456789")
        let marker = buffer.addMarker(start: 2, end: 5)
        buffer.moveMarker(marker, to: 7..<9)
        #expect(buffer.markerRange(marker) == 7..<9)
        buffer.insert("X", at: 0)
        #expect(buffer.markerRange(marker) == 8..<10)
    }

    @Test
    func untouchedBuffersHaveNoEdits() {
        #expect(makeBuffer("abc").edits().isEmpty)
    }

    @Test
    func insertionIsReportedAsAnEmptyRangeEdit() {
        var buffer = makeBuffer("abc")
        buffer.insert("X", at: 1)
        #expect(text(of: buffer) == "aXbc")
        #expect(buffer.edits() == [EditorTextEdit(range: NSRange(location: 1, length: 0), replacement: "X")])
    }

    @Test
    func insertionAtTheEndIsReported() {
        var buffer = makeBuffer("abc")
        buffer.insert("X", at: 3)
        #expect(buffer.edits() == [EditorTextEdit(range: NSRange(location: 3, length: 0), replacement: "X")])
    }

    @Test
    func deletionIsReportedWithTheOriginalRange() {
        var buffer = makeBuffer("abc")
        buffer.delete(1..<2)
        #expect(buffer.edits() == [EditorTextEdit(range: NSRange(location: 1, length: 1), replacement: "")])
    }

    @Test
    func replacementIsReportedWithTheOriginalRange() {
        var buffer = makeBuffer("abcd")
        buffer.replace(1..<3, with: "Z")
        #expect(buffer.edits() == [EditorTextEdit(range: NSRange(location: 1, length: 2), replacement: "Z")])
    }

    @Test
    func editsAreOrderedByPositionAndUseOriginalCoordinates() {
        var buffer = makeBuffer("abcdef")
        buffer.insert("X", at: 4)
        buffer.insert("Y", at: 1)
        #expect(
            buffer.edits() == [
                EditorTextEdit(range: NSRange(location: 1, length: 0), replacement: "Y"),
                EditorTextEdit(range: NSRange(location: 4, length: 0), replacement: "X"),
            ]
        )
    }

    @Test
    func adjacentInsertionsMergeIntoOneEdit() {
        var buffer = makeBuffer("abcd")
        buffer.insert("X", at: 2)
        buffer.insert("Y", at: 3)
        #expect(text(of: buffer) == "abXYcd")
        #expect(buffer.edits() == [EditorTextEdit(range: NSRange(location: 2, length: 0), replacement: "XY")])
    }

    @Test
    func separateDeletionsKeepOriginalCoordinates() {
        var buffer = makeBuffer("abcdef")
        buffer.delete(1..<2)
        buffer.delete(2..<3)
        #expect(text(of: buffer) == "acef")
        #expect(
            buffer.edits() == [
                EditorTextEdit(range: NSRange(location: 1, length: 1), replacement: ""),
                EditorTextEdit(range: NSRange(location: 3, length: 1), replacement: ""),
            ]
        )
    }

    @Test
    func overlappingReplacementsMergeIntoOneEdit() {
        var buffer = makeBuffer("abcdef")
        buffer.replace(1..<3, with: "XYZ")
        buffer.replace(2..<5, with: "")
        #expect(text(of: buffer) == "aXef")
        #expect(buffer.edits() == [EditorTextEdit(range: NSRange(location: 1, length: 3), replacement: "X")])
    }

    @Test
    func editsThatCancelOutAreDropped() {
        var inserted = makeBuffer("abc")
        inserted.insert("X", at: 1)
        inserted.delete(1..<2)
        #expect(text(of: inserted) == "abc")
        #expect(inserted.edits().isEmpty)

        var replaced = makeBuffer("abc")
        replaced.replace(1..<2, with: "b")
        #expect(replaced.edits().isEmpty)
    }

    @Test(arguments: [
        TextCase(input: "<!--a--b-->", expected: "<!--a&#45;&#45;b-->"),
        TextCase(input: "<!---->", expected: "<!---->"),
        TextCase(input: "<!-->-->", expected: "<!--&gt;-->"),
        TextCase(input: "<!----->", expected: "<!-- - -->"),
        TextCase(input: "<!--a--->", expected: "<!--a- -->"),
        TextCase(input: "<!---a-->", expected: "<!-- -a-->"),
        TextCase(input: "  <!--a--b-->", expected: "  <!--a&#45;&#45;b-->"),
        TextCase(input: "\n <!--a--b-->", expected: "\n <!--a&#45;&#45;b-->"),
        TextCase(input: "<!--a--b", expected: "<!--a&#45;&#45;b"),
        TextCase(input: "<!--a-->", expected: "<!--a-->"),
        TextCase(input: "x<!--y-->", expected: "x<!--y-->"),
    ])
    func escapeXmlCommentRewritesDashesAndAngleBrackets(testCase: TextCase) {
        var pair = markedBuffer(testCase.input)
        pair.buffer.escapeXmlComment(in: pair.marker)
        #expect(text(of: pair.buffer) == testCase.expected)
    }

    @Test(arguments: [
        TextCase(input: "&gt;a&#45;&#45;b", expected: ">a--b"),
        TextCase(input: "a&gt;", expected: "a&gt;"),
        TextCase(input: "&#45;&#45;&#45;&#45;", expected: "----"),
        TextCase(input: "plain", expected: "plain"),
    ])
    func unescapeXmlCommentRestoresDashesAndAngleBrackets(testCase: TextCase) {
        var pair = markedBuffer(testCase.input)
        pair.buffer.unescapeXmlComment(in: pair.marker)
        #expect(text(of: pair.buffer) == testCase.expected)
    }

    @Test
    func unescapeOnlyTouchesTheMarkerRange() {
        var buffer = makeBuffer("&#45;&#45; &#45;&#45;")
        let marker = buffer.addMarker(start: 0, end: 10)
        buffer.unescapeXmlComment(in: marker)
        #expect(text(of: buffer) == "-- &#45;&#45;")
    }

    @Test
    func processEscapingDispatchesOnTheEscapeFlag() {
        var escaping = markedBuffer("<!--a--b-->")
        escaping.buffer.processEscaping(.markup, marker: escaping.marker, escape: true)
        #expect(text(of: escaping.buffer) == "<!--a&#45;&#45;b-->")

        var unescaping = markedBuffer("&gt;a&#45;&#45;b")
        unescaping.buffer.processEscaping(.markup, marker: unescaping.marker, escape: false)
        #expect(text(of: unescaping.buffer) == ">a--b")
    }

    @Test
    func processEscapingIsANoOpForLanguagesWithoutXmlDashEscaping() {
        var escaping = markedBuffer("<!--a--b-->")
        escaping.buffer.processEscaping(.javaStyle, marker: escaping.marker, escape: true)
        #expect(text(of: escaping.buffer) == "<!--a--b-->")

        var unescaping = markedBuffer("&gt;a&#45;&#45;b")
        unescaping.buffer.processEscaping(.javaStyle, marker: unescaping.marker, escape: false)
        #expect(text(of: unescaping.buffer) == "&gt;a&#45;&#45;b")
        #expect(unescaping.buffer.edits().isEmpty)
    }

    @Test(arguments: [
        TextCase(input: "&lt;!&ndash;a&ndash;&gt;", expected: "<!--a-->"),
        TextCase(
            input: "&lt;!&ndash;a&lt;!&ndash;b&ndash;&gt;c&ndash;&gt;",
            expected: "<!--a&lt;!&ndash;b&ndash;&gt;c-->"
        ),
        TextCase(
            input: "&lt;!&ndash;a&ndash;&gt; &lt;!&ndash;b&ndash;&gt;",
            expected: "<!--a--> <!--b-->"
        ),
        TextCase(input: "a&ndash;&gt;b", expected: "a-->b"),
        TextCase(input: "&lt;!&ndash;a", expected: "<!--a"),
        TextCase(input: "plain", expected: "plain"),
    ])
    func commentNestedCommentsRestoresOnlyTheOutermostMarkers(testCase: TextCase) {
        var buffer = makeBuffer(testCase.input)
        buffer.commentNestedComments(in: 0..<buffer.length, language: .markup)
        #expect(text(of: buffer) == testCase.expected)
    }

    @Test
    func commentNestedCommentsStaysInsideTheGivenRange() {
        var buffer = makeBuffer("xx&lt;!&ndash;a&ndash;&gt;yy&lt;!&ndash;b")
        buffer.commentNestedComments(in: 2..<("xx&lt;!&ndash;a&ndash;&gt;".utf16.count), language: .markup)
        #expect(text(of: buffer) == "xx<!--a-->yy&lt;!&ndash;b")
    }
}
