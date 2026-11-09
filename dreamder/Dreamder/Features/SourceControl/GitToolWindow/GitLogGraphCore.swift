import Foundation

nonisolated enum GitLogLinearEdgeType: Hashable, Sendable {
    case usual
    case dotted
    case notLoadCommit
    case dottedArrowUp
    case dottedArrowDown

    var isNormal: Bool {
        self == .usual || self == .dotted
    }
}

nonisolated struct GitLogEdgeFilter: Sendable {
    let upNormal: Bool
    let downNormal: Bool
    let special: Bool

    static let all = GitLogEdgeFilter(upNormal: true, downNormal: true, special: true)
    static let normalDown = GitLogEdgeFilter(upNormal: false, downNormal: true, special: false)
    static let normalUp = GitLogEdgeFilter(upNormal: true, downNormal: false, special: false)
    static let normalAll = GitLogEdgeFilter(upNormal: true, downNormal: true, special: false)
    static let special = GitLogEdgeFilter(upNormal: false, downNormal: false, special: true)
}

nonisolated struct GitLogNormalEdge: Hashable, Sendable {
    let up: Int
    let down: Int
}

nonisolated struct GitLogLinearEdge: Hashable, Sendable {
    let upNodeIndex: Int?
    let downNodeIndex: Int?
    let targetId: Int?
    let type: GitLogLinearEdgeType

    static func normal(_ first: Int, _ second: Int, type: GitLogLinearEdgeType = .usual) -> GitLogLinearEdge {
        GitLogLinearEdge(
            upNodeIndex: min(first, second),
            downNodeIndex: max(first, second),
            targetId: nil,
            type: type
        )
    }

    static func withTarget(nodeIndex: Int, targetId: Int?, type: GitLogLinearEdgeType) -> GitLogLinearEdge {
        switch type {
        case .dottedArrowUp:
            return GitLogLinearEdge(upNodeIndex: nil, downNodeIndex: nodeIndex, targetId: targetId, type: type)
        case .notLoadCommit, .dottedArrowDown:
            return GitLogLinearEdge(upNodeIndex: nodeIndex, downNodeIndex: nil, targetId: targetId, type: type)
        case .usual, .dotted:
            return GitLogLinearEdge(upNodeIndex: nodeIndex, downNodeIndex: nil, targetId: targetId, type: .notLoadCommit)
        }
    }

    var normalEdge: GitLogNormalEdge? {
        guard type.isNormal, let upNodeIndex, let downNodeIndex else { return nil }
        return GitLogNormalEdge(up: upNodeIndex, down: downNodeIndex)
    }

    var notNullNodeIndex: Int {
        upNodeIndex ?? downNodeIndex ?? 0
    }

    func isEdgeUp(at nodeIndex: Int) -> Bool {
        downNodeIndex == nodeIndex
    }

    func isEdgeDown(at nodeIndex: Int) -> Bool {
        upNodeIndex == nodeIndex
    }

    var sortKey: [Int] {
        [upNodeIndex ?? -1, downNodeIndex ?? -1, targetId ?? 0, GitLogLinearEdge.order(of: type)]
    }

    private static func order(of type: GitLogLinearEdgeType) -> Int {
        switch type {
        case .usual: 0
        case .dotted: 1
        case .notLoadCommit: 2
        case .dottedArrowUp: 3
        case .dottedArrowDown: 4
        }
    }
}

nonisolated enum GitLogGraphElement: Hashable, Sendable {
    case node(Int)
    case edge(GitLogLinearEdge)

    var sortKey: [Int] {
        switch self {
        case .node(let index): [0, index]
        case .edge(let edge): [1] + edge.sortKey
        }
    }
}

nonisolated protocol GitLogLinearGraph: Sendable {
    var nodesCount: Int { get }
    func adjacentEdges(of nodeIndex: Int, filter: GitLogEdgeFilter) -> [GitLogLinearEdge]
}

extension GitLogLinearGraph {
    nonisolated func upNodes(of nodeIndex: Int) -> [Int] {
        adjacentEdges(of: nodeIndex, filter: .normalUp).compactMap(\.upNodeIndex)
    }

    nonisolated func downNodes(of nodeIndex: Int) -> [Int] {
        adjacentEdges(of: nodeIndex, filter: .normalDown).compactMap(\.downNodeIndex)
    }
}

nonisolated struct GitLogGraphCommit: Hashable, Sendable {
    let id: String
    let parents: [String]
}

nonisolated struct GitLogPermanentGraph: GitLogLinearGraph {
    let simpleNodes: [Bool]
    let nodeToEdgeIndex: [Int]
    let longEdges: [Int]
    let dottedEdges: Set<GitLogNormalEdge>

    init(simpleNodes: [Bool], nodeToEdgeIndex: [Int], longEdges: [Int], dottedEdges: Set<GitLogNormalEdge> = []) {
        self.simpleNodes = simpleNodes
        self.nodeToEdgeIndex = nodeToEdgeIndex
        self.longEdges = longEdges
        self.dottedEdges = dottedEdges
    }

    var nodesCount: Int {
        simpleNodes.count
    }

    func withDottedEdges(_ edges: Set<GitLogNormalEdge>) -> GitLogPermanentGraph {
        GitLogPermanentGraph(
            simpleNodes: simpleNodes,
            nodeToEdgeIndex: nodeToEdgeIndex,
            longEdges: longEdges,
            dottedEdges: edges
        )
    }

    func adjacentEdges(of nodeIndex: Int, filter: GitLogEdgeFilter) -> [GitLogLinearEdge] {
        guard nodeIndex >= 0, nodeIndex < nodesCount else { return [] }
        var result: [GitLogLinearEdge] = []

        let hasUpSimpleEdge = nodeIndex != 0 && simpleNodes[nodeIndex - 1]
        if hasUpSimpleEdge && filter.upNormal {
            result.append(makeNormal(nodeIndex - 1, nodeIndex))
        }

        for index in nodeToEdgeIndex[nodeIndex]..<nodeToEdgeIndex[nodeIndex + 1] {
            let adjacentNode = longEdges[index]
            if adjacentNode < 0 {
                if filter.special {
                    result.append(.withTarget(nodeIndex: nodeIndex, targetId: adjacentNode, type: .notLoadCommit))
                }
                continue
            }
            if nodeIndex > adjacentNode && filter.upNormal {
                result.append(makeNormal(adjacentNode, nodeIndex))
            }
            if nodeIndex < adjacentNode && filter.downNormal {
                result.append(makeNormal(nodeIndex, adjacentNode))
            }
        }

        if simpleNodes[nodeIndex] && filter.downNormal {
            result.append(makeNormal(nodeIndex, nodeIndex + 1))
        }
        return result
    }

    private func makeNormal(_ up: Int, _ down: Int) -> GitLogLinearEdge {
        .normal(up, down, type: dottedEdges.contains(GitLogNormalEdge(up: up, down: down)) ? .dotted : .usual)
    }
}

nonisolated struct GitLogPermanentGraphBuildResult: Sendable {
    let graph: GitLogPermanentGraph
    let notLoadedCommitIds: [Int: String]
}

nonisolated enum GitLogPermanentGraphBuilder {
    static func fixDuplicateParents(_ commit: GitLogGraphCommit) -> GitLogGraphCommit {
        let parents = commit.parents
        guard parents.count > 1 else { return commit }
        var seen = Set<String>()
        var correct: [String] = []
        for parent in parents where seen.insert(parent).inserted {
            correct.append(parent)
        }
        return correct.count == parents.count ? commit : GitLogGraphCommit(id: commit.id, parents: correct)
    }

    static func build(
        commits rawCommits: [GitLogGraphCommit],
        notLoadedCommitId: ((String) -> Int)? = nil
    ) -> GitLogPermanentGraphBuildResult {
        let commits = rawCommits.map(fixDuplicateParents)
        let count = commits.count
        var simpleNodes = [Bool](repeating: false, count: count)
        var longEdgesCount = 0

        for nodeIndex in 0..<count {
            let next: String? = nodeIndex < count - 1 ? commits[nodeIndex + 1].id : nil
            let parents = commits[nodeIndex].parents
            if parents.count == 1, parents[0] == next {
                simpleNodes[nodeIndex] = true
            } else {
                longEdgesCount += parents.count
            }
        }

        var nodeToEdgeIndex = [Int](repeating: 0, count: count + 1)
        var longEdges = [Int](repeating: 0, count: 2 * longEdgesCount)
        var upAdjacentNodes: [String: [Int]] = [:]

        for nodeIndex in 0..<count {
            let commit = commits[nodeIndex]
            let upNodes = upAdjacentNodes.removeValue(forKey: commit.id) ?? []
            var edgeIndex = nodeToEdgeIndex[nodeIndex]
            for upNodeIndex in upNodes {
                fixUnderdoneEdge(
                    commits: commits,
                    nodeToEdgeIndex: nodeToEdgeIndex,
                    longEdges: &longEdges,
                    upNodeIndex: upNodeIndex,
                    downNodeIndex: nodeIndex,
                    downCommitId: commit.id
                )
                longEdges[edgeIndex] = upNodeIndex
                edgeIndex += 1
            }
            if !simpleNodes[nodeIndex] {
                for downCommitId in commit.parents {
                    upAdjacentNodes[downCommitId, default: []].append(nodeIndex)
                    longEdges[edgeIndex] = -1
                    edgeIndex += 1
                }
            }
            nodeToEdgeIndex[nodeIndex + 1] = edgeIndex
        }

        let notLoaded = fixUnderdoneEdges(
            commits: commits,
            nodeToEdgeIndex: nodeToEdgeIndex,
            longEdges: &longEdges,
            upAdjacentNodes: upAdjacentNodes,
            notLoadedCommitId: notLoadedCommitId
        )

        return GitLogPermanentGraphBuildResult(
            graph: GitLogPermanentGraph(simpleNodes: simpleNodes, nodeToEdgeIndex: nodeToEdgeIndex, longEdges: longEdges),
            notLoadedCommitIds: notLoaded
        )
    }

    private static func fixUnderdoneEdge(
        commits: [GitLogGraphCommit],
        nodeToEdgeIndex: [Int],
        longEdges: inout [Int],
        upNodeIndex: Int,
        downNodeIndex: Int,
        downCommitId: String
    ) {
        let end = nodeToEdgeIndex[upNodeIndex + 1]
        let parents = commits[upNodeIndex].parents
        for (slot, parent) in zip((end - parents.count)..<end, parents) where parent == downCommitId {
            longEdges[slot] = downNodeIndex
        }
    }

    private static func fixUnderdoneEdges(
        commits: [GitLogGraphCommit],
        nodeToEdgeIndex: [Int],
        longEdges: inout [Int],
        upAdjacentNodes: [String: [Int]],
        notLoadedCommitId: ((String) -> Int)?
    ) -> [Int: String] {
        func order(_ entry: (key: String, value: [Int])) -> (Int, Int) {
            let minUp = entry.value.reduce(Int.max, min)
            return (minUp, commits[minUp].parents.prefix(while: { $0 != entry.key }).count)
        }

        let sortedEntries = upAdjacentNodes.sorted { left, right in
            let l = order(left)
            let r = order(right)
            return l.0 != r.0 ? l.0 < r.0 : l.1 < r.1
        }

        var notLoaded: [Int: String] = [:]
        for (notLoadedCommit, upNodes) in sortedEntries {
            let notLoadedId = notLoadedCommitId?(notLoadedCommit) ?? -(notLoaded.count + 2)
            notLoaded[notLoadedId] = notLoadedCommit
            for upNodeIndex in upNodes {
                for edgeIndex in nodeToEdgeIndex[upNodeIndex]..<nodeToEdgeIndex[upNodeIndex + 1]
                where longEdges[edgeIndex] == -1 {
                    longEdges[edgeIndex] = notLoadedId
                    break
                }
            }
        }
        return notLoaded
    }
}
