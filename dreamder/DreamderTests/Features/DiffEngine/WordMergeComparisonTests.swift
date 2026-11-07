import Testing
import Foundation
@testable import Dreamder

@Suite struct WordMergeComparisonTests {
    typealias Marks = (String, String, String)

    private func markLength(_ marks: String) -> Int {
        marks.filter { $0 != "." }.count
    }

    private func words(
        _ left: String,
        _ base: String,
        _ right: String,
        defaultMarks: Marks,
        trim: Marks? = nil,
        ignore: Marks? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let leftText = DiffEngineTestSupport.source(left)
        let baseText = DiffEngineTestSupport.source(base)
        let rightText = DiffEngineTestSupport.source(right)
        let expectation = PolicyExpectation<Marks>(default: defaultMarks, trim: trim, ignore: ignore)
        let policies: [ComparisonPolicy] = [.default, .trimWhitespaces, .ignoreWhitespaces]

        for policy in policies {
            let marks = try #require(expectation.value(for: policy), "policy: \(policy)", sourceLocation: sourceLocation)
            let ranges = try ComparisonManager.compareWords(leftText, baseText, rightText, policy: policy)

            for range in ranges {
                for side in ThreeSide.allCases {
                    #expect(range.start(side) <= range.end(side), "consistency, policy: \(policy)", sourceLocation: sourceLocation)
                }
                #expect(!range.isEmpty, "consistency, policy: \(policy)", sourceLocation: sourceLocation)
            }

            #expect(markLength(marks.0) == leftText.count, "Left marks length, policy: \(policy)", sourceLocation: sourceLocation)
            #expect(markLength(marks.1) == baseText.count, "Base marks length, policy: \(policy)", sourceLocation: sourceLocation)
            #expect(markLength(marks.2) == rightText.count, "Right marks length, policy: \(policy)", sourceLocation: sourceLocation)

            #expect(
                DiffEngineTestSupport.changedOffsets(ranges, side: .left) == DiffEngineTestSupport.matchedPositions(marks.0),
                "Left, policy: \(policy)",
                sourceLocation: sourceLocation
            )
            #expect(
                DiffEngineTestSupport.changedOffsets(ranges, side: .base) == DiffEngineTestSupport.matchedPositions(marks.1),
                "Base, policy: \(policy)",
                sourceLocation: sourceLocation
            )
            #expect(
                DiffEngineTestSupport.changedOffsets(ranges, side: .right) == DiffEngineTestSupport.matchedPositions(marks.2),
                "Right, policy: \(policy)",
                sourceLocation: sourceLocation
            )
        }
    }

    @Test func simple() throws {
        try words("", "", "", defaultMarks: ("", "", ""))

        try words("", "X", "", defaultMarks: ("", "-", ""))

        try words("X", "", "", defaultMarks: ("-", "", ""))

        try words("a b", "a b", "a b", defaultMarks: ("   ", "   ", "   "))

        try words("A b c", "a b c", "a b C", defaultMarks: ("-   -", "-   -", "-   -"))

        try words(
            "a c", "a c", "a X c",
            defaultMarks: ("   ", "   ", " --  "),
            ignore: ("   ", "   ", "  -  ")
        )

        try words(
            "a X c", "a X c", "a c",
            defaultMarks: (" --  ", " --  ", "   "),
            ignore: ("  -  ", "  -  ", "   ")
        )

        try words(
            "a X c", "a c", "a Y c",
            defaultMarks: (" --  ", "   ", " --  "),
            ignore: ("  -  ", "   ", "  -  ")
        )

        try words(
            "a c", "a X c", "a Y c",
            defaultMarks: ("   ", " --  ", " --  "),
            ignore: ("   ", "  -  ", "  -  ")
        )
    }

    @Test func newlines() throws {
        try words(
            "i", "i_", "_i",
            defaultMarks: ("-", "--", "--"),
            trim: (" ", "  ", "  ")
        )

        try words(
            "_i", "i_", "i",
            defaultMarks: ("--", "--", "-"),
            trim: ("  ", "  ", " ")
        )

        try words(
            "i", "_i", "i_",
            defaultMarks: (" ", "- ", " -"),
            trim: (" ", "  ", "  ")
        )

        try words(
            "_i", "i", "i_",
            defaultMarks: ("- ", " ", " -"),
            trim: ("  ", " ", "  ")
        )
    }
}

@Suite struct CharMergeComparisonTests {
    typealias Marks = (String, String, String)

    private func markLength(_ marks: String) -> Int {
        marks.filter { $0 != "." }.count
    }

    private func mod(
        _ line1: Int,
        _ line2: Int,
        _ line3: Int,
        _ count1: Int,
        _ count2: Int,
        _ count3: Int
    ) -> MergeRange {
        MergeRange(line1, line1 + count1, line2, line2 + count2, line3, line3 + count3)
    }

    private func chars(
        _ left: String,
        _ base: String,
        _ right: String,
        matching: Marks? = nil,
        changes: [MergeRange]? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let hasExpectation = matching != nil || changes != nil
        #expect(hasExpectation, "matching or changes required", sourceLocation: sourceLocation)

        let leftText = DiffEngineTestSupport.source(left)
        let baseText = DiffEngineTestSupport.source(base)
        let rightText = DiffEngineTestSupport.source(right)

        let leftChanges = try ByChar.compare(Array(baseText.utf16), Array(leftText.utf16))
        let rightChanges = try ByChar.compare(Array(baseText.utf16), Array(rightText.utf16))
        let ranges = try ComparisonMergeUtil.buildSimple(leftChanges, rightChanges)

        var lasts = (left: -1, base: -1, right: -1)
        for range in ranges {
            #expect(lasts.left <= range.start1 && lasts.base <= range.start2 && lasts.right <= range.start3, "ordering", sourceLocation: sourceLocation)
            #expect(range.start1 <= range.end1 && range.start2 <= range.end2 && range.start3 <= range.end3, "start <= end", sourceLocation: sourceLocation)
            #expect(!range.isEmpty, "non-empty", sourceLocation: sourceLocation)
            let squashed = range.start1 == lasts.left && range.start2 == lasts.base && range.start3 == lasts.right
            #expect(!squashed, "not squashed", sourceLocation: sourceLocation)
            lasts = (range.end1, range.end2, range.end3)
        }

        if let matching {
            #expect(markLength(matching.0) == leftText.count, "Left marks length", sourceLocation: sourceLocation)
            #expect(markLength(matching.1) == baseText.count, "Base marks length", sourceLocation: sourceLocation)
            #expect(markLength(matching.2) == rightText.count, "Right marks length", sourceLocation: sourceLocation)
            #expect(
                DiffEngineTestSupport.changedOffsets(ranges, side: .left) == DiffEngineTestSupport.matchedPositions(matching.0),
                "Left",
                sourceLocation: sourceLocation
            )
            #expect(
                DiffEngineTestSupport.changedOffsets(ranges, side: .base) == DiffEngineTestSupport.matchedPositions(matching.1),
                "Base",
                sourceLocation: sourceLocation
            )
            #expect(
                DiffEngineTestSupport.changedOffsets(ranges, side: .right) == DiffEngineTestSupport.matchedPositions(matching.2),
                "Right",
                sourceLocation: sourceLocation
            )
        }
        if let changes {
            #expect(ranges == changes, sourceLocation: sourceLocation)
        }
    }

    @Test func simpleCases() throws {
        try chars("", "", "", matching: ("", "", ""), changes: [])

        try chars("xyz", "xyz", "xyz", matching: ("   ", "   ", "   "), changes: [])

        try chars("", "", "x", matching: ("", "", "-"), changes: [mod(0, 0, 0, 0, 0, 1)])

        try chars("x", "yx", "x", matching: (" ", "- ", " "))

        try chars("x", "xy", "x", matching: (" ", " -", " "))

        try chars("xyz", "xYz", "xyz", matching: (" - ", " - ", " - "))

        try chars("xyz", "XyZ", "xyz", matching: ("- -", "- -", "- -"))
    }

    @Test func conflictTYpes() throws {
        try chars("abcd", "abcd", "abXcd", matching: ("    ", "    ", "  -  "))

        try chars("abXcd", "abcd", "abXcd", matching: ("  -  ", "    ", "  -  "))

        try chars("abcd", "abXcd", "abXcd", matching: ("    ", "  -  ", "  -  "))

        try chars("abcd", "abXcd", "abcd", matching: ("    ", "  -  ", "    "))

        try chars("abcd", "abXcd", "abYcd", matching: ("    ", "  -  ", "  -  "))

        try chars("abXcd", "abXcd", "abYcd", matching: ("  -  ", "  -  ", "  -  "))

        try chars("abYcd", "abXcd", "abYcd", matching: ("  -  ", "  -  ", "  -  "))

        try chars("abYcd", "abXcd", "abZcd", matching: ("  -  ", "  -  ", "  -  "))

        try chars("abXcd", "abcd", "abYcd", matching: ("  -  ", "    ", "  -  "))
    }

    @Test func boundaryConflicts() throws {
        try chars("abcd", "abcd", "abcdx", matching: ("    ", "    ", "    -"))

        try chars("abcd", "abcdx", "abcdx", matching: ("    ", "    -", "    -"))

        try chars("abcd", "abcdx", "abcdy", matching: ("    ", "    -", "    -"))

        try chars("abcdz", "abcdx", "abcdy", matching: ("    -", "    -", "    -"))

        try chars("xabcd", "abcd", "abcd", matching: ("-    ", "    ", "    "))

        try chars("xabcd", "yabcd", "abcd", matching: ("-    ", "-    ", "    "))

        try chars("abcd", "yabcd", "abcd", matching: ("    ", "-    ", "    "))
    }

    @Test func multipleChanges() throws {
        try chars("XXbXcXXeX", "XyXzXXnXkX", "XqXXeXrXX", matching: ("  - -  - ", " - -  - - ", " -  - -  "))

        try chars("Ax", "z", "zA", matching: ("--", "-", "--"))

        try chars("ayz", "xyz", "xyq", matching: ("- -", "- -", "- -"))
    }
}
