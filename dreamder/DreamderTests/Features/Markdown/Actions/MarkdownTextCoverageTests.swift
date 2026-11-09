import Foundation
import Testing
@testable import Dreamder

struct MarkdownTextCoverageTests {
    @Test
    func lineRangesExcludeTheTerminator() {
        let text = MarkdownText("ab\r\ncd")

        #expect(text.lines[0].contentRange == 0..<2)
        #expect(text.lines[0].end == 4)
        #expect(text.lines[1].contentRange == 4..<6)
    }

    @Test
    func blankLinesIgnoreOnlySpacesAndTabs() {
        let text = MarkdownText(" \t\nx\n")

        #expect(text.isBlankLine(0))
        #expect(!text.isBlankLine(1))
        #expect(text.isBlankLine(2))
    }

    @Test
    func skipSpacesAndTabsStopsAtTheLimit() {
        let text = MarkdownText("  \tx")

        #expect(text.skipSpacesAndTabs(from: 0, to: 4) == 3)
        #expect(text.skipSpacesAndTabs(from: 0, to: 2) == 2)
    }

    @Test(arguments: [
        (UInt16(0x2003), true),
        (UInt16(0x2028), true),
        (UInt16(0x2029), true),
        (UInt16(0x2007), false),
        (UInt16(0x202F), false),
        (UInt16(0xD800), false),
        (UInt16(0x1C), true)
    ])
    func javaWhitespaceCoversSeparatorCategories(unit: UInt16, expected: Bool) {
        #expect(MarkdownText.isJavaWhitespace(unit) == expected)
    }

    @Test(arguments: [(UInt16(0xD800), false), (UInt16(0x0041), true), (UInt16(0x0031), true), (UInt16(0x0020), false)])
    func letterOrDigitRejectsLoneSurrogates(unit: UInt16, expected: Bool) {
        #expect(MarkdownText.isLetterOrDigit(unit) == expected)
    }

    @Test
    func newlineClassification() {
        #expect(MarkdownText.isNewline(MarkdownText.lineFeed))
        #expect(MarkdownText.isNewline(MarkdownText.carriageReturn))
        #expect(!MarkdownText.isNewline(MarkdownText.space))
    }
}
