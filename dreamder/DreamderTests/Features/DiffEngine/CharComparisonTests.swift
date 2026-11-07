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

private enum CharCheckKind {
    case chars
    case charsSmart
    case charsRaw
}

private func check(
    _ kind: CharCheckKind,
    _ before: String,
    _ after: String,
    marks: PolicyExpectation<Marks> = PolicyExpectation(),
    changes: PolicyExpectation<[DiffRange]> = PolicyExpectation(),
    policies: [ComparisonPolicy] = ComparisonPolicy.allCases
) throws {
    let text1 = Support.source(before)
    let text2 = Support.source(after)
    for policy in policies {
        let context = Comment(rawValue: "policy: \(policy), before: \(text1.debugDescription), after: \(text2.debugDescription)")
        let expectedMarks = marks.value(for: policy)
        let expectedChanges = changes.value(for: policy)
        #expect(expectedMarks != nil || expectedChanges != nil, context)

        if kind == .chars || kind == .charsSmart {
            let fragments = try ComparisonManager.compareChars(text1, text2, policy: policy)
            verify(fragments, text1: text1, text2: text2, marks: expectedMarks, changes: expectedChanges, context: context)
        }
        if (kind == .chars || kind == .charsRaw) && policy == .default {
            let iterable = try ByChar.compare(Array(text1.utf16), Array(text2.utf16))
            let fragments = ByWord.convertIntoDiffFragments(iterable)
            verify(fragments, text1: text1, text2: text2, marks: expectedMarks, changes: expectedChanges, context: Comment(rawValue: "raw; \(context)"))
        }
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
        #expect(Support.changedOffsets(fragments, side: .left) == Support.matchedPositions(marks.before), Comment(rawValue: "Before; \(context)"))
        #expect(Support.changedOffsets(fragments, side: .right) == Support.matchedPositions(marks.after), Comment(rawValue: "After; \(context)"))
    }
    if let changes {
        #expect(Support.offsetRanges(fragments) == changes, context)
    }
}

@Suite struct CharComparisonTests {
    @Test func equalStrings() throws {
        try check(.chars, "", "",
                  marks: .init(default: Marks("", "")))

        try check(.chars, "x", "x",
                  marks: .init(default: Marks(" ", " ")))

        try check(.chars, "x_y_z_", "x_y_z_",
                  marks: .init(default: Marks("      ", "      ")))

        try check(.chars, "_", "_",
                  marks: .init(default: Marks(" ", " ")))

        try check(.chars, "xxx", "xxx",
                  marks: .init(default: Marks("   ", "   ")))

        try check(.chars, "xyz", "xyz",
                  marks: .init(default: Marks("   ", "   ")))

        try check(.chars, ".x!", ".x!",
                  marks: .init(default: Marks("   ", "   ")))
    }

    @Test func trivialCases() throws {
        try check(.chars, "x", "",
                  marks: .init(default: Marks("-", "")))

        try check(.chars, "", "x",
                  marks: .init(default: Marks("", "-")))

        try check(.chars, "x", "y",
                  marks: .init(default: Marks("-", "-")))

        try check(.chars, "x_", "",
                  marks: .init(default: Marks("--", ""), trim: Marks("- ", "")))

        try check(.chars, "", "x_",
                  marks: .init(default: Marks("", "--"), trim: Marks("", "- ")))

        try check(.chars, "x_", "y_",
                  marks: .init(default: Marks("- ", "- ")))

        try check(.chars, "_x", "_y",
                  marks: .init(default: Marks(" -", " -")))
    }

    @Test func simpleCases() throws {
        try check(.chars, "xyx", "xxx",
                  marks: .init(default: Marks(" - ", " - ")))

        try check(.chars, "xyyx", "xmx",
                  marks: .init(default: Marks(" -- ", " - ")))

        try check(.chars, "xyy", "yyx",
                  marks: .init(default: Marks("-  ", "  -")))

        try check(.chars, "x!!", "!!x",
                  marks: .init(default: Marks("-  ", "  -")))

        try check(.chars, "xyx", "xx",
                  marks: .init(default: Marks(" - ", "  ")))

        try check(.chars, "xx", "xyx",
                  marks: .init(default: Marks("  ", " - ")))

        try check(.chars, "!...", "...!",
                  marks: .init(default: Marks("-   ", "   -")))
    }

    @Test func whitespaceChangesOnly() throws {
        try check(.chars, " x y z ", "xyz",
                  marks: .init(default: Marks("- - - -", "   "),
                               trim: Marks("  - -  ", "   "),
                               ignore: Marks("       ", "   ")))

        try check(.chars, "xyz", " x y z ",
                  marks: .init(default: Marks("   ", "- - - -"),
                               trim: Marks("   ", "  - -  "),
                               ignore: Marks("   ", "       ")))

        try check(.chars, "x ", "x",
                  marks: .init(default: Marks(" -", " "), trim: Marks("  ", " ")))

        try check(.chars, "x", " x",
                  marks: .init(default: Marks(" ", "- "), trim: Marks(" ", "  ")))

        try check(.chars, " x ", "x",
                  marks: .init(default: Marks("- -", " "), trim: Marks("   ", " ")))

        try check(.chars, "x", " x ",
                  marks: .init(default: Marks(" ", "- -"), trim: Marks(" ", "   ")))
    }

    @Test func whitespaceChanges() throws {
        try check(.chars, " x ", "z",
                  marks: .init(default: Marks("---", "-"), trim: Marks(" - ", "-")))

        try check(.chars, "x", " z ",
                  marks: .init(default: Marks("-", "---"), trim: Marks("-", " - ")))

        try check(.chars, " x", "z\t",
                  marks: .init(default: Marks("--", "-.-"), trim: Marks(" -", "-. ")))

        try check(.chars, "x ", "\tz",
                  marks: .init(default: Marks("--", ".--"), trim: Marks("- ", ". -")))

        try check(.chars, "x y z", "xy_z",
                  marks: .init(default: Marks(" - - ", "  - "),
                               trim: Marks(" - - ", "    "),
                               ignore: Marks("     ", "    ")))

        try check(.chars, "x y \n z", "xy\nz",
                  marks: .init(default: Marks(" - -. - ", "  .  "),
                               trim: Marks(" -  .   ", "  .  "),
                               ignore: Marks("    .   ", "  .  ")))
    }

    @Test func ignoreInnerWhitespaces() throws {
        try check(.chars, "x z y", "xmn",
                  marks: .init(default: Marks(" ----", " --"), ignore: Marks("  ---", " --")))

        try check(.chars, "x y z ", "x y m ",
                  marks: .init(default: Marks("    - ", "    - ")))

        try check(.chars, "x y z", "x y m ",
                  marks: .init(default: Marks("    -", "    --"), trim: Marks("    -", "    - ")))

        try check(.chars, " x y z", " m y z",
                  marks: .init(default: Marks(" -    ", " -    ")))

        try check(.chars, "x y z", " m y z",
                  marks: .init(default: Marks("-    ", "--    "), trim: Marks("-    ", " -    ")))

        try check(.chars, "x y z", "x m z",
                  marks: .init(default: Marks("  -  ", "  -  ")))

        try check(.chars, "x y z", "x  z",
                  marks: .init(default: Marks("  -  ", "    ")))

        try check(.chars, "x  z", "x m z",
                  marks: .init(default: Marks("    ", "  -  ")))

        try check(.chars, "x  z", "x n m z",
                  marks: .init(default: Marks("    ", "  ---  ")))
    }

    @Test func emptyRangePositions() throws {
        try check(.chars, "x y", "x zy",
                  changes: .init(default: [Support.ins(2, 2, 1)]))

        try check(.chars, "x y", "xz y",
                  changes: .init(default: [Support.ins(1, 1, 1)]))

        try check(.chars, "x y z", "x  z",
                  changes: .init(default: [Support.del(2, 2, 1)]))

        try check(.chars, "x  z", "x m z",
                  changes: .init(default: [Support.ins(2, 2, 1)]))

        try check(.chars, "xyx", "xx",
                  changes: .init(default: [Support.del(1, 1, 1)]))

        try check(.chars, "xx", "xyx",
                  changes: .init(default: [Support.ins(1, 1, 1)]))

        try check(.chars, "xy", "x",
                  changes: .init(default: [Support.del(1, 1, 1)]))

        try check(.chars, "x", "xy",
                  changes: .init(default: [Support.ins(1, 1, 1)]))
    }

    @Test func algorithmSpecific() throws {
        try check(.chars, "x   y   z", "xX      Zz",
                  marks: .init(default: Marks("    -    ", " -      - "), ignore: Marks("    -    ", " -------- ")))
    }

    @Test func nonDeterministicCases() throws {
        try check(.chars, "x", "  ",
                  changes: .init(ignore: [Support.del(0, 0, 1)]),
                  policies: [.ignoreWhitespaces])

        try check(.chars, "  ", "x",
                  changes: .init(ignore: [Support.ins(0, 0, 1)]),
                  policies: [.ignoreWhitespaces])

        try check(.chars, "x .. z", "x y .. z",
                  marks: .init(default: Marks("      ", "  --    "), ignore: Marks("      ", "  -     ")),
                  changes: .init(default: [Support.ins(2, 2, 2)], ignore: [Support.ins(2, 2, 1)]))

        try check(.chars, " x _ y _ z ", "x z",
                  marks: .init(default: Marks("-  ------ -", "   "), trim: Marks("     -     ", "   ")),
                  changes: .init(default: [Support.del(0, 0, 1), Support.del(3, 2, 6), Support.del(10, 3, 1)],
                                 trim: [Support.del(5, 2, 1)]))

        try check(.chars, "x z", " x _ y _ z ",
                  marks: .init(default: Marks("   ", "-  ------ -"), trim: Marks("   ", "     -     ")),
                  changes: .init(default: [Support.ins(0, 0, 1), Support.ins(2, 3, 6), Support.ins(3, 10, 1)],
                                 trim: [Support.ins(2, 5, 1)]))
    }

    @Test func twoSteps() throws {
        try check(.charsSmart, "  a", "a  ",
                  marks: .init(default: Marks("-- ", " --")),
                  policies: [.default])

        try check(.charsRaw, "  a", "a  ",
                  marks: .init(default: Marks("  -", "-  ")),
                  policies: [.default])

        try check(.charsSmart, "bba", "abb",
                  marks: .init(default: Marks("  -", "-  ")),
                  policies: [.default])

        try check(.charsRaw, "bba", "abb",
                  marks: .init(default: Marks("  -", "-  ")),
                  policies: [.default])

        try check(.charsSmart, "\(chSmile)\(chFace) \(chMan)", " \(chGun)\(chFace)\(chMan) ",
                  marks: .init(default: Marks("--  -  ", "---    -")),
                  policies: [.default])

        try check(.charsRaw, "\(chSmile)\(chFace) \(chMan)", " \(chGun)\(chFace)\(chMan) ",
                  marks: .init(default: Marks("--   --", "---  -- ")),
                  policies: [.default])
    }

    @Test func highSurrogates() throws {
        try check(.chars, chSmile, chSmile,
                  marks: .init(default: Marks("  ", "  ")))

        try check(.chars, chSmile, chMan,
                  marks: .init(default: Marks("--", "--")))

        try check(.chars, chSmile, chGun,
                  marks: .init(default: Marks("--", "--")))

        try check(.chars, chFace, chGun,
                  marks: .init(default: Marks("--", "--")))

        try check(.chars, "\(chSmile)\(chGun)\(chMan)\(chFace)", "\(chGun)\(chMan)\(chFace)\(chSmile)",
                  marks: .init(default: Marks("--      ", "      --")))

        try check(.chars, chSmile, chGun,
                  marks: .init(default: Marks("--", "--")))

        try check(.chars, chFace, chGun,
                  marks: .init(default: Marks("--", "--")))

        try check(.chars, "\(chSmile) ", chGun,
                  marks: .init(default: Marks("---", "--"), trim: Marks("-- ", "--")))

        try check(.chars, " \(chSmile)\(chFace) \(chMan)", "\(chGun)\(chFace)\(chMan)",
                  marks: .init(default: Marks("---  -  ", "--    "),
                               trim: Marks(" --  -  ", "--    "),
                               ignore: Marks(" --     ", "--    ")))
    }
}
