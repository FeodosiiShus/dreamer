import Testing
@testable import Dreamder

struct GoToLineTargetTests {
    private func parse(_ text: String, lineCount: Int = 50, currentLine: Int = 10) -> GoToLineTarget? {
        GoToLineInput.parse(text, lineCount: lineCount, currentLine: currentLine)
    }

    @Test(arguments: [
        ("7", 7, 1),
        ("7:3", 7, 3),
        ("7,3", 7, 3),
        ("7 3", 7, 3),
        ("  7  :  3  ", 7, 3),
        ("7:", 7, 1),
        ("7,", 7, 1),
        (":4", 10, 4),
        (",4", 10, 4),
        ("", 10, 1),
        ("   ", 10, 1),
        (":", 10, 1),
        ("7:0", 7, 1),
        ("007:002", 7, 2),
        ("999", 50, 1),
        ("3:99999", 3, 99999),
        ("99999999999999999999", 10, 1),
        ("5:99999999999999999999", 5, 1),
        ("\t5\n", 5, 1)
    ])
    func absoluteForms(text: String, line: Int, column: Int) {
        #expect(parse(text) == GoToLineTarget(line: line, column: column))
    }

    @Test(arguments: ["0", "0:5", "abc", "7:x", "7:3:1", "1.5", "7;3", "-", "+", "+x", "5 -3"])
    func rejectedForms(text: String) {
        #expect(parse(text) == nil)
    }

    @Test(arguments: [
        ("+3", 13),
        ("-3", 7),
        ("  +3  ", 13),
        ("+0", 10),
        ("-0", 10),
        ("+1000", 50),
        ("-1000", 1),
        ("+9223372036854775807", 50),
        ("-9223372036854775807", 1)
    ])
    func relativeForms(text: String, line: Int) {
        #expect(parse(text) == GoToLineTarget(line: line, column: 1))
    }

    @Test func relativeOverflowIsRejected() {
        #expect(parse("+99999999999999999999") == nil)
    }

    @Test func relativeNeedsDigits() {
        #expect(parse("+ 3") == nil)
        #expect(parse("+3 4") == nil)
    }

    @Test func lineCountBelowOneClampsToFirstLine() {
        #expect(parse("5", lineCount: 0) == GoToLineTarget(line: 1, column: 1))
        #expect(parse("+5", lineCount: 0, currentLine: 1) == GoToLineTarget(line: 1, column: 1))
    }

    @Test func emptyInputKeepsTheCurrentLineClamped() {
        #expect(parse("", lineCount: 3, currentLine: 8) == GoToLineTarget(line: 3, column: 1))
    }
}
