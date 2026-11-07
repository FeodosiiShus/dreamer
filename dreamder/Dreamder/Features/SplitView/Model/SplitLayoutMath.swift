import CoreGraphics

nonisolated struct SplitLayoutPane: Equatable, Sendable {
    static let defaultHoldingPriority: Float = 250

    var weight: CGFloat
    var minLength: CGFloat
    var maxLength: CGFloat
    var isCollapsed: Bool
    var holdingPriority: Float

    init(
        weight: CGFloat = 1,
        minLength: CGFloat = 0,
        maxLength: CGFloat = .infinity,
        isCollapsed: Bool = false,
        holdingPriority: Float = SplitLayoutPane.defaultHoldingPriority
    ) {
        self.weight = weight
        self.minLength = minLength
        self.maxLength = maxLength
        self.isCollapsed = isCollapsed
        self.holdingPriority = holdingPriority
    }

    var lowerBound: CGFloat {
        minLength.isFinite ? max(0, minLength) : 0
    }

    var upperBound: CGFloat {
        guard !maxLength.isNaN else { return .infinity }
        return max(lowerBound, maxLength)
    }
}

nonisolated struct SplitLayoutMath: Equatable, Sendable {
    var panes: [SplitLayoutPane]

    init(panes: [SplitLayoutPane]) {
        self.panes = panes
    }

    var visibleIndices: [Int] {
        panes.indices.filter { !panes[$0].isCollapsed }
    }

    var normalizedWeights: [CGFloat] {
        Self.normalizedWeights(panes.map(\.weight), count: panes.count)
    }

    static func equalWeights(count: Int) -> [CGFloat] {
        guard count > 0 else { return [] }
        return [CGFloat](repeating: 1 / CGFloat(count), count: count)
    }

    static func isValid(weights: [CGFloat], count: Int) -> Bool {
        guard weights.count == count, count > 0 else { return count == 0 && weights.isEmpty }
        var sum: CGFloat = 0
        for weight in weights {
            guard weight.isFinite, weight >= 0 else { return false }
            sum += weight
        }
        return sum > 0
    }

    static func normalizedWeights(_ weights: [CGFloat], count: Int) -> [CGFloat] {
        guard isValid(weights: weights, count: count) else { return equalWeights(count: count) }
        let sum = weights.reduce(0, +)
        return weights.map { $0 / sum }
    }

    func equalize() -> [CGFloat] {
        Self.equalWeights(count: panes.count)
    }

    func weights(forLengths lengths: [CGFloat]) -> [CGFloat] {
        guard lengths.count == panes.count else { return normalizedWeights }
        return weights(applying: lengths, visible: visibleIndices)
    }

    func distribute(length: CGFloat, dividerThickness: CGFloat) -> [CGFloat] {
        var lengths = [CGFloat](repeating: 0, count: panes.count)
        let visible = visibleIndices
        guard length.isFinite, length > 0, let first = visible.first else { return lengths }
        if visible.count == 1 {
            lengths[first] = length
            return lengths
        }

        let divider = Self.sanitizedThickness(dividerThickness)
        let available = length - divider * CGFloat(visible.count - 1)
        guard available > 0 else { return lengths }

        let weights = Self.normalizedWeights(visible.map { panes[$0].weight }, count: visible.count)
        let lower = visible.map { panes[$0].lowerBound }
        let upper = visible.map { panes[$0].upperBound }
        let lowerSum = lower.reduce(0, +)
        let lacksSpace = lowerSum > available

        let ideal: [CGFloat]
        if lacksSpace {
            ideal = lower.map { $0 / lowerSum * available }
        } else {
            ideal = Self.waterFill(total: available, weights: weights, lower: lower, upper: upper)
        }

        var rounded = ideal.indices.map { offset -> CGFloat in
            let whole = ideal[offset].rounded()
            return lacksSpace ? whole : min(max(whole, lower[offset]), upper[offset])
        }
        var remainder = available - rounded.reduce(0, +)
        let flexible = ideal.indices.filter { lacksSpace || (ideal[$0] > lower[$0] && ideal[$0] < upper[$0]) }
        let absorbers = Array(flexible.reversed()) + Array(ideal.indices.reversed())
        for cursor in absorbers where remainder != 0 {
            let low = lacksSpace ? 0 : lower[cursor]
            let high = lacksSpace ? CGFloat.infinity : upper[cursor]
            let adjusted = min(max(rounded[cursor] + remainder, low), high)
            remainder -= adjusted - rounded[cursor]
            rounded[cursor] = adjusted
        }

        for (offset, index) in visible.enumerated() {
            lengths[index] = rounded[offset]
        }
        return lengths
    }

    func drag(dividerIndex: Int, delta: CGFloat, lengths: [CGFloat]) -> [CGFloat] {
        let visible = visibleIndices
        guard lengths.count == panes.count,
              visible.count >= 2,
              dividerIndex >= 0,
              dividerIndex < visible.count - 1,
              delta.isFinite
        else { return normalizedWeights }

        let before = visible[dividerIndex]
        let after = visible[dividerIndex + 1]
        let lowest = min(0, max(panes[before].lowerBound - lengths[before], lengths[after] - panes[after].upperBound))
        let highest = max(0, min(panes[before].upperBound - lengths[before], lengths[after] - panes[after].lowerBound))
        let clamped = min(max(delta, lowest), highest)

        var updated = lengths
        updated[before] += clamped
        updated[after] -= clamped
        return weights(applying: updated, visible: visible)
    }

    func resize(
        lengths: [CGFloat],
        newLength: CGFloat,
        dividerThickness: CGFloat
    ) -> [CGFloat] {
        let visible = visibleIndices
        guard lengths.count == panes.count,
              visible.count >= 2,
              newLength.isFinite
        else { return normalizedWeights }

        let gaps = Self.sanitizedThickness(dividerThickness) * CGFloat(visible.count - 1)
        let newAvailable = newLength - gaps
        guard newAvailable > 0 else { return normalizedWeights }

        var updated = lengths
        var remaining = newAvailable - visible.reduce(0) { $0 + lengths[$1] }
        let priorities = Set(visible.map { panes[$0].holdingPriority }).sorted()
        for priority in priorities where remaining != 0 {
            let group = visible.filter { panes[$0].holdingPriority == priority }
            let shrinkable = group.map { -max(0, lengths[$0] - panes[$0].lowerBound) }
            let growable = group.map { max(0, panes[$0].upperBound - lengths[$0]) }
            let deltas = Self.waterFill(
                total: remaining,
                weights: group.map { lengths[$0] },
                lower: shrinkable,
                upper: growable
            )
            for (offset, index) in group.enumerated() {
                updated[index] += deltas[offset]
            }
            remaining -= deltas.reduce(0, +)
        }
        return weights(applying: updated, visible: visible)
    }

    private func weights(applying lengths: [CGFloat], visible: [Int]) -> [CGFloat] {
        let current = normalizedWeights
        let visibleLength = visible.reduce(0) { $0 + lengths[$1] }
        guard visibleLength > 0 else { return current }
        let visibleWeight = visible.reduce(0) { $0 + current[$1] }
        let scale = visibleWeight > 0 ? visibleWeight : CGFloat(visible.count) / CGFloat(panes.count)
        var result = current
        for index in visible {
            result[index] = lengths[index] / visibleLength * scale
        }
        return Self.normalizedWeights(result, count: panes.count)
    }

    private static func sanitizedThickness(_ thickness: CGFloat) -> CGFloat {
        thickness.isFinite ? max(0, thickness) : 0
    }

    private static func waterFill(
        total: CGFloat,
        weights: [CGFloat],
        lower: [CGFloat],
        upper: [CGFloat]
    ) -> [CGFloat] {
        var result = [CGFloat](repeating: 0, count: weights.count)
        var free = Array(weights.indices)
        var remaining = total
        while !free.isEmpty {
            let weightSum = free.reduce(0) { $0 + weights[$1] }
            let shares = free.map { index -> CGFloat in
                weightSum > 0 ? remaining * weights[index] / weightSum : remaining / CGFloat(free.count)
            }
            var excess: CGFloat = 0
            var belowLower: [Int] = []
            var aboveUpper: [Int] = []
            for (offset, index) in free.enumerated() {
                let clamped = min(max(shares[offset], lower[index]), upper[index])
                excess += clamped - shares[offset]
                if shares[offset] < lower[index] {
                    belowLower.append(offset)
                } else if shares[offset] > upper[index] {
                    aboveUpper.append(offset)
                }
            }

            let pinned: [Int]
            let bounds: [CGFloat]
            if excess >= 0, !belowLower.isEmpty {
                pinned = belowLower
                bounds = lower
            } else if !aboveUpper.isEmpty {
                pinned = aboveUpper
                bounds = upper
            } else if !belowLower.isEmpty {
                pinned = belowLower
                bounds = lower
            } else {
                for (offset, index) in free.enumerated() {
                    result[index] = shares[offset]
                }
                return result
            }

            let pinnedSet = Set(pinned)
            for offset in pinned {
                let index = free[offset]
                result[index] = bounds[index]
                remaining -= bounds[index]
            }
            free = free.enumerated().filter { !pinnedSet.contains($0.offset) }.map(\.element)
        }
        return result
    }
}
