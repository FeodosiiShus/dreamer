import Foundation

nonisolated enum GitLogEdgeDirection: Hashable, Sendable {
    case up
    case down
}

nonisolated enum GitLogEdgeLineStyle: Hashable, Sendable {
    case solid
    case dashed
}

nonisolated struct GitLogNodePrintElement: Hashable, Sendable {
    let rowIndex: Int
    let position: Int
    let nodeIndex: Int
    let colorId: Int
}

nonisolated struct GitLogEdgePrintElement: Hashable, Sendable {
    let rowIndex: Int
    let positionInCurrentRow: Int
    let positionInOtherRow: Int
    let direction: GitLogEdgeDirection
    let lineStyle: GitLogEdgeLineStyle
    let hasArrow: Bool
    let isTerminal: Bool
    let colorId: Int
    let edge: GitLogLinearEdge
}

nonisolated enum GitLogPrintElement: Hashable, Sendable {
    case node(GitLogNodePrintElement)
    case edge(GitLogEdgePrintElement)

    var colorId: Int {
        switch self {
        case .node(let node): node.colorId
        case .edge(let edge): edge.colorId
        }
    }
}

nonisolated final class GitLogEdgesInRowGenerator {
    private static let blockSize = 40

    private struct Edges {
        var edges: Set<GitLogLinearEdge>
        var row: Int
    }

    private let graph: any GitLogLinearGraph
    private let walkSize: Int
    private var cacheUp: [Int: Edges] = [:]
    private var cacheDown: [Int: Edges] = [:]

    init(graph: any GitLogLinearGraph, walkSize: Int = 1000) {
        self.graph = graph
        self.walkSize = walkSize
    }

    func edgesInRow(_ rowIndex: Int) -> Set<GitLogLinearEdge> {
        var neighborUp = upNeighbor(rowIndex)
        while neighborUp.row < rowIndex {
            neighborUp = oneDownStep(neighborUp)
        }
        var neighborDown = downNeighbor(rowIndex)
        while neighborDown.row > rowIndex {
            neighborDown = oneUpStep(neighborDown)
        }
        return neighborUp.edges.union(neighborDown.edges)
    }

    func invalidate() {
        cacheUp.removeAll()
        cacheDown.removeAll()
    }

    private func upNeighbor(_ rowIndex: Int) -> Edges {
        let index = upNeighborIndex(rowIndex)
        if let cached = cacheUp[index] {
            return cached
        }
        let computed = correctUpEdges(index)
        cacheUp[index] = computed
        return computed
    }

    private func downNeighbor(_ rowIndex: Int) -> Edges {
        let index = upNeighborIndex(rowIndex) + Self.blockSize
        if index >= graph.nodesCount {
            return Edges(edges: [], row: graph.nodesCount - 1)
        }
        if let cached = cacheDown[index] {
            return cached
        }
        let computed = correctDownEdges(index)
        cacheDown[index] = computed
        return computed
    }

    private func upNeighborIndex(_ rowIndex: Int) -> Int {
        (rowIndex / Self.blockSize) * Self.blockSize
    }

    private func correctUpEdges(_ rowIndex: Int) -> Edges {
        let start = max(rowIndex - walkSize, 0)
        var edges = Edges(edges: [], row: start)
        var index = start
        while index < rowIndex {
            edges = oneDownStep(edges)
            index += 1
        }
        return edges
    }

    private func correctDownEdges(_ rowIndex: Int) -> Edges {
        let end = min(rowIndex + walkSize, graph.nodesCount - 1)
        var edges = Edges(edges: [], row: end)
        var index = end
        while index > rowIndex {
            edges = oneUpStep(edges)
            index -= 1
        }
        return edges
    }

    private func oneDownStep(_ state: Edges) -> Edges {
        var edges = state.edges
        for edge in graph.adjacentEdges(of: state.row, filter: .normalDown) {
            edges.insert(edge)
        }
        for edge in graph.adjacentEdges(of: state.row + 1, filter: .normalUp) {
            edges.remove(edge)
        }
        return Edges(edges: edges, row: state.row + 1)
    }

    private func oneUpStep(_ state: Edges) -> Edges {
        var edges = state.edges
        for edge in graph.adjacentEdges(of: state.row, filter: .normalUp) {
            edges.insert(edge)
        }
        for edge in graph.adjacentEdges(of: state.row - 1, filter: .normalDown) {
            edges.remove(edge)
        }
        return Edges(edges: edges, row: state.row - 1)
    }
}

nonisolated struct GitLogElementComparator {
    let layoutIndex: (Int) -> Int

    func compare(_ first: GitLogGraphElement, _ second: GitLogGraphElement) -> Int {
        switch (first, second) {
        case (.edge(let edge1), .edge(let edge2)):
            guard let normal1 = edge1.normalEdge else {
                return -compare2(edge2, nodeIndex: edge1.notNullNodeIndex)
            }
            guard let normal2 = edge2.normalEdge else {
                return compare2(edge1, nodeIndex: edge2.notNullNodeIndex)
            }
            if normal1.up == normal2.up {
                if normal1.down < normal2.down {
                    return -compare2(edge2, nodeIndex: normal1.down)
                }
                return compare2(edge1, nodeIndex: normal2.down)
            }
            if normal1.up < normal2.up {
                return compare2(edge1, nodeIndex: normal2.up)
            }
            return -compare2(edge2, nodeIndex: normal1.up)
        case (.edge(let edge), .node(let nodeIndex)):
            return compare2(edge, nodeIndex: nodeIndex)
        case (.node(let nodeIndex), .edge(let edge)):
            return -compare2(edge, nodeIndex: nodeIndex)
        case (.node, .node):
            return 0
        }
    }

    func areInIncreasingOrder(_ first: GitLogGraphElement, _ second: GitLogGraphElement) -> Bool {
        let result = compare(first, second)
        if result != 0 {
            return result < 0
        }
        return first.sortKey.lexicographicallyPrecedes(second.sortKey)
    }

    private func compare2(_ edge: GitLogLinearEdge, nodeIndex: Int) -> Int {
        guard let normal = edge.normalEdge else {
            return layoutIndex(edge.notNullNodeIndex) - layoutIndex(nodeIndex)
        }
        let upLayout = layoutIndex(normal.up)
        let downLayout = layoutIndex(normal.down)
        let nodeLayout = layoutIndex(nodeIndex)
        if max(upLayout, downLayout) != nodeLayout {
            return max(upLayout, downLayout) - nodeLayout
        }
        return normal.up - nodeIndex
    }
}

nonisolated final class GitLogPrintElementGenerator {
    static let longEdgeSize = 30
    static let veryLongEdgeSize = 1000
    static let longEdgePartSize = 1
    static let veryLongEdgePartSize = 250

    private let graph: any GitLogLinearGraph
    private let colorId: (GitLogGraphElement) -> Int
    private let comparator: GitLogElementComparator
    private let longEdgeSize: Int
    private let visiblePartSize: Int
    private let edgeWithArrowSize: Int
    private let edgesInRowGenerator: GitLogEdgesInRowGenerator
    private var cache: [Int: [GitLogGraphElement]] = [:]

    init(
        graph: any GitLogLinearGraph,
        comparator: GitLogElementComparator,
        longEdgeSize: Int,
        visiblePartSize: Int,
        edgeWithArrowSize: Int,
        colorId: @escaping (GitLogGraphElement) -> Int
    ) {
        self.graph = graph
        self.comparator = comparator
        self.longEdgeSize = longEdgeSize
        self.visiblePartSize = visiblePartSize
        self.edgeWithArrowSize = edgeWithArrowSize
        self.colorId = colorId
        self.edgesInRowGenerator = GitLogEdgesInRowGenerator(graph: graph)
    }

    convenience init(
        graph: any GitLogLinearGraph,
        comparator: GitLogElementComparator,
        showLongEdges: Bool,
        colorId: @escaping (GitLogGraphElement) -> Int
    ) {
        self.init(
            graph: graph,
            comparator: comparator,
            longEdgeSize: showLongEdges ? Self.veryLongEdgeSize : Self.longEdgeSize,
            visiblePartSize: showLongEdges ? Self.veryLongEdgePartSize : Self.longEdgePartSize,
            edgeWithArrowSize: showLongEdges ? Self.longEdgeSize : Int.max,
            colorId: colorId
        )
    }

    func recommendedWidth() -> Int {
        let nodesCount = graph.nodesCount
        if nodesCount == 0 { return 0 }
        if nodesCount == 1 { return 1 }

        let sampleSize = 20000
        let k = 0.1
        let n = min(sampleSize, nodesCount)
        var sum = 0.0
        var sumSquares = 0.0
        var edgesCount = 0
        var currentNormalEdges = Set<GitLogNormalEdge>()

        for index in 0..<n {
            var upArrows = 0
            var downArrows = 0
            for edge in graph.adjacentEdges(of: index, filter: .all) {
                if let normal = edge.normalEdge {
                    if edge.isEdgeUp(at: index) {
                        currentNormalEdges.remove(normal)
                    } else {
                        currentNormalEdges.insert(normal)
                    }
                } else if edge.type == .dottedArrowUp {
                    upArrows += 1
                } else {
                    downArrows += 1
                }
            }

            var newEdgesCount = 0
            for normal in currentNormalEdges {
                if isEdgeVisible(normal, in: index) {
                    newEdgesCount += 1
                } else {
                    switch arrowDirection(normal, in: index) {
                    case .down: downArrows += 1
                    case .up: upArrows += 1
                    case nil: break
                    }
                }
            }

            let width = max(edgesCount + upArrows, newEdgesCount + downArrows)
            let weight = 2 / (Double(n) * (k + 1)) * (1 + (k - 1) * Double(index) / Double(n - 1))
            sum += Double(width) * weight
            sumSquares += Double(width) * Double(width) * weight
            edgesCount = newEdgesCount
        }

        let deviation = max(0, sumSquares - sum * sum).squareRoot()
        return Int((sum + deviation).rounded())
    }

    func printElements(at rowIndex: Int) -> [GitLogPrintElement] {
        var result: [GitLogPrintElement] = []
        var nodes: [GitLogPrintElement] = []

        let visibleElements = sortedVisibleElements(in: rowIndex)
        let upPosition = endPositions(visibleRow: rowIndex - 1, up: true)
        let downPosition = endPositions(visibleRow: rowIndex + 1, up: false)

        for (position, element) in visibleElements.enumerated() {
            switch element {
            case .node(let nodeIndex):
                nodes.append(.node(GitLogNodePrintElement(
                    rowIndex: rowIndex,
                    position: position,
                    nodeIndex: nodeIndex,
                    colorId: colorId(element)
                )))
                for edge in graph.adjacentEdges(of: nodeIndex, filter: .all) {
                    let arrow = arrowDirection(edge, in: rowIndex)
                    if let down = downPosition(edge) {
                        result.append(.edge(edgeElement(rowIndex, position, down, .down, edge, arrow == .down, false)))
                    }
                    if let up = upPosition(edge) {
                        result.append(.edge(edgeElement(rowIndex, position, up, .up, edge, arrow == .up, false)))
                    }
                }
            case .edge(let edge):
                let down = downPosition(edge)
                let up = upPosition(edge)
                let arrow = arrowDirection(edge, in: rowIndex)
                if let down {
                    result.append(.edge(edgeElement(rowIndex, position, down, .down, edge, arrow == .down, false)))
                } else if arrow == .down {
                    result.append(.edge(edgeElement(rowIndex, position, position, .down, edge, true, true)))
                }
                if let up {
                    result.append(.edge(edgeElement(rowIndex, position, up, .up, edge, arrow == .up, false)))
                } else if arrow == .up {
                    result.append(.edge(edgeElement(rowIndex, position, position, .up, edge, true, true)))
                }
            }
        }
        result.append(contentsOf: nodes)
        return result
    }

    private func edgeElement(
        _ rowIndex: Int,
        _ position: Int,
        _ otherPosition: Int,
        _ direction: GitLogEdgeDirection,
        _ edge: GitLogLinearEdge,
        _ hasArrow: Bool,
        _ isTerminal: Bool
    ) -> GitLogEdgePrintElement {
        let style: GitLogEdgeLineStyle = switch edge.type {
        case .usual, .notLoadCommit: .solid
        case .dotted, .dottedArrowUp, .dottedArrowDown: .dashed
        }
        return GitLogEdgePrintElement(
            rowIndex: rowIndex,
            positionInCurrentRow: position,
            positionInOtherRow: otherPosition,
            direction: direction,
            lineStyle: style,
            hasArrow: hasArrow,
            isTerminal: isTerminal,
            colorId: colorId(.edge(edge)),
            edge: edge
        )
    }

    private func endPositions(visibleRow: Int, up: Bool) -> (GitLogLinearEdge) -> Int? {
        guard visibleRow >= 0, visibleRow < graph.nodesCount else { return { _ in nil } }
        let elements = sortedVisibleElements(in: visibleRow)
        var toPosition: [GitLogGraphElement: Int] = [:]
        toPosition.reserveCapacity(elements.count)
        for (position, element) in elements.enumerated() {
            toPosition[element] = position
        }
        return { edge in
            if let position = toPosition[.edge(edge)] {
                return position
            }
            guard let nodeIndex = up ? edge.upNodeIndex : edge.downNodeIndex else { return nil }
            return toPosition[.node(nodeIndex)]
        }
    }

    private func arrowDirection(_ edge: GitLogLinearEdge, in rowIndex: Int) -> GitLogEdgeDirection? {
        if let normal = edge.normalEdge {
            return arrowDirection(normal, in: rowIndex)
        }
        switch edge.type {
        case .dottedArrowDown, .notLoadCommit:
            return edge.upNodeIndex == rowIndex - 1 ? .down : nil
        case .dottedArrowUp:
            return edge.downNodeIndex == rowIndex + 1 ? .up : nil
        case .usual, .dotted:
            return nil
        }
    }

    private func arrowDirection(_ normal: GitLogNormalEdge, in rowIndex: Int) -> GitLogEdgeDirection? {
        let edgeSize = normal.down - normal.up
        let upOffset = rowIndex - normal.up
        let downOffset = normal.down - rowIndex

        if edgeSize >= longEdgeSize {
            if upOffset == visiblePartSize { return .down }
            if downOffset == visiblePartSize { return .up }
        }
        if edgeSize >= edgeWithArrowSize {
            if upOffset == 1 { return .down }
            if downOffset == 1 { return .up }
        }
        return nil
    }

    private func isEdgeVisible(_ edge: GitLogLinearEdge, in rowIndex: Int) -> Bool {
        guard let normal = edge.normalEdge else { return false }
        return isEdgeVisible(normal, in: rowIndex)
    }

    private func isEdgeVisible(_ normal: GitLogNormalEdge, in rowIndex: Int) -> Bool {
        normal.down - normal.up < longEdgeSize || min(rowIndex - normal.up, normal.down - rowIndex) <= visiblePartSize
    }

    private func sortedVisibleElements(in rowIndex: Int) -> [GitLogGraphElement] {
        if let cached = cache[rowIndex] {
            return cached
        }
        var result: [GitLogGraphElement] = [.node(rowIndex)]
        for edge in edgesInRowGenerator.edgesInRow(rowIndex) where isEdgeVisible(edge, in: rowIndex) {
            result.append(.edge(edge))
        }
        if rowIndex > 0 {
            for edge in graph.adjacentEdges(of: rowIndex - 1, filter: .special) where edge.isEdgeDown(at: rowIndex - 1) {
                result.append(.edge(edge))
            }
        }
        if rowIndex < graph.nodesCount - 1 {
            for edge in graph.adjacentEdges(of: rowIndex + 1, filter: .special) where edge.isEdgeUp(at: rowIndex + 1) {
                result.append(.edge(edge))
            }
        }
        result.sort(by: comparator.areInIncreasingOrder)
        cache[rowIndex] = result
        return result
    }
}
