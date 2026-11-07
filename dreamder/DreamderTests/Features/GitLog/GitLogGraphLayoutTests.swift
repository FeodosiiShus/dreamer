import Foundation
import Testing
@testable import Dreamder

@Suite
struct GitLogGraphLayoutTests {
    private func commit(_ hash: String, _ parents: [String], refs: [GitLogRef] = []) -> GitLogCommit {
        GitLogCommit(
            hash: hash,
            parents: parents,
            authorName: "Ada Lovelace",
            authorEmail: "ada@example.com",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            refs: refs,
            subject: hash
        )
    }

    private var mergeCommits: [GitLogCommit] {
        [
            commit("merge", ["main1", "feature1"]),
            commit("main1", ["base"]),
            commit("feature1", ["base"]),
            commit("base", [])
        ]
    }

    @Test
    func linearHistoryUsesOneLane() throws {
        let commits = [
            commit("a", ["b"]),
            commit("b", ["c"]),
            commit("c", [])
        ]

        let rows = GitLogGraphLayout.rows(for: commits)
        #expect(rows.count == 3)
        #expect(rows.map(\.lane) == [0, 0, 0])
        #expect(GitLogGraphLayout.laneCount(rows) == 1)
        let last = try #require(rows.last)
        #expect(last.edges.isEmpty)
    }

    @Test
    func mergeCreatesAndClosesSecondLane() throws {
        let rows = GitLogGraphLayout.rows(for: mergeCommits)
        #expect(rows.map(\.lane) == [0, 0, 1, 0])
        #expect(GitLogGraphLayout.laneCount(rows) == 2)

        let mergeRow = try #require(rows.first)
        #expect(mergeRow.edges.contains(GitLogGraphEdge(fromLane: 0, toLane: 1)))

        let closeRow = try #require(rows.first { $0.hash == "feature1" })
        #expect(closeRow.edges.contains(GitLogGraphEdge(fromLane: 1, toLane: 0)))
        #expect(!closeRow.edges.contains(GitLogGraphEdge(fromLane: 0, toLane: 1)))
    }

    @Test
    func independentBranchesUseDistinctLanes() throws {
        let commits = [
            commit("x1", ["x2"]),
            commit("y1", ["y2"]),
            commit("x2", []),
            commit("y2", [])
        ]

        let rows = GitLogGraphLayout.rows(for: commits)
        #expect(rows.map(\.lane) == [0, 1, 0, 0])
        #expect(GitLogGraphLayout.laneCount(rows) == 2)

        let second = try #require(rows.first { $0.hash == "y1" })
        #expect(second.lane == 1)
        #expect(second.edges.contains(GitLogGraphEdge(fromLane: 0, toLane: 0)))
        #expect(second.edges.contains(GitLogGraphEdge(fromLane: 1, toLane: 1)))
    }

    @Test
    func repeatedMergesReuseTheSameSecondLane() throws {
        let commits = [
            commit("mergeA", ["a1", "a2"]),
            commit("a1", ["mergeB"]),
            commit("a2", ["mergeB"]),
            commit("mergeB", ["b1", "b2"]),
            commit("b1", ["base"]),
            commit("b2", ["base"]),
            commit("base", [])
        ]

        let rows = GitLogGraphLayout.rows(for: commits)
        #expect(GitLogGraphLayout.laneCount(rows) == 2)
        #expect(rows.map(\.lane) == [0, 0, 1, 0, 0, 1, 0])
        let secondMerge = try #require(rows.first { $0.hash == "mergeB" })
        #expect(secondMerge.edges.contains(GitLogGraphEdge(fromLane: 0, toLane: 1)))
        #expect(rows.last?.lane == 0)
    }

    @Test
    func emptyHistoryHasSingleLane() {
        #expect(GitLogGraphLayout.laneCount([GitLogGraphRow]()) == 1)
    }

    @Test
    func downEdgesMatchPositionsInTheNextRow() throws {
        let rows = GitLogGraphLayout.rows(for: mergeCommits)
        #expect(rows.map(\.edges) == [
            [GitLogGraphEdge(fromLane: 0, toLane: 0), GitLogGraphEdge(fromLane: 0, toLane: 1)],
            [GitLogGraphEdge(fromLane: 0, toLane: 0), GitLogGraphEdge(fromLane: 1, toLane: 1)],
            [GitLogGraphEdge(fromLane: 0, toLane: 0), GitLogGraphEdge(fromLane: 1, toLane: 0)],
            []
        ])
    }

    @Test
    func everyRowHasExactlyOneNodeElementAtItsLane() throws {
        let rows = GitLogGraphLayout.rows(for: mergeCommits)
        #expect(rows.count == 4)
        for (index, row) in rows.enumerated() {
            #expect(!row.elements.isEmpty)
            let nodes = row.elements.compactMap { element -> GitLogNodePrintElement? in
                if case .node(let node) = element { node } else { nil }
            }
            #expect(nodes.count == 1)
            let node = try #require(nodes.first)
            #expect(node.rowIndex == index)
            #expect(node.position == row.lane)
            #expect(node.colorId == row.nodeColorId)
        }
    }

    @Test
    func unloadedParentProducesTerminalArrowElement() throws {
        let commits = [
            commit("a", ["missing"]),
            commit("b", [])
        ]

        let rows = GitLogGraphLayout.rows(for: commits)
        #expect(rows.count == 2)
        let second = try #require(rows.last)
        let arrows = second.elements.compactMap { element -> GitLogEdgePrintElement? in
            if case .edge(let edge) = element, edge.isTerminal { edge } else { nil }
        }
        let arrow = try #require(arrows.first)
        #expect(arrows.count == 1)
        #expect(arrow.hasArrow)
        #expect(arrow.direction == .down)
        #expect(arrow.edge.type == .notLoadCommit)
        #expect(second.edges.isEmpty)
        #expect(second.lane == 1)
    }

    @Test
    func hiddenCommitsAreCollapsedIntoDashedEdge() throws {
        let commits = [
            commit("a", ["b"]),
            commit("b", ["c"]),
            commit("c", [])
        ]

        let snapshot = GitLogGraphLayout.snapshot(commits: commits, visibleHashes: ["a", "c"], firstParentOnly: false)
        #expect(snapshot.rows.map(\.hash) == ["a", "c"])
        #expect(snapshot.rows.map(\.lane) == [0, 0])

        let first = try #require(snapshot.rows.first)
        #expect(first.edges == [GitLogGraphEdge(fromLane: 0, toLane: 0)])
        let downEdges = first.elements.compactMap { element -> GitLogEdgePrintElement? in
            if case .edge(let edge) = element, edge.direction == .down { edge } else { nil }
        }
        let downEdge = try #require(downEdges.first)
        #expect(downEdges.count == 1)
        #expect(downEdge.lineStyle == .dashed)
        #expect(downEdge.edge.type == .dotted)
    }

    @Test
    func fullyVisibleHistoryKeepsSolidEdges() throws {
        let commits = [
            commit("a", ["b"]),
            commit("b", [])
        ]

        let snapshot = GitLogGraphLayout.snapshot(commits: commits, visibleHashes: ["a", "b"], firstParentOnly: false)
        #expect(snapshot.rows.map(\.hash) == ["a", "b"])
        let first = try #require(snapshot.rows.first)
        let styles = first.elements.compactMap { element -> GitLogEdgeLineStyle? in
            if case .edge(let edge) = element { edge.lineStyle } else { nil }
        }
        #expect(styles == [.solid])
    }

    @Test
    func emptyVisibleSetYieldsEmptySnapshot() {
        let snapshot = GitLogGraphLayout.snapshot(commits: mergeCommits, visibleHashes: [], firstParentOnly: false)
        #expect(snapshot.rows.isEmpty)
        #expect(snapshot.recommendedWidth == 0)
    }

    @Test
    func firstParentOnlyDropsSecondParentEdges() throws {
        let rows = GitLogGraphLayout.snapshot(commits: mergeCommits, visibleHashes: nil, firstParentOnly: true).rows
        #expect(rows.map(\.hash) == ["merge", "main1", "feature1", "base"])
        let mergeRow = try #require(rows.first)
        #expect(mergeRow.edges == [GitLogGraphEdge(fromLane: 0, toLane: 0)])

        let withSecondParent = GitLogGraphLayout.rows(for: mergeCommits)
        let fullMergeRow = try #require(withSecondParent.first)
        #expect(fullMergeRow.edges.count == 2)
    }

    @Test
    func branchHeadNodeColorUsesBestRefNameHash() throws {
        let commits = [
            commit("a", ["b"], refs: [GitLogRef(name: "feature", kind: .branch), GitLogRef(name: "HEAD", kind: .head)]),
            commit("b", [])
        ]

        let rows = GitLogGraphLayout.rows(for: commits)
        let first = try #require(rows.first)
        #expect(first.nodeColorId == Int(GitLogGraphColors.javaHash("feature")))
        #expect(first.isHead)
        let second = try #require(rows.last)
        #expect(!second.isHead)
    }

    @Test
    func headFlagFollowsHeadRefKindOnly() throws {
        let branchOnly = GitLogGraphLayout.rows(for: [commit("a", [], refs: [GitLogRef(name: "main", kind: .branch)])])
        let branchRow = try #require(branchOnly.first)
        #expect(!branchRow.isHead)
        #expect(branchRow.nodeColorId == Int(GitLogGraphColors.javaHash("main")))
        #expect(branchRow.nodeColorId == 3_343_801)

        let headOnly = GitLogGraphLayout.rows(for: [commit("a", [], refs: [GitLogRef(name: "HEAD", kind: .head)])])
        let headRow = try #require(headOnly.first)
        #expect(headRow.isHead)
        #expect(headRow.nodeColorId == Int(GitLogGraphColors.javaHash("HEAD")))
    }

    @Test
    func headWithoutRefsUsesDefaultColor() throws {
        let commits = [
            commit("a", [], refs: [GitLogRef(name: "main", kind: .branch)]),
            commit("x", [])
        ]

        let rows = GitLogGraphLayout.rows(for: commits)
        let plain = try #require(rows.last)
        #expect(plain.nodeColorId == GitLogGraphColorGetter.defaultColorId)
    }

    @Test
    func duplicateParentsAreDeduplicated() throws {
        let commits = [
            commit("a", ["b", "b"]),
            commit("b", [])
        ]

        let rows = GitLogGraphLayout.rows(for: commits)
        let first = try #require(rows.first)
        #expect(first.edges == [GitLogGraphEdge(fromLane: 0, toLane: 0)])
        let downElements = first.elements.filter {
            if case .edge(let edge) = $0 { edge.direction == .down } else { false }
        }
        #expect(downElements.count == 1)
        #expect(GitLogGraphLayout.laneCount(rows) == 1)
    }
}
