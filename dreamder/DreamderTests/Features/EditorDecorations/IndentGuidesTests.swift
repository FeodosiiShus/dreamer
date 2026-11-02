import Testing
@testable import Dreamder

@Suite
struct IndentGuidesTests {
    @Test
    func countsSpaceIndentation() {
        #expect(IndentGuides.indentationColumns(of: "    let a = 1", tabWidth: 4) == 4)
        #expect(IndentGuides.indentationColumns(of: "no indent", tabWidth: 4) == 0)
        #expect(IndentGuides.indentationColumns(of: "", tabWidth: 4) == 0)
        #expect(IndentGuides.indentationColumns(of: "   ", tabWidth: 4) == 3)
    }

    @Test
    func expandsTabsToTabStops() {
        #expect(IndentGuides.indentationColumns(of: "\tlet a = 1", tabWidth: 4) == 4)
        #expect(IndentGuides.indentationColumns(of: "\t\tlet a = 1", tabWidth: 4) == 8)
        #expect(IndentGuides.indentationColumns(of: "\t\tlet a = 1", tabWidth: 2) == 4)
    }

    @Test
    func expandsTabsAfterSpaces() {
        #expect(IndentGuides.indentationColumns(of: "  \tlet a = 1", tabWidth: 4) == 4)
        #expect(IndentGuides.indentationColumns(of: " \tlet a = 1", tabWidth: 4) == 4)
        #expect(IndentGuides.indentationColumns(of: "     \tlet a = 1", tabWidth: 4) == 8)
    }

    @Test
    func countsLevels() {
        let lines = [
            "struct Greeter {",
            "    let name: String",
            "",
            "        func greet() {}",
            "}"
        ]
        #expect(IndentGuides.levels(of: lines, tabWidth: 4) == [0, 1, 1, 2, 0])
    }

    @Test
    func blankLinesInheritPreviousLevel() {
        let lines = ["    a", "", "      ", "    b"]
        #expect(IndentGuides.levels(of: lines, tabWidth: 4) == [1, 1, 1, 1])
    }

    @Test
    func tabIndentedLevels() {
        let lines = ["\tfirst", "\t\tsecond", ""]
        #expect(IndentGuides.levels(of: lines, tabWidth: 4) == [1, 2, 2])
    }

    @Test
    func blockSpansNestedLines() {
        let levels = [0, 1, 2, 2, 1, 0]
        #expect(IndentGuides.block(containingLine: 2, levels: levels) == 2...3)
        #expect(IndentGuides.block(containingLine: 1, levels: levels) == 1...4)
        #expect(IndentGuides.block(containingLine: 0, levels: levels) == nil)
        #expect(IndentGuides.block(containingLine: 9, levels: levels) == nil)
    }

    @Test
    func blockStopsAtSibling() {
        let levels = [0, 1, 1]
        #expect(IndentGuides.block(containingLine: 1, levels: levels) == 1...2)
    }
}
