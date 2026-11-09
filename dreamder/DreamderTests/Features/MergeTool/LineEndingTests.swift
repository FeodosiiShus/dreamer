import Testing
@testable import Dreamder

@Suite
struct LineEndingTests {
    @Test
    func rawValuesAreTheLiteralSeparators() {
        #expect(LineEnding.lineFeed.rawValue == "\n")
        #expect(LineEnding.crlf.rawValue == "\r\n")
        #expect(LineEnding.carriageReturn.rawValue == "\r")
    }

    @Test(arguments: [
        ("a\nb\n", LineEnding.lineFeed),
        ("a\r\nb\r\n", LineEnding.crlf),
        ("a\rb\r", LineEnding.carriageReturn),
        ("a\r\nb\r\nc\n", LineEnding.crlf),
        ("a\nb\nc\r\n", LineEnding.lineFeed),
        ("a\rb\rc\r\n", LineEnding.carriageReturn),
        ("a\nb\r\n", LineEnding.lineFeed),
        ("a\r\nb\r", LineEnding.crlf),
        ("\r\n", LineEnding.crlf),
        ("\n\n\r\n", LineEnding.lineFeed)
    ])
    func dominantEndingIsTheMostFrequentSeparator(text: String, expected: LineEnding) {
        #expect(LineEnding.dominant(in: text) == expected)
    }

    @Test(arguments: ["", "no line breaks at all", " "])
    func textWithoutLineBreaksHasNoDominantEnding(text: String) {
        #expect(LineEnding.dominant(in: text) == nil)
    }

    @Test(arguments: [
        ("a\n", true),
        ("a\r\n", true),
        ("a\r", true),
        ("a", false),
        ("a\nb", false),
        ("", false)
    ])
    func endsWithLineBreakLooksAtTheLastByte(text: String, expected: Bool) {
        #expect(LineEnding.endsWithLineBreak(text) == expected)
    }

    @Test(arguments: [
        (LineEnding.lineFeed, "a\r\nb\rc\nd", "a\nb\nc\nd"),
        (LineEnding.crlf, "a\nb", "a\r\nb"),
        (LineEnding.crlf, "a\r\nb", "a\r\nb"),
        (LineEnding.crlf, "a\rb\r\nc\n", "a\r\nb\r\nc\r\n"),
        (LineEnding.carriageReturn, "a\nb\r\n", "a\rb\r"),
        (LineEnding.carriageReturn, "no breaks", "no breaks"),
        (LineEnding.crlf, "", "")
    ])
    func convertingUnifiesEveryLineBreakToTheChosenEnding(ending: LineEnding, text: String, expected: String) {
        #expect(ending.converting(text) == expected)
    }

    @Test
    func normalizingLineBreaksTurnsEverySeparatorIntoLineFeeds() {
        #expect(TextDiff.normalizingLineBreaks(in: "a\r\nb\rc\nd") == "a\nb\nc\nd")
        #expect(TextDiff.normalizingLineBreaks(in: "a\nb") == "a\nb")
    }
}
