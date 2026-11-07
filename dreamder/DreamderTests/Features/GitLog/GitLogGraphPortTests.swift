import Foundation
import Testing
@testable import Dreamder

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
        #expect(NotationGraph(notation: "0_X|-") == nil)
        #expect(NotationGraph(notation: "zero") == nil)
    }

    @Test(arguments: try IntelliJTestData.pairs(in: "platform/vcs-log/graph/testData/edgesInRow"))
    func edgesInRowMatchesIntelliJ(_ fixture: IntelliJTestData.Pair) throws {
        let graph = try #require(NotationGraph(notation: fixture.input))
        #expect(GitLogPortNotation.edgesInRowText(graph) == fixture.expected)
    }

    @Test(arguments: try IntelliJTestData.pairs(in: "platform/vcs-log/graph/testData/layoutBuilder"))
    func nodeLayoutMatchesIntelliJ(_ fixture: IntelliJTestData.Pair) {
        #expect(GitLogPortNotation.layoutText(fixture.input) == fixture.expected)
    }

    @Test(arguments: try IntelliJTestData.pairs(in: "platform/vcs-log/graph/testData/graphBuilder"))
    func permanentGraphMatchesIntelliJ(_ fixture: IntelliJTestData.Pair) {
        #expect(GitLogPortNotation.graphText(GitLogPortNotation.permanentGraph(fixture.input)) == fixture.expected)
    }

    @Test(arguments: try IntelliJTestData.pairs(in: "platform/vcs-log/graph/testData/testParser"))
    func parserDumpMatchesIntelliJ(_ fixture: IntelliJTestData.Pair) throws {
        let graph = try #require(NotationGraph(notation: fixture.input))
        #expect(GitLogPortNotation.graphText(graph) == fixture.expected)
    }

    @Test(arguments: TestGraphBuilderCase.all)
    func testGraphBuilderMatchesIntelliJ(_ testCase: TestGraphBuilderCase) throws {
        let graph = try #require(TestLinearGraph(nodes: testCase.nodes))
        let expected = try IntelliJTestData.text("platform/vcs-log/graph/testData/testGraphBuilder/\(testCase.name).txt")
        #expect(GitLogPortNotation.graphText(graph) == expected)
    }

    @Test
    func testGraphBuilderRejectsNormalEdgeToUnknownNode() {
        #expect(TestLinearGraph(nodes: [TestGraphNode(1, edges: [.usual(2)])]) == nil)
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
    func notLoadedCommitIdFunctionProvidesTargetIds() {
        let commits = GitLogPortNotation.commits("""
        a0|-a1 a6
        a1|-a6
        """)
        let result = GitLogPermanentGraphBuilder.build(commits: commits, notLoadedCommitId: GitLogPortNotation.negatedHexId)
        #expect(result.notLoadedCommitIds == [-166: "a6"])
    }

    @Test
    func duplicateParentsAreRemovedBeforeBuilding() {
        let commit = GitLogGraphCommit(id: "0", parents: ["1", "1", "1", "3", "1", "1"])
        #expect(GitLogPermanentGraphBuilder.fixDuplicateParents(commit).parents == ["1", "3"])
        let unique = GitLogGraphCommit(id: "0", parents: ["1", "3"])
        #expect(GitLogPermanentGraphBuilder.fixDuplicateParents(unique) == unique)
    }

    @Test(arguments: try IntelliJTestData.pairs(in: "platform/vcs-log/graph/testData/elementGenerator"))
    func printElementsMatchIntelliJ(_ fixture: IntelliJTestData.Pair) throws {
        let graph = try #require(NotationGraph(notation: fixture.input))
        #expect(GitLogPortNotation.printElementsText(name: fixture.name, graph: graph) == fixture.expected)
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
