import Foundation
import Testing
@testable import Dreamder

struct GitLogPortCase: Sendable, CustomTestStringConvertible {
    let name: String
    let input: String
    let expected: String

    var testDescription: String { name }
}

struct GitLogPortElementCase: Sendable, CustomTestStringConvertible {
    let name: String
    let input: String
    let expected: String
    let longEdgeSize: Int
    let visiblePartSize: Int
    let edgeWithArrowSize: Int

    var testDescription: String { name }
}

private struct NotationGraph: GitLogLinearGraph {
    let nodeTypes: [Character]
    private let upEdges: [[GitLogLinearEdge]]
    private let downEdges: [[GitLogLinearEdge]]

    init?(notation: String) {
        var types: [Character] = []
        var edgeTokens: [[Substring]] = []
        var nodeIndexById: [Int: Int] = [:]
        for line in notation.split(separator: "\n") {
            guard let separator = line.range(of: "|-"),
                  let (nodeId, nodeType) = GitLogPortNotation.numberWithCharacter(line[..<separator.lowerBound])
            else { return nil }
            nodeIndexById[nodeId] = types.count
            types.append(nodeType)
            edgeTokens.append(line[separator.upperBound...].split(whereSeparator: \.isWhitespace))
        }

        var up = [[GitLogLinearEdge]](repeating: [], count: types.count)
        var down = [[GitLogLinearEdge]](repeating: [], count: types.count)
        for (nodeIndex, tokens) in edgeTokens.enumerated() {
            for token in tokens {
                guard let (targetId, typeCharacter) = GitLogPortNotation.numberWithCharacter(token),
                      let type = GitLogPortNotation.edgeType(typeCharacter)
                else { return nil }
                let edge: GitLogLinearEdge
                if type.isNormal {
                    guard let downIndex = nodeIndexById[targetId] else { return nil }
                    edge = .normal(nodeIndex, downIndex, type: type)
                } else {
                    edge = .withTarget(nodeIndex: nodeIndex, targetId: targetId, type: type)
                }
                if let upIndex = edge.upNodeIndex {
                    down[upIndex].append(edge)
                }
                if let downIndex = edge.downNodeIndex {
                    up[downIndex].append(edge)
                }
            }
        }
        self.nodeTypes = types
        self.upEdges = up
        self.downEdges = down
    }

    var nodesCount: Int {
        nodeTypes.count
    }

    func adjacentEdges(of nodeIndex: Int, filter: GitLogEdgeFilter) -> [GitLogLinearEdge] {
        guard nodeTypes.indices.contains(nodeIndex) else { return [] }
        var result: [GitLogLinearEdge] = []
        for edge in upEdges[nodeIndex] where edge.type.isNormal ? filter.upNormal : filter.special {
            result.append(edge)
        }
        for edge in downEdges[nodeIndex] where edge.type.isNormal ? filter.downNormal : filter.special {
            result.append(edge)
        }
        return result
    }
}

private enum GitLogPortNotation {
    static func numberWithCharacter(_ text: Substring) -> (Int, Character)? {
        guard text.count >= 3, let character = text.last, let number = Int(text.dropLast(2)) else { return nil }
        return (number, character)
    }

    static func edgeType(_ character: Character) -> GitLogLinearEdgeType? {
        switch character {
        case "U": return .usual
        case "D": return .dotted
        case "N": return .notLoadCommit
        case "P": return .dottedArrowUp
        case "O": return .dottedArrowDown
        default: return nil
        }
    }

    static func character(of type: GitLogLinearEdgeType) -> Character {
        switch type {
        case .usual: "U"
        case .dotted: "D"
        case .notLoadCommit: "N"
        case .dottedArrowUp: "P"
        case .dottedArrowDown: "O"
        }
    }

    static func optional(_ value: Int?) -> String {
        value.map { String($0) } ?? "n"
    }

    static func describe(_ edge: GitLogLinearEdge) -> String {
        "\(optional(edge.upNodeIndex)):\(optional(edge.downNodeIndex)):\(optional(edge.targetId))_\(character(of: edge.type))"
    }

    static func describeInRow(_ edge: GitLogLinearEdge) -> String {
        "\(optional(edge.upNodeIndex))_\(optional(edge.downNodeIndex))_\(character(of: edge.type))"
    }

    static func commits(_ text: String) -> [GitLogGraphCommit] {
        text.split(separator: "\n").compactMap { line in
            guard let separator = line.range(of: "|-") else { return nil }
            let parents = line[separator.upperBound...].split(whereSeparator: \.isWhitespace).map { String($0) }
            return GitLogGraphCommit(id: String(line[..<separator.lowerBound]), parents: parents)
        }
    }

    static func compare(_ left: String, _ right: String) -> Int {
        if left < right { return -1 }
        return left == right ? 0 : 1
    }

    static func edgesInRowText(_ graph: NotationGraph) -> String {
        let generator = GitLogEdgesInRowGenerator(graph: graph)
        let comparator = GitLogElementComparator(layoutIndex: { _ in 0 })
        return (0..<graph.nodesCount).map { row in
            let edges = generator.edgesInRow(row).sorted {
                comparator.areInIncreasingOrder(.edge($0), .edge($1))
            }
            return edges.isEmpty ? "none" : edges.map(describeInRow).joined(separator: " ")
        }.joined(separator: "\n")
    }

    static func layoutText(_ text: String) -> String {
        let parsed = commits(text)
        let ids = parsed.map(\.id)
        let graph = GitLogPermanentGraphBuilder.build(commits: parsed).graph
        let layout = GitLogNodeLayoutBuilder.build(graph: graph) { left, right in
            guard ids.indices.contains(left), ids.indices.contains(right) else { return 0 }
            return compare(ids[left], ids[right])
        }
        return (0..<graph.nodesCount).map { index in
            "\(layout.layoutIndex(of: index))|-\(layout.oneOfHeadNodeIndex(of: index))"
        }.joined(separator: "\n")
    }

    static func graphText(_ graph: some GitLogLinearGraph) -> String {
        (0..<graph.nodesCount).map { index in
            let edges = graph.adjacentEdges(of: index, filter: .all).map { describe($0) }.joined(separator: " ")
            return "\(index)_U|-\(edges)"
        }.joined(separator: "\n")
    }

    static func colorId(of element: GitLogGraphElement) -> Int {
        switch element {
        case .node(let nodeIndex):
            return nodeIndex
        case .edge(let edge):
            if let normal = edge.normalEdge {
                return normal.up + normal.down
            }
            return edge.notNullNodeIndex
        }
    }

    static func sortKey(_ element: GitLogPrintElement) -> Int {
        switch element {
        case .node(let node):
            return 1024 * node.position
        case .edge(let edge):
            let typeOrdinal = edge.direction == .up ? 0 : 1
            return 1024 * edge.positionInCurrentRow + (typeOrdinal + 1) * 64 + edge.positionInOtherRow
        }
    }

    static func describePrintElement(_ element: GitLogPrintElement, in graph: NotationGraph) -> String {
        switch element {
        case .node(let node):
            let type = graph.nodeTypes.indices.contains(node.nodeIndex) ? graph.nodeTypes[node.nodeIndex] : "?"
            return "Node|-\(node.rowIndex):\(node.position)|-\(node.colorId):Unselect(\(node.nodeIndex)_\(type))"
        case .edge(let edge):
            let direction = edge.direction == .up ? "UP" : "DOWN"
            let arrow = edge.hasArrow ? "_ARROW" : ""
            let style = edge.lineStyle == .solid ? "SOLID" : "DASHED"
            let positions = "\(edge.rowIndex):\(edge.positionInCurrentRow):\(edge.positionInOtherRow)"
            return "Edge:\(direction)\(arrow):\(style)|-\(positions)|-\(edge.colorId):Unselect(\(describe(edge.edge)))"
        }
    }

    static func printElementsText(_ testCase: GitLogPortElementCase, graph: NotationGraph) -> String {
        let layout = GitLogNodeLayoutBuilder.build(graph: graph) { $0 - $1 }
        let comparator = GitLogElementComparator(layoutIndex: { layout.layoutIndex(of: $0) })
        let generator = GitLogPrintElementGenerator(
            graph: graph,
            comparator: comparator,
            longEdgeSize: testCase.longEdgeSize,
            visiblePartSize: testCase.visiblePartSize,
            edgeWithArrowSize: testCase.edgeWithArrowSize,
            colorId: colorId(of:)
        )
        return (0..<graph.nodesCount).map { row in
            generator.printElements(at: row)
                .sorted { sortKey($0) < sortKey($1) }
                .map { describePrintElement($0, in: graph) }
                .joined(separator: "\n  ")
        }.joined(separator: "\n")
    }
}

@Suite
struct GitLogGraphPortTests {
    @Test
    func notationParserBuildsEdgeListsLikeIntelliJ() throws {
        let graph = try #require(NotationGraph(notation: """
        0_G|-10_N 2_D
        1_U|-0_P
        2_U|-3_O
        """))
        #expect(graph.nodesCount == 3)
        #expect(graph.nodeTypes == ["G", "U", "U"])
        #expect(graph.adjacentEdges(of: 0, filter: .normalDown) == [.normal(0, 2, type: .dotted)])
        #expect(graph.adjacentEdges(of: 2, filter: .normalUp) == [.normal(0, 2, type: .dotted)])
        #expect(graph.adjacentEdges(of: 0, filter: .special) == [.withTarget(nodeIndex: 0, targetId: 10, type: .notLoadCommit)])
        #expect(graph.adjacentEdges(of: 1, filter: .special) == [.withTarget(nodeIndex: 1, targetId: 0, type: .dottedArrowUp)])
        #expect(graph.adjacentEdges(of: 2, filter: .special) == [.withTarget(nodeIndex: 2, targetId: 3, type: .dottedArrowDown)])
        #expect(graph.adjacentEdges(of: 2, filter: .all).count == 2)
        #expect(graph.adjacentEdges(of: 1, filter: .normalAll).isEmpty)
    }

    @Test
    func notationParserRejectsMalformedInput() {
        #expect(NotationGraph(notation: "0_U|-9_U") == nil)
        #expect(NotationGraph(notation: "0_U|-0_X") == nil)
        #expect(NotationGraph(notation: "zero") == nil)
    }

    @Test(arguments: GitLogPortData.edgesInRow)
    func edgesInRowMatchesIntelliJ(_ testCase: GitLogPortCase) throws {
        let graph = try #require(NotationGraph(notation: testCase.input))
        #expect(GitLogPortNotation.edgesInRowText(graph) == testCase.expected)
    }

    @Test(arguments: GitLogPortData.layoutBuilder)
    func nodeLayoutMatchesIntelliJ(_ testCase: GitLogPortCase) {
        #expect(GitLogPortNotation.layoutText(testCase.input) == testCase.expected)
    }

    @Test(arguments: GitLogPortData.graphBuilder)
    func permanentGraphMatchesIntelliJ(_ testCase: GitLogPortCase) {
        let graph = GitLogPermanentGraphBuilder.build(commits: GitLogPortNotation.commits(testCase.input)).graph
        #expect(GitLogPortNotation.graphText(graph) == testCase.expected)
    }

    @Test
    func notLoadedParentsGetDescendingNegativeIds() {
        let commits = GitLogPortNotation.commits("""
        a0|-a1 a6 a3
        a1|-a6
        a2|-a3
        a3|-
        a4|-a5
        """)
        let result = GitLogPermanentGraphBuilder.build(commits: commits)
        #expect(result.notLoadedCommitIds == [-2: "a6", -3: "a5"])
        #expect(GitLogPermanentGraphBuilder.build(commits: GitLogPortNotation.commits("a0|-")).notLoadedCommitIds.isEmpty)
    }

    @Test
    func duplicateParentsAreRemovedBeforeBuilding() {
        let commit = GitLogGraphCommit(id: "0", parents: ["1", "1", "1", "3", "1", "1"])
        #expect(GitLogPermanentGraphBuilder.fixDuplicateParents(commit).parents == ["1", "3"])
        let unique = GitLogGraphCommit(id: "0", parents: ["1", "3"])
        #expect(GitLogPermanentGraphBuilder.fixDuplicateParents(unique) == unique)
    }

    @Test(arguments: GitLogPortData.elementGenerator)
    func printElementsMatchIntelliJ(_ testCase: GitLogPortElementCase) throws {
        let graph = try #require(NotationGraph(notation: testCase.input))
        #expect(GitLogPortNotation.printElementsText(testCase, graph: graph) == testCase.expected)
    }

    @Test
    func headOrderTiersFollowIntelliJRefOrder() {
        let refs = [
            GitLogRef(name: "origin/main", kind: .remote),
            GitLogRef(name: "origin/feature", kind: .remote),
            GitLogRef(name: "main", kind: .branch),
            GitLogRef(name: "feature", kind: .branch),
            GitLogRef(name: "v1", kind: .tag),
            GitLogRef(name: "HEAD", kind: .head)
        ]
        for (index, ref) in refs.enumerated() {
            for other in refs[(index + 1)...] {
                #expect(GitLogHeadOrder.compare(ref, other) < 0)
                #expect(GitLogHeadOrder.compare(other, ref) > 0)
            }
        }
        #expect(GitLogHeadOrder.bestRef(of: refs.reversed()) == refs.first)
        #expect(GitLogHeadOrder.bestRef(of: []) == nil)
    }

    @Test
    func headsWithoutRefsSortAfterHeadsWithRefs() {
        let bestRefs = [1: GitLogRef(name: "main", kind: .branch)]
        #expect(GitLogHeadOrder.compareHeads(1, 0, bestRefs: bestRefs) < 0)
        #expect(GitLogHeadOrder.compareHeads(0, 1, bestRefs: bestRefs) > 0)
        #expect(GitLogHeadOrder.compareHeads(0, 2, bestRefs: bestRefs) < 0)
        #expect(GitLogHeadOrder.compareHeads(1, 1, bestRefs: bestRefs) == 0)
    }

    @Test
    func javaHashMatchesStringHashCode() {
        #expect(GitLogGraphColors.javaHash("main") == 3_343_801)
        #expect(GitLogGraphColors.javaHash("") == 0)
    }

    @Test(arguments: [-1_000, -1, 0, 1, 2, 3, 7, 42, 64, 255, 1_000, 3_343_801, Int(Int32.max), Int(Int32.min)])
    func hueStaysInUnitRangeAndIsDeterministic(_ colorId: Int) {
        let hue = GitLogGraphColors.hue(forColorId: colorId)
        #expect(hue >= 0)
        #expect(hue <= 1)
        #expect(hue == GitLogGraphColors.hue(forColorId: colorId))
    }

    @Test
    func recommendedWidthIsZeroForEmptyAndOneForSingleNode() {
        for (text, expected) in [("", 0), ("a0|-", 1)] {
            let graph = GitLogPermanentGraphBuilder.build(commits: GitLogPortNotation.commits(text)).graph
            let generator = GitLogPrintElementGenerator(
                graph: graph,
                comparator: GitLogElementComparator(layoutIndex: { _ in 0 }),
                showLongEdges: false,
                colorId: { _ in 0 }
            )
            #expect(generator.recommendedWidth() == expected)
        }
    }
}

enum GitLogPortData {
    static let edgesInRow: [GitLogPortCase] = [
        GitLogPortCase(
            name: "simple",
            input: """
            0_U|-1_U 3_D
            1_U|-2_U
            2_U|-3_U
            3_U|-
            """,
            expected: """
            none
            0_3_D
            0_3_D
            none
            """
        ),
        GitLogPortCase(
            name: "manyNodes",
            input: """
            0_U|-1_U 6_U 3_U
            1_U|-6_D
            2_U|-3_U
            3_U|-
            4_U|-5_U
            5_U|-
            6_U|-7_U
            7_U|-
            """,
            expected: """
            none
            0_6_U 0_3_U
            0_6_U 0_3_U 1_6_D
            0_6_U 1_6_D
            0_6_U 1_6_D
            0_6_U 1_6_D
            none
            none
            """
        ),
        GitLogPortCase(
            name: "manyUpNodes",
            input: """
            0_U|-4_U
            1_U|-4_U
            2_U|-4_D
            3_U|-4_U
            4_U|-
            """,
            expected: """
            none
            0_4_U
            0_4_U 1_4_U
            0_4_U 1_4_U 2_4_D
            none
            """
        ),
        GitLogPortCase(
            name: "manyDownNodes",
            input: """
            0_U|-1_U 2_U 3_U 4_U
            1_U|-
            2_U|-
            3_U|-
            4_U|-
            """,
            expected: """
            none
            0_4_U 0_3_U 0_2_U
            0_4_U 0_3_U
            0_4_U
            none
            """
        ),
        GitLogPortCase(
            name: "oneNode",
            input: """
            0_U|-
            """,
            expected: """
            none
            """
        ),
        GitLogPortCase(
            name: "oneNodeNotFullGraph",
            input: """
            0_U|-1_N 3_N 5_N
            """,
            expected: """
            none
            """
        ),
        GitLogPortCase(
            name: "notFullGraph",
            input: """
            0_U|-1_D 6_N 3_D
            1_U|-6_N
            2_U|-3_U
            3_U|-
            4_U|-5_N
            """,
            expected: """
            none
            0_3_D
            0_3_D
            none
            none
            """
        ),
        GitLogPortCase(
            name: "longGraph",
            input: """
            0_U|-17_U
            1_U|-
            2_U|-15_U
            3_U|-
            4_U|-
            5_U|-
            6_U|-10_U
            7_U|-
            8_U|-
            9_U|-
            10_U|-
            11_U|-
            12_U|-16_U
            13_U|-
            14_U|-
            15_U|-
            16_U|-
            17_U|-
            """,
            expected: """
            none
            0_17_U
            0_17_U
            0_17_U 2_15_U
            0_17_U 2_15_U
            0_17_U 2_15_U
            0_17_U 2_15_U
            0_17_U 2_15_U 6_10_U
            0_17_U 2_15_U 6_10_U
            0_17_U 2_15_U 6_10_U
            0_17_U 2_15_U
            0_17_U 2_15_U
            0_17_U 2_15_U
            0_17_U 2_15_U 12_16_U
            0_17_U 2_15_U 12_16_U
            0_17_U 12_16_U
            0_17_U
            none
            """
        ),
        GitLogPortCase(
            name: "notLoadNode",
            input: """
            0_U|-6_N 2_U
            1_U|-5_N
            2_U|-
            """,
            expected: """
            none
            0_2_U
            none
            """
        )
    ]

    static let layoutBuilder: [GitLogPortCase] = [
        GitLogPortCase(
            name: "manyNodes",
            input: """
            a0|-a1 a6 a3
            a1|-a7
            a2|-a3
            a3|-
            a4|-a5
            a5|-
            a6|-a7
            a7|-a8
            a8|-
            """,
            expected: """
            1|-0
            1|-0
            4|-2
            3|-0
            5|-4
            5|-4
            2|-0
            1|-0
            1|-0
            """
        ),
        GitLogPortCase(
            name: "notFullGraph",
            input: """
            a0|-a1 a6 a3
            a1|-a6
            a2|-a3
            a3|-
            a4|-a5
            """,
            expected: """
            1|-0
            1|-0
            3|-2
            2|-0
            4|-4
            """
        ),
        GitLogPortCase(
            name: "oneNode",
            input: """
            a0|-
            """,
            expected: """
            1|-0
            """
        ),
        GitLogPortCase(
            name: "oneNodeNotFullGraph",
            input: """
            a0|-a1 a3 a5
            """,
            expected: """
            1|-0
            """
        ),
        GitLogPortCase(
            name: "headsOrder",
            input: """
            ff|-a1 a3
            a1|-a4
            a2|-a3
            a3|-a4
            a4|-
            """,
            expected: """
            2|-0
            2|-0
            1|-2
            1|-2
            1|-2
            """
        )
    ]

    static let graphBuilder: [GitLogPortCase] = [
        GitLogPortCase(
            name: "simple",
            input: """
            a0|-a1
            a1|-a2
            a2|-a3
            a3|-
            """,
            expected: """
            0_U|-0:1:n_U
            1_U|-0:1:n_U 1:2:n_U
            2_U|-1:2:n_U 2:3:n_U
            3_U|-2:3:n_U
            """
        ),
        GitLogPortCase(
            name: "manyNodes",
            input: """
            a0|-a1 a6 a3
            a1|-a6
            a2|-a3
            a3|-
            a4|-a5
            a5|-
            a6|-a7
            a7|-
            """,
            expected: """
            0_U|-0:1:n_U 0:6:n_U 0:3:n_U
            1_U|-0:1:n_U 1:6:n_U
            2_U|-2:3:n_U
            3_U|-2:3:n_U 0:3:n_U
            4_U|-4:5:n_U
            5_U|-4:5:n_U
            6_U|-0:6:n_U 1:6:n_U 6:7:n_U
            7_U|-6:7:n_U
            """
        ),
        GitLogPortCase(
            name: "manyUpNodes",
            input: """
            a0|-a4
            a1|-a4
            a2|-a4
            a3|-a4
            a4|-
            """,
            expected: """
            0_U|-0:4:n_U
            1_U|-1:4:n_U
            2_U|-2:4:n_U
            3_U|-3:4:n_U
            4_U|-3:4:n_U 0:4:n_U 1:4:n_U 2:4:n_U
            """
        ),
        GitLogPortCase(
            name: "manyDownNodes",
            input: """
            a0|-a1 a2 a3 a4
            a1|-
            a2|-
            a3|-
            a4|-
            """,
            expected: """
            0_U|-0:1:n_U 0:2:n_U 0:3:n_U 0:4:n_U
            1_U|-0:1:n_U
            2_U|-0:2:n_U
            3_U|-0:3:n_U
            4_U|-0:4:n_U
            """
        ),
        GitLogPortCase(
            name: "oneNode",
            input: """
            a0|-
            """,
            expected: """
            0_U|-
            """
        ),
        GitLogPortCase(
            name: "oneNodeNotFullGraph",
            input: """
            a0|-a5
            """,
            expected: """
            0_U|-0:n:-2_N
            """
        ),
        GitLogPortCase(
            name: "notFullGraph",
            input: """
            a0|-a1 a6 a3
            a1|-a6
            a2|-a3
            a3|-
            a4|-a5
            """,
            expected: """
            0_U|-0:1:n_U 0:n:-2_N 0:3:n_U
            1_U|-0:1:n_U 1:n:-2_N
            2_U|-2:3:n_U
            3_U|-2:3:n_U 0:3:n_U
            4_U|-4:n:-3_N
            """
        ),
        GitLogPortCase(
            name: "parentsOrder",
            input: """
            a66|-ffff a aa
            aa|-f ffff ff
            ffff|-ff
            ff|-
            a|-
            f|-
            """,
            expected: """
            0_U|-0:2:n_U 0:4:n_U 0:1:n_U
            1_U|-0:1:n_U 1:5:n_U 1:2:n_U 1:3:n_U
            2_U|-0:2:n_U 1:2:n_U 2:3:n_U
            3_U|-2:3:n_U 1:3:n_U
            4_U|-0:4:n_U
            5_U|-1:5:n_U
            """
        ),
        GitLogPortCase(
            name: "duplicateParents",
            input: """
            0|-1 1 1 3 1 1
            1|-6
            2|-3 4 4 3
            3|-4 4
            4|-5 6
            5|-
            6|-
            """,
            expected: """
            0_U|-0:1:n_U 0:3:n_U
            1_U|-0:1:n_U 1:6:n_U
            2_U|-2:3:n_U 2:4:n_U
            3_U|-0:3:n_U 2:3:n_U 3:4:n_U
            4_U|-3:4:n_U 2:4:n_U 4:5:n_U 4:6:n_U
            5_U|-4:5:n_U
            6_U|-1:6:n_U 4:6:n_U
            """
        )
    ]

    static let elementGenerator: [GitLogPortElementCase] = [
        GitLogPortElementCase(
            name: "oneNode",
            input: """
            0_U|-
            """,
            expected: """
            Node|-0:0|-0:Unselect(0_U)
            """,
            longEdgeSize: 7,
            visiblePartSize: 2,
            edgeWithArrowSize: 10
        ),
        GitLogPortElementCase(
            name: "manyNodes",
            input: """
            0_U|-1_U 6_U 3_U
            1_U|-6_D
            2_U|-3_U
            3_U|-
            4_U|-5_U
            5_U|-
            6_U|-7_U
            7_U|-
            """,
            expected: """
            Node|-0:0|-0:Unselect(0_U)
              Edge:DOWN:SOLID|-0:0:0|-6:Unselect(0:6:n_U)
              Edge:DOWN:SOLID|-0:0:1|-1:Unselect(0:1:n_U)
              Edge:DOWN:SOLID|-0:0:2|-3:Unselect(0:3:n_U)
            Edge:UP:SOLID|-1:0:0|-6:Unselect(0:6:n_U)
              Edge:DOWN:SOLID|-1:0:0|-6:Unselect(0:6:n_U)
              Node|-1:1|-1:Unselect(1_U)
              Edge:UP:SOLID|-1:1:0|-1:Unselect(0:1:n_U)
              Edge:DOWN:DASHED|-1:1:1|-7:Unselect(1:6:n_D)
              Edge:UP:SOLID|-1:2:0|-3:Unselect(0:3:n_U)
              Edge:DOWN:SOLID|-1:2:2|-3:Unselect(0:3:n_U)
            Edge:UP:SOLID|-2:0:0|-6:Unselect(0:6:n_U)
              Edge:DOWN:SOLID|-2:0:0|-6:Unselect(0:6:n_U)
              Edge:UP:DASHED|-2:1:1|-7:Unselect(1:6:n_D)
              Edge:DOWN:DASHED|-2:1:1|-7:Unselect(1:6:n_D)
              Edge:UP:SOLID|-2:2:2|-3:Unselect(0:3:n_U)
              Edge:DOWN:SOLID|-2:2:2|-3:Unselect(0:3:n_U)
              Node|-2:3|-2:Unselect(2_U)
              Edge:DOWN:SOLID|-2:3:2|-5:Unselect(2:3:n_U)
            Edge:UP:SOLID|-3:0:0|-6:Unselect(0:6:n_U)
              Edge:DOWN:SOLID|-3:0:0|-6:Unselect(0:6:n_U)
              Edge:UP:DASHED|-3:1:1|-7:Unselect(1:6:n_D)
              Edge:DOWN:DASHED|-3:1:1|-7:Unselect(1:6:n_D)
              Node|-3:2|-3:Unselect(3_U)
              Edge:UP:SOLID|-3:2:2|-3:Unselect(0:3:n_U)
              Edge:UP:SOLID|-3:2:3|-5:Unselect(2:3:n_U)
            Edge:UP:SOLID|-4:0:0|-6:Unselect(0:6:n_U)
              Edge:DOWN:SOLID|-4:0:0|-6:Unselect(0:6:n_U)
              Edge:UP:DASHED|-4:1:1|-7:Unselect(1:6:n_D)
              Edge:DOWN:DASHED|-4:1:1|-7:Unselect(1:6:n_D)
              Node|-4:2|-4:Unselect(4_U)
              Edge:DOWN:SOLID|-4:2:2|-9:Unselect(4:5:n_U)
            Edge:UP:SOLID|-5:0:0|-6:Unselect(0:6:n_U)
              Edge:DOWN:SOLID|-5:0:0|-6:Unselect(0:6:n_U)
              Edge:UP:DASHED|-5:1:1|-7:Unselect(1:6:n_D)
              Edge:DOWN:DASHED|-5:1:0|-7:Unselect(1:6:n_D)
              Node|-5:2|-5:Unselect(5_U)
              Edge:UP:SOLID|-5:2:2|-9:Unselect(4:5:n_U)
            Node|-6:0|-6:Unselect(6_U)
              Edge:UP:SOLID|-6:0:0|-6:Unselect(0:6:n_U)
              Edge:UP:DASHED|-6:0:1|-7:Unselect(1:6:n_D)
              Edge:DOWN:SOLID|-6:0:0|-13:Unselect(6:7:n_U)
            Node|-7:0|-7:Unselect(7_U)
              Edge:UP:SOLID|-7:0:0|-13:Unselect(6:7:n_U)
            """,
            longEdgeSize: 7,
            visiblePartSize: 2,
            edgeWithArrowSize: 10
        ),
        GitLogPortElementCase(
            name: "longEdges",
            input: """
            0_U|-1_U 2_U 3_U 4_U 5_U 6_U 7_U 8_U 9_U 10_U 11_U 12_U
            1_U|-12_U
            2_U|-12_U
            3_U|-12_U
            4_U|-12_U
            5_U|-12_U
            6_U|-12_U
            7_U|-12_U
            8_U|-12_U
            9_U|-12_U
            10_U|-12_U
            11_U|-12_U
            12_U|-
            """,
            expected: """
            Node|-0:0|-0:Unselect(0_U)
              Edge:DOWN:SOLID|-0:0:0|-12:Unselect(0:12:n_U)
              Edge:DOWN:SOLID|-0:0:1|-1:Unselect(0:1:n_U)
              Edge:DOWN:SOLID|-0:0:2|-2:Unselect(0:2:n_U)
              Edge:DOWN:SOLID|-0:0:3|-3:Unselect(0:3:n_U)
              Edge:DOWN:SOLID|-0:0:4|-4:Unselect(0:4:n_U)
              Edge:DOWN:SOLID|-0:0:5|-5:Unselect(0:5:n_U)
              Edge:DOWN:SOLID|-0:0:6|-6:Unselect(0:6:n_U)
              Edge:DOWN:SOLID|-0:0:7|-7:Unselect(0:7:n_U)
              Edge:DOWN:SOLID|-0:0:8|-8:Unselect(0:8:n_U)
              Edge:DOWN:SOLID|-0:0:9|-9:Unselect(0:9:n_U)
              Edge:DOWN:SOLID|-0:0:10|-10:Unselect(0:10:n_U)
              Edge:DOWN:SOLID|-0:0:11|-11:Unselect(0:11:n_U)
            Edge:UP:SOLID|-1:0:0|-12:Unselect(0:12:n_U)
              Edge:DOWN_ARROW:SOLID|-1:0:0|-12:Unselect(0:12:n_U)
              Node|-1:1|-1:Unselect(1_U)
              Edge:UP:SOLID|-1:1:0|-1:Unselect(0:1:n_U)
              Edge:DOWN:SOLID|-1:1:1|-13:Unselect(1:12:n_U)
              Edge:UP:SOLID|-1:2:0|-2:Unselect(0:2:n_U)
              Edge:DOWN:SOLID|-1:2:2|-2:Unselect(0:2:n_U)
              Edge:UP:SOLID|-1:3:0|-3:Unselect(0:3:n_U)
              Edge:DOWN:SOLID|-1:3:3|-3:Unselect(0:3:n_U)
              Edge:UP:SOLID|-1:4:0|-4:Unselect(0:4:n_U)
              Edge:DOWN:SOLID|-1:4:4|-4:Unselect(0:4:n_U)
              Edge:UP:SOLID|-1:5:0|-5:Unselect(0:5:n_U)
              Edge:DOWN:SOLID|-1:5:5|-5:Unselect(0:5:n_U)
              Edge:UP:SOLID|-1:6:0|-6:Unselect(0:6:n_U)
              Edge:DOWN:SOLID|-1:6:6|-6:Unselect(0:6:n_U)
              Edge:UP:SOLID|-1:7:0|-7:Unselect(0:7:n_U)
              Edge:DOWN:SOLID|-1:7:7|-7:Unselect(0:7:n_U)
              Edge:UP:SOLID|-1:8:0|-8:Unselect(0:8:n_U)
              Edge:DOWN:SOLID|-1:8:8|-8:Unselect(0:8:n_U)
              Edge:UP:SOLID|-1:9:0|-9:Unselect(0:9:n_U)
              Edge:DOWN:SOLID|-1:9:9|-9:Unselect(0:9:n_U)
              Edge:UP:SOLID|-1:10:0|-10:Unselect(0:10:n_U)
              Edge:DOWN_ARROW:SOLID|-1:10:10|-10:Unselect(0:10:n_U)
              Edge:UP:SOLID|-1:11:0|-11:Unselect(0:11:n_U)
              Edge:DOWN_ARROW:SOLID|-1:11:11|-11:Unselect(0:11:n_U)
            Edge:UP:SOLID|-2:0:0|-12:Unselect(0:12:n_U)
              Edge:DOWN_ARROW:SOLID|-2:0:0|-12:Unselect(0:12:n_U)
              Edge:UP:SOLID|-2:1:1|-13:Unselect(1:12:n_U)
              Edge:DOWN_ARROW:SOLID|-2:1:0|-13:Unselect(1:12:n_U)
              Node|-2:2|-2:Unselect(2_U)
              Edge:UP:SOLID|-2:2:2|-2:Unselect(0:2:n_U)
              Edge:DOWN:SOLID|-2:2:1|-14:Unselect(2:12:n_U)
              Edge:UP:SOLID|-2:3:3|-3:Unselect(0:3:n_U)
              Edge:DOWN:SOLID|-2:3:2|-3:Unselect(0:3:n_U)
              Edge:UP:SOLID|-2:4:4|-4:Unselect(0:4:n_U)
              Edge:DOWN:SOLID|-2:4:3|-4:Unselect(0:4:n_U)
              Edge:UP:SOLID|-2:5:5|-5:Unselect(0:5:n_U)
              Edge:DOWN:SOLID|-2:5:4|-5:Unselect(0:5:n_U)
              Edge:UP:SOLID|-2:6:6|-6:Unselect(0:6:n_U)
              Edge:DOWN:SOLID|-2:6:5|-6:Unselect(0:6:n_U)
              Edge:UP:SOLID|-2:7:7|-7:Unselect(0:7:n_U)
              Edge:DOWN_ARROW:SOLID|-2:7:7|-7:Unselect(0:7:n_U)
              Edge:UP:SOLID|-2:8:8|-8:Unselect(0:8:n_U)
              Edge:DOWN_ARROW:SOLID|-2:8:8|-8:Unselect(0:8:n_U)
              Edge:UP:SOLID|-2:9:9|-9:Unselect(0:9:n_U)
              Edge:DOWN_ARROW:SOLID|-2:9:9|-9:Unselect(0:9:n_U)
              Edge:UP:SOLID|-2:10:10|-10:Unselect(0:10:n_U)
              Edge:DOWN_ARROW:SOLID|-2:10:10|-10:Unselect(0:10:n_U)
              Edge:UP:SOLID|-2:11:11|-11:Unselect(0:11:n_U)
              Edge:DOWN_ARROW:SOLID|-2:11:11|-11:Unselect(0:11:n_U)
            Edge:UP:SOLID|-3:0:1|-13:Unselect(1:12:n_U)
              Edge:DOWN_ARROW:SOLID|-3:0:0|-13:Unselect(1:12:n_U)
              Edge:UP:SOLID|-3:1:2|-14:Unselect(2:12:n_U)
              Edge:DOWN_ARROW:SOLID|-3:1:0|-14:Unselect(2:12:n_U)
              Node|-3:2|-3:Unselect(3_U)
              Edge:UP:SOLID|-3:2:3|-3:Unselect(0:3:n_U)
              Edge:DOWN:SOLID|-3:2:1|-15:Unselect(3:12:n_U)
              Edge:UP:SOLID|-3:3:4|-4:Unselect(0:4:n_U)
              Edge:DOWN:SOLID|-3:3:2|-4:Unselect(0:4:n_U)
              Edge:UP:SOLID|-3:4:5|-5:Unselect(0:5:n_U)
              Edge:DOWN:SOLID|-3:4:3|-5:Unselect(0:5:n_U)
              Edge:UP:SOLID|-3:5:6|-6:Unselect(0:6:n_U)
              Edge:DOWN:SOLID|-3:5:4|-6:Unselect(0:6:n_U)
            Edge:UP:SOLID|-4:0:1|-14:Unselect(2:12:n_U)
              Edge:DOWN_ARROW:SOLID|-4:0:0|-14:Unselect(2:12:n_U)
              Edge:UP:SOLID|-4:1:2|-15:Unselect(3:12:n_U)
              Edge:DOWN:SOLID|-4:1:0|-15:Unselect(3:12:n_U)
              Node|-4:2|-4:Unselect(4_U)
              Edge:UP:SOLID|-4:2:3|-4:Unselect(0:4:n_U)
              Edge:DOWN:SOLID|-4:2:1|-16:Unselect(4:12:n_U)
              Edge:UP:SOLID|-4:3:4|-5:Unselect(0:5:n_U)
              Edge:DOWN:SOLID|-4:3:2|-5:Unselect(0:5:n_U)
              Edge:UP:SOLID|-4:4:5|-6:Unselect(0:6:n_U)
              Edge:DOWN:SOLID|-4:4:3|-6:Unselect(0:6:n_U)
            Edge:UP:SOLID|-5:0:1|-15:Unselect(3:12:n_U)
              Edge:DOWN_ARROW:SOLID|-5:0:0|-15:Unselect(3:12:n_U)
              Edge:UP:SOLID|-5:1:2|-16:Unselect(4:12:n_U)
              Edge:DOWN:SOLID|-5:1:0|-16:Unselect(4:12:n_U)
              Node|-5:2|-5:Unselect(5_U)
              Edge:UP:SOLID|-5:2:3|-5:Unselect(0:5:n_U)
              Edge:DOWN:SOLID|-5:2:1|-17:Unselect(5:12:n_U)
              Edge:UP:SOLID|-5:3:4|-6:Unselect(0:6:n_U)
              Edge:DOWN:SOLID|-5:3:2|-6:Unselect(0:6:n_U)
              Edge:UP_ARROW:SOLID|-5:4:4|-7:Unselect(0:7:n_U)
              Edge:DOWN:SOLID|-5:4:3|-7:Unselect(0:7:n_U)
            Edge:UP:SOLID|-6:0:1|-16:Unselect(4:12:n_U)
              Edge:DOWN_ARROW:SOLID|-6:0:0|-16:Unselect(4:12:n_U)
              Edge:UP:SOLID|-6:1:2|-17:Unselect(5:12:n_U)
              Edge:DOWN:SOLID|-6:1:0|-17:Unselect(5:12:n_U)
              Node|-6:2|-6:Unselect(6_U)
              Edge:UP:SOLID|-6:2:3|-6:Unselect(0:6:n_U)
              Edge:DOWN:SOLID|-6:2:1|-18:Unselect(6:12:n_U)
              Edge:UP:SOLID|-6:3:4|-7:Unselect(0:7:n_U)
              Edge:DOWN:SOLID|-6:3:2|-7:Unselect(0:7:n_U)
              Edge:UP_ARROW:SOLID|-6:4:4|-8:Unselect(0:8:n_U)
              Edge:DOWN:SOLID|-6:4:3|-8:Unselect(0:8:n_U)
            Edge:UP:SOLID|-7:0:1|-17:Unselect(5:12:n_U)
              Edge:DOWN_ARROW:SOLID|-7:0:0|-17:Unselect(5:12:n_U)
              Edge:UP:SOLID|-7:1:2|-18:Unselect(6:12:n_U)
              Edge:DOWN:SOLID|-7:1:0|-18:Unselect(6:12:n_U)
              Node|-7:2|-7:Unselect(7_U)
              Edge:UP:SOLID|-7:2:3|-7:Unselect(0:7:n_U)
              Edge:DOWN:SOLID|-7:2:1|-19:Unselect(7:12:n_U)
              Edge:UP:SOLID|-7:3:4|-8:Unselect(0:8:n_U)
              Edge:DOWN:SOLID|-7:3:2|-8:Unselect(0:8:n_U)
              Edge:UP_ARROW:SOLID|-7:4:4|-9:Unselect(0:9:n_U)
              Edge:DOWN:SOLID|-7:4:3|-9:Unselect(0:9:n_U)
            Edge:UP:SOLID|-8:0:1|-18:Unselect(6:12:n_U)
              Edge:DOWN:SOLID|-8:0:0|-18:Unselect(6:12:n_U)
              Edge:UP:SOLID|-8:1:2|-19:Unselect(7:12:n_U)
              Edge:DOWN:SOLID|-8:1:1|-19:Unselect(7:12:n_U)
              Node|-8:2|-8:Unselect(8_U)
              Edge:UP:SOLID|-8:2:3|-8:Unselect(0:8:n_U)
              Edge:DOWN:SOLID|-8:2:2|-20:Unselect(8:12:n_U)
              Edge:UP:SOLID|-8:3:4|-9:Unselect(0:9:n_U)
              Edge:DOWN:SOLID|-8:3:3|-9:Unselect(0:9:n_U)
              Edge:UP_ARROW:SOLID|-8:4:4|-10:Unselect(0:10:n_U)
              Edge:DOWN:SOLID|-8:4:4|-10:Unselect(0:10:n_U)
            Edge:UP:SOLID|-9:0:0|-18:Unselect(6:12:n_U)
              Edge:DOWN:SOLID|-9:0:6|-18:Unselect(6:12:n_U)
              Edge:UP:SOLID|-9:1:1|-19:Unselect(7:12:n_U)
              Edge:DOWN:SOLID|-9:1:7|-19:Unselect(7:12:n_U)
              Edge:UP:SOLID|-9:2:2|-20:Unselect(8:12:n_U)
              Edge:DOWN:SOLID|-9:2:8|-20:Unselect(8:12:n_U)
              Node|-9:3|-9:Unselect(9_U)
              Edge:UP:SOLID|-9:3:3|-9:Unselect(0:9:n_U)
              Edge:DOWN:SOLID|-9:3:9|-21:Unselect(9:12:n_U)
              Edge:UP_ARROW:SOLID|-9:4:4|-10:Unselect(0:10:n_U)
              Edge:DOWN:SOLID|-9:4:10|-10:Unselect(0:10:n_U)
              Edge:UP_ARROW:SOLID|-9:5:5|-11:Unselect(0:11:n_U)
              Edge:DOWN:SOLID|-9:5:11|-11:Unselect(0:11:n_U)
            Edge:UP_ARROW:SOLID|-10:0:0|-12:Unselect(0:12:n_U)
              Edge:DOWN:SOLID|-10:0:0|-12:Unselect(0:12:n_U)
              Edge:UP_ARROW:SOLID|-10:1:1|-13:Unselect(1:12:n_U)
              Edge:DOWN:SOLID|-10:1:1|-13:Unselect(1:12:n_U)
              Edge:UP_ARROW:SOLID|-10:2:2|-14:Unselect(2:12:n_U)
              Edge:DOWN:SOLID|-10:2:2|-14:Unselect(2:12:n_U)
              Edge:UP_ARROW:SOLID|-10:3:3|-15:Unselect(3:12:n_U)
              Edge:DOWN:SOLID|-10:3:3|-15:Unselect(3:12:n_U)
              Edge:UP_ARROW:SOLID|-10:4:4|-16:Unselect(4:12:n_U)
              Edge:DOWN:SOLID|-10:4:4|-16:Unselect(4:12:n_U)
              Edge:UP_ARROW:SOLID|-10:5:5|-17:Unselect(5:12:n_U)
              Edge:DOWN:SOLID|-10:5:5|-17:Unselect(5:12:n_U)
              Edge:UP:SOLID|-10:6:0|-18:Unselect(6:12:n_U)
              Edge:DOWN:SOLID|-10:6:6|-18:Unselect(6:12:n_U)
              Edge:UP:SOLID|-10:7:1|-19:Unselect(7:12:n_U)
              Edge:DOWN:SOLID|-10:7:7|-19:Unselect(7:12:n_U)
              Edge:UP:SOLID|-10:8:2|-20:Unselect(8:12:n_U)
              Edge:DOWN:SOLID|-10:8:8|-20:Unselect(8:12:n_U)
              Edge:UP:SOLID|-10:9:3|-21:Unselect(9:12:n_U)
              Edge:DOWN:SOLID|-10:9:9|-21:Unselect(9:12:n_U)
              Node|-10:10|-10:Unselect(10_U)
              Edge:UP:SOLID|-10:10:4|-10:Unselect(0:10:n_U)
              Edge:DOWN:SOLID|-10:10:10|-22:Unselect(10:12:n_U)
              Edge:UP_ARROW:SOLID|-10:11:5|-11:Unselect(0:11:n_U)
              Edge:DOWN:SOLID|-10:11:11|-11:Unselect(0:11:n_U)
            Edge:UP_ARROW:SOLID|-11:0:0|-12:Unselect(0:12:n_U)
              Edge:DOWN:SOLID|-11:0:0|-12:Unselect(0:12:n_U)
              Edge:UP_ARROW:SOLID|-11:1:1|-13:Unselect(1:12:n_U)
              Edge:DOWN:SOLID|-11:1:0|-13:Unselect(1:12:n_U)
              Edge:UP_ARROW:SOLID|-11:2:2|-14:Unselect(2:12:n_U)
              Edge:DOWN:SOLID|-11:2:0|-14:Unselect(2:12:n_U)
              Edge:UP:SOLID|-11:3:3|-15:Unselect(3:12:n_U)
              Edge:DOWN:SOLID|-11:3:0|-15:Unselect(3:12:n_U)
              Edge:UP:SOLID|-11:4:4|-16:Unselect(4:12:n_U)
              Edge:DOWN:SOLID|-11:4:0|-16:Unselect(4:12:n_U)
              Edge:UP:SOLID|-11:5:5|-17:Unselect(5:12:n_U)
              Edge:DOWN:SOLID|-11:5:0|-17:Unselect(5:12:n_U)
              Edge:UP:SOLID|-11:6:6|-18:Unselect(6:12:n_U)
              Edge:DOWN:SOLID|-11:6:0|-18:Unselect(6:12:n_U)
              Edge:UP:SOLID|-11:7:7|-19:Unselect(7:12:n_U)
              Edge:DOWN:SOLID|-11:7:0|-19:Unselect(7:12:n_U)
              Edge:UP:SOLID|-11:8:8|-20:Unselect(8:12:n_U)
              Edge:DOWN:SOLID|-11:8:0|-20:Unselect(8:12:n_U)
              Edge:UP:SOLID|-11:9:9|-21:Unselect(9:12:n_U)
              Edge:DOWN:SOLID|-11:9:0|-21:Unselect(9:12:n_U)
              Edge:UP:SOLID|-11:10:10|-22:Unselect(10:12:n_U)
              Edge:DOWN:SOLID|-11:10:0|-22:Unselect(10:12:n_U)
              Node|-11:11|-11:Unselect(11_U)
              Edge:UP:SOLID|-11:11:11|-11:Unselect(0:11:n_U)
              Edge:DOWN:SOLID|-11:11:0|-23:Unselect(11:12:n_U)
            Node|-12:0|-12:Unselect(12_U)
              Edge:UP:SOLID|-12:0:0|-12:Unselect(0:12:n_U)
              Edge:UP:SOLID|-12:0:1|-13:Unselect(1:12:n_U)
              Edge:UP:SOLID|-12:0:2|-14:Unselect(2:12:n_U)
              Edge:UP:SOLID|-12:0:3|-15:Unselect(3:12:n_U)
              Edge:UP:SOLID|-12:0:4|-16:Unselect(4:12:n_U)
              Edge:UP:SOLID|-12:0:5|-17:Unselect(5:12:n_U)
              Edge:UP:SOLID|-12:0:6|-18:Unselect(6:12:n_U)
              Edge:UP:SOLID|-12:0:7|-19:Unselect(7:12:n_U)
              Edge:UP:SOLID|-12:0:8|-20:Unselect(8:12:n_U)
              Edge:UP:SOLID|-12:0:9|-21:Unselect(9:12:n_U)
              Edge:UP:SOLID|-12:0:10|-22:Unselect(10:12:n_U)
              Edge:UP:SOLID|-12:0:11|-23:Unselect(11:12:n_U)
            """,
            longEdgeSize: 7,
            visiblePartSize: 2,
            edgeWithArrowSize: 10
        ),
        GitLogPortElementCase(
            name: "specialElements",
            input: """
            0_G|-10_N 11_O 4_D
            1_U|-0_P
            2_U|-0_P 3_O 12_N
            3_G|-
            4_U|-
            """,
            expected: """
            Node|-0:0|-0:Unselect(0_G)
              Edge:DOWN:SOLID|-0:0:0|-0:Unselect(0:n:10_N)
              Edge:DOWN:DASHED|-0:0:1|-0:Unselect(0:n:11_O)
              Edge:DOWN:DASHED|-0:0:2|-4:Unselect(0:4:n_D)
              Edge:UP_ARROW:DASHED|-0:1:1|-1:Unselect(n:1:0_P)
              Edge:DOWN:DASHED|-0:1:3|-1:Unselect(n:1:0_P)
            Edge:UP:SOLID|-1:0:0|-0:Unselect(0:n:10_N)
              Edge:DOWN_ARROW:SOLID|-1:0:0|-0:Unselect(0:n:10_N)
              Edge:UP:DASHED|-1:1:0|-0:Unselect(0:n:11_O)
              Edge:DOWN_ARROW:DASHED|-1:1:1|-0:Unselect(0:n:11_O)
              Edge:UP:DASHED|-1:2:0|-4:Unselect(0:4:n_D)
              Edge:DOWN:DASHED|-1:2:0|-4:Unselect(0:4:n_D)
              Node|-1:3|-1:Unselect(1_U)
              Edge:UP:DASHED|-1:3:1|-1:Unselect(n:1:0_P)
              Edge:UP_ARROW:DASHED|-1:4:4|-2:Unselect(n:2:0_P)
              Edge:DOWN:DASHED|-1:4:1|-2:Unselect(n:2:0_P)
            Edge:UP:DASHED|-2:0:2|-4:Unselect(0:4:n_D)
              Edge:DOWN:DASHED|-2:0:0|-4:Unselect(0:4:n_D)
              Node|-2:1|-2:Unselect(2_U)
              Edge:UP:DASHED|-2:1:4|-2:Unselect(n:2:0_P)
              Edge:DOWN:DASHED|-2:1:1|-2:Unselect(2:n:3_O)
              Edge:DOWN:SOLID|-2:1:2|-2:Unselect(2:n:12_N)
            Edge:UP:DASHED|-3:0:0|-4:Unselect(0:4:n_D)
              Edge:DOWN:DASHED|-3:0:0|-4:Unselect(0:4:n_D)
              Edge:UP:DASHED|-3:1:1|-2:Unselect(2:n:3_O)
              Edge:DOWN_ARROW:DASHED|-3:1:1|-2:Unselect(2:n:3_O)
              Edge:UP:SOLID|-3:2:1|-2:Unselect(2:n:12_N)
              Edge:DOWN_ARROW:SOLID|-3:2:2|-2:Unselect(2:n:12_N)
              Node|-3:3|-3:Unselect(3_G)
            Node|-4:0|-4:Unselect(4_U)
              Edge:UP:DASHED|-4:0:0|-4:Unselect(0:4:n_D)
            """,
            longEdgeSize: 7,
            visiblePartSize: 2,
            edgeWithArrowSize: 10
        ),
        GitLogPortElementCase(
            name: "oneUpOneDown1",
            input: """
            0_U|-1_U 7_U
            1_U|-2_U
            2_U|-3_U
            3_U|-4_U 12_U
            4_U|-5_U 6_U
            5_U|-8_U
            6_U|-8_U
            7_U|-15_U
            8_U|-9_U 10_U
            9_U|-11_U
            10_U|-11_U
            11_U|-12_U
            12_U|-13_U
            13_U|-14_U
            14_U|-15_U
            15_U|-
            """,
            expected: """
            Node|-0:0|-0:Unselect(0_U)
              Edge:DOWN:SOLID|-0:0:0|-1:Unselect(0:1:n_U)
              Edge:DOWN:SOLID|-0:0:1|-7:Unselect(0:7:n_U)
            Node|-1:0|-1:Unselect(1_U)
              Edge:UP:SOLID|-1:0:0|-1:Unselect(0:1:n_U)
              Edge:DOWN:SOLID|-1:0:0|-3:Unselect(1:2:n_U)
              Edge:UP:SOLID|-1:1:0|-7:Unselect(0:7:n_U)
              Edge:DOWN_ARROW:SOLID|-1:1:1|-7:Unselect(0:7:n_U)
            Node|-2:0|-2:Unselect(2_U)
              Edge:UP:SOLID|-2:0:0|-3:Unselect(1:2:n_U)
              Edge:DOWN:SOLID|-2:0:0|-5:Unselect(2:3:n_U)
            Node|-3:0|-3:Unselect(3_U)
              Edge:UP:SOLID|-3:0:0|-5:Unselect(2:3:n_U)
              Edge:DOWN:SOLID|-3:0:0|-15:Unselect(3:12:n_U)
              Edge:DOWN:SOLID|-3:0:1|-7:Unselect(3:4:n_U)
            Edge:UP:SOLID|-4:0:0|-15:Unselect(3:12:n_U)
              Edge:DOWN_ARROW:SOLID|-4:0:0|-15:Unselect(3:12:n_U)
              Node|-4:1|-4:Unselect(4_U)
              Edge:UP:SOLID|-4:1:0|-7:Unselect(3:4:n_U)
              Edge:DOWN:SOLID|-4:1:0|-9:Unselect(4:5:n_U)
              Edge:DOWN:SOLID|-4:1:1|-10:Unselect(4:6:n_U)
            Node|-5:0|-5:Unselect(5_U)
              Edge:UP:SOLID|-5:0:1|-9:Unselect(4:5:n_U)
              Edge:DOWN:SOLID|-5:0:0|-13:Unselect(5:8:n_U)
              Edge:UP:SOLID|-5:1:1|-10:Unselect(4:6:n_U)
              Edge:DOWN:SOLID|-5:1:1|-10:Unselect(4:6:n_U)
            Edge:UP:SOLID|-6:0:0|-13:Unselect(5:8:n_U)
              Edge:DOWN:SOLID|-6:0:0|-13:Unselect(5:8:n_U)
              Node|-6:1|-6:Unselect(6_U)
              Edge:UP:SOLID|-6:1:1|-10:Unselect(4:6:n_U)
              Edge:DOWN:SOLID|-6:1:1|-14:Unselect(6:8:n_U)
              Edge:UP_ARROW:SOLID|-6:2:2|-7:Unselect(0:7:n_U)
              Edge:DOWN:SOLID|-6:2:2|-7:Unselect(0:7:n_U)
            Edge:UP:SOLID|-7:0:0|-13:Unselect(5:8:n_U)
              Edge:DOWN:SOLID|-7:0:0|-13:Unselect(5:8:n_U)
              Edge:UP:SOLID|-7:1:1|-14:Unselect(6:8:n_U)
              Edge:DOWN:SOLID|-7:1:0|-14:Unselect(6:8:n_U)
              Node|-7:2|-7:Unselect(7_U)
              Edge:UP:SOLID|-7:2:2|-7:Unselect(0:7:n_U)
              Edge:DOWN:SOLID|-7:2:1|-22:Unselect(7:15:n_U)
            Node|-8:0|-8:Unselect(8_U)
              Edge:UP:SOLID|-8:0:0|-13:Unselect(5:8:n_U)
              Edge:UP:SOLID|-8:0:1|-14:Unselect(6:8:n_U)
              Edge:DOWN:SOLID|-8:0:0|-17:Unselect(8:9:n_U)
              Edge:DOWN:SOLID|-8:0:1|-18:Unselect(8:10:n_U)
              Edge:UP:SOLID|-8:1:2|-22:Unselect(7:15:n_U)
              Edge:DOWN_ARROW:SOLID|-8:1:1|-22:Unselect(7:15:n_U)
            Node|-9:0|-9:Unselect(9_U)
              Edge:UP:SOLID|-9:0:0|-17:Unselect(8:9:n_U)
              Edge:DOWN:SOLID|-9:0:0|-20:Unselect(9:11:n_U)
              Edge:UP:SOLID|-9:1:0|-18:Unselect(8:10:n_U)
              Edge:DOWN:SOLID|-9:1:1|-18:Unselect(8:10:n_U)
            Edge:UP:SOLID|-10:0:0|-20:Unselect(9:11:n_U)
              Edge:DOWN:SOLID|-10:0:1|-20:Unselect(9:11:n_U)
              Node|-10:1|-10:Unselect(10_U)
              Edge:UP:SOLID|-10:1:1|-18:Unselect(8:10:n_U)
              Edge:DOWN:SOLID|-10:1:1|-21:Unselect(10:11:n_U)
            Edge:UP_ARROW:SOLID|-11:0:0|-15:Unselect(3:12:n_U)
              Edge:DOWN:SOLID|-11:0:0|-15:Unselect(3:12:n_U)
              Node|-11:1|-11:Unselect(11_U)
              Edge:UP:SOLID|-11:1:0|-20:Unselect(9:11:n_U)
              Edge:UP:SOLID|-11:1:1|-21:Unselect(10:11:n_U)
              Edge:DOWN:SOLID|-11:1:0|-23:Unselect(11:12:n_U)
            Node|-12:0|-12:Unselect(12_U)
              Edge:UP:SOLID|-12:0:0|-15:Unselect(3:12:n_U)
              Edge:UP:SOLID|-12:0:1|-23:Unselect(11:12:n_U)
              Edge:DOWN:SOLID|-12:0:0|-25:Unselect(12:13:n_U)
            Node|-13:0|-13:Unselect(13_U)
              Edge:UP:SOLID|-13:0:0|-25:Unselect(12:13:n_U)
              Edge:DOWN:SOLID|-13:0:0|-27:Unselect(13:14:n_U)
            Node|-14:0|-14:Unselect(14_U)
              Edge:UP:SOLID|-14:0:0|-27:Unselect(13:14:n_U)
              Edge:DOWN:SOLID|-14:0:0|-29:Unselect(14:15:n_U)
              Edge:UP_ARROW:SOLID|-14:1:1|-22:Unselect(7:15:n_U)
              Edge:DOWN:SOLID|-14:1:0|-22:Unselect(7:15:n_U)
            Node|-15:0|-15:Unselect(15_U)
              Edge:UP:SOLID|-15:0:0|-29:Unselect(14:15:n_U)
              Edge:UP:SOLID|-15:0:1|-22:Unselect(7:15:n_U)
            """,
            longEdgeSize: 7,
            visiblePartSize: 1,
            edgeWithArrowSize: 10
        ),
        GitLogPortElementCase(
            name: "oneUpOneDown2",
            input: """
            0_U|-1_U 10_U
            1_U|-2_U
            2_U|-3_U
            3_U|-4_U
            4_U|-5_U
            5_U|-7_U 6_U
            6_U|-15_U
            7_U|-8_U 9_U
            8_U|-11_U
            9_U|-11_U
            10_U|-22_U
            11_U|-12_U 13_U
            12_U|-14_U
            13_U|-14_U
            14_U|-16_U
            15_U|-16_U
            16_U|-17_U
            17_U|-18_U
            18_U|-19_U
            19_U|-20_U
            20_U|-21_U
            21_U|-22_U
            22_U|-
            """,
            expected: """
            Node|-0:0|-0:Unselect(0_U)
              Edge:DOWN:SOLID|-0:0:0|-1:Unselect(0:1:n_U)
              Edge:DOWN:SOLID|-0:0:1|-10:Unselect(0:10:n_U)
            Node|-1:0|-1:Unselect(1_U)
              Edge:UP:SOLID|-1:0:0|-1:Unselect(0:1:n_U)
              Edge:DOWN:SOLID|-1:0:0|-3:Unselect(1:2:n_U)
              Edge:UP:SOLID|-1:1:0|-10:Unselect(0:10:n_U)
              Edge:DOWN_ARROW:SOLID|-1:1:1|-10:Unselect(0:10:n_U)
            Node|-2:0|-2:Unselect(2_U)
              Edge:UP:SOLID|-2:0:0|-3:Unselect(1:2:n_U)
              Edge:DOWN:SOLID|-2:0:0|-5:Unselect(2:3:n_U)
            Node|-3:0|-3:Unselect(3_U)
              Edge:UP:SOLID|-3:0:0|-5:Unselect(2:3:n_U)
              Edge:DOWN:SOLID|-3:0:0|-7:Unselect(3:4:n_U)
            Node|-4:0|-4:Unselect(4_U)
              Edge:UP:SOLID|-4:0:0|-7:Unselect(3:4:n_U)
              Edge:DOWN:SOLID|-4:0:0|-9:Unselect(4:5:n_U)
            Node|-5:0|-5:Unselect(5_U)
              Edge:UP:SOLID|-5:0:0|-9:Unselect(4:5:n_U)
              Edge:DOWN:SOLID|-5:0:0|-12:Unselect(5:7:n_U)
              Edge:DOWN:SOLID|-5:0:1|-11:Unselect(5:6:n_U)
            Edge:UP:SOLID|-6:0:0|-12:Unselect(5:7:n_U)
              Edge:DOWN:SOLID|-6:0:0|-12:Unselect(5:7:n_U)
              Node|-6:1|-6:Unselect(6_U)
              Edge:UP:SOLID|-6:1:0|-11:Unselect(5:6:n_U)
              Edge:DOWN:SOLID|-6:1:1|-21:Unselect(6:15:n_U)
            Node|-7:0|-7:Unselect(7_U)
              Edge:UP:SOLID|-7:0:0|-12:Unselect(5:7:n_U)
              Edge:DOWN:SOLID|-7:0:0|-15:Unselect(7:8:n_U)
              Edge:DOWN:SOLID|-7:0:1|-16:Unselect(7:9:n_U)
              Edge:UP:SOLID|-7:1:1|-21:Unselect(6:15:n_U)
              Edge:DOWN:SOLID|-7:1:2|-21:Unselect(6:15:n_U)
            Node|-8:0|-8:Unselect(8_U)
              Edge:UP:SOLID|-8:0:0|-15:Unselect(7:8:n_U)
              Edge:DOWN:SOLID|-8:0:0|-19:Unselect(8:11:n_U)
              Edge:UP:SOLID|-8:1:0|-16:Unselect(7:9:n_U)
              Edge:DOWN:SOLID|-8:1:1|-16:Unselect(7:9:n_U)
              Edge:UP:SOLID|-8:2:1|-21:Unselect(6:15:n_U)
              Edge:DOWN:SOLID|-8:2:2|-21:Unselect(6:15:n_U)
            Edge:UP:SOLID|-9:0:0|-19:Unselect(8:11:n_U)
              Edge:DOWN:SOLID|-9:0:0|-19:Unselect(8:11:n_U)
              Node|-9:1|-9:Unselect(9_U)
              Edge:UP:SOLID|-9:1:1|-16:Unselect(7:9:n_U)
              Edge:DOWN:SOLID|-9:1:1|-20:Unselect(9:11:n_U)
              Edge:UP:SOLID|-9:2:2|-21:Unselect(6:15:n_U)
              Edge:DOWN:SOLID|-9:2:2|-21:Unselect(6:15:n_U)
              Edge:UP_ARROW:SOLID|-9:3:3|-10:Unselect(0:10:n_U)
              Edge:DOWN:SOLID|-9:3:3|-10:Unselect(0:10:n_U)
            Edge:UP:SOLID|-10:0:0|-19:Unselect(8:11:n_U)
              Edge:DOWN:SOLID|-10:0:0|-19:Unselect(8:11:n_U)
              Edge:UP:SOLID|-10:1:1|-20:Unselect(9:11:n_U)
              Edge:DOWN:SOLID|-10:1:0|-20:Unselect(9:11:n_U)
              Edge:UP:SOLID|-10:2:2|-21:Unselect(6:15:n_U)
              Edge:DOWN:SOLID|-10:2:1|-21:Unselect(6:15:n_U)
              Node|-10:3|-10:Unselect(10_U)
              Edge:UP:SOLID|-10:3:3|-10:Unselect(0:10:n_U)
              Edge:DOWN:SOLID|-10:3:2|-32:Unselect(10:22:n_U)
            Node|-11:0|-11:Unselect(11_U)
              Edge:UP:SOLID|-11:0:0|-19:Unselect(8:11:n_U)
              Edge:UP:SOLID|-11:0:1|-20:Unselect(9:11:n_U)
              Edge:DOWN:SOLID|-11:0:0|-23:Unselect(11:12:n_U)
              Edge:DOWN:SOLID|-11:0:1|-24:Unselect(11:13:n_U)
              Edge:UP:SOLID|-11:1:2|-21:Unselect(6:15:n_U)
              Edge:DOWN:SOLID|-11:1:2|-21:Unselect(6:15:n_U)
              Edge:UP:SOLID|-11:2:3|-32:Unselect(10:22:n_U)
              Edge:DOWN_ARROW:SOLID|-11:2:2|-32:Unselect(10:22:n_U)
            Node|-12:0|-12:Unselect(12_U)
              Edge:UP:SOLID|-12:0:0|-23:Unselect(11:12:n_U)
              Edge:DOWN:SOLID|-12:0:0|-26:Unselect(12:14:n_U)
              Edge:UP:SOLID|-12:1:0|-24:Unselect(11:13:n_U)
              Edge:DOWN:SOLID|-12:1:1|-24:Unselect(11:13:n_U)
              Edge:UP:SOLID|-12:2:1|-21:Unselect(6:15:n_U)
              Edge:DOWN:SOLID|-12:2:2|-21:Unselect(6:15:n_U)
            Edge:UP:SOLID|-13:0:0|-26:Unselect(12:14:n_U)
              Edge:DOWN:SOLID|-13:0:0|-26:Unselect(12:14:n_U)
              Node|-13:1|-13:Unselect(13_U)
              Edge:UP:SOLID|-13:1:1|-24:Unselect(11:13:n_U)
              Edge:DOWN:SOLID|-13:1:0|-27:Unselect(13:14:n_U)
              Edge:UP:SOLID|-13:2:2|-21:Unselect(6:15:n_U)
              Edge:DOWN:SOLID|-13:2:1|-21:Unselect(6:15:n_U)
            Node|-14:0|-14:Unselect(14_U)
              Edge:UP:SOLID|-14:0:0|-26:Unselect(12:14:n_U)
              Edge:UP:SOLID|-14:0:1|-27:Unselect(13:14:n_U)
              Edge:DOWN:SOLID|-14:0:0|-30:Unselect(14:16:n_U)
              Edge:UP:SOLID|-14:1:2|-21:Unselect(6:15:n_U)
              Edge:DOWN:SOLID|-14:1:1|-21:Unselect(6:15:n_U)
            Edge:UP:SOLID|-15:0:0|-30:Unselect(14:16:n_U)
              Edge:DOWN:SOLID|-15:0:0|-30:Unselect(14:16:n_U)
              Node|-15:1|-15:Unselect(15_U)
              Edge:UP:SOLID|-15:1:1|-21:Unselect(6:15:n_U)
              Edge:DOWN:SOLID|-15:1:0|-31:Unselect(15:16:n_U)
            Node|-16:0|-16:Unselect(16_U)
              Edge:UP:SOLID|-16:0:0|-30:Unselect(14:16:n_U)
              Edge:UP:SOLID|-16:0:1|-31:Unselect(15:16:n_U)
              Edge:DOWN:SOLID|-16:0:0|-33:Unselect(16:17:n_U)
            Node|-17:0|-17:Unselect(17_U)
              Edge:UP:SOLID|-17:0:0|-33:Unselect(16:17:n_U)
              Edge:DOWN:SOLID|-17:0:0|-35:Unselect(17:18:n_U)
            Node|-18:0|-18:Unselect(18_U)
              Edge:UP:SOLID|-18:0:0|-35:Unselect(17:18:n_U)
              Edge:DOWN:SOLID|-18:0:0|-37:Unselect(18:19:n_U)
            Node|-19:0|-19:Unselect(19_U)
              Edge:UP:SOLID|-19:0:0|-37:Unselect(18:19:n_U)
              Edge:DOWN:SOLID|-19:0:0|-39:Unselect(19:20:n_U)
            Node|-20:0|-20:Unselect(20_U)
              Edge:UP:SOLID|-20:0:0|-39:Unselect(19:20:n_U)
              Edge:DOWN:SOLID|-20:0:0|-41:Unselect(20:21:n_U)
            Node|-21:0|-21:Unselect(21_U)
              Edge:UP:SOLID|-21:0:0|-41:Unselect(20:21:n_U)
              Edge:DOWN:SOLID|-21:0:0|-43:Unselect(21:22:n_U)
              Edge:UP_ARROW:SOLID|-21:1:1|-32:Unselect(10:22:n_U)
              Edge:DOWN:SOLID|-21:1:0|-32:Unselect(10:22:n_U)
            Node|-22:0|-22:Unselect(22_U)
              Edge:UP:SOLID|-22:0:0|-43:Unselect(21:22:n_U)
              Edge:UP:SOLID|-22:0:1|-32:Unselect(10:22:n_U)
            """,
            longEdgeSize: 10,
            visiblePartSize: 1,
            edgeWithArrowSize: 10
        )
    ]
}
