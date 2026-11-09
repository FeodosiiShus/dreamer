import AppKit
import CodeEditTextView
import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@MainActor
@Suite("LSPTextPositionConverter", .serialized, .uiGate)
struct LSPTextPositionConverterTests {
    private let text = "ab\ncdef"

    private func makeTextView(_ string: String) -> TextView {
        let textView = TextView(string: string)
        textView.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
        return textView
    }

    private func offset(_ line: Int, _ character: Int, in textView: TextView) -> Int? {
        LSPTextPositionConverter.offset(of: Position(line: line, character: character), in: textView)
    }

    @Test
    func aCharacterInsideTheLineMapsToItsOffset() {
        let textView = makeTextView(text)

        #expect(offset(0, 0, in: textView) == 0)
        #expect(offset(0, 1, in: textView) == 1)
        #expect(offset(1, 0, in: textView) == 3)
        #expect(offset(1, 2, in: textView) == 5)
    }

    @Test
    func aCharacterAtTheEndOfTheLineContentIsTheOffsetBeforeTheTerminator() {
        let textView = makeTextView(text)

        #expect(offset(0, 2, in: textView) == 2)
        #expect(offset(1, 4, in: textView) == 7)
    }

    @Test
    func aCharacterBeyondTheLineIsClampedToTheLineLengthInsteadOfSpillingIntoTheNextLine() {
        let textView = makeTextView(text)

        #expect(offset(0, 3, in: textView) == 2)
        #expect(offset(0, 5, in: textView) == 2)
        #expect(offset(0, 100, in: textView) == 2)
        #expect(offset(1, 100, in: textView) == 7)
    }

    @Test
    func aNegativeCharacterIsClampedToTheStartOfTheLine() {
        let textView = makeTextView(text)

        #expect(offset(0, -4, in: textView) == 0)
        #expect(offset(1, -1, in: textView) == 3)
    }

    @Test
    func aLineEndingInANewlineIsClampedBeforeTheTerminator() {
        let textView = makeTextView("ab\ncd\n")

        #expect(offset(0, 9, in: textView) == 2)
        #expect(offset(1, 9, in: textView) == 5)
    }

    @Test
    func aLineBeyondTheDocumentHasNoOffset() {
        let textView = makeTextView(text)

        #expect(offset(2, 0, in: textView) == nil)
        #expect(offset(99, 0, in: textView) == nil)
    }

    @Test
    func aRangeEndingBeyondItsLineKeepsToTheLineEnd() throws {
        let textView = makeTextView(text)
        let range = LSPRange(start: Position(line: 0, character: 1), end: Position(line: 0, character: 5))

        let resolved = try #require(LSPTextPositionConverter.nsRange(from: range, in: textView))

        #expect(resolved == NSRange(location: 1, length: 1))
        #expect((textView.string as NSString).substring(with: resolved) == "b")
    }

    @Test
    func aRangeAcrossLinesSpansFromTheStartToTheClampedEnd() throws {
        let textView = makeTextView(text)
        let range = LSPRange(start: Position(line: 0, character: 1), end: Position(line: 1, character: 100))

        let resolved = try #require(LSPTextPositionConverter.nsRange(from: range, in: textView))

        #expect(resolved == NSRange(location: 1, length: 6))
    }

    @Test
    func rangesThatEndBeforeTheyStartOrLeaveTheDocumentHaveNoResolution() {
        let textView = makeTextView(text)
        let reversed = LSPRange(start: Position(line: 1, character: 0), end: Position(line: 0, character: 1))
        let outside = LSPRange(start: Position(line: 0, character: 0), end: Position(line: 9, character: 0))

        #expect(LSPTextPositionConverter.nsRange(from: reversed, in: textView) == nil)
        #expect(LSPTextPositionConverter.nsRange(from: outside, in: textView) == nil)
    }
}
