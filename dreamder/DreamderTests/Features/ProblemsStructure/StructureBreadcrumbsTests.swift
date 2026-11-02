import Foundation
import Testing
@testable import Dreamder

@Suite
struct StructureBreadcrumbsTests {
    private let source = """
    struct Outer {
        let value: Int
        func run() {
            print(value)
        }
    }

    func topLevel() {}
    """

    private var nodes: [StructureNode] {
        let extracted = SymbolExtractor.symbols(in: source, fileExtension: "swift")
        return StructureTreeBuilder.nodes(from: extracted, text: source)
    }

    @Test(arguments: [
        (1, ["Outer"]),
        (2, ["Outer", "value"]),
        (3, ["Outer", "run"]),
        (4, ["Outer", "run"]),
        (8, ["topLevel"])
    ])
    func crumbsFollowTheCaretLine(line: Int, expected: [String]) {
        #expect(StructureBreadcrumbs.path(in: nodes, line: line).map(\.name) == expected)
    }

    @Test
    func nodesWithoutRangeNeverMatch() {
        let node = StructureNode(id: "a", name: "a", detail: nil, kind: .function, line: 1, column: 1, children: [])
        #expect(StructureBreadcrumbs.path(in: [node], line: 1).isEmpty)
    }

    @Test
    func innermostChildWinsOverItsParent() {
        let child = StructureNode(
            id: "c", name: "child", detail: nil, kind: .method, line: 3, column: 1, children: [],
            rangeStartLine: 3, rangeEndLine: 5
        )
        let parent = StructureNode(
            id: "p", name: "parent", detail: nil, kind: .classType, line: 1, column: 1, children: [child],
            rangeStartLine: 1, rangeEndLine: 10
        )
        #expect(StructureBreadcrumbs.path(in: [parent], line: 4).map(\.name) == ["parent", "child"])
        #expect(StructureBreadcrumbs.path(in: [parent], line: 7).map(\.name) == ["parent"])
        #expect(StructureBreadcrumbs.path(in: [parent], line: 11).isEmpty)
    }
}
