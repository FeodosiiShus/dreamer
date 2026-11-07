import Foundation
@testable import Dreamder

nonisolated protocol GitLogTypedLinearGraph: GitLogLinearGraph {
    func nodeTypeCharacter(at nodeIndex: Int) -> Character
}

extension GitLogPermanentGraph: GitLogTypedLinearGraph {
    func nodeTypeCharacter(at nodeIndex: Int) -> Character {
        "U"
    }
}

nonisolated struct NotationGraph: GitLogTypedLinearGraph {
    let nodeTypes: [Character]
    private let upEdges: [[GitLogLinearEdge]]
    private let downEdges: [[GitLogLinearEdge]]

    init?(notation: String) {
        var types: [Character] = []
        var edgeTokens: [[Substring]] = []
        var nodeIndexById: [Int: Int] = [:]
        for line in notation.split(separator: "\n") {
            guard let separator = line.range(of: "|-"),
                  let (nodeId, nodeType) = GitLogPortNotation.numberWithCharacter(line[..<separator.lowerBound]),
                  GitLogPortNotation.nodeTypeCharacters.contains(nodeType)
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

    func nodeTypeCharacter(at nodeIndex: Int) -> Character {
        nodeTypes.indices.contains(nodeIndex) ? nodeTypes[nodeIndex] : "?"
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

nonisolated struct TestGraphNode: Sendable {
    let id: Int
    let type: Character
    let edges: [TestGraphEdge]

    init(_ id: Int, type: Character = "U", edges: [TestGraphEdge] = []) {
        self.id = id
        self.type = type
        self.edges = edges
    }
}

nonisolated struct TestGraphEdge: Sendable {
    let toNode: Int?
    let type: GitLogLinearEdgeType

    static func usual(_ toNode: Int) -> TestGraphEdge {
        TestGraphEdge(toNode: toNode, type: .usual)
    }

    static func dotted(_ toNode: Int) -> TestGraphEdge {
        TestGraphEdge(toNode: toNode, type: .dotted)
    }

    static func upDot(_ toNode: Int?) -> TestGraphEdge {
        TestGraphEdge(toNode: toNode, type: .dottedArrowUp)
    }

    static func downDot(_ toNode: Int?) -> TestGraphEdge {
        TestGraphEdge(toNode: toNode, type: .dottedArrowDown)
    }

    static func notLoad(_ toNode: Int?) -> TestGraphEdge {
        TestGraphEdge(toNode: toNode, type: .notLoadCommit)
    }
}

nonisolated struct TestLinearGraph: GitLogTypedLinearGraph {
    private let nodes: [TestGraphNode]
    private let edges: [[GitLogLinearEdge]]

    init?(nodes: [TestGraphNode]) {
        var indexById: [Int: Int] = [:]
        for (index, node) in nodes.enumerated() {
            indexById[node.id] = index
        }
        var edges = [[GitLogLinearEdge]](repeating: [], count: nodes.count)
        for node in nodes {
            guard let nodeIndex = indexById[node.id] else { return nil }
            for edge in node.edges {
                if edge.type.isNormal {
                    guard let toNode = edge.toNode, let anotherIndex = indexById[toNode] else { return nil }
                    let graphEdge = GitLogLinearEdge.normal(anotherIndex, nodeIndex, type: edge.type)
                    edges[nodeIndex].append(graphEdge)
                    edges[anotherIndex].append(graphEdge)
                } else {
                    edges[nodeIndex].append(.withTarget(nodeIndex: nodeIndex, targetId: edge.toNode, type: edge.type))
                }
            }
        }
        self.nodes = nodes
        self.edges = edges
    }

    var nodesCount: Int {
        nodes.count
    }

    func nodeTypeCharacter(at nodeIndex: Int) -> Character {
        nodes.indices.contains(nodeIndex) ? nodes[nodeIndex].type : "?"
    }

    func adjacentEdges(of nodeIndex: Int, filter: GitLogEdgeFilter) -> [GitLogLinearEdge] {
        guard edges.indices.contains(nodeIndex) else { return [] }
        return edges[nodeIndex].filter { edge in
            if edge.type.isNormal {
                return (edge.isEdgeUp(at: nodeIndex) && filter.upNormal) || (edge.isEdgeDown(at: nodeIndex) && filter.downNormal)
            }
            return filter.special
        }
    }
}

nonisolated struct TestGraphBuilderCase: Sendable, CustomStringConvertible {
    let name: String
    let nodes: [TestGraphNode]

    var description: String { name }

    static let all: [TestGraphBuilderCase] = [
        TestGraphBuilderCase(name: "simple", nodes: [
            TestGraphNode(1, edges: [.usual(2)]),
            TestGraphNode(2, edges: [.usual(3)]),
            TestGraphNode(3)
        ]),
        TestGraphBuilderCase(name: "simpleManyNodes", nodes: [
            TestGraphNode(3, edges: [.usual(4), .usual(6), .usual(8)]),
            TestGraphNode(4, edges: [.usual(5), .usual(6), .usual(7), .usual(8)]),
            TestGraphNode(7, edges: [.usual(8), .usual(6)]),
            TestGraphNode(6, edges: [.usual(9), .usual(10), .usual(11)]),
            TestGraphNode(9, edges: [.usual(10), .usual(11)]),
            TestGraphNode(10, edges: [.usual(11)]),
            TestGraphNode(5, edges: [.usual(8), .usual(11)]),
            TestGraphNode(8, edges: [.usual(11)]),
            TestGraphNode(11)
        ]),
        TestGraphBuilderCase(name: "specialEdges", nodes: [
            TestGraphNode(1, edges: [
                .usual(2), .dotted(3), .notLoad(100), .downDot(42), .downDot(nil), .notLoad(nil), .upDot(0), .upDot(nil)
            ]),
            TestGraphNode(2, edges: [.upDot(nil)]),
            TestGraphNode(3, edges: [.upDot(0)])
        ]),
        TestGraphBuilderCase(name: "specialNodes", nodes: [
            TestGraphNode(2, edges: [.usual(3), .usual(4)]),
            TestGraphNode(3, type: "G", edges: [.dotted(4)]),
            TestGraphNode(4),
            TestGraphNode(100, type: "N")
        ])
    ]
}

nonisolated enum GitLogPortNotation {
    static let nodeTypeCharacters: Set<Character> = ["U", "G", "N"]

    static let defaultElementParameters = GitLogPrintElementParameters(
        longEdgeSize: 7,
        visiblePartSize: 2,
        edgeWithArrowSize: 10
    )

    static let elementParameters: [String: GitLogPrintElementParameters] = [
        "oneUpOneDown1": GitLogPrintElementParameters(longEdgeSize: 7, visiblePartSize: 1, edgeWithArrowSize: 10),
        "oneUpOneDown2": GitLogPrintElementParameters(longEdgeSize: 10, visiblePartSize: 1, edgeWithArrowSize: 10)
    ]

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

    static func negatedHexId(_ commitId: String) -> Int {
        -(Int(commitId, radix: 16) ?? 0)
    }

    static func permanentGraph(_ input: String) -> GitLogPermanentGraph {
        GitLogPermanentGraphBuilder.build(commits: commits(input), notLoadedCommitId: negatedHexId).graph
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

    static func graphText(_ graph: some GitLogTypedLinearGraph) -> String {
        (0..<graph.nodesCount).map { index in
            let edges = graph.adjacentEdges(of: index, filter: .all).map { describe($0) }.joined(separator: " ")
            return "\(index)_\(graph.nodeTypeCharacter(at: index))|-\(edges)"
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
            return "Node|-\(node.rowIndex):\(node.position)|-\(node.colorId):Unselect(\(node.nodeIndex)_\(graph.nodeTypeCharacter(at: node.nodeIndex)))"
        case .edge(let edge):
            let direction = edge.direction == .up ? "UP" : "DOWN"
            let arrow = edge.hasArrow ? "_ARROW" : ""
            let style = edge.lineStyle == .solid ? "SOLID" : "DASHED"
            let positions = "\(edge.rowIndex):\(edge.positionInCurrentRow):\(edge.positionInOtherRow)"
            return "Edge:\(direction)\(arrow):\(style)|-\(positions)|-\(edge.colorId):Unselect(\(describe(edge.edge)))"
        }
    }

    static func printElementsText(
        name: String,
        graph: NotationGraph
    ) -> String {
        let parameters = elementParameters[name] ?? defaultElementParameters
        let layout = GitLogNodeLayoutBuilder.build(graph: graph) { $0 - $1 }
        let comparator = GitLogElementComparator(layoutIndex: { layout.layoutIndex(of: $0) })
        let generator = GitLogPrintElementGenerator(
            graph: graph,
            comparator: comparator,
            longEdgeSize: parameters.longEdgeSize,
            visiblePartSize: parameters.visiblePartSize,
            edgeWithArrowSize: parameters.edgeWithArrowSize,
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

nonisolated struct GitLogPrintElementParameters: Sendable {
    let longEdgeSize: Int
    let visiblePartSize: Int
    let edgeWithArrowSize: Int
}
