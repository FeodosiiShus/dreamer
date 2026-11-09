import Foundation
import Testing
@testable import Dreamder

@Suite("Snippet template")
struct SnippetTemplateTests {
    struct Stop: Sendable, CustomStringConvertible {
        let index: Int
        let ranges: [[Int]]
        var choices: [String] = []

        var description: String { "stop \(index)" }
    }

    struct Case: Sendable, CustomStringConvertible {
        let source: String
        let text: String
        let stops: [Stop]
        let finalCaret: Int

        var description: String { source }
    }

    static let fileURL = URL(fileURLWithPath: "/tmp/project/Foo.swift")

    static let cases: [Case] = [
        Case(source: "plain text", text: "plain text", stops: [], finalCaret: 10),
        Case(
            source: "print(${1:value})",
            text: "print(value)",
            stops: [Stop(index: 1, ranges: [[6, 5]])],
            finalCaret: 12
        ),
        Case(
            source: "for ${1:item} in ${2:items} {\n\t$0\n}",
            text: "for item in items {\n\t\n}",
            stops: [Stop(index: 1, ranges: [[4, 4]]), Stop(index: 2, ranges: [[12, 5]])],
            finalCaret: 21
        ),
        Case(source: "let x = $1", text: "let x = ", stops: [Stop(index: 1, ranges: [[8, 0]])], finalCaret: 8),
        Case(
            source: "${1|public,private|} func",
            text: "public func",
            stops: [Stop(index: 1, ranges: [[0, 6]], choices: ["public", "private"])],
            finalCaret: 11
        ),
        Case(
            source: "${1|a\\,b,c\\|d|}",
            text: "a,b",
            stops: [Stop(index: 1, ranges: [[0, 3]], choices: ["a,b", "c|d"])],
            finalCaret: 3
        ),
        Case(source: "cost: \\$5", text: "cost: $5", stops: [], finalCaret: 8),
        Case(source: "a\\}b", text: "a}b", stops: [], finalCaret: 3),
        Case(source: "a\\\\b", text: "a\\b", stops: [], finalCaret: 3),
        Case(source: "a\\nb", text: "a\\nb", stops: [], finalCaret: 4),
        Case(source: "price $", text: "price $", stops: [], finalCaret: 7),
        Case(source: "$ 5 }", text: "$ 5 }", stops: [], finalCaret: 5),
        Case(source: "${1:foo", text: "${1:foo", stops: [], finalCaret: 7),
        Case(source: "${1|a,b}", text: "${1|a,b}", stops: [], finalCaret: 8),
        Case(source: "${a-b}", text: "${a-b}", stops: [], finalCaret: 6),
        Case(source: "${1x}", text: "${1x}", stops: [], finalCaret: 5),
        Case(source: "${}", text: "${}", stops: [], finalCaret: 3),
        Case(source: "${1}", text: "", stops: [Stop(index: 1, ranges: [[0, 0]])], finalCaret: 0),
        Case(source: "${1:}", text: "", stops: [Stop(index: 1, ranges: [[0, 0]])], finalCaret: 0),
        Case(source: "$10", text: "", stops: [Stop(index: 10, ranges: [[0, 0]])], finalCaret: 0),
        Case(
            source: "$2 $1",
            text: " ",
            stops: [Stop(index: 1, ranges: [[1, 0]]), Stop(index: 2, ranges: [[0, 0]])],
            finalCaret: 1
        ),
        Case(source: "a$0b$1", text: "ab", stops: [Stop(index: 1, ranges: [[2, 0]])], finalCaret: 1),
        Case(source: "x${0}y", text: "xy", stops: [], finalCaret: 1),
        Case(source: "x$0y$0z", text: "xyz", stops: [], finalCaret: 1),
        Case(source: "x${0:body}y", text: "xbodyy", stops: [], finalCaret: 1),
        Case(
            source: "${1:x} = $1;",
            text: "x = x;",
            stops: [Stop(index: 1, ranges: [[0, 1], [4, 1]])],
            finalCaret: 6
        ),
        Case(
            source: "$1 = ${1:x}",
            text: "x = x",
            stops: [Stop(index: 1, ranges: [[4, 1], [0, 1]])],
            finalCaret: 5
        ),
        Case(
            source: "${1:a} ${1:b}",
            text: "a a",
            stops: [Stop(index: 1, ranges: [[0, 1], [2, 1]])],
            finalCaret: 3
        ),
        Case(
            source: "${1:foo ${2:bar}} baz",
            text: "foo bar baz",
            stops: [Stop(index: 1, ranges: [[0, 7]]), Stop(index: 2, ranges: [[4, 3]])],
            finalCaret: 11
        ),
        Case(
            source: "${1:a${2:b}} $1",
            text: "ab ab",
            stops: [Stop(index: 1, ranges: [[0, 2], [3, 2]]), Stop(index: 2, ranges: [[1, 1]])],
            finalCaret: 5
        ),
        Case(source: "${1:$1}", text: "", stops: [Stop(index: 1, ranges: [[0, 0], [0, 0]])], finalCaret: 0),
        Case(
            source: "$1 ${1:${2:x}} $2",
            text: "x x x",
            stops: [Stop(index: 1, ranges: [[2, 1], [0, 1]]), Stop(index: 2, ranges: [[2, 1], [4, 1]])],
            finalCaret: 5
        ),
        Case(
            source: "$1 ${1:$2}${2:z}",
            text: "z zz",
            stops: [Stop(index: 1, ranges: [[2, 1], [0, 1]]), Stop(index: 2, ranges: [[3, 1], [2, 1]])],
            finalCaret: 4
        ),
        Case(
            source: "$1 ${1:a${0}b}",
            text: "ab ab",
            stops: [Stop(index: 1, ranges: [[3, 2], [0, 2]])],
            finalCaret: 4
        ),
        Case(
            source: "$1 ${1:${TM_FILENAME}}",
            text: "Foo.swift Foo.swift",
            stops: [Stop(index: 1, ranges: [[10, 9], [0, 9]])],
            finalCaret: 19
        ),
        Case(
            source: "$1 ${1:${NOPE}}",
            text: "NOPE NOPE",
            stops: [Stop(index: 1, ranges: [[5, 4], [0, 4]])],
            finalCaret: 9
        ),
        Case(
            source: "$1 ${1:${2|p,q|}}",
            text: "p p",
            stops: [Stop(index: 1, ranges: [[2, 1], [0, 1]]), Stop(index: 2, ranges: [[2, 1]], choices: ["p", "q"])],
            finalCaret: 3
        ),
        Case(
            source: "$1 ${1|a,b|}",
            text: "a a",
            stops: [Stop(index: 1, ranges: [[2, 1], [0, 1]], choices: ["a", "b"])],
            finalCaret: 3
        ),
        Case(
            source: "${TM_FILENAME} ${TM_FILENAME_BASE} ${TM_DIRECTORY} ${TM_FILEPATH}",
            text: "Foo.swift Foo /tmp/project /tmp/project/Foo.swift",
            stops: [],
            finalCaret: 49
        ),
        Case(
            source: "${TM_LINE_INDEX}:${TM_LINE_NUMBER} $TM_CURRENT_LINE|$TM_CURRENT_WORD",
            text: "3:4 let x = fo|fo",
            stops: [],
            finalCaret: 17
        ),
        Case(
            source: "$TM_SELECTED_TEXT ${TM_SELECTED_TEXT} ${TM_SELECTED_TEXT:fallback}",
            text: "sel sel sel",
            stops: [],
            finalCaret: 11
        ),
        Case(
            source: "${UNKNOWN} ${UNKNOWN:dflt} $UNKNOWN",
            text: "UNKNOWN dflt UNKNOWN",
            stops: [],
            finalCaret: 20
        ),
        Case(
            source: "\u{E9}$1\u{1F642}${2:\u{FC}}",
            text: "\u{E9}\u{1F642}\u{FC}",
            stops: [Stop(index: 1, ranges: [[1, 0]]), Stop(index: 2, ranges: [[3, 1]])],
            finalCaret: 4
        )
    ]

    static let variables = SnippetVariableContext(
        selectedText: "sel",
        currentLine: "let x = fo",
        currentWord: "fo",
        lineIndex: 3,
        fileURL: fileURL
    )

    @Test(arguments: SnippetTemplateTests.cases)
    func parsesTemplates(_ testCase: Case) {
        let template = SnippetTemplate(parsing: testCase.source, variables: Self.variables)
        #expect(template.text == testCase.text)
        #expect(template.finalCaret == testCase.finalCaret)
        #expect(template.tabStops.map(\.index) == testCase.stops.map(\.index))
        #expect(template.tabStops.map { $0.ranges.map { [$0.location, $0.length] } } == testCase.stops.map(\.ranges))
        #expect(template.tabStops.map(\.choices) == testCase.stops.map(\.choices))
    }

    @Test func emptySelectionFallsBackToThePlaceholderDefault() {
        let template = SnippetTemplate(parsing: "${TM_SELECTED_TEXT:fallback}|$TM_SELECTED_TEXT|")
        #expect(template.text == "fallback||")
    }

    @Test func variableDefaultsFlowThroughMirrors() {
        let template = SnippetTemplate(parsing: "$1 ${1:${TM_SELECTED_TEXT:dflt}}")
        #expect(template.text == "dflt dflt")
        #expect(template.tabStops.map { $0.ranges.map { [$0.location, $0.length] } } == [[[5, 4], [0, 4]]])
    }

    @Test func missingFileYieldsEmptyFileVariables() {
        let template = SnippetTemplate(parsing: "[$TM_FILENAME][$TM_FILENAME_BASE][$TM_DIRECTORY][$TM_FILEPATH]")
        #expect(template.text == "[][][][]")
    }

    @Test func plainTemplateKeepsTheTextAndTheEndCaret() {
        let template = SnippetTemplate(text: "abc")
        #expect(template.tabStops.isEmpty)
        #expect(template.finalCaret == 3)
        #expect(SnippetTemplate(text: "abc", finalCaret: 1).finalCaret == 1)
    }

    @Test func parserBuildsTheNodeTree() {
        let nodes = SnippetParser.parse("a${1:b${2|x,y|}}$VAR")
        #expect(nodes == [
            .text("a"),
            .tabStop(index: 1, children: [
                .text("b"),
                .tabStop(index: 2, children: [], choices: ["x", "y"])
            ], choices: []),
            .variable(name: "VAR", children: [])
        ])
    }
}
