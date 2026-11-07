import Testing
import Foundation
@testable import Dreamder

private func mod(_ line1: Int, _ line2: Int, _ count1: Int, _ count2: Int) -> DiffRange {
    DiffEngineTestSupport.mod(line1, line2, count1, count2)
}

private func del(_ line1: Int, _ line2: Int, _ count1: Int) -> DiffRange {
    DiffEngineTestSupport.del(line1, line2, count1)
}

private func ins(_ line1: Int, _ line2: Int, _ count2: Int) -> DiffRange {
    DiffEngineTestSupport.ins(line1, line2, count2)
}

private func parseText(_ input: String) -> String {
    input.replacingOccurrences(of: "_", with: "\n")
}

private func marked(_ marks: String, _ marker: Character) -> [Int] {
    var result: [Int] = []
    for (index, character) in marks.utf16.enumerated() where character == marker.utf16.first {
        result.append(index)
    }
    return result
}

private func parseIgnored(_ ignored: String, _ context: Comment) -> [Range<Int>] {
    #expect(ignored.utf16.allSatisfy { $0 == 0x20 || $0 == 0x2B }, context)
    return marked(ignored, "+").map { $0..<($0 + 1) }
}

private func parseExpected(_ result: String, _ context: Comment) -> Set<Int> {
    #expect(result.utf16.allSatisfy { $0 == 0x20 || $0 == 0x2D }, context)
    return Set(marked(result, "-"))
}

private func parseActual(_ result: [LineFragment]) -> (Set<Int>, Set<Int>) {
    var set1: Set<Int> = []
    var set2: Set<Int> = []
    for fragment in result {
        if let inner = fragment.innerFragments {
            for it in inner {
                set1.formUnion((fragment.startOffset1 + it.startOffset1)..<max(fragment.startOffset1 + it.startOffset1, fragment.startOffset1 + it.endOffset1))
                set2.formUnion((fragment.startOffset2 + it.startOffset2)..<max(fragment.startOffset2 + it.startOffset2, fragment.startOffset2 + it.endOffset2))
            }
        } else {
            set1.formUnion(fragment.startOffset1..<max(fragment.startOffset1, fragment.endOffset1))
            set2.formUnion(fragment.startOffset2..<max(fragment.startOffset2, fragment.endOffset2))
        }
    }
    return (set1, set2)
}

private func countChangedLines(_ result: [LineFragment]) -> (Int, Int) {
    var count1 = 0
    var count2 = 0
    for fragment in result {
        count1 += fragment.endLine1 - fragment.startLine1
        count2 += fragment.endLine2 - fragment.startLine2
    }
    return (count1, count2)
}

private func runIgnore(
    _ input1: String,
    _ input2: String,
    _ ignored1: String,
    _ ignored2: String,
    _ result1: String,
    _ result2: String,
    noInnerChanges: Bool = false,
    changedLinesNumber: (Int, Int)? = nil,
    ranged: DiffRange? = nil,
    changedLines: [DiffRange]? = nil
) throws {
    let context = Comment(rawValue: "before: \(input1.debugDescription), after: \(input2.debugDescription)")
    let ignoredMarks1 = ignored1.filter { $0 != "." }
    let ignoredMarks2 = ignored2.filter { $0 != "." }
    let resultMarks1 = result1.filter { $0 != "." }
    let resultMarks2 = result2.filter { $0 != "." }

    #expect(input1.utf16.count == ignoredMarks1.utf16.count, context)
    #expect(input1.utf16.count == resultMarks1.utf16.count, context)
    #expect(input2.utf16.count == ignoredMarks2.utf16.count, context)
    #expect(input2.utf16.count == resultMarks2.utf16.count, context)

    let text1 = Array(parseText(input1).utf16)
    let text2 = Array(parseText(input2).utf16)

    let ignored1Set = ComparisonManager.collectIgnoredRanges(parseIgnored(ignoredMarks1, context))
    let ignored2Set = ComparisonManager.collectIgnoredRanges(parseIgnored(ignoredMarks2, context))

    let lineOffsets1 = LineOffsets(text: text1)
    let lineOffsets2 = LineOffsets(text: text2)
    let innerPolicy: InnerFragmentsPolicy = noInnerChanges ? .none : .words

    let result: [LineFragment]
    if let ranged {
        result = try ComparisonManager.compareLinesWithIgnoredRanges(
            boundary: ranged,
            text1,
            text2,
            lineOffsets1,
            lineOffsets2,
            ignored1Set,
            ignored2Set,
            innerPolicy
        )
    } else {
        result = try ComparisonManager.compareLinesWithIgnoredRanges(
            text1,
            text2,
            lineOffsets1,
            lineOffsets2,
            ignored1Set,
            ignored2Set,
            innerPolicy
        )
    }

    let expected = (parseExpected(resultMarks1, context), parseExpected(resultMarks2, context))
    let actual = parseActual(result)
    #expect(actual.0 == expected.0, "Before; \(context)")
    #expect(actual.1 == expected.1, "After; \(context)")

    if let changedLinesNumber {
        let actualLines = countChangedLines(result)
        #expect(actualLines.0 == changedLinesNumber.0, "Before lines; \(context)")
        #expect(actualLines.1 == changedLinesNumber.1, "After lines; \(context)")
    }

    if let changedLines {
        #expect(DiffEngineTestSupport.lineRanges(result) == changedLines, context)
    }
}

@Suite struct IgnoreComparisonTests {
    @Test func testSimple() throws {
        try runIgnore(
            "", "",
            "", "",
            "", "")

        try runIgnore(
            "X", "Y",
            " ", " ",
            "-", "-")

        try runIgnore(
            "X", "Y",
            "+", " ",
            " ", "-")

        try runIgnore(
            "X", "Y",
            " ", "+",
            "-", " ")

        try runIgnore(
            "X", "Y",
            "+", "+",
            " ", " ")

        try runIgnore(
            "X", "",
            " ", "",
            "-", "")

        try runIgnore(
            "X", "",
            "+", "",
            " ", "")

        try runIgnore(
            "", "Y",
            "", "+",
            "", " ")
    }

    @Test func testSpaces() throws {
        try runIgnore(
            "X Y Z", "A B Z",
            "++   ", "++   ",
            "  -  ", "  -  ")

        try runIgnore(
            "X Y Z", "A B Z",
            "   ++", "   ++",
            "---  ", "---  ")

        try runIgnore(
            "X Y Z", "A Y C",
            "++   ", "++   ",
            "    -", "    -")

        try runIgnore(
            "X Y Z", "A Y C",
            "+++++", "+++++",
            "     ", "     ")

        try runIgnore(
            "X Y Z", "A B C",
            "+   +", "+   +",
            "-----", "-----")

        try runIgnore(
            "A Y C", "A B C",
            "+   +", "+   +",
            "  -  ", "  -  ")

        try runIgnore(
            "A  B", "A B",
            " ++ ", " + ",
            "    ", "   ")

        try runIgnore(
            "A  B", "A X",
            " ++ ", " + ",
            "   -", "  -")

        try runIgnore(
            " A  B", "X B ",
            "+ ++ ", " + +",
            " -   ", "-   ")

        try runIgnore(
            "A   B", "A B",
            "  +  ", "   ",
            " -   ", "   ")

        try runIgnore(
            "A   B", "A B",
            "   + ", "   ",
            " --  ", "   ")
    }

    @Test func testTrim() throws {
        try runIgnore(
            "A B_", "",
            "    ", "",
            "----", "")

        try runIgnore(
            "A B_", "",
            "++++", "",
            "    ", "")

        try runIgnore(
            "A B_", "",
            "   +", "",
            "----", "")

        try runIgnore(
            "A B_", "",
            "+++ ", "",
            "----", "")

        try runIgnore(
            "A B_", "",
            "+  +", "",
            "----", "")

        try runIgnore(
            "A B_", "",
            "+ ++", "",
            "----", "")

        try runIgnore(
            "A B_", "",
            " +++", "",
            "----", "")

        try runIgnore(
            "A_B_C_", "",
            " +++++", "",
            "--    ", "")

        try runIgnore(
            "A_B_C_", "",
            "++++ +", "",
            "    --", "")
    }

    @Test func testLines() throws {
        try runIgnore(
            "X_", "X_Y_",
            "  ", "    ",
            "  ", "  --",
            changedLinesNumber: (0, 1))

        try runIgnore(
            "X_", "X_Y_",
            "  ", "  ++",
            "  ", "    ")

        try runIgnore(
            "X_", "X_Y_",
            "  ", "++  ",
            "- ", "  - ",
            changedLines: [mod(0, 1, 1, 1)])

        try runIgnore(
            "X_Y_", "X_",
            "    ", "  ",
            "  --", "  ")

        try runIgnore(
            "X_Y_", "X_",
            "  ++", "  ",
            "    ", "  ")

        try runIgnore(
            "X_Y_Z", "X_B_Z",
            "     ", "     ",
            "  -  ", "  -  ",
            changedLinesNumber: (1, 1))

        try runIgnore(
            "X_Y_Z", "X_Y_Z",
            "     ", "     ",
            "     ", "     ")

        try runIgnore(
            "X_Y_Z", "X_Y_Z",
            " + + ", " + + ",
            "     ", "     ")

        try runIgnore(
            "X_Y_Z", "A_Y_Z",
            "     ", "     ",
            "-    ", "-    ")

        try runIgnore(
            "X_Y_Z", "A_Y_Z",
            "++   ", "     ",
            "     ", "--   ",
            changedLines: [ins(1, 0, 1)])

        try runIgnore(
            "X_Y_Z", "A_Y_Z",
            "++   ", "++   ",
            "     ", "     ")

        try runIgnore(
            "X_Y_Z", "A_Y_Z",
            "     ", " ++  ",
            "-    ", "-    ")

        try runIgnore(
            "X_Y_Z", "X_Y_C",
            "     ", "     ",
            "    -", "    -")

        try runIgnore(
            "X_Y_Z", "X_Y_C",
            "     ", "    +",
            "    -", "     ")

        try runIgnore(
            "X_Y_Z", "X_Y_C",
            "    +", "     ",
            "     ", "    -")

        try runIgnore(
            "X_Y_Z", "X_B_Z",
            "     ", "     ",
            "  -  ", "  -  ")

        try runIgnore(
            "X_Y_Z", "X_B_Z",
            "  +  ", "  +  ",
            "     ", "     ")

        try runIgnore(
            "X_Y_Z", "X_B_Z",
            "  +  ", "     ",
            "     ", "  -  ")

        try runIgnore(
            "X_Y_Z", "X_B_Z",
            "  +  ", "     ",
            "     ", "  -  ")
    }

    @Test func testTrimLines() throws {
        try runIgnore(
            "X_W_Y_W_Z", "X_B_Z",
            " +++ +++ ", " + + ",
            "    -    ", "  -  ",
            changedLinesNumber: (1, 1))

        try runIgnore(
            "X_W_W_Z", "X_Z",
            " +++++ ", " + ",
            "       ", "   ",
            changedLinesNumber: (0, 0))

        try runIgnore(
            "X_W 1 W_Y_W 2 W_Z", "X_W 3 W_B_W 4 W_Z",
            "    +       +    ", "    +       +    ",
            "        -        ", "        -        ",
            changedLinesNumber: (1, 1))

        try runIgnore(
            "X_W W W_Z", "X_W W_ W_Z",
            " + + + + ", " + + ++ + ",
            "         ", "          ",
            changedLinesNumber: (0, 0))

        try runIgnore(
            "X_W M W_Z", "X_W W_ W_Z",
            " + + + + ", " + + ++ + ",
            "    -    ", "    -     ",
            changedLinesNumber: (1, 2))
    }

    @Test func testNoInnerChanges() throws {
        try runIgnore(
            "X_W_Y_W_Z", "X_B_Z",
            " +++ +++ ", " + + ",
            "    --   ", "  -- ",
            noInnerChanges: true,
            changedLinesNumber: (1, 1))

        try runIgnore(
            "X_W_W_Z", "X_Z",
            " +++++ ", " + ",
            "       ", "   ",
            noInnerChanges: true,
            changedLinesNumber: (0, 0))

        try runIgnore(
            "X_W 1 W_Y_W 2 W_Z", "X_W 3 W_B_W 4 W_Z",
            "    +       +    ", "    +       +    ",
            "        --       ", "        --       ",
            noInnerChanges: true,
            changedLinesNumber: (1, 1))

        try runIgnore(
            "X_W W W_Z", "X_W W_ W_Z",
            " + + + + ", " + + ++ + ",
            "  ------ ", "  ------- ",
            noInnerChanges: true,
            changedLinesNumber: (1, 2))

        try runIgnore(
            "X_W M W_Z", "X_W W_ W_Z",
            " + + + + ", " + + ++ + ",
            "  ------ ", "  ------- ",
            noInnerChanges: true,
            changedLinesNumber: (1, 2))
    }

    @Test("test trim vs trimExpand for inner ranges")
    func trimVsTrimExpandForInnerRanges() throws {
        try runIgnore(
            "X M Y Z", "A B Y C",
            "+     +", "+     +",
            " --    ", " --    ")

        try runIgnore(
            "X M Y Z", "A B Y C",
            "  +    ", "  +    ",
            "--    -", "--    -")

        try runIgnore(
            "X MZ Y Z", "A BZ Y C",
            "  +     ", "  +     ",
            "----   -", "----   -")

        try runIgnore(
            "ZX M Y Z", "A B Y C",
            " +     +", "+     +",
            "----    ", " --    ")

        try runIgnore(
            "X Y", "XY",
            " + ", "  ",
            "---", "--",
            changedLinesNumber: (1, 1))
    }

    @Test("test Java samples")
    func javaSamples() throws {
        try runIgnore(
            "System . out.println(\"Hello world\");", "System.out.println(\"Hello world\");",
            "      + +            .            .   ", "                   .            .   ",
            "                     .            .   ", "                   .            .   ",
            changedLinesNumber: (0, 0))

        try runIgnore(
            " System . out . println(\"Hello  world\") ; ", "System.out.println(\"Hello world\");",
            "+      + +   + +   .                  .  + +", "                   .            .   ",
            "                        .      -      .     ", "                   .            .   ")

        try runIgnore(
            "import java.util.Random;_import java.util.List;__class Test {_}", "import java.util.List;_import java.util.Timer;__class Foo {_}",
            "+++++++++++++++++++++++++++++++++++++++++++++++++              ", "++++++++++++++++++++++++++++++++++++++++++++++++             ",
            "                                                       ----    ", "                                                      ---    ",
            changedLinesNumber: (1, 1))

        try runIgnore(
            "final_int x = 0;", "final int Y = 0;",
            "     +   + + +  ", "     +   + + +  ",
            "          -     ", "          -     ",
            changedLinesNumber: (2, 1),
            changedLines: [mod(0, 0, 2, 1)])

        try runIgnore(
            "int X = 0;", "intX = 0;",
            "   + + +  ", "    + +  ",
            "-----     ", "----     ",
            changedLinesNumber: (1, 1))

        try runIgnore(
            "import xx.x;_import xx.y;_import xx.z;", "import xx.x;_// import xx.y;_import xx.z;",
            "++++++++++++++++++++++++++++++++++++++", "+++++++++++++               +++++++++++++",
            "                                      ", "             ----------------            ",
            changedLinesNumber: (0, 1))

        try runIgnore(
            "import xx.x;_import xx.y;_import xx.z;_import xx.a;", "//import xx.x;_import xx.y;_import xx.z;_//import xx.a;",
            "+++++++++++++++++++++++++++++++++++++++++++++++++++", "              +++++++++++++++++++++++++++              ",
            "                                                   ", "---------------                          --------------",
            changedLinesNumber: (0, 2))

        try runIgnore(
            "foo();_bar 'text';", "foo();_// TODO: bar 'text'",
            "          +       ", "      ++++++++++++++++++++",
            "       -----------", "                          ",
            changedLinesNumber: (1, 0),
            changedLines: [del(1, 2, 1)])

        try runIgnore(
            "import x.A;_import x.B;_import x.C;__@C_class Test { }_", "import x.B;__@x.C_class Test {}_",
            "+++++++++++++++++++++++++++++++++++++  +     +    + + +", "+++++++++++++    +     +    +  +",
            "                                                       ", "              --                ",
            changedLinesNumber: (1, 1),
            changedLines: [mod(4, 2, 1, 1)])
    }

    @Test("test Java bad samples")
    func javaBadSamples() throws {
        try runIgnore(
            "System.out.println (\"Hello  world\");", "System.out.println(\"Hello world\");",
            "              .   +               .   ", "                   .            .   ",
            "                  - .      -      .   ", "                   .            .   ")

        try runIgnore(
            "private static final Cleaner NOP = () -> { };_", "private static final Cleaner NOP = () -> { _ };_",
            "       +      +     +       +   + +  +  + +  +", "       +      +     +       +   + +  +  + +++  +",
            "                                           -- ", "                                             -- ")

        try runIgnore(
            "private static final Cleaner NOP = () -> { };", "private static final Cleaner NOP = () -> { _ };",
            "       +      +     +       +   + +  +  + +  ", "       +      +     +       +   + +  +  + +++  ",
            "                                             ", "                                               ")
    }

    @Test("test explicit blocks")
    func explicitBlocks() throws {
        try runIgnore(
            "X_a_Y_b_Z", "X_a 1 c_Y_b 1 c_Z",
            "         ", "   +++     +++   ",
            "         ", "      -          ",
            changedLinesNumber: (1, 1),
            ranged: DiffRange(1, 2, 1, 2))

        try runIgnore(
            "X_a_Y_b_Z", "X_a 1 c_Y_b 1 c_Z",
            "         ", "   ++++    +++   ",
            "         ", "                 ",
            changedLinesNumber: (0, 0),
            ranged: DiffRange(1, 2, 1, 2))

        try runIgnore(
            "X_a_Y_b_Z", "X_a 1 c_Y_b 1 c_Z",
            "         ", "              +  ",
            "         ", "           ---   ",
            changedLinesNumber: (1, 1),
            ranged: DiffRange(3, 4, 3, 4))

        try runIgnore(
            "X_a_Y_b_Z", "X_a 1 c_Y_b 1 c_Z",
            "         ", "              +  ",
            "  -      ", "          ----   ",
            changedLinesNumber: (1, 1),
            ranged: DiffRange(1, 2, 3, 4))

        try runIgnore(
            "X_a_Y_b_Z", "Y_b 1 c_Z",
            "         ", "      +  ",
            "         ", "   ---   ",
            changedLinesNumber: (1, 1),
            ranged: DiffRange(3, 4, 1, 2))

        try runIgnore(
            "X_a_Y_b_Z", "Y_c_d_b_Z",
            "         ", "  ++++   ",
            "         ", "         ",
            changedLinesNumber: (0, 0),
            ranged: DiffRange(3, 4, 1, 4))

        try runIgnore(
            "X_a_Y_Z", "Y_c_d_Z",
            "       ", "  ++++ ",
            "       ", "       ",
            changedLinesNumber: (0, 0),
            ranged: DiffRange(3, 3, 1, 3))

        try runIgnore(
            "X_a_Y_Z", "Y_c_d_Z",
            "       ", "       ",
            "       ", "  ---- ",
            changedLinesNumber: (0, 2),
            ranged: DiffRange(3, 3, 1, 3))

        try runIgnore(
            "X_W 1 W_Y_W 2 W_Z", "X_W 3 W_B_W 4 W_Z",
            "    +       +    ", "    +       +    ",
            "        --       ", "        --       ",
            noInnerChanges: true,
            changedLinesNumber: (1, 1),
            ranged: DiffRange(2, 4, 2, 4))

        try runIgnore(
            "X_W 1 W_Y_W 2 W_Z", "X_W 3 W_B_W 4 W_Z",
            "    +       +    ", "    +       +    ",
            "        --       ", "        --       ",
            noInnerChanges: true,
            changedLinesNumber: (1, 1),
            ranged: DiffRange(1, 5, 1, 5))

        try runIgnore(
            "X_W 1 W_Y_W 2 W_Z", "X_W 3 W_B_W 4 W_Z",
            "    +       +    ", "    +       +    ",
            "                 ", "                 ",
            noInnerChanges: true,
            changedLinesNumber: (0, 0),
            ranged: DiffRange(1, 2, 3, 4))

        try runIgnore(
            "X_a Y_Z", "Y_aY_Z",
            "   + + ", "    + ",
            "  ---  ", "  --  ",
            changedLinesNumber: (1, 1),
            ranged: DiffRange(1, 2, 1, 2))

        try runIgnore(
            "X_a Y_Z", "X_aY_Z",
            "   + + ", "    + ",
            "  ---  ", "  --  ",
            changedLinesNumber: (1, 1),
            ranged: DiffRange(1, 2, 1, 2))
    }
}
