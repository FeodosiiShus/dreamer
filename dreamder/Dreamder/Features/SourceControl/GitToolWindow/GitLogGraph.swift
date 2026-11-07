import Foundation

nonisolated struct GitLogGraphEdge: Hashable, Sendable {
    let fromLane: Int
    let toLane: Int
}

nonisolated struct GitLogGraphRow: Hashable, Sendable {
    let hash: String
    let lane: Int
    let edges: [GitLogGraphEdge]
    let elements: [GitLogPrintElement]
    let nodeColorId: Int
    let isHead: Bool

    init(
        hash: String,
        lane: Int,
        edges: [GitLogGraphEdge],
        elements: [GitLogPrintElement] = [],
        nodeColorId: Int = 0,
        isHead: Bool = false
    ) {
        self.hash = hash
        self.lane = lane
        self.edges = edges
        self.elements = elements
        self.nodeColorId = nodeColorId
        self.isHead = isHead
    }
}

nonisolated struct GitLogGraphSnapshot: Sendable {
    let rows: [GitLogGraphRow]
    let recommendedWidth: Int

    static let empty = GitLogGraphSnapshot(rows: [], recommendedWidth: 0)
}

nonisolated enum GitLogGraphLayout {
    static let minimumDisplayedLanes = 8

    static func rows(for commits: [GitLogCommit]) -> [GitLogGraphRow] {
        snapshot(commits: commits, visibleHashes: nil, firstParentOnly: false).rows
    }

    @concurrent
    static func snapshotAsync(
        commits: [GitLogCommit],
        visibleHashes: Set<String>?,
        firstParentOnly: Bool
    ) async -> GitLogGraphSnapshot {
        snapshot(commits: commits, visibleHashes: visibleHashes, firstParentOnly: firstParentOnly)
    }

    static func snapshot(
        commits allCommits: [GitLogCommit],
        visibleHashes: Set<String>?,
        firstParentOnly: Bool
    ) -> GitLogGraphSnapshot {
        let base = allCommits.map { commit -> GitLogGraphCommit in
            let parents = firstParentOnly ? Array(commit.parents.prefix(1)) : commit.parents
            return GitLogGraphCommit(id: commit.hash, parents: parents)
        }
        var visibleCommits = allCommits
        var graphCommits = base
        var dottedPairs = Set<String>()
        if let visibleHashes, !allCommits.allSatisfy({ visibleHashes.contains($0.hash) }) {
            visibleCommits = allCommits.filter { visibleHashes.contains($0.hash) }
            let collapsed = collapse(base, visible: visibleHashes)
            graphCommits = collapsed.commits
            dottedPairs = collapsed.dotted
        }

        guard !visibleCommits.isEmpty else { return .empty }

        let built = GitLogPermanentGraphBuilder.build(commits: graphCommits)
        var graph = built.graph

        var indexById: [String: Int] = [:]
        indexById.reserveCapacity(graphCommits.count)
        for (index, commit) in graphCommits.enumerated() where indexById[commit.id] == nil {
            indexById[commit.id] = index
        }

        if !dottedPairs.isEmpty {
            var dottedEdges = Set<GitLogNormalEdge>()
            for pair in dottedPairs {
                let ids = pair.components(separatedBy: " ")
                guard ids.count == 2, let child = indexById[ids[0]], let parent = indexById[ids[1]] else { continue }
                dottedEdges.insert(GitLogNormalEdge(up: min(child, parent), down: max(child, parent)))
            }
            graph = graph.withDottedEdges(dottedEdges)
        }
        var bestRefs: [Int: GitLogRef] = [:]
        var branchNodes = Set<Int>()
        for (index, commit) in visibleCommits.enumerated() {
            if let best = GitLogHeadOrder.bestRef(of: commit.refs) {
                bestRefs[index] = best
            }
            if commit.refs.contains(where: GitLogHeadOrder.isBranch) {
                branchNodes.insert(index)
            }
        }

        let layout = GitLogNodeLayoutBuilder.build(graph: graph, branches: branchNodes) { left, right in
            GitLogHeadOrder.compareHeads(left, right, bestRefs: bestRefs)
        }

        let seeds = bestRefs.mapValues { Int(GitLogGraphColors.javaHash($0.name)) }
        let colorGetter = GitLogGraphColorGetter(layout: layout, headColorSeeds: seeds)
        let comparator = GitLogElementComparator(layoutIndex: { layout.layoutIndex(of: $0) })
        let generator = GitLogPrintElementGenerator(
            graph: graph,
            comparator: comparator,
            showLongEdges: false,
            colorId: { colorGetter.colorId(of: $0) }
        )

        var rows: [GitLogGraphRow] = []
        rows.reserveCapacity(visibleCommits.count)
        for (index, commit) in visibleCommits.enumerated() {
            let elements = generator.printElements(at: index)
            rows.append(makeRow(commit: commit, elements: elements))
        }
        return GitLogGraphSnapshot(rows: rows, recommendedWidth: generator.recommendedWidth())
    }

    static func laneCount(_ rows: [GitLogGraphRow]) -> Int {
        var count = 1
        for row in rows {
            count = max(count, row.lane + 1)
            for edge in row.edges {
                count = max(count, edge.fromLane + 1)
                count = max(count, edge.toLane + 1)
            }
            for element in row.elements {
                switch element {
                case .node(let node):
                    count = max(count, node.position + 1)
                case .edge(let edge):
                    count = max(count, edge.positionInCurrentRow + 1)
                    count = max(count, edge.positionInOtherRow + 1)
                }
            }
        }
        return count
    }

    static func displayedLaneCount(_ snapshot: GitLogGraphSnapshot) -> Int {
        let maximum = laneCount(snapshot.rows)
        return min(maximum, max(snapshot.recommendedWidth, minimumDisplayedLanes))
    }

    private static func makeRow(commit: GitLogCommit, elements: [GitLogPrintElement]) -> GitLogGraphRow {
        var lane = 0
        var colorId = 0
        var edges: [GitLogGraphEdge] = []
        for element in elements {
            switch element {
            case .node(let node):
                lane = node.position
                colorId = node.colorId
            case .edge(let edge) where edge.direction == .down && !edge.isTerminal:
                edges.append(GitLogGraphEdge(fromLane: edge.positionInCurrentRow, toLane: edge.positionInOtherRow))
            case .edge:
                break
            }
        }
        return GitLogGraphRow(
            hash: commit.hash,
            lane: lane,
            edges: edges,
            elements: elements,
            nodeColorId: colorId,
            isHead: commit.refs.contains { $0.kind == .head }
        )
    }

    private struct Collapsed {
        let commits: [GitLogGraphCommit]
        let dotted: Set<String>
    }

    private static func collapse(_ base: [GitLogGraphCommit], visible: Set<String>) -> Collapsed {
        var nearestVisible: [String: [String]] = [:]
        for commit in base.reversed() where !visible.contains(commit.id) {
            var ancestors: [String] = []
            var seen = Set<String>()
            for parent in commit.parents {
                let candidates = visible.contains(parent) ? [parent] : (nearestVisible[parent] ?? [parent])
                for candidate in candidates where seen.insert(candidate).inserted {
                    ancestors.append(candidate)
                }
            }
            nearestVisible[commit.id] = ancestors
        }

        var commits: [GitLogGraphCommit] = []
        var dotted = Set<String>()
        for commit in base where visible.contains(commit.id) {
            var parents: [String] = []
            var seen = Set<String>()
            let direct = Set(commit.parents)
            for parent in commit.parents {
                let candidates = visible.contains(parent) ? [parent] : (nearestVisible[parent] ?? [parent])
                for candidate in candidates where seen.insert(candidate).inserted {
                    parents.append(candidate)
                    if !direct.contains(candidate) {
                        dotted.insert("\(commit.id) \(candidate)")
                    }
                }
            }
            commits.append(GitLogGraphCommit(id: commit.id, parents: parents))
        }
        return Collapsed(commits: commits, dotted: dotted)
    }
}
