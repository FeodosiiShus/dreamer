import Testing
import Foundation
@testable import Dreamder

private func range(_ start1: Int, _ end1: Int, _ start2: Int, _ end2: Int) -> DiffRange {
    DiffRange(start1, end1, start2, end2)
}

private func compareExplicitBlocks(
    _ text1: String,
    _ text2: String,
    _ ranges: [DiffRange],
    _ highlightPolicy: HighlightPolicy,
    _ ignorePolicy: IgnorePolicy
) throws -> [LineFragment] {
    let fragments = try TextDiffProvider.compare(
        text1,
        text2,
        ranges: ranges,
        ignorePolicy: ignorePolicy,
        highlightPolicy: highlightPolicy
    )
    return try #require(fragments).flatMap { $0 }
}

private func parseInnerExpected(_ inner: String) -> Set<Int> {
    var set: Set<Int> = []
    for (index, character) in inner.utf16.enumerated() where character == 0x2D {
        set.insert(index)
    }
    return set
}

private func parseInnerActual(_ fragments: [LineFragment], _ side: DiffSide) -> Set<Int> {
    var set: Set<Int> = []
    for fragment in fragments {
        if let inner = fragment.innerFragments {
            for it in inner {
                let start = side == .left ? fragment.startOffset1 + it.startOffset1 : fragment.startOffset2 + it.startOffset2
                let end = side == .left ? fragment.startOffset1 + it.endOffset1 : fragment.startOffset2 + it.endOffset2
                set.formUnion(start..<max(start, end))
            }
        } else {
            let start = side == .left ? fragment.startOffset1 : fragment.startOffset2
            let end = side == .left ? fragment.endOffset1 : fragment.endOffset2
            set.formUnion(start..<max(start, end))
        }
    }
    return set
}

private func runBlocks(
    _ input1: String,
    _ input2: String,
    inner: (String, String)? = nil,
    blocks: [DiffRange],
    expected: [DiffRange]? = nil,
    policies: [IgnorePolicy]
) throws {
    for ignorePolicy in policies {
        let context = Comment(rawValue: "policy: \(ignorePolicy), before: \(input1.debugDescription), after: \(input2.debugDescription)")
        #expect(expected != nil || inner != nil, context)
        let text1 = DiffEngineTestSupport.source(input1)
        let text2 = DiffEngineTestSupport.source(input2)

        if let expected {
            let byLine = try compareExplicitBlocks(text1, text2, blocks, .byLine, ignorePolicy)
            let byWord = try compareExplicitBlocks(text1, text2, blocks, .byWord, ignorePolicy)
            #expect(DiffEngineTestSupport.lineRanges(byLine) == expected, "BY_LINE; \(context)")
            #expect(DiffEngineTestSupport.lineRanges(byWord) == expected, "BY_WORD; \(context)")
        }

        if let inner {
            let fragments = try compareExplicitBlocks(text1, text2, blocks, .byWord, ignorePolicy)
            #expect(parseInnerActual(fragments, .left) == parseInnerExpected(inner.0), "Before; \(context)")
            #expect(parseInnerActual(fragments, .right) == parseInnerExpected(inner.1), "After; \(context)")
        }
    }
}

@Suite struct BlocksComparisonTests {
    @Test("test simple blocks")
    func simpleBlocks() throws {
        try runBlocks(
            "X_a_Y_c_Z", "X_  a__Y__ c_Z",
            blocks: [range(1, 2, 1, 3), range(3, 4, 4, 6)],
            expected: [range(1, 2, 1, 3), range(3, 4, 4, 6)],
            policies: [.default])

        try runBlocks(
            "X_a_Y_c_Z", "X_  a__Y__ c_Z",
            blocks: [range(1, 2, 1, 3), range(3, 4, 4, 6)],
            expected: [range(2, 2, 2, 3), range(3, 3, 4, 5)],
            policies: [.trimWhitespaces, .ignoreWhitespaces])

        try runBlocks(
            "X_a_Y_c_Z", "X_  a__Y__ c_Z",
            blocks: [range(1, 2, 1, 3), range(3, 4, 4, 6)],
            expected: [],
            policies: [.ignoreWhitespacesChunks])
    }

    @Test("test changes outside of blocks are ignored")
    func changesOutsideOfBlocksAreIgnored() throws {
        try runBlocks(
            "X_a_Y_c_Z", "N_  a__N__ c_N",
            blocks: [range(1, 2, 1, 3), range(3, 4, 4, 6)],
            expected: [range(1, 2, 1, 3), range(3, 4, 4, 6)],
            policies: [.default])

        try runBlocks(
            "X_X_X_a_Y_c_Z", "N_  a__N__ c_N",
            blocks: [range(5, 6, 4, 6)],
            expected: [range(5, 6, 4, 6)],
            policies: [.default])
    }

    @Test("test multiple fragments in a block")
    func multipleFragmentsInABlock() throws {
        try runBlocks(
            "X_a_b_c_Y", "X_a1_ b_c2_Y",
            blocks: [range(1, 4, 1, 4)],
            expected: [range(1, 4, 1, 4)],
            policies: [.default])

        try runBlocks(
            "X_a_b_c_Y", "X_a1_ b_c2_Y",
            blocks: [range(1, 4, 1, 4)],
            expected: [range(1, 2, 1, 2), range(3, 4, 3, 4)],
            policies: [.trimWhitespaces, .ignoreWhitespaces, .ignoreWhitespacesChunks])
    }

    @Test("test fragments respect ignore options")
    func fragmentsRespectIgnoreOptions() throws {
        try runBlocks(
            "X_a_b_c_Y", "X_a1_ b_c2_Y",
            blocks: [range(1, 4, 1, 4)],
            expected: [range(1, 4, 1, 4)],
            policies: [.default])

        try runBlocks(
            "X_Y", "X_a_c_Y",
            blocks: [range(1, 1, 1, 3)],
            expected: [range(1, 1, 1, 3)],
            policies: [.default, .trimWhitespaces, .ignoreWhitespaces, .ignoreWhitespacesChunks])

        try runBlocks(
            "X_Y", "X___Y",
            blocks: [range(1, 1, 1, 3)],
            expected: [range(1, 1, 1, 3)],
            policies: [.default, .trimWhitespaces, .ignoreWhitespaces])

        try runBlocks(
            "X_Y", "X___Y",
            blocks: [range(1, 1, 1, 3)],
            expected: [],
            policies: [.ignoreWhitespacesChunks])
    }

    @Test("test leading-trailing empty lines")
    func leadingTrailingEmptyLines() throws {
        let policies: [IgnorePolicy] = [.default, .trimWhitespaces, .ignoreWhitespaces]

        try runBlocks(
            "X_a__Y", "X__y_Y",
            blocks: [range(1, 3, 1, 3)],
            expected: [range(1, 2, 1, 1), range(3, 3, 2, 3)],
            policies: policies)

        try runBlocks(
            "X_a__", "X__y_",
            blocks: [range(1, 3, 1, 3)],
            expected: [range(1, 2, 1, 1), range(3, 3, 2, 3)],
            policies: policies)

        try runBlocks(
            "a__", "_y_",
            blocks: [range(0, 2, 0, 2)],
            expected: [range(0, 1, 0, 0), range(2, 2, 1, 2)],
            policies: policies)

        try runBlocks(
            "a__", "_y_",
            blocks: [range(0, 3, 0, 3)],
            expected: [range(0, 1, 0, 0), range(2, 2, 1, 2)],
            policies: policies)

        try runBlocks(
            "a_", "_y",
            blocks: [range(0, 2, 0, 2)],
            expected: [range(0, 1, 0, 0), range(2, 2, 1, 2)],
            policies: policies)
    }

    @Test("test inner changes")
    func innerChanges() throws {
        try runBlocks(
            "X_a_Y", "X_b_Y",
            inner: ("  -  ", "  -  "),
            blocks: [range(1, 2, 1, 2)],
            policies: [.default, .trimWhitespaces, .ignoreWhitespaces, .ignoreWhitespacesChunks])

        try runBlocks(
            "X_a_Y", "X_  a_b_Y",
            inner: ("     ", "  --  -- "),
            blocks: [range(1, 2, 1, 3)],
            policies: [.default])

        try runBlocks(
            "X_a_Y", "X_  a_b_Y",
            inner: ("     ", "      -- "),
            blocks: [range(1, 2, 1, 3)],
            expected: [range(2, 2, 2, 3)],
            policies: [.trimWhitespaces, .ignoreWhitespaces])

        try runBlocks(
            "X_a b_Y", "X_a  b_Y",
            inner: ("       ", "   -    "),
            blocks: [range(1, 2, 1, 2)],
            policies: [.default, .trimWhitespaces])

        try runBlocks(
            "X_a b_Y", "X_a  b_Y",
            inner: ("       ", "        "),
            blocks: [range(1, 2, 1, 2)],
            policies: [.ignoreWhitespaces, .ignoreWhitespacesChunks])

        try runBlocks(
            "X_a_Y_c_Z", "X_ a__Y__ c_Z",
            inner: ("         ", "  -  -  --   "),
            blocks: [range(1, 2, 1, 3), range(3, 4, 4, 6)],
            expected: [range(1, 2, 1, 3), range(3, 4, 4, 6)],
            policies: [.default])

        try runBlocks(
            "X_a_Y_c_Z", "X_ a__Y__ c_Z",
            inner: ("         ", "     -  -    "),
            blocks: [range(1, 2, 1, 3), range(3, 4, 4, 6)],
            expected: [range(2, 2, 2, 3), range(3, 3, 4, 5)],
            policies: [.trimWhitespaces])

        try runBlocks(
            "X_a_Y_c_Z", "X_ a__Y__ c_Z",
            inner: ("         ", "             "),
            blocks: [range(1, 2, 1, 3), range(3, 4, 4, 6)],
            expected: [range(2, 2, 2, 3), range(3, 3, 4, 5)],
            policies: [.ignoreWhitespaces])
    }

    @Test("test inner changes for inserted empty line")
    func innerChangesForInsertedEmptyLine() throws {
        try runBlocks(
            "X_Y", "X_ _Y",
            inner: ("   ", "  -- "),
            blocks: [range(1, 1, 1, 2)],
            policies: [.trimWhitespaces, .default])

        try runBlocks(
            "X_Y", "X_ _Y",
            inner: ("   ", "     "),
            blocks: [range(1, 1, 1, 2)],
            expected: [range(1, 1, 1, 2)],
            policies: [.ignoreWhitespaces])

        try runBlocks(
            "X_Y", "X_ _Y",
            inner: ("   ", "     "),
            blocks: [range(1, 1, 1, 2)],
            expected: [],
            policies: [.ignoreWhitespacesChunks])
    }

    @Test("test inner changes with leading-trailing empty lines")
    func innerChangesWithLeadingTrailingEmptyLines() throws {
        let policies: [IgnorePolicy] = [.default, .trimWhitespaces, .ignoreWhitespaces]

        try runBlocks(
            "X_a__Y", "X__y_Y",
            inner: ("  --  ", "   -- "),
            blocks: [range(1, 3, 1, 3)],
            expected: [range(1, 2, 1, 1), range(3, 3, 2, 3)],
            policies: policies)

        try runBlocks(
            "a__", "_y_",
            inner: ("-- ", " --"),
            blocks: [range(0, 2, 0, 2)],
            expected: [range(0, 1, 0, 0), range(2, 2, 1, 2)],
            policies: policies)
    }
}
