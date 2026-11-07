import Foundation

nonisolated struct GitLogNodeLayout: Sendable {
    let layoutIndexes: [Int]
    let headNodeIndexes: [Int]
    private let layoutIndexesForHeads: [Int]

    init(layoutIndexes: [Int], headNodeIndexes: [Int]) {
        self.layoutIndexes = layoutIndexes
        self.headNodeIndexes = headNodeIndexes
        self.layoutIndexesForHeads = headNodeIndexes.map { layoutIndexes.indices.contains($0) ? layoutIndexes[$0] : 0 }
    }

    func layoutIndex(of nodeIndex: Int) -> Int {
        layoutIndexes.indices.contains(nodeIndex) ? layoutIndexes[nodeIndex] : 0
    }

    func oneOfHeadNodeIndex(of nodeIndex: Int) -> Int {
        guard !headNodeIndexes.isEmpty else { return 0 }
        return headNodeIndexes[headOrder(forLayoutIndex: layoutIndex(of: nodeIndex))]
    }

    private func headOrder(forLayoutIndex layoutIndex: Int) -> Int {
        var low = 0
        var high = layoutIndexesForHeads.count
        while low < high {
            let middle = (low + high) / 2
            if layoutIndexesForHeads[middle] <= layoutIndex {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return max(0, low - 1)
    }
}

nonisolated enum GitLogNodeLayoutBuilder {
    static func heads(of graph: some GitLogLinearGraph) -> [Int] {
        (0..<graph.nodesCount).filter { graph.upNodes(of: $0).isEmpty }
    }

    static func build(
        graph: some GitLogLinearGraph,
        branches: Set<Int> = [],
        comparator: (Int, Int) -> Int
    ) -> GitLogNodeLayout {
        var allHeads = Set(branches)
        for head in heads(of: graph) {
            allHeads.insert(head)
        }
        let sortedHeads = allHeads.sorted { left, right in
            let result = comparator(left, right)
            return result != 0 ? result < 0 : left < right
        }
        return build(graph: graph, sortedHeads: sortedHeads)
    }

    private static func build(graph: some GitLogLinearGraph, sortedHeads: [Int]) -> GitLogNodeLayout {
        var layoutIndex = [Int](repeating: 0, count: graph.nodesCount)
        var importantHeads: [Int] = []
        var currentLayoutIndex = 1

        for head in sortedHeads where layoutIndex.indices.contains(head) {
            if layoutIndex[head] != 0 { continue }
            importantHeads.append(head)

            var stack = [head]
            while let current = stack.last {
                let firstVisit = layoutIndex[current] == 0
                if firstVisit {
                    layoutIndex[current] = currentLayoutIndex
                }
                if let child = graph.downNodes(of: current).first(where: { layoutIndex[$0] == 0 }) {
                    stack.append(child)
                } else {
                    if firstVisit {
                        currentLayoutIndex += 1
                    }
                    stack.removeLast()
                }
            }
        }

        return GitLogNodeLayout(layoutIndexes: layoutIndex, headNodeIndexes: importantHeads)
    }
}

nonisolated enum GitLogRefTier: Int, Sendable {
    case originMaster
    case remoteBranch
    case master
    case localBranch
    case tag
    case head
    case other
}

nonisolated enum GitLogHeadOrder {
    static func tier(of ref: GitLogRef) -> GitLogRefTier {
        switch ref.kind {
        case .head, .branch:
            if ref.name == "HEAD" { return .head }
            return ref.name == "master" || ref.name == "main" ? .master : .localBranch
        case .remote:
            return ref.name == "origin/master" || ref.name == "origin/main" ? .originMaster : .remoteBranch
        case .tag:
            return .tag
        }
    }

    static func isBranch(_ ref: GitLogRef) -> Bool {
        ref.kind != .tag
    }

    static func compare(_ left: GitLogRef, _ right: GitLogRef) -> Int {
        let leftTier = tier(of: left).rawValue
        let rightTier = tier(of: right).rawValue
        if leftTier != rightTier {
            return leftTier - rightTier
        }
        switch left.name.localizedStandardCompare(right.name) {
        case .orderedAscending: return -1
        case .orderedDescending: return 1
        case .orderedSame: return 0
        }
    }

    static func bestRef(of refs: [GitLogRef]) -> GitLogRef? {
        var best: GitLogRef?
        for ref in refs {
            if let current = best {
                if compare(ref, current) < 0 {
                    best = ref
                }
            } else {
                best = ref
            }
        }
        return best
    }

    static func compareHeads(_ left: Int, _ right: Int, bestRefs: [Int: GitLogRef]) -> Int {
        if left == right { return 0 }
        let leftRef = bestRefs[left]
        let rightRef = bestRefs[right]
        switch (leftRef, rightRef) {
        case (nil, nil): return left - right
        case (nil, _): return 1
        case (_, nil): return -1
        case (let l?, let r?): return compare(l, r)
        }
    }
}

nonisolated enum GitLogGraphColors {
    static func javaHash(_ string: String) -> Int32 {
        var hash: Int32 = 0
        for unit in string.utf16 {
            hash = 31 &* hash &+ Int32(unit)
        }
        return hash
    }

    static func hue(forColorId colorId: Int) -> Double {
        let id = Int32(truncatingIfNeeded: colorId)
        let r = rangeFix(id &* 200 &+ 30)
        let g = rangeFix(id &* 130 &+ 50)
        let b = rangeFix(id &* 90 &+ 100)
        let maxValue = max(r, g, b)
        let minValue = min(r, g, b)
        guard maxValue != minValue else { return 0 }
        let delta = Double(maxValue - minValue)
        let red = Double(maxValue - r) / delta
        let green = Double(maxValue - g) / delta
        let blue = Double(maxValue - b) / delta
        var hue: Double
        if r == maxValue {
            hue = blue - green
        } else if g == maxValue {
            hue = 2 + red - blue
        } else {
            hue = 4 + green - red
        }
        hue /= 6
        if hue < 0 {
            hue += 1
        }
        return hue
    }

    private static func rangeFix(_ value: Int32) -> Int {
        Int(abs(Int64(value) % 100)) + 70
    }
}

nonisolated struct GitLogGraphColorGetter: Sendable {
    let layout: GitLogNodeLayout
    let headColorSeeds: [Int: Int]

    static let defaultColorId = 0

    func nodeColor(nodeId: Int, layoutIndex: Int) -> Int {
        let headNode = nodeId < 0 ? 0 : layout.oneOfHeadNodeIndex(of: nodeId)
        let headLayoutIndex = layout.layoutIndex(of: headNode)
        if headLayoutIndex == layoutIndex {
            return headColorSeeds[headNode] ?? Self.defaultColorId
        }
        return layoutIndex
    }

    func colorId(of element: GitLogGraphElement) -> Int {
        switch element {
        case .node(let nodeIndex):
            return nodeColor(nodeId: nodeIndex, layoutIndex: layoutIndexOf(nodeIndex))
        case .edge(let edge):
            guard let normal = edge.normalEdge else {
                let nodeId = edge.notNullNodeIndex
                return nodeColor(nodeId: nodeId, layoutIndex: layoutIndexOf(nodeId))
            }
            let upLayoutIndex = layoutIndexOf(normal.up)
            let downLayoutIndex = layoutIndexOf(normal.down)
            if upLayoutIndex >= downLayoutIndex {
                return nodeColor(nodeId: normal.up, layoutIndex: upLayoutIndex)
            }
            return nodeColor(nodeId: normal.down, layoutIndex: downLayoutIndex)
        }
    }

    private func layoutIndexOf(_ nodeId: Int) -> Int {
        nodeId < 0 ? nodeId : layout.layoutIndex(of: nodeId)
    }
}
