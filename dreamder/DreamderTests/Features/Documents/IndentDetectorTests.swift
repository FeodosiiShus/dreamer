import Foundation
import Testing
@testable import Dreamder

@Suite
struct IndentDetectorTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let text: String
        let expected: DetectedIndent?

        var testDescription: String { name }
    }

    static let cases: [Case] = [
        Case(
            name: "four space blocks",
            text: "func a() {\n    let x = 1\n    if x {\n        print(x)\n    }\n}\n",
            expected: .spaces(size: 4)
        ),
        Case(
            name: "two space blocks",
            text: "a {\n  b\n  c {\n    d\n  }\n}\n",
            expected: .spaces(size: 2)
        ),
        Case(
            name: "three space blocks",
            text: "a\n   b\n   c\n   d\n",
            expected: .spaces(size: 3)
        ),
        Case(
            name: "tab blocks",
            text: "func a() {\n\tlet x = 1\n\tif x {\n\t\tprint(x)\n\t}\n}\n",
            expected: .tabs
        ),
        Case(
            name: "more tab lines than space lines",
            text: "a\n\tb\n\tc\n\td\n  e\n  f\n",
            expected: .tabs
        ),
        Case(
            name: "spaces dominate a stray tab line",
            text: "a\n    b\n    c\n    d\n    e\n    f\n    g\n    h\n    i\n    j\n\tk\n",
            expected: .spaces(size: 4)
        ),
        Case(
            name: "balanced tabs and spaces are inconclusive",
            text: "a\n    b\n    c\n    d\n    e\n\tf\n\tg\n\th\n\ti\n",
            expected: nil
        ),
        Case(
            name: "fewer than three lines",
            text: "a\n    b",
            expected: nil
        ),
        Case(
            name: "no indentation at all",
            text: "a\nb\nc\nd\n",
            expected: nil
        ),
        Case(
            name: "block comment lines are ignored",
            text: "/**\n * doc\n */\nclass A {\n    int x;\n    int y;\n}\n",
            expected: .spaces(size: 4)
        ),
        Case(
            name: "line comments are ignored",
            text: "a {\n   // odd\n    b\n    c\n}\n",
            expected: .spaces(size: 4)
        ),
        Case(
            name: "a lone slash is code",
            text: "a\n  /\n  /\n  /\n",
            expected: .spaces(size: 2)
        ),
        Case(
            name: "last line without a newline",
            text: "a\n    b/\n    c/\n    d/",
            expected: .spaces(size: 4)
        ),
        Case(
            name: "crlf line endings",
            text: "a\r\n    b\r\n    c\r\nd\r\n",
            expected: .spaces(size: 4)
        ),
        Case(
            name: "whitespace only lines are ignored",
            text: "a\n    \n\r\n    b\n    c\n",
            expected: .spaces(size: 4)
        ),
        Case(
            name: "most used indent zero falls back to the second",
            text: "a\nb\nc\nd\ne\n    f\n",
            expected: .spaces(size: 4)
        ),
        Case(
            name: "indent wider than eight is not reported",
            text: "a\n            b\n            c\n",
            expected: .spaces(size: nil)
        ),
        Case(
            name: "mixed indent sizes stay below the usage threshold",
            text: "x\n    a\n    b\n  c\n  d\ny\n",
            expected: .spaces(size: nil)
        ),
        Case(
            name: "only blank lines",
            text: "\n\n\n\n",
            expected: nil
        )
    ]

    @Test(arguments: cases)
    func detectsIndent(_ testCase: Case) {
        #expect(IndentDetector.detect(in: testCase.text) == testCase.expected)
    }

    @Test
    func filesLargerThanOneMegabyteAreNotAnalysed() {
        let line = "    value\n"
        let large = String(repeating: line, count: IndentDetector.maximumDetectableByteCount / line.utf8.count + 1)

        #expect(large.utf8.count > IndentDetector.maximumDetectableByteCount)
        #expect(IndentDetector.detect(in: large) == nil)
    }

    @Test
    func aFileExactlyAtTheLimitIsAnalysed() {
        let line = "    value\n"
        let text = String(repeating: line, count: IndentDetector.maximumDetectableByteCount / line.utf8.count)

        #expect(text.utf8.count <= IndentDetector.maximumDetectableByteCount)
        #expect(IndentDetector.detect(in: text) == .spaces(size: 4))
    }

    @Test
    func statisticsOrderByUsageThenLargerIndent() {
        var statistics = IndentUsageStatistics()
        statistics.addLineWithSpaces(indent: 0)
        statistics.addLineWithSpaces(indent: 4)
        statistics.addLineWithSpaces(indent: 4)
        statistics.addLineWithSpaces(indent: 0)
        statistics.addLineWithSpaces(indent: 2)
        statistics.addLineWithTabs()

        #expect(statistics.totalLinesWithLeadingSpaces == 3)
        #expect(statistics.totalLinesWithLeadingTabs == 1)
        #expect(
            statistics.sortedUsages == [
                IndentUsageStatistics.Usage(indent: 4, timesUsed: 2),
                IndentUsageStatistics.Usage(indent: 0, timesUsed: 2),
                IndentUsageStatistics.Usage(indent: 2, timesUsed: 1)
            ]
        )
    }

    @Test
    func statisticsResolveDedentThroughTheParentStack() {
        var statistics = IndentUsageStatistics()
        for indent in [0, 4, 8, 4, 0] {
            statistics.addLineWithSpaces(indent: indent)
        }

        #expect(
            statistics.sortedUsages == [
                IndentUsageStatistics.Usage(indent: 4, timesUsed: 3),
                IndentUsageStatistics.Usage(indent: 0, timesUsed: 2)
            ]
        )
    }

    @Test
    func positiveIndentSizeOfEmptyStatisticsIsNegative() {
        #expect(IndentDetector.positiveIndentSize(IndentUsageStatistics()) == -1)
    }

    @Test
    func positiveIndentSizeNeedsASecondSizeWhenZeroDominates() {
        var statistics = IndentUsageStatistics()
        statistics.addLineWithSpaces(indent: 0)

        #expect(IndentDetector.positiveIndentSize(statistics) == -1)
    }
}
