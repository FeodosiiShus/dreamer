import Foundation
import Testing
@testable import Dreamder

@Suite
struct IndentGuideLineContentTests {
    private let text = "    foo\r\n  bar\nbaz\rlast" as NSString

    @Test
    func stripsCRLFTerminator() {
        let content = IndentGuideOverlayView.lineContent(in: NSRange(location: 0, length: 9), text: text)

        #expect(content == "    foo")
    }

    @Test
    func stripsLFTerminator() {
        let content = IndentGuideOverlayView.lineContent(in: NSRange(location: 9, length: 6), text: text)

        #expect(content == "  bar")
    }

    @Test
    func stripsCRTerminator() {
        let content = IndentGuideOverlayView.lineContent(in: NSRange(location: 15, length: 4), text: text)

        #expect(content == "baz")
    }

    @Test
    func keepsLineWithoutTerminator() {
        let content = IndentGuideOverlayView.lineContent(in: NSRange(location: 19, length: 4), text: text)

        #expect(content == "last")
    }

    @Test
    func terminatorOnlyLineIsEmpty() {
        let lf = IndentGuideOverlayView.lineContent(in: NSRange(location: 0, length: 1), text: "\nx" as NSString)
        let crlf = IndentGuideOverlayView.lineContent(in: NSRange(location: 0, length: 2), text: "\r\nx" as NSString)

        #expect(lf.isEmpty)
        #expect(crlf.isEmpty)
    }

    @Test
    func emptyRangeIsEmpty() {
        let content = IndentGuideOverlayView.lineContent(in: NSRange(location: 4, length: 0), text: text)

        #expect(content.isEmpty)
    }

    @Test(arguments: [
        NSRange(location: 20, length: 10),
        NSRange(location: 100, length: 1),
        NSRange(location: -1, length: 3),
        NSRange(location: 0, length: -2),
        NSRange(location: NSNotFound, length: 5),
        NSRange(location: 5, length: Int.max)
    ])
    func rangesOutsideTheTextAreEmptyInsteadOfTrapping(range: NSRange) {
        let content = IndentGuideOverlayView.lineContent(in: range, text: text)

        #expect(content.isEmpty)
    }

    @Test
    func lastCharacterOfTheTextIsReachable() {
        let content = IndentGuideOverlayView.lineContent(in: NSRange(location: 22, length: 1), text: text)

        #expect(content == "t")
    }
}
