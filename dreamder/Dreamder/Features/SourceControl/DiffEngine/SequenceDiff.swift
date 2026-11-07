import Foundation

nonisolated struct UniqueLCS {
    let first: [Int]
    let second: [Int]
    let start1: Int
    let count1: Int
    let start2: Int
    let count2: Int

    func execute() -> (first: [Int], second: [Int])? {
        var map: [Int: Int] = [:]
        map.reserveCapacity(count1 + count2)
        var match = [Int](repeating: 0, count: count1)

        for i in 0..<count1 {
            let key = first[start1 + i]
            let value = map[key] ?? 0
            if value == -1 { continue }
            if value == 0 {
                map[key] = i + 1
            } else {
                map[key] = -1
            }
        }

        var count = 0
        for i in 0..<count2 {
            let key = second[start2 + i]
            let value = map[key] ?? 0
            if value == 0 || value == -1 { continue }
            if match[value - 1] == 0 {
                match[value - 1] = i + 1
                count += 1
            } else {
                match[value - 1] = 0
                map[key] = -1
                count -= 1
            }
        }

        if count == 0 { return nil }

        var sequence = [Int](repeating: 0, count: count)
        var lastElement = [Int](repeating: 0, count: count)
        var predecessor = [Int](repeating: 0, count: count1)

        var length = 0
        for i in 0..<count1 {
            if match[i] == 0 { continue }
            let j = Self.insertionPoint(sequence, match[i], length)
            if j == length || match[i] < sequence[j] {
                sequence[j] = match[i]
                lastElement[j] = i
                predecessor[i] = j > 0 ? lastElement[j - 1] : -1
                if j == length { length += 1 }
            }
        }

        guard length > 0 else { return nil }
        var result1 = [Int](repeating: 0, count: length)
        var result2 = [Int](repeating: 0, count: length)
        var index = length - 1
        var current = lastElement[length - 1]
        while current != -1 && index >= 0 {
            result1[index] = current
            result2[index] = match[current] - 1
            index -= 1
            current = predecessor[current]
        }
        return (result1, result2)
    }

    private static func insertionPoint(_ sequence: [Int], _ value: Int, _ length: Int) -> Int {
        var low = 0
        var high = length
        while low < high {
            let middle = (low + high) / 2
            if sequence[middle] < value {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }
}

nonisolated struct PatienceIntLCS {
    private let first: [Int]
    private let second: [Int]
    private let start1: Int
    private let count1: Int
    private let start2: Int
    private let count2: Int
    private(set) var changes1: DiffBitSet
    private(set) var changes2: DiffBitSet

    init(first: [Int], second: [Int]) {
        self.first = first
        self.second = second
        self.start1 = 0
        self.count1 = first.count
        self.start2 = 0
        self.count2 = second.count
        self.changes1 = DiffBitSet(count: first.count)
        self.changes2 = DiffBitSet(count: second.count)
    }

    mutating func execute(failOnSmallReduction: Bool = false) throws {
        let thresholdCheckCounter = failOnSmallReduction ? 2 : -1
        try execute(start1: start1, count1: count1, start2: start2, count2: count2, thresholdCheckCounter: thresholdCheckCounter)
    }

    private mutating func execute(
        start1 startA: Int,
        count1 countA: Int,
        start2 startB: Int,
        count2 countB: Int,
        thresholdCheckCounter counter: Int
    ) throws {
        try Task.checkCancellation()
        var start1 = startA
        var count1 = countA
        var start2 = startB
        var count2 = countB
        var thresholdCheckCounter = counter

        if count1 == 0 && count2 == 0 { return }

        if count1 == 0 || count2 == 0 {
            addChange(start1, count1, start2, count2)
            return
        }

        let startOffset = matchForward(start1, count1, start2, count2)
        start1 += startOffset
        start2 += startOffset
        count1 -= startOffset
        count2 -= startOffset

        let endOffset = matchBackward(start1, count1, start2, count2)
        count1 -= endOffset
        count2 -= endOffset

        if count1 == 0 || count2 == 0 {
            addChange(start1, count1, start2, count2)
            return
        }

        if thresholdCheckCounter == 0 { try checkReduction(count1, count2) }
        thresholdCheckCounter = max(-1, thresholdCheckCounter - 1)

        let uniqueLCS = UniqueLCS(first: first, second: second, start1: start1, count1: count1, start2: start2, count2: count2)
        guard let matching = uniqueLCS.execute() else {
            if thresholdCheckCounter >= 0 { try checkReduction(count1, count2) }
            var myers = MyersLCS(
                first: first,
                second: second,
                start1: start1,
                count1: count1,
                start2: start2,
                count2: count2,
                changes1: changes1,
                changes2: changes2
            )
            try myers.executeLinear()
            changes1 = myers.changes1
            changes2 = myers.changes2
            return
        }

        let matched = matching.first.count
        guard matched > 0 else { return }

        var c1 = matching.first[0]
        var c2 = matching.second[0]
        try execute(start1: start1, count1: c1, start2: start2, count2: c2, thresholdCheckCounter: thresholdCheckCounter)

        for i in 1..<max(matched, 1) {
            let s1 = matching.first[i - 1] + 1
            let s2 = matching.second[i - 1] + 1
            c1 = matching.first[i] - s1
            c2 = matching.second[i] - s2
            if c1 > 0 || c2 > 0 {
                try execute(
                    start1: start1 + s1,
                    count1: c1,
                    start2: start2 + s2,
                    count2: c2,
                    thresholdCheckCounter: thresholdCheckCounter
                )
            }
        }

        let tailStart1: Int
        let tailCount1: Int
        if matching.first[matched - 1] == count1 - 1 {
            tailStart1 = count1 - 1
            tailCount1 = 0
        } else {
            tailStart1 = matching.first[matched - 1] + 1
            tailCount1 = count1 - tailStart1
        }
        let tailStart2: Int
        let tailCount2: Int
        if matching.second[matched - 1] == count2 - 1 {
            tailStart2 = count2 - 1
            tailCount2 = 0
        } else {
            tailStart2 = matching.second[matched - 1] + 1
            tailCount2 = count2 - tailStart2
        }
        try execute(
            start1: start1 + tailStart1,
            count1: tailCount1,
            start2: start2 + tailStart2,
            count2: tailCount2,
            thresholdCheckCounter: thresholdCheckCounter
        )
    }

    private func matchForward(_ start1: Int, _ count1: Int, _ start2: Int, _ count2: Int) -> Int {
        let size = min(count1, count2)
        var index = 0
        while index < size && first[start1 + index] == second[start2 + index] {
            index += 1
        }
        return index
    }

    private func matchBackward(_ start1: Int, _ count1: Int, _ start2: Int, _ count2: Int) -> Int {
        let size = min(count1, count2)
        var index = 1
        var matched = 0
        while index <= size && first[start1 + count1 - index] == second[start2 + count2 - index] {
            matched += 1
            index += 1
        }
        return matched
    }

    private mutating func addChange(_ start1: Int, _ count1: Int, _ start2: Int, _ count2: Int) {
        changes1.set(from: start1, to: start1 + count1)
        changes2.set(from: start2, to: start2 + count2)
    }

    private func checkReduction(_ reducedCount1: Int, _ reducedCount2: Int) throws {
        if reducedCount1 * 2 < count1 { return }
        if reducedCount2 * 2 < count2 { return }
        throw DiffTooBigError()
    }
}

nonisolated struct LCSBuilder {
    private(set) var index1: Int
    private(set) var index2: Int
    private(set) var ranges: [DiffRange] = []

    init(startShift: Int) {
        index1 = startShift
        index2 = startShift
    }

    mutating func addEqual(_ length: Int) {
        index1 += length
        index2 += length
    }

    mutating func addChange(_ deleted: Int, _ inserted: Int) {
        ranges.append(DiffRange(index1, index1 + deleted, index2, index2 + inserted))
        index1 += deleted
        index2 += inserted
    }
}

nonisolated struct Reindexer {
    private var oldIndices: [[Int]] = [[], []]
    private var originalLengths = [-1, -1]
    private var discardedLengths = [-1, -1]

    mutating func discardUnique(_ ints1: [Int], _ ints2: [Int]) -> (first: [Int], second: [Int]) {
        let discarded1 = discard(needed: ints2, toDiscard: ints1, arrayIndex: 0)
        let discarded2 = discard(needed: discarded1, toDiscard: ints2, arrayIndex: 1)
        return (discarded1, discarded2)
    }

    private mutating func discard(needed: [Int], toDiscard: [Int], arrayIndex: Int) -> [Int] {
        originalLengths[arrayIndex] = toDiscard.count
        let neededSet = Set(needed)
        var discarded: [Int] = []
        var indices: [Int] = []
        discarded.reserveCapacity(toDiscard.count)
        indices.reserveCapacity(toDiscard.count)
        for (index, value) in toDiscard.enumerated() where neededSet.contains(value) {
            discarded.append(value)
            indices.append(index)
        }
        oldIndices[arrayIndex] = indices
        discardedLengths[arrayIndex] = discarded.count
        return discarded
    }

    func reindex(_ discardedChanges: (first: DiffBitSet, second: DiffBitSet), into builder: inout LCSBuilder) {
        var changes1: DiffBitSet
        var changes2: DiffBitSet

        if discardedLengths[0] == originalLengths[0] && discardedLengths[1] == originalLengths[1] {
            changes1 = discardedChanges.first
            changes2 = discardedChanges.second
        } else {
            changes1 = DiffBitSet(count: originalLengths[0])
            changes2 = DiffBitSet(count: originalLengths[1])
            var x = 0
            var y = 0
            while x < discardedLengths[0] || y < discardedLengths[1] {
                if x < discardedLengths[0] && y < discardedLengths[1] && !discardedChanges.first[x] && !discardedChanges.second[y] {
                    x = increment(oldIndices[0], x, &changes1, originalLengths[0])
                    y = increment(oldIndices[1], y, &changes2, originalLengths[1])
                } else if discardedChanges.first[x] {
                    changes1[oldIndices[0][x]] = true
                    x = increment(oldIndices[0], x, &changes1, originalLengths[0])
                } else if discardedChanges.second[y] {
                    changes2[oldIndices[1][y]] = true
                    y = increment(oldIndices[1], y, &changes2, originalLengths[1])
                } else {
                    break
                }
            }
            if discardedLengths[0] == 0 {
                changes1.set(from: 0, to: originalLengths[0])
            } else {
                changes1.set(from: 0, to: oldIndices[0][0])
            }
            if discardedLengths[1] == 0 {
                changes2.set(from: 0, to: originalLengths[1])
            } else {
                changes2.set(from: 0, to: oldIndices[1][0])
            }
        }

        let length1 = originalLengths[0]
        let length2 = originalLengths[1]
        var x = 0
        var y = 0
        while x < length1 && y < length2 {
            let startX = x
            while x < length1 && y < length2 && !changes1[x] && !changes2[y] {
                x += 1
                y += 1
            }
            if x > startX { builder.addEqual(x - startX) }
            var dx = 0
            var dy = 0
            while x < length1 && changes1[x] {
                dx += 1
                x += 1
            }
            while y < length2 && changes2[y] {
                dy += 1
                y += 1
            }
            if dx != 0 || dy != 0 { builder.addChange(dx, dy) }
        }
        if x != length1 || y != length2 {
            builder.addChange(length1 - x, length2 - y)
        }
    }

    private func increment(_ indexes: [Int], _ index: Int, _ set: inout DiffBitSet, _ length: Int) -> Int {
        if index + 1 < indexes.count {
            set.set(from: indexes[index] + 1, to: indexes[index + 1])
        } else {
            set.set(from: indexes[index] + 1, to: length)
        }
        return index + 1
    }
}

nonisolated enum SequenceDiff {
    static func compare<T: Hashable>(_ objects1: [T], _ objects2: [T]) throws -> DiffChanges {
        try Task.checkCancellation()
        let minCount = min(objects1.count, objects2.count)

        var startShift = 0
        while startShift < minCount && objects1[startShift] == objects2[startShift] {
            startShift += 1
        }

        var endCut = 0
        let suffixLimit = minCount - startShift
        while endCut < suffixLimit && objects1[objects1.count - endCut - 1] == objects2[objects2.count - endCut - 1] {
            endCut += 1
        }

        let trimmed1 = objects1.count - startShift - endCut
        let trimmed2 = objects2.count - startShift - endCut
        if trimmed1 == 0 || trimmed2 == 0 {
            guard trimmed1 != 0 || trimmed2 != 0 else {
                return DiffChanges(changes: [], length1: objects1.count, length2: objects2.count)
            }
            let range = DiffRange(startShift, startShift + trimmed1, startShift, startShift + trimmed2)
            return DiffChanges(changes: [range], length1: objects1.count, length2: objects2.count)
        }

        var numbers: [T: Int] = [:]
        numbers.reserveCapacity(trimmed1 + trimmed2)
        var nextNumber = 1
        var ints1 = [Int]()
        ints1.reserveCapacity(trimmed1)
        var ints2 = [Int]()
        ints2.reserveCapacity(trimmed2)
        for index in startShift..<(startShift + trimmed1) {
            ints1.append(number(for: objects1[index], in: &numbers, next: &nextNumber))
        }
        for index in startShift..<(startShift + trimmed2) {
            ints2.append(number(for: objects2[index], in: &numbers, next: &nextNumber))
        }

        let ranges = try buildRanges(ints1, ints2, startShift: startShift)
        return DiffChanges(changes: ranges, length1: objects1.count, length2: objects2.count)
    }

    private static func number<T: Hashable>(for object: T, in numbers: inout [T: Int], next: inout Int) -> Int {
        if let existing = numbers[object] { return existing }
        let number = next
        next += 1
        numbers[object] = number
        return number
    }

    private static func buildRanges(_ ints1: [Int], _ ints2: [Int], startShift: Int) throws -> [DiffRange] {
        var builder = LCSBuilder(startShift: startShift)
        var reindexer = Reindexer()
        let discarded = reindexer.discardUnique(ints1, ints2)

        if discarded.first.isEmpty && discarded.second.isEmpty {
            builder.addChange(ints1.count, ints2.count)
            return builder.ranges
        }

        var changes1: DiffBitSet
        var changes2: DiffBitSet
        do {
            var myers = MyersLCS(first: discarded.first, second: discarded.second)
            try myers.executeWithThreshold()
            changes1 = myers.changes1
            changes2 = myers.changes2
        } catch is DiffTooBigError {
            var patience = PatienceIntLCS(first: discarded.first, second: discarded.second)
            try patience.execute(failOnSmallReduction: true)
            changes1 = patience.changes1
            changes2 = patience.changes2
        }

        reindexer.reindex((changes1, changes2), into: &builder)
        return builder.ranges
    }
}
