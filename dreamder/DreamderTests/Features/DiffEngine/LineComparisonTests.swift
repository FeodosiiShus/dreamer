import Testing
import Foundation
@testable import Dreamder

private struct LineDocument {
    let textLength: Int
    let lineStarts: [Int]

    init(_ text: String) {
        var starts = [0]
        var offset = 0
        for unit in text.utf16 {
            offset += 1
            if unit == 10 { starts.append(offset) }
        }
        textLength = offset
        lineStarts = starts
    }

    var lineCount: Int { lineStarts.count }

    func lineStartOffset(_ line: Int) -> Int? {
        lineStarts.indices.contains(line) ? lineStarts[line] : nil
    }

    func lineEndOffset(_ line: Int) -> Int? {
        guard lineStarts.indices.contains(line) else { return nil }
        return line + 1 < lineStarts.count ? lineStarts[line + 1] - 1 : textLength
    }
}

private func mod(_ line1: Int, _ line2: Int, _ count1: Int, _ count2: Int) -> DiffRange {
    DiffEngineTestSupport.mod(line1, line2, count1, count2)
}

private func del(_ line1: Int, _ line2: Int, _ count1: Int) -> DiffRange {
    DiffEngineTestSupport.del(line1, line2, count1)
}

private func ins(_ line1: Int, _ line2: Int, _ count2: Int) -> DiffRange {
    DiffEngineTestSupport.ins(line1, line2, count2)
}

private func checkLineOffsets(
    _ document: LineDocument,
    startLine: Int,
    endLine: Int,
    startOffset: Int,
    endOffset: Int,
    _ context: Comment
) {
    if startLine != endLine {
        #expect(document.lineStartOffset(startLine) == startOffset, context)
        if var offset = document.lineEndOffset(endLine - 1) {
            if offset < document.textLength { offset += 1 }
            #expect(offset == endOffset, context)
        } else {
            Issue.record(context)
        }
    } else {
        let offset: Int? = startLine == document.lineCount ? document.textLength : document.lineStartOffset(startLine)
        #expect(offset == startOffset, context)
        #expect(offset == endOffset, context)
    }
}

private func checkLineConsistency(_ fragments: [LineFragment], _ text1: String, _ text2: String, _ context: Comment) {
    let before = LineDocument(text1)
    let after = LineDocument(text2)
    for fragment in fragments {
        #expect(fragment.startOffset1 <= fragment.endOffset1, context)
        #expect(fragment.startOffset2 <= fragment.endOffset2, context)
        #expect(fragment.startLine1 <= fragment.endLine1, context)
        #expect(fragment.startLine2 <= fragment.endLine2, context)
        #expect(fragment.startLine1 != fragment.endLine1 || fragment.startLine2 != fragment.endLine2, context)
        #expect(fragment.startLine1 >= 0, context)
        #expect(fragment.startLine2 >= 0, context)
        #expect(fragment.endLine1 <= before.lineCount, context)
        #expect(fragment.endLine2 <= after.lineCount, context)
        checkLineOffsets(
            before,
            startLine: fragment.startLine1,
            endLine: fragment.endLine1,
            startOffset: fragment.startOffset1,
            endOffset: fragment.endOffset1,
            context
        )
        checkLineOffsets(
            after,
            startLine: fragment.startLine2,
            endLine: fragment.endLine2,
            startOffset: fragment.startOffset2,
            endOffset: fragment.endOffset2,
            context
        )
        for inner in fragment.innerFragments ?? [] {
            #expect(inner.startOffset1 <= inner.endOffset1, context)
            #expect(inner.startOffset2 <= inner.endOffset2, context)
            #expect(inner.startOffset1 != inner.endOffset1 || inner.startOffset2 != inner.endOffset2, context)
        }
    }
}

private func runLines(
    _ before: String,
    _ after: String,
    matching: PolicyExpectation<(String, String)> = PolicyExpectation(),
    changes: PolicyExpectation<[DiffRange]> = PolicyExpectation(),
    policies: [ComparisonPolicy] = ComparisonPolicy.allCases
) throws {
    let text1 = DiffEngineTestSupport.source(before)
    let text2 = DiffEngineTestSupport.source(after)
    for policy in policies {
        let context: Comment = "policy: \(policy)"
        let expectedMatching = matching.value(for: policy)
        let expectedChanges = changes.value(for: policy)
        let hasExpectation = expectedMatching != nil || expectedChanges != nil
        #expect(hasExpectation, context)

        let fragments = try ComparisonManager.compareLines(text1, text2, policy: policy)
        checkLineConsistency(fragments, text1, text2, context)

        if let expectedMatching {
            #expect(expectedMatching.0.utf16.count == text1.utf16.count, context)
            #expect(expectedMatching.1.utf16.count == text2.utf16.count, context)
            #expect(
                DiffEngineTestSupport.changedLines(fragments, side: .left) == DiffEngineTestSupport.matchedLines(expectedMatching.0),
                "Before, policy: \(policy)"
            )
            #expect(
                DiffEngineTestSupport.changedLines(fragments, side: .right) == DiffEngineTestSupport.matchedLines(expectedMatching.1),
                "After, policy: \(policy)"
            )
        }
        if let expectedChanges {
            #expect(DiffEngineTestSupport.lineRanges(fragments) == expectedChanges, context)
        }
    }
}

@Suite struct LineComparisonTests {
    @Test func equalStrings() throws {
        try runLines("", "", changes: .init(default: []))
        try runLines("x", "x", changes: .init(default: []))
        try runLines("x_y_z_", "x_y_z_", changes: .init(default: []))
        try runLines("_", "_", changes: .init(default: []))
        try runLines(" x_y ", " x_y ", changes: .init(default: []))
    }

    @Test func trivialCases() throws {
        try runLines("x_", "y_", changes: .init(default: [mod(0, 0, 1, 1)]))
        try runLines("x", "", changes: .init(default: [mod(0, 0, 1, 1)]))
        try runLines("", "x", changes: .init(default: [mod(0, 0, 1, 1)]))
        try runLines("x", "y", changes: .init(default: [mod(0, 0, 1, 1)]))
        try runLines("x_z", "y_z", changes: .init(default: [mod(0, 0, 1, 1)]))
        try runLines("z_x", "z_y", changes: .init(default: [mod(1, 1, 1, 1)]))
        try runLines("x", "x_", changes: .init(default: [ins(1, 1, 1)]))
        try runLines("x_", "x", changes: .init(default: [del(1, 1, 1)]))
    }

    @Test func simpleCases() throws {
        try runLines("x_z", "y_z", changes: .init(default: [mod(0, 0, 1, 1)]))
        try runLines("x_", "x_z", changes: .init(default: [mod(1, 1, 1, 1)]))
        try runLines("x_y", "n_m", changes: .init(default: [mod(0, 0, 2, 2)]))
        try runLines("x_y_z", "n_y_m", changes: .init(default: [mod(0, 0, 1, 1), mod(2, 2, 1, 1)]))
        try runLines("x_y_z", "n_k_y", changes: .init(default: [mod(0, 0, 1, 2), del(2, 3, 1)]))
        try runLines("x_y_z", "y", changes: .init(default: [del(0, 0, 1), del(2, 1, 1)]))
        try runLines("a_b_x", "x_m_n", changes: .init(default: [del(0, 0, 2), ins(3, 1, 2)]))
    }

    @Test func emptyLastLine() throws {
        try runLines("x_", "", changes: .init(default: [del(0, 0, 1)]))
        try runLines("", "x_", changes: .init(default: [ins(0, 0, 1)]))
        try runLines("x_", "x", changes: .init(default: [del(1, 1, 1)]))
        try runLines("x_", "x_z ", changes: .init(default: [mod(1, 1, 1, 1)]))
    }

    @Test func whitespaceOnlyChanges() throws {
        try runLines("x ", " x", changes: .init(default: [mod(0, 0, 1, 1)], trim: []))
        try runLines("x \t", "\t x", changes: .init(default: [mod(0, 0, 1, 1)], trim: []))
        try runLines("x_", "x ", changes: .init(default: [mod(0, 0, 2, 1)], trim: [del(1, 1, 1)]))
        try runLines(" x_y ", "x _ y", changes: .init(default: [mod(0, 0, 2, 2)], trim: []))
        try runLines("x y ", "x  y", changes: .init(default: [mod(0, 0, 1, 1)], ignore: []))
        try runLines(
            "x y_x y_x y",
            "  x y  _x y  _x   y",
            changes: .init(default: [mod(0, 0, 3, 3)], trim: [mod(2, 2, 1, 1)], ignore: [])
        )
    }

    @Test func algorithmSpecific() throws {
        try runLines("x_y_z_AAAAA", "AAAAA_x_y_z", changes: .init(default: [del(0, 0, 3), ins(4, 1, 3)]))
        try runLines(
            "x_y_z",
            " y_ m_ n",
            changes: .init(default: [mod(0, 0, 3, 3)], trim: [del(0, 0, 1), mod(2, 1, 1, 2)])
        )
        try runLines("}_ }", " }", changes: .init(default: [del(0, 0, 1)]), policies: [.default])
        try runLines("{_}", "{_ {_ }_}_x", changes: .init(default: [ins(1, 1, 2), ins(2, 4, 1)]), policies: [.default])
    }

    @Test func nonDeterministicCases() throws {
        try runLines("", "__", changes: .init(default: [ins(1, 1, 2)]))
        try runLines("__", "", changes: .init(default: [del(1, 1, 2)]))
    }

    @Test("test regression - shifted similar lines should be matched as a single change, not insertion-deletion")
    func regressionShiftedSimilarLinesShouldBeMatchedAsASingleChangeNotInsertionDeletion() throws {
        try runLines(
            " X_  X",
            "  X_   X",
            matching: .init(default: ("--_---", "---_----")),
            policies: [.default]
        )
    }

    @Test("test prefer chunks bounded by empty line")
    func preferChunksBoundedByEmptyLine() throws {
        try runLines(
            "A_B_o_o_Y_Z_ _A_B_z_z_Y_Z",
            "A_B_o_o_Y_Z_ _A_B_u_u_Y_Z_ _A_B_z_z_Y_Z",
            matching: .init(default: (" _ _ _ _ _ _ _ _ _ _ _ _ ", " _ _ _ _ _ _ _-_-_-_-_-_-_-_ _ _ _ _ _ "))
        )
        try runLines(
            "A_B_o_o_Y_Z_ _A_B_ _ _Y_Z",
            "A_B_o_o_Y_Z_ _A_B_u_u_Y_Z_ _A_B_ _ _Y_Z",
            matching: .init(default: (" _ _ _ _ _ _ _ _ _ _ _ _ ", " _ _ _ _ _ _ _ _ _-_-_-_-_-_-_-_ _ _ _ "))
        )
        try runLines(
            "A_B_o_o_ _A_B_z_z",
            "A_B_o_o_ _A_B_u_u_ _A_B_z_z",
            matching: .init(default: (" _ _ _ _ _ _ _ _ ", " _ _ _ _ _-_-_-_-_-_ _ _ _ "))
        )
        try runLines(
            "o_o_Y_Z_ _z_z_Y_Z",
            "o_o_Y_Z_ _u_u_Y_Z_ _z_z_Y_Z",
            matching: .init(default: (" _ _ _ _ _ _ _ _ ", " _ _ _ _ _-_-_-_-_-_ _ _ _ "))
        )
    }

    @Test("test prefer chunks bounded by short line")
    func preferChunksBoundedByShortLine() throws {
        try runLines(
            "A====_B====_o====_o====_Y====_Z====_!_A====_B====_z====_z====_Y====_Z====",
            "A====_B====_o====_o====_Y====_Z====_!_A====_B====_u====_u====_Y====_Z====_!_A====_B====_z====_z====_Y====_Z====",
            matching: .init(default: (
                "     _     _     _     _     _     _ _     _     _     _     _     _     ",
                "     _     _     _     _     _     _ _-----_-----_-----_-----_-----_-----_-_     _     _     _     _     _     "
            ))
        )
        try runLines(
            "A====_B====_o====_o====_Y====_Z====_ _A====_B====_!_!_Y====_Z====",
            "A====_B====_o====_o====_Y====_Z====_ _A====_B====_u====_u====_Y====_Z====_ _A====_B====_!_!_Y====_Z====",
            matching: .init(default: (
                "     _     _     _     _     _     _ _     _     _ _ _     _     ",
                "     _     _     _     _     _     _ _-----_-----_-----_-----_-----_-----_-_     _     _ _ _     _     "
            ))
        )
        try runLines(
            "A====_B====_o====_o====_Y====_Z====_!_A====_B====_ _ _Y====_Z====",
            "A====_B====_o====_o====_Y====_Z====_!_A====_B====_u====_u====_Y====_Z====_!_A====_B====_ _ _Y====_Z====",
            matching: .init(default: (
                "     _     _     _     _     _     _ _     _     _ _ _     _     ",
                "     _     _     _     _     _     _ _     _     _-----_-----_-----_-----_-_-----_-----_ _ _     _     "
            ))
        )
    }

    @Test("test prefer chunks bounded by empty line - using inserted content")
    func preferChunksBoundedByEmptyLineUsingInsertedContent() throws {
        try runLines(
            "e_x_A_B_z",
            "x_A_B_ _q_A_B_z",
            matching: .init(default: ("-_ _ _ _ ", " _ _ _-_-_-_-_ "))
        )
    }

    @Test("test prefer smaller amount of chunks")
    func preferSmallerAmountOfChunks() throws {
        try runLines(
            "X_A_X_Y_",
            "X_Y_",
            matching: .init(default: ("-_-_ _ _", " _ _"))
        )
        try runLines(
            " __x___y",
            "__y",
            matching: .init(default: ("-**-*__ ", "__ ")),
            changes: .init(default: [del(0, 0, 3)])
        )
        try runLines(
            "U======_X======_Y======_z======_X======_Y======_X======_U======_X======_z======",
            "U======_Y======_X======_U======_X======",
            matching: .init(default: (
                "       _-------_-------_-------_-------_       _       _       _       _-------",
                "       _       _       _       _       "
            ))
        )
    }

    @Test("test regression - can trim chunks after 'compareTwoSteps'")
    func regressionCanTrimChunksAfterCompareTwoSteps() throws {
        try runLines(
            "q__7_ 6_ 7",
            "_7",
            matching: .init(default: ("-*_ _--*--", "_ ")),
            policies: [.default]
        )
    }

    @Test("test regression - can trim chunks after 'optimizeLineChunks'")
    func regressionCanTrimChunksAfterOptimizeLineChunks() throws {
        try runLines(
            "A=====_ B=====_ }_}_B=====_",
            "A=====_ }_}_B=====_",
            matching: .init(default: ("      _-------_  _ _      _", "      _  _ _      _"))
        )
    }

    @Test("test bad cases caused by 'compareTwoStep' logic")
    func badCasesCausedByCompareTwoStepLogic() throws {
        try runLines(
            "x_!",
            "!_x_y",
            matching: .init(default: ("-_ ", " _-_-"))
        )
        try runLines(
            "!_x_y",
            "x_!",
            matching: .init(default: ("-_ _-", " _-"))
        )
        try runLines(
            "x_! ",
            "!_x_y",
            matching: .init(default: ("-_--", "-_-_-"), trim: ("-_  ", " _-_-"))
        )
        try runLines(
            "!_x_y",
            "x_! ",
            matching: .init(default: ("-_ _-", " _--"))
        )

        let text1 = DiffEngineTestSupport.source("M===_X===_Y===")
        let text2 = DiffEngineTestSupport.source(" Y===_X===_N")
        let policy = ComparisonPolicy.default
        let context: Comment = "policy: \(policy)"
        var fragments = try ComparisonManager.compareLinesInner(text1, text2, policy: policy)
        checkLineConsistency(fragments, text1, text2, context)
        fragments = ComparisonManager.processBlocks(fragments, text1: text1, text2: text2, policy: policy, squash: false, trim: false)
        checkLineConsistency(fragments, text1, text2, context)
        #expect(
            DiffEngineTestSupport.lineRanges(fragments) == [mod(0, 0, 1, 1), mod(1, 1, 1, 1), mod(2, 2, 1, 1)],
            context
        )
    }

    @Test("test bad cases caused by 'compareSmart' logic")
    func badCasesCausedByCompareSmartLogic() throws {
        try runLines(
            "A=====_ B=====_ }_}_B=====",
            "A=====_ }_}_B=====",
            matching: .init(
                default: ("      _-------_  _ _      ", "      _  _ _      "),
                trim: ("      _       _--_-_------", "      _--_-_      ")
            )
        )
        try runLines(
            "A=====_ B=====_X_ }_}_Z_B=====_",
            "A=====_ }_}_B=====_",
            matching: .init(default: ("      _-------_-_--_-_-_      _", "      _--_-_      _"))
        )
    }

    @Test("test trim changed blocks after second step correction")
    func trimChangedBlocksAfterSecondStepCorrection() throws {
        try runLines(
            "====}_==== }_Y_====}",
            "====}_Y_====}",
            matching: .init(
                default: ("     _------_ _     ", "     _ _     "),
                ignore: ("     _      _-_-----", "     _-_     ")
            )
        )
    }

    @Test("test second step correction processes all confusing lines")
    func secondStepCorrectionProcessesAllConfusingLines() throws {
        try runLines(
            "====}_==== }_Y_==== }_====}",
            "==== }_Y_==== }",
            matching: .init(default: ("-----_      _ _      _-----", "      _ _      ")),
            policies: [.default]
        )
    }

    @Test("test ignore whitespace policy does not applies two-step correction")
    func ignoreWhitespacePolicyDoesNotApplyTwoStepCorrection() throws {
        try runLines(
            "1_ _  1",
            "  1",
            matching: .init(default: ("-_-_   ", "   "), trim: (" _-_---", "   "))
        )
        try runLines(
            "  1_ _1",
            "  1",
            matching: .init(default: ("   _-_-", "   "))
        )
        try runLines(
            "X_ Y_X",
            "Y ",
            matching: .init(default: ("-_--_-", "--"), trim: ("-_  _-", "  "))
        )
    }

    @Test("test regression - second step correction should be performed if there are no ambiguous matchings")
    func regressionSecondStepCorrectionShouldBePerformedIfThereAreNoAmbiguousMatchings() throws {
        try runLines(
            "}_ }",
            " }_}",
            matching: .init(default: ("-_--", "--_-"), trim: (" _  ", "  _ "))
        )
        try runLines(
            " }_}_ }",
            "}_}_}",
            matching: .init(default: ("--_ _--", "-_ _-"), trim: ("  _ _  ", " _ _ "))
        )
        try runLines(
            "X_X __Y",
            "X__Z",
            matching: .init(default: (" _--__-", " __-"), trim: ("-_  __-", " __-"))
        )
    }

    @Test("test regression - second step with too many possible matchings")
    func regressionSecondStepWithTooManyPossibleMatchings() throws {
        try runLines(
            " X_X_X_X_X_X_X_X_X_X_X_X_X_X_X_X_X_X_X_X_X_X_X_ X",
            "X_X_X_X_X_X_X_X_X_X_X_X_X_X_X_X_X_X_X ",
            matching: .init(
                default: (
                    "--_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _-_-_-_-_-_--",
                    "-_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _--"
                ),
                trim: (
                    "  _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _-_-_-_-_--",
                    " _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _  "
                )
            )
        )
    }

    @Test("test regression - second step correction should search for matchings in its prefix")
    func regressionSecondStepCorrectionShouldSearchForMatchingsInItsPrefix() throws {
        try runLines(
            "Z_X_Z_X __Y",
            "X__Y",
            matching: .init(default: ("-_ _-_--__ ", " __ "), trim: ("-_-_-_  __ ", " __ "))
        )
        try runLines(
            "Z_X_K_Z_X __Y",
            "K _X__Y",
            matching: .init(default: ("-_-_-_-_--__ ", "--_-__ "), trim: ("-_-_ _-_  __ ", "  _ __ "))
        )
    }

    @Test("test regression - multiple similar braces nearby")
    func regressionMultipleSimilarBracesNearby() throws {
        try runLines(
            "function fn() {_  return {_    a: 1_  }_}_",
            "function fn() {_  return {_    a: 1_  };_}_",
            matching: .init(default: (
                "               _          _        _---_ _",
                "               _          _        _----_ _"
            ))
        )
        try runLines(
            "function fn() {_  return {_    a: 1_  }_}_",
            "function fn() {_  return {_    a: 1_  }_};_",
            matching: .init(default: (
                "               _          _        _   _-_",
                "               _          _        _   _--_"
            ))
        )
    }
}
