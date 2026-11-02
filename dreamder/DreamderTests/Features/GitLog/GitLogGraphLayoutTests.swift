import Foundation
import Testing
@testable import Dreamder

@Suite
struct GitLogGraphLayoutTests {
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
        let commits = [
            commit("merge", ["main1", "feature1"]),
            commit("main1", ["base"]),
            commit("feature1", ["base"]),
            commit("base", [])
        ]

        let rows = GitLogGraphLayout.rows(for: commits)
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
        #expect(rows.map(\.lane) == [0, 1, 0, 1])
        #expect(GitLogGraphLayout.laneCount(rows) == 2)

        let second = try #require(rows.first { $0.hash == "y1" })
        #expect(second.lane == 1)
        #expect(second.edges.contains(GitLogGraphEdge(fromLane: 0, toLane: 0)))
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
}
