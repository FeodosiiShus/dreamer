import Testing
import Foundation
@testable import Dreamder

private typealias Support = DiffEngineTestSupport

private let chSmile = "\u{1F602}"
private let chGun = "\u{1F52B}"
private let chMan = "\u{1F9D2}"
private let chFace = "\u{1F92B}"

private struct Marks {
    let before: String
    let after: String

    init(_ before: String, _ after: String) {
        self.before = before
        self.after = after
    }
}

private enum WordCheckKind {
    case linesInner
    case words
}

private func check(
    _ kind: WordCheckKind,
    _ before: String,
    _ after: String,
    plainSource: Bool = false,
    marks: PolicyExpectation<Marks> = PolicyExpectation(),
    changes: PolicyExpectation<[DiffRange]> = PolicyExpectation(),
    policies: [ComparisonPolicy] = ComparisonPolicy.allCases
) throws {
    let text1 = plainSource ? before : Support.source(before)
    let text2 = plainSource ? after : Support.source(after)
    for policy in policies {
        let context = Comment(rawValue: "policy: \(policy), before: \(text1.debugDescription), after: \(text2.debugDescription)")
        let expectedMarks = marks.value(for: policy)
        let expectedChanges = changes.value(for: policy)
        #expect(expectedMarks != nil || expectedChanges != nil, context)

        if kind == .linesInner {
            let rawFragments = try ComparisonManager.compareLinesInner(text1, text2, policy: policy)
            let fragments = ComparisonManager.squash(rawFragments)
            #expect(fragments.count == 1, context)
            let fragment = try #require(fragments.first, context)
            #expect(fragment.startOffset1 == 0, context)
            #expect(fragment.startOffset2 == 0, context)
            #expect(fragment.endOffset1 == text1.utf16.count, context)
            #expect(fragment.endOffset2 == text2.utf16.count, context)
            let innerFragments = try #require(fragment.innerFragments, context)
            verify(innerFragments, text1: text1, text2: text2, marks: expectedMarks, changes: expectedChanges, context: context)
        }

        let wordFragments = try ComparisonManager.compareWords(text1, text2, policy: policy)
        verify(wordFragments, text1: text1, text2: text2, marks: expectedMarks, changes: expectedChanges, context: context)
    }
}

private func verify(
    _ fragments: [DiffFragment],
    text1: String,
    text2: String,
    marks: Marks?,
    changes: [DiffRange]?,
    context: Comment
) {
    for fragment in fragments {
        #expect(fragment.startOffset1 <= fragment.endOffset1, context)
        #expect(fragment.startOffset2 <= fragment.endOffset2, context)
        #expect(fragment.startOffset1 != fragment.endOffset1 || fragment.startOffset2 != fragment.endOffset2, context)
    }
    if let marks {
        #expect(marks.before.filter { $0 != "." }.utf16.count == text1.utf16.count, context)
        #expect(marks.after.filter { $0 != "." }.utf16.count == text2.utf16.count, context)
        #expect(Support.changedOffsets(fragments, side: .left) == Support.matchedPositions(marks.before), "Before; \(context)")
        #expect(Support.changedOffsets(fragments, side: .right) == Support.matchedPositions(marks.after), "After; \(context)")
    }
    if let changes {
        #expect(Support.offsetRanges(fragments) == changes, context)
    }
}

@Suite struct WordComparisonTests {
    @Test func simpleCases() throws {
        try check(.linesInner, "x z", "y z",
                  marks: .init(default: Marks("-  ", "-  ")))

        try check(.linesInner, "x z", "y z",
                  marks: .init(default: Marks("-  ", "-  ")))

        try check(.linesInner, " x z", "y z",
                  marks: .init(default: Marks("--  ", "-  "), trim: Marks(" -  ", "-  ")))

        try check(.linesInner, "x z ", "y z",
                  marks: .init(default: Marks("-  -", "-  "), trim: Marks("-   ", "-  ")))

        try check(.linesInner, "x z ", "y z",
                  marks: .init(default: Marks("-  -", "-  "), trim: Marks("-   ", "-  ")))

        try check(.linesInner, "x z", " y z ",
                  marks: .init(default: Marks("-  ", "--  -"), trim: Marks("-  ", " -   ")))

        try check(.linesInner, "x y", "x z ",
                  marks: .init(default: Marks("  -", "  --"), trim: Marks("  -", "  - ")))

        try check(.linesInner, "x,y", "x",
                  marks: .init(default: Marks(" --", " ")))

        try check(.linesInner, "x,y", "y",
                  marks: .init(default: Marks("-- ", " ")))

        try check(.linesInner, ".x=", ".!=",
                  marks: .init(default: Marks(" - ", " - ")))

        try check(.linesInner, "X xyz1 Z", "X xyz2 Z",
                  marks: .init(default: Marks("  ----  ", "  ----  ")))
    }

    @Test func punctuation() throws {
        try check(.linesInner, " x.z.x ", "x..x",
                  marks: .init(default: Marks("-  -  -", "    "), trim: Marks("   -   ", "    ")))

        try check(.linesInner, "x..x", " x.z.x ",
                  marks: .init(default: Marks("    ", "-  -  -"), trim: Marks("    ", "   -   ")))

        try check(.linesInner, "x ... z", "y ... z",
                  marks: .init(default: Marks("-      ", "-      ")))

        try check(.linesInner, "x ... z", "x ... y",
                  marks: .init(default: Marks("      -", "      -")))

        try check(.linesInner, "x ,... z", "x ... y",
                  marks: .init(default: Marks("  -    -", "      -")))

        try check(.linesInner, "x . , .. z", "x ... y",
                  marks: .init(default: Marks("   ---   -", "      -"), ignore: Marks("    -    -", "      -")))

        try check(.linesInner, "x==y==z", "x====z",
                  marks: .init(default: Marks("   -   ", "      ")))

        try check(.linesInner, "x====z", "x==t==z",
                  marks: .init(default: Marks("      ", "   -   ")))

        try check(.linesInner, "X Y ) {_ A B C", "X Y Z ) {_ y B C ) {",
                  marks: .init(default: Marks("         -    ", "   --      -    ----"),
                               ignore: Marks("         -    ", "    -      -     ---")))

        try check(.words, "@Deprecated @NotNull", "@NotNull",
                  marks: .init(default: Marks(" ------------       ", "        ")))

        try check(.words, "@Deprecated_ @NotNull", "@NotNull",
                  marks: .init(default: Marks(" -------------       ", "        ")))
    }

    @Test func oldDiffBug() throws {
        try check(.linesInner, "x'y'>", "x'>",
                  marks: .init(default: Marks("  -- ", "   ")))

        try check(.linesInner, "x'>", "x'y'>",
                  marks: .init(default: Marks("   ", "  -- ")))

        try check(.linesInner, "x'>", "x'y'>",
                  marks: .init(default: Marks("   ", "  -- ")))

        try check(.linesInner, "x'y'>", "x'>",
                  marks: .init(default: Marks("  -- ", "   ")))
    }

    @Test func whitespaceOnlyChanges() throws {
        try check(.linesInner, "x  =z", "x=  z",
                  marks: .init(default: Marks(" --  ", "  -- ")),
                  policies: [.default, .trimWhitespaces])

        try check(.linesInner, "x  =", "x=  z",
                  marks: .init(default: Marks(" -- ", "  ---"), ignore: Marks("    ", "    -")))
    }

    @Test func newlines() throws {
        try check(.linesInner, " x _ y _ z ", "x z",
                  marks: .init(default: Marks("- ------  -", "   "),
                               trim: Marks("     -     ", "   "),
                               ignore: Marks("     -     ", "   ")))

        try check(.linesInner, "x z", " x _ y _ z ",
                  marks: .init(default: Marks("   ", "- ------  -"),
                               trim: Marks("   ", "     -     "),
                               ignore: Marks("   ", "     -     ")))

        try check(.words, "_i", "i_",
                  marks: .init(default: Marks("- ", " -"), trim: Marks("  ", "  ")))

        try check(.words, "i_", "_i",
                  marks: .init(default: Marks("- ", " -")))

        try check(.words, "x_y", "xy",
                  marks: .init(ignore: Marks("   ", "  ")),
                  policies: [.ignoreWhitespaces])

        try check(.words, "A x_y B", "a xy b",
                  marks: .init(ignore: Marks("-------", "------")),
                  policies: [.ignoreWhitespaces])

        try check(.words, "A xy B", "a xy b",
                  marks: .init(ignore: Marks("-    -", "-    -")),
                  policies: [.ignoreWhitespaces])

        try check(.words, "A_B_", "X_",
                  marks: .init(default: Marks("--- ", "- ")))
    }

    @Test func fixedBugs() throws {
        try check(.linesInner, ".! ", ".  y!",
                  marks: .init(default: Marks("  -", " --- "),
                               trim: Marks("   ", " --- "),
                               ignore: Marks("   ", "   - ")))

        try check(.linesInner, " x n", " y_  x m",
                  marks: .init(default: Marks("   -", "----   -"),
                               trim: Marks("   -", " -     -"),
                               ignore: Marks("   -", " -     -")))

        try check(.linesInner, "x_", "x!  ",
                  marks: .init(default: Marks(" -", " ---"),
                               trim: Marks("  ", " -  "),
                               ignore: Marks("  ", " -  ")))
    }

    @Test func innerWhitespaces() throws {
        try check(.linesInner, "<< x >>", "<.<>.>",
                  marks: .init(default: Marks("  ---  ", " -  - "), ignore: Marks("   -   ", " -  - ")))

        try check(.linesInner, "<< x >>", "y<<x>>y",
                  marks: .init(default: Marks("  - -  ", "-     -"), ignore: Marks("       ", "-     -")))

        try check(.linesInner, "x .. z", "x y .. z",
                  marks: .init(default: Marks("      ", " --     "), ignore: Marks("      ", "  -     ")))

        try check(.linesInner, "  x..z", "x..y  ",
                  marks: .init(default: Marks("--   -", "   ---"), trim: Marks("     -", "   -  ")))

        try check(.linesInner, " x y x _ x z x ", "x x_x x",
                  marks: .init(default: Marks("- --  - - --  -", "       "),
                               trim: Marks("  --      --   ", "       "),
                               ignore: Marks("   -       -   ", "       ")))
    }

    @Test func algorithmSpecific() throws {
        try check(.linesInner, "...x", "x...",
                  marks: .init(default: Marks("--- ", " ---")))

        try check(.linesInner, "x x y", "x y",
                  marks: .init(default: Marks("--   ", "   "), ignore: Marks("-    ", "   ")))

        try check(.linesInner, "y x x", "y x",
                  marks: .init(default: Marks("   --", "   "), ignore: Marks("    -", "   ")))

        try check(.linesInner, "A X A B", "A B",
                  marks: .init(default: Marks("----   ", "   "), ignore: Marks("---    ", "   ")))

        try check(.linesInner, "A.X A.Z", "A.X A.Y A.Z",
                  marks: .init(default: Marks("       ", "   ----    "), ignore: Marks("       ", "    ---    ")))

        try check(.linesInner, "X.A Z.A", "X.A Y.A Z.A",
                  marks: .init(default: Marks("       ", "   ----    "), ignore: Marks("       ", "    ---    ")))

        try check(.linesInner, ".   ", "   .",
                  marks: .init(default: Marks(" ---", "--- ")),
                  policies: [.default])

        try check(.linesInner, "A B_C D", "A_B C_D",
                  marks: .init(default: Marks(" -  -- ", " - --  "),
                               trim: Marks(" -  -- ", "   --  "),
                               ignore: Marks("    -  ", "    -  ")))

        try check(.linesInner, "B_C_D_", "X_Y_Z_",
                  marks: .init(default: Marks("- - - ", "- - - ")))

        try check(.words, "!x_!_z", "!_!_y z",
                  marks: .init(default: Marks(" -    ", "    -- ")),
                  policies: [.default])
    }

    @Test func trailingPunctuation() throws {
        try check(.linesInner, "X = { };", "X = { _ };",
                  marks: .init(default: Marks("        ", "     --   "), trim: Marks("        ", "          ")))

        try check(.linesInner, "X = { };_", "X = { _ };_",
                  marks: .init(default: Marks("      -- ", "       ----"), trim: Marks("      -- ", "        -- ")))
    }

    @Test func legacyCasesFromByWordTest() throws {
        try check(.linesInner, "abc def, 123", "ab def, 12",
                  marks: .init(default: Marks("---      ---", "--      --")))

        try check(.linesInner, " a[xy]+1", ",a[]+1",
                  marks: .init(default: Marks("-  --   ", "-     "), trim: Marks("   --   ", "-     ")))

        try check(.linesInner, "0987_  a.g();_", "yyyy_",
                  marks: .init(default: Marks("------------- ", "---- ")))

        try check(.linesInner, "  abc_2222_", "    x = abc_zzzz_",
                  marks: .init(default: Marks("      ---- ", " ------     ---- "),
                               trim: Marks("      ---- ", "    ---     ---- ")))

        try check(.linesInner,
                  "   if (eventMerger!=null && !dataSelection.getValueIsAdjusting()) {",
                  "   if (eventMerger!=null && (dataSelection==null || !dataSelection.getValueIsAdjusting())) {",
                  marks: .init(default: Marks("                                                                   ",
                                              "                           ------------------------                                      -  "),
                               ignore: Marks("                                                                   ",
                                             "                            -----------------------                                      -  ")))

        try check(.linesInner,
                  "messageInsertStatement = connection.prepareStatement(\"INSERT INTO AUDIT (AUDIT_TYPE_ID, STATUS, SERVER_ID, INSTANCE_ID, REQUEST_ID) VALUES (?, ?, ?, ?, ?)\");",
                  "messageInsertStatement = connection.prepareStatement(\"INSERT INTO AUDIT (AUDIT_TYPE_ID, CREATION_TIMESTAMP, STATUS, SERVER_ID, INSTANCE_ID, REQUEST_ID) VALUES (?, ?, ?, ?, ?, ?)\");",
                  plainSource: true,
                  marks: .init(default: Marks("                                                     .                                                                                                     .   ",
                                              "                                                     .                                  --------------------                                                                  --- .   "),
                               ignore: Marks("                                                     .                                                                                                     .   ",
                                             "                                                     .                                   -------------------                                                                  --- .   ")))

        try check(.linesInner, "f(a, b);", "f(a,_  b);",
                  marks: .init(default: Marks("        ", "    --    "), trim: Marks("        ", "          ")))

        try check(.linesInner, " o.f(a)", "o. f( b)",
                  marks: .init(default: Marks("-    - ", "  -  -- "),
                               trim: Marks("     - ", "  -  -- "),
                               ignore: Marks("     - ", "      - ")))

        try check(.linesInner, " 123 ", "xyz",
                  marks: .init(trim: Marks(" --- ", "---")),
                  policies: [.trimWhitespaces])
    }

    @Test func emptyRangePositions() throws {
        try check(.linesInner, "x? y", "x y",
                  marks: .init(default: Marks(" -  ", "   ")),
                  changes: .init(default: [Support.del(1, 1, 1)]))

        try check(.linesInner, "x ?y", "x y",
                  marks: .init(default: Marks("  - ", "   ")),
                  changes: .init(default: [Support.del(2, 2, 1)]))
    }

    @Test func continuousScript() throws {
        try check(.words, "ABCD", "DABC",
                  marks: .init(default: Marks("----", "----")),
                  policies: [.default])

        try check(.words, "汉语漢語", "語汉语漢",
                  marks: .init(default: Marks("   -", "-   ")),
                  policies: [.default])

        try check(.words, "AB漢CD", "DA漢CD",
                  marks: .init(default: Marks("--   ", "--   ")),
                  policies: [.default])

        try check(.words, "AB漢CD", "DA语CD",
                  marks: .init(default: Marks("---  ", "---  ")),
                  policies: [.default])

        try check(.words, "a_c", "x_c",
                  plainSource: true,
                  marks: .init(default: Marks("---", "---")),
                  policies: [.default])

        try check(.words, "!_?", "!_+",
                  marks: .init(default: Marks("  -", "  +")),
                  policies: [.default])
    }

    @Test func highSurrogates() throws {
        try check(.words, "\(chSmile)\(chGun)\(chMan)\(chFace)", "\(chGun)\(chMan)\(chFace)\(chSmile)",
                  marks: .init(default: Marks("--      ", "      --")),
                  policies: [.default])

        try check(.words, chSmile, chGun,
                  marks: .init(default: Marks("--", "--")),
                  policies: [.default])

        try check(.words, chFace, chGun,
                  marks: .init(default: Marks("--", "--")),
                  policies: [.default])

        try check(.words, "\(chSmile) ", " \(chGun)",
                  marks: .init(default: Marks("---", "---"), trim: Marks("-- ", " --")))

        try check(.words, "\(chSmile)\(chFace) \(chMan)", " \(chGun)\(chFace)\(chMan) ",
                  marks: .init(default: Marks("--  -  ", "---    -"),
                               trim: Marks("--  -  ", " --     "),
                               ignore: Marks("--     ", " --     ")))
    }
}
