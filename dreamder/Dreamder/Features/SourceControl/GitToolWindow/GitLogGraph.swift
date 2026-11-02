import Foundation

struct GitLogGraphEdge: Hashable {
    let fromLane: Int
    let toLane: Int
}

struct GitLogGraphRow: Hashable {
    let hash: String
    let lane: Int
    let edges: [GitLogGraphEdge]
}

enum GitLogGraphLayout {
    static func rows(for commits: [GitLogCommit]) -> [GitLogGraphRow] {
        var lanes: [String?] = []
        var result: [GitLogGraphRow] = []
        result.reserveCapacity(commits.count)

        for commit in commits {
            var lane: Int
            if let existing = lanes.firstIndex(where: { $0 == commit.hash }) {
                lane = existing
            } else if let free = lanes.firstIndex(where: { $0 == nil }) {
                lane = free
            } else {
                lane = lanes.count
                lanes.append(nil)
            }

            let lanesBefore = lanes
            lanes[lane] = nil
            for index in lanes.indices where lanes[index] == commit.hash {
                lanes[index] = nil
            }

            var edges: [GitLogGraphEdge] = []
            for (index, parent) in commit.parents.enumerated() {
                let target: Int
                if let existing = lanes.firstIndex(where: { $0 == parent }) {
                    target = existing
                } else if index == 0 {
                    target = lane
                } else if let free = lanes.firstIndex(where: { $0 == nil }) {
                    target = free
                } else {
                    target = lanes.count
                    lanes.append(nil)
                }
                lanes[target] = parent
                edges.append(GitLogGraphEdge(fromLane: lane, toLane: target))
            }

            for (index, occupant) in lanesBefore.enumerated() where occupant != nil && index != lane {
                edges.append(GitLogGraphEdge(fromLane: index, toLane: index))
            }

            while let last = lanes.last, last == nil {
                lanes.removeLast()
            }

            result.append(GitLogGraphRow(hash: commit.hash, lane: lane, edges: edges))
        }

        return result
    }

    static func laneCount(_ rows: [GitLogGraphRow]) -> Int {
        var count = 1
        for row in rows {
            count = max(count, row.lane + 1)
            for edge in row.edges {
                count = max(count, edge.fromLane + 1)
                count = max(count, edge.toLane + 1)
            }
        }
        return count
    }
}
