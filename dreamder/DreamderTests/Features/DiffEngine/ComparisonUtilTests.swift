import Testing
import Foundation
@testable import Dreamder

private func doTestTrim(_ expected: Bool, _ string1: String, _ string2: String) {
    let result = ComparisonManager.isEquals(string1, string2, policy: .trimWhitespaces)
    #expect(result == expected, "---\n\(string1)\n---\n\(string2)\n---")
}

private func doTestLineFragment(
    _ string1: String,
    _ string2: String,
    offsets1: (Int, Int),
    offsets2: (Int, Int),
    lines1: (Int, Int),
    lines2: (Int, Int)
) throws {
    let source1 = DiffEngineTestSupport.source(string1)
    let source2 = DiffEngineTestSupport.source(string2)
    let fragments = try ComparisonManager.compareLines(source1, source2, policy: .default)
    #expect(fragments.count == 1, "Side: \(fragments.count))")
    let fragment = try #require(fragments.first)
    let context = Comment(rawValue: "\(fragment)")

    #expect(fragment.startOffset1 == offsets1.0, context)
    #expect(fragment.endOffset1 == offsets1.1, context)
    #expect(fragment.startOffset2 == offsets2.0, context)
    #expect(fragment.endOffset2 == offsets2.1, context)
    #expect(fragment.startLine1 == lines1.0, context)
    #expect(fragment.endLine1 == lines1.1, context)
    #expect(fragment.startLine2 == lines2.0, context)
    #expect(fragment.endLine2 == lines2.1, context)
}

@Suite struct ComparisonUtilTests {
    @Test func testTrimEquals() {
        doTestTrim(true, "", "")
        doTestTrim(true, "", "   ")
        doTestTrim(true, "   ", "   ")
        doTestTrim(true, "\n   ", "  \n")
        doTestTrim(true, "asd ", "asd  ")
        doTestTrim(true, "    asd", "asd")
        doTestTrim(true, "\n\n\n", "\n\n\n")
        doTestTrim(true, "\n  \n  \n ", "  \n \n\n  ")
        doTestTrim(false, "\n\n", "\n\n\n")

        doTestTrim(false, "\nasd ", "asd\n  ")
        doTestTrim(true, "\nasd \n", "\n asd\n  ")
        doTestTrim(false, "x", "y")
        doTestTrim(false, "\n", " ")

        doTestTrim(true, "\t ", "")
        doTestTrim(false, "", "\t\n \n\t")
        doTestTrim(false, "\t", "\n")

        doTestTrim(true, "x", " x")
        doTestTrim(true, "x", "x ")
        doTestTrim(false, "x\n", "x")

        doTestTrim(false, "abc", "a\nb\nc\n")
        doTestTrim(true, "\nx y x\n", "\nx y x\n")
        doTestTrim(false, "\nxyx\n", "\nx y x\n")
        doTestTrim(true, "\nx y x", "\nx y x")
        doTestTrim(false, "\nxyx", "\nx y x")
        doTestTrim(true, "x y x", "x y x")
        doTestTrim(false, "xyx", "x y x")
        doTestTrim(true, "  x y x  ", "x y x")

        doTestTrim(false, "x", "\t\n ")
        doTestTrim(false, "", " x ")
        doTestTrim(false, "", "x ")
        doTestTrim(false, "", " x")
        doTestTrim(false, "xyx", "xxx")
        doTestTrim(false, "xyx", "xYx")
    }

    @Test func testLineFragment() throws {
        try doTestLineFragment(
            "", "x",
            offsets1: (0, 0), offsets2: (0, 1),
            lines1: (0, 1), lines2: (0, 1))

        try doTestLineFragment(
            "x", "y",
            offsets1: (0, 1), offsets2: (0, 1),
            lines1: (0, 1), lines2: (0, 1))

        try doTestLineFragment(
            "x_", "y_",
            offsets1: (0, 2), offsets2: (0, 2),
            lines1: (0, 1), lines2: (0, 1))

        try doTestLineFragment(
            "x", "y_",
            offsets1: (0, 1), offsets2: (0, 2),
            lines1: (0, 1), lines2: (0, 2))

        try doTestLineFragment(
            "x", "x_",
            offsets1: (1, 1), offsets2: (2, 2),
            lines1: (1, 1), lines2: (1, 2))

        try doTestLineFragment(
            "x_y_z_", "x_Y_z_",
            offsets1: (2, 4), offsets2: (2, 4),
            lines1: (1, 2), lines2: (1, 2))

        try doTestLineFragment(
            "x_y_z_", "x_y_Z_",
            offsets1: (4, 6), offsets2: (4, 6),
            lines1: (2, 3), lines2: (2, 3))

        try doTestLineFragment(
            "x_y_z_", "x_y_Z_",
            offsets1: (4, 6), offsets2: (4, 6),
            lines1: (2, 3), lines2: (2, 3))

        try doTestLineFragment(
            "x_y_z_", "x_y_Z",
            offsets1: (4, 6), offsets2: (4, 5),
            lines1: (2, 4), lines2: (2, 3))

        try doTestLineFragment(
            "x_y_z", "x_y_Z_",
            offsets1: (4, 5), offsets2: (4, 6),
            lines1: (2, 3), lines2: (2, 4))

        try doTestLineFragment(
            " ", "_ ",
            offsets1: (0, 0), offsets2: (0, 1),
            lines1: (0, 0), lines2: (0, 1))

        try doTestLineFragment(
            " ", " _",
            offsets1: (1, 1), offsets2: (2, 2),
            lines1: (1, 1), lines2: (1, 2))
    }
}
