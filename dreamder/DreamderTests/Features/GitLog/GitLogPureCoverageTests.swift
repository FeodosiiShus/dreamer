import Foundation
import Testing
@testable import Dreamder

@Suite
struct GitLogPureCoverageTests {
    private func commit(_ hash: String, _ parents: [String]) -> GitLogCommit {
        GitLogCommit(
            hash: hash,
            parents: parents,
            authorName: "Ada Lovelace",
            authorEmail: "ada@example.com",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            refs: [],
            subject: hash
        )
    }

    private static func longGraph(count: Int) -> GitLogPermanentGraph {
        let commits = (0..<count).map { index -> GitLogGraphCommit in
            var parents: [String] = []
            if index + 1 < count { parents.append("c\(index + 1)") }
            if index % 7 == 0, index + 9 < count { parents.append("c\(index + 9)") }
            if index % 13 == 0, index + 45 < count { parents.append("c\(index + 45)") }
            return GitLogGraphCommit(id: "c\(index)", parents: parents)
        }
        return GitLogPermanentGraphBuilder.build(commits: commits).graph
    }

    private static func chainWithLongEdge(count: Int, to target: Int) -> GitLogPermanentGraph {
        let commits = (0..<count).map { index -> GitLogGraphCommit in
            var parents: [String] = []
            if index + 1 < count { parents.append("c\(index + 1)") }
            if index == 0 { parents.append("c\(target)") }
            return GitLogGraphCommit(id: "c\(index)", parents: parents)
        }
        return GitLogPermanentGraphBuilder.build(commits: commits).graph
    }

    @Test
    func commitIdentifierIsItsHash() {
        #expect(commit("0123456789abcdef", []).id == "0123456789abcdef")
    }

    @Test
    func rangeFilterWithoutRangesYieldsNoParameters() {
        let filters = GitLogFilterCollection(range: GitLogRangeFilter(ranges: []))
        #expect(GitLogArguments.parameters(filters: filters, maxCount: nil, existingBranches: []) == nil)
    }

    @Test
    func invalidRegularExpressionsNeverMatch() {
        #expect(GitLogTextSyntax.matchesWhole("(", in: "(") == false)
        #expect(GitLogTextSyntax.matchesWhole("ma.n", in: "main"))
        let broken = GitLogTextFilter(text: "(", isRegex: true, matchesCase: false)
        #expect(broken.matcher().matches("(") == false)
    }

    @Test
    func edgeSortKeysCoverEveryEdgeType() {
        #expect(GitLogLinearEdge.normal(2, 5).sortKey == [2, 5, 0, 0])
        #expect(GitLogLinearEdge.normal(5, 2, type: .dotted).sortKey == [2, 5, 0, 1])
        #expect(GitLogLinearEdge.withTarget(nodeIndex: 3, targetId: -7, type: .notLoadCommit).sortKey == [3, -1, -7, 2])
        #expect(GitLogLinearEdge.withTarget(nodeIndex: 4, targetId: nil, type: .dottedArrowUp).sortKey == [-1, 4, 0, 3])
        #expect(GitLogLinearEdge.withTarget(nodeIndex: 1, targetId: 9, type: .dottedArrowDown).sortKey == [1, -1, 9, 4])
        #expect(GitLogGraphElement.node(3).sortKey == [0, 3])
        #expect(GitLogGraphElement.edge(.normal(2, 5)).sortKey == [1, 2, 5, 0, 0])
    }

    @Test
    func comparatorBreaksTiesByElementSortKey() {
        let comparator = GitLogElementComparator(layoutIndex: { _ in 0 })
        #expect(comparator.areInIncreasingOrder(.node(1), .node(2)))
        #expect(comparator.areInIncreasingOrder(.node(2), .node(1)) == false)

        let first = GitLogLinearEdge.withTarget(nodeIndex: 3, targetId: -2, type: .notLoadCommit)
        let second = GitLogLinearEdge.withTarget(nodeIndex: 3, targetId: -3, type: .notLoadCommit)
        #expect(comparator.compare(.edge(first), .edge(second)) == 0)
        #expect(comparator.areInIncreasingOrder(.edge(second), .edge(first)))
        #expect(comparator.areInIncreasingOrder(.edge(first), .edge(second)) == false)
    }

    @Test
    func comparatorOrdersNormalEdgesAgainstSpecialEdges() {
        let comparator = GitLogElementComparator(layoutIndex: { $0 })
        let normal = GitLogLinearEdge.normal(1, 4)
        let special = GitLogLinearEdge.withTarget(nodeIndex: 4, targetId: -2, type: .notLoadCommit)
        #expect(comparator.compare(.edge(normal), .edge(special)) == -3)
        #expect(comparator.compare(.edge(special), .edge(normal)) == 3)
    }

    @Test
    func printElementsExposeTheirColor() {
        let node = GitLogPrintElement.node(GitLogNodePrintElement(rowIndex: 0, position: 1, nodeIndex: 2, colorId: 7))
        let edge = GitLogPrintElement.edge(GitLogEdgePrintElement(
            rowIndex: 0,
            positionInCurrentRow: 1,
            positionInOtherRow: 2,
            direction: .down,
            lineStyle: .solid,
            hasArrow: false,
            isTerminal: false,
            colorId: 11,
            edge: .normal(0, 1)
        ))
        #expect(node.colorId == 7)
        #expect(edge.colorId == 11)
    }

    @Test
    func edgesInRowOfALongGraphMatchTheEdgesCrossingEachRow() {
        let graph = Self.longGraph(count: 130)
        var crossing = Set<GitLogNormalEdge>()
        for node in 0..<graph.nodesCount {
            for edge in graph.adjacentEdges(of: node, filter: .normalDown) {
                if let normal = edge.normalEdge { crossing.insert(normal) }
            }
        }
        #expect(crossing.contains { $0.down - $0.up > 40 })

        let generator = GitLogEdgesInRowGenerator(graph: graph)
        func edgesInRow(_ row: Int) -> Set<GitLogNormalEdge> {
            Set(generator.edgesInRow(row).compactMap(\.normalEdge))
        }
        func expected(_ row: Int) -> Set<GitLogNormalEdge> {
            crossing.filter { $0.up < row && $0.down > row }
        }

        for row in 0..<graph.nodesCount {
            #expect(edgesInRow(row) == expected(row))
        }
        for row in (0..<graph.nodesCount).reversed() {
            #expect(edgesInRow(row) == expected(row))
        }
        generator.invalidate()
        for row in stride(from: 0, to: graph.nodesCount, by: 3) {
            #expect(edgesInRow(row) == expected(row))
        }
    }

    @Test
    func recommendedWidthIgnoresHiddenLongEdges() {
        let graph = Self.chainWithLongEdge(count: 46, to: 40)
        let generator = GitLogPrintElementGenerator(
            graph: graph,
            comparator: GitLogElementComparator(layoutIndex: { _ in 0 }),
            showLongEdges: false,
            colorId: { _ in 0 }
        )
        let width = generator.recommendedWidth()
        #expect(width >= 1)
        #expect(width <= 2)
    }

    @Test
    func recommendedWidthCountsArrowsOfHiddenLongEdges() {
        let graph = Self.chainWithLongEdge(count: 46, to: 40)
        let generator = GitLogPrintElementGenerator(
            graph: graph,
            comparator: GitLogElementComparator(layoutIndex: { _ in 0 }),
            longEdgeSize: 30,
            visiblePartSize: 0,
            edgeWithArrowSize: 30,
            colorId: { _ in 0 }
        )
        let width = generator.recommendedWidth()
        #expect(width >= 1)
        #expect(width <= 3)
    }

    @Test
    func recommendedWidthCountsUpArrowsOfSpecialEdges() throws {
        let testCase = try #require(TestGraphBuilderCase.all.first { $0.name == "specialEdges" })
        let graph = try #require(TestLinearGraph(nodes: testCase.nodes))
        let generator = GitLogPrintElementGenerator(
            graph: graph,
            comparator: GitLogElementComparator(layoutIndex: { _ in 0 }),
            showLongEdges: false,
            colorId: { _ in 0 }
        )
        #expect(generator.recommendedWidth() >= 1)
    }

    @Test
    func sameTierRefsAreOrderedByNaturalName() {
        let two = GitLogRef(name: "feature-2", kind: .branch)
        let ten = GitLogRef(name: "feature-10", kind: .branch)
        #expect(GitLogHeadOrder.compare(two, ten) == -1)
        #expect(GitLogHeadOrder.compare(ten, two) == 1)
        #expect(GitLogHeadOrder.compare(two, two) == 0)
        #expect(GitLogHeadOrder.bestRef(of: [ten, two]) == two)
    }

    @Test
    func negativeHueWrapsIntoTheUnitRange() {
        let hue = GitLogGraphColors.hue(forColorId: -296)
        #expect(abs(hue - 0.958333) < 0.001)
    }

    @Test
    func collapsedHistoryKeepsParentsThatWereNeverLoaded() {
        let commits = [
            commit("v1", ["h"]),
            commit("h", ["zz"]),
            commit("v2", ["qq"])
        ]
        let snapshot = GitLogGraphLayout.snapshot(commits: commits, visibleHashes: ["v1", "v2"], firstParentOnly: false)
        #expect(snapshot.rows.map(\.hash) == ["v1", "v2"])
        let terminalArrows = snapshot.rows.last?.elements.filter { element in
            if case .edge(let edge) = element { edge.isTerminal } else { false }
        }
        #expect(terminalArrows?.count == 1)
    }

    @Test
    func targetedNormalEdgesBecomeNotLoadedEdges() {
        for type in [GitLogLinearEdgeType.usual, .dotted] {
            let edge = GitLogLinearEdge.withTarget(nodeIndex: 2, targetId: 5, type: type)
            #expect(edge.type == .notLoadCommit)
            #expect(edge.upNodeIndex == 2)
            #expect(edge.downNodeIndex == nil)
            #expect(edge.targetId == 5)
        }
        let detached = GitLogLinearEdge(upNodeIndex: nil, downNodeIndex: nil, targetId: nil, type: .notLoadCommit)
        #expect(detached.notNullNodeIndex == 0)
    }

    @Test
    func permanentGraphHasNoEdgesOutsideItsNodes() {
        let graph = GitLogPortNotation.permanentGraph("a|-b\nb|-")
        #expect(graph.adjacentEdges(of: -1, filter: .all).isEmpty)
        #expect(graph.adjacentEdges(of: graph.nodesCount, filter: .all).isEmpty)
    }

    @Test
    func comparatorOrdersNodesAgainstEdgesSymmetrically() {
        let comparator = GitLogElementComparator(layoutIndex: { $0 })
        let edge = GitLogLinearEdge.normal(1, 4)
        #expect(comparator.compare(.node(4), .edge(edge)) == -comparator.compare(.edge(edge), .node(4)))
        #expect(comparator.compare(.node(2), .edge(edge)) == -2)
    }

    @Test
    func longEdgeVisibilityShowsArrowsNextToTheEndpoints() {
        let graph = Self.chainWithLongEdge(count: 46, to: 40)
        let generator = GitLogPrintElementGenerator(
            graph: graph,
            comparator: GitLogElementComparator(layoutIndex: { _ in 0 }),
            showLongEdges: true,
            colorId: { _ in 0 }
        )
        let width = generator.recommendedWidth()
        #expect(width >= 1)
        #expect(width <= 3)

        func arrows(at row: Int, direction: GitLogEdgeDirection) -> [GitLogEdgePrintElement] {
            generator.printElements(at: row).compactMap { element -> GitLogEdgePrintElement? in
                if case .edge(let edge) = element, edge.hasArrow, edge.direction == direction { edge } else { nil }
            }
        }
        #expect(arrows(at: 1, direction: .down).isEmpty == false)
        #expect(arrows(at: 39, direction: .up).isEmpty == false)
        #expect(arrows(at: 20, direction: .down).isEmpty)
    }

    @Test
    func malformedEdgesCarryNoArrow() {
        let generator = GitLogPrintElementGenerator(
            graph: GitLogMalformedEdgeGraph(),
            comparator: GitLogElementComparator(layoutIndex: { _ in 0 }),
            showLongEdges: false,
            colorId: { _ in 0 }
        )
        let elements = generator.printElements(at: 0)
        #expect(elements.count == 1)
        if case .node(let node) = elements.first {
            #expect(node.nodeIndex == 0)
        } else {
            Issue.record("Expected the node element")
        }
    }

    @Test
    func nodeLayoutFallsBackForUnknownNodesAndMissingHeads() {
        let layout = GitLogNodeLayout(layoutIndexes: [1], headNodeIndexes: [5])
        #expect(layout.layoutIndex(of: 3) == 0)
        #expect(layout.oneOfHeadNodeIndex(of: 0) == 5)

        let headless = GitLogNodeLayout(layoutIndexes: [1], headNodeIndexes: [])
        #expect(headless.oneOfHeadNodeIndex(of: 0) == 0)
    }

    @Test
    func layoutBuilderSkipsVisitedAndUnknownBranchHeads() {
        let graph = GitLogPortNotation.permanentGraph("a|-b\nb|-")
        let layout = GitLogNodeLayoutBuilder.build(graph: graph, branches: [1, 99]) { _, _ in 0 }
        #expect(layout.headNodeIndexes == [0])
        #expect(layout.layoutIndexes == [1, 1])
    }

    @Test
    func colorGetterTreatsNegativeNodeIdsAsNotLoadedCommits() {
        let layout = GitLogNodeLayout(layoutIndexes: [1, 1], headNodeIndexes: [0])
        let getter = GitLogGraphColorGetter(layout: layout, headColorSeeds: [0: 42])
        #expect(getter.nodeColor(nodeId: -3, layoutIndex: 1) == 42)
        #expect(getter.nodeColor(nodeId: -3, layoutIndex: 2) == 2)
        #expect(getter.colorId(of: .node(-3)) == -3)
        #expect(getter.colorId(of: .node(1)) == 42)
    }
}

private nonisolated struct GitLogMalformedEdgeGraph: GitLogLinearGraph {
    var nodesCount: Int { 1 }

    func adjacentEdges(of nodeIndex: Int, filter: GitLogEdgeFilter) -> [GitLogLinearEdge] {
        [GitLogLinearEdge(upNodeIndex: 0, downNodeIndex: nil, targetId: nil, type: .usual)]
    }
}
