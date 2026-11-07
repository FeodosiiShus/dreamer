import Foundation

nonisolated struct DiffChanges: Sendable, Equatable {
    let length1: Int
    let length2: Int
    let changes: [DiffRange]
    let unchanged: [DiffRange]

    init(changes: [DiffRange], length1: Int, length2: Int) {
        self.length1 = length1
        self.length2 = length2
        self.changes = changes
        self.unchanged = Self.complement(of: changes, length1: length1, length2: length2)
    }

    init(unchanged: [DiffRange], length1: Int, length2: Int) {
        self.length1 = length1
        self.length2 = length2
        self.unchanged = unchanged
        self.changes = Self.complement(of: unchanged, length1: length1, length2: length2)
    }

    var isEmpty: Bool { changes.isEmpty }

    func iterateAll() -> [(range: DiffRange, isUnchanged: Bool)] {
        var result: [(range: DiffRange, isUnchanged: Bool)] = []
        var last1 = 0
        var last2 = 0
        for change in changes {
            let gap = DiffRange(last1, change.start1, last2, change.start2)
            if !gap.isEmpty { result.append((gap, true)) }
            result.append((change, false))
            last1 = change.end1
            last2 = change.end2
        }
        let tail = DiffRange(last1, length1, last2, length2)
        if !tail.isEmpty { result.append((tail, true)) }
        return result
    }

    private static func complement(of ranges: [DiffRange], length1: Int, length2: Int) -> [DiffRange] {
        var result: [DiffRange] = []
        result.reserveCapacity(ranges.count + 1)
        var last1 = 0
        var last2 = 0
        for range in ranges {
            let gap = DiffRange(last1, range.start1, last2, range.start2)
            if !gap.isEmpty { result.append(gap) }
            last1 = range.end1
            last2 = range.end2
        }
        let tail = DiffRange(last1, length1, last2, length2)
        if !tail.isEmpty { result.append(tail) }
        return result
    }
}

nonisolated struct DiffChangeBuilder {
    let length1: Int
    let length2: Int
    private(set) var index1 = 0
    private(set) var index2 = 0
    private var ranges: [DiffRange] = []
    private let expansionEquals: ((Int, Int) -> Bool)?

    init(length1: Int, length2: Int, expandingWith equals: ((Int, Int) -> Bool)? = nil) {
        self.length1 = length1
        self.length2 = length2
        self.expansionEquals = equals
    }

    mutating func markEqual(_ index1: Int, _ index2: Int) {
        markEqual(index1, index2, end1: index1 + 1, end2: index2 + 1)
    }

    mutating func markEqual(_ index1: Int, _ index2: Int, count: Int) {
        markEqual(index1, index2, end1: index1 + count, end2: index2 + count)
    }

    mutating func markEqual(_ index1: Int, _ index2: Int, end1: Int, end2: Int) {
        if index1 == end1 && index2 == end2 { return }
        guard self.index1 <= index1, self.index2 <= index2, index1 <= end1, index2 <= end2 else { return }
        if self.index1 != index1 || self.index2 != index2 {
            addChange(self.index1, self.index2, index1, index2)
        }
        self.index1 = end1
        self.index2 = end2
    }

    mutating func finish() -> DiffChanges {
        if length1 != index1 || length2 != index2 {
            addChange(index1, index2, length1, length2)
            index1 = length1
            index2 = length2
        }
        return DiffChanges(changes: ranges, length1: length1, length2: length2)
    }

    private mutating func addChange(_ start1: Int, _ start2: Int, _ end1: Int, _ end2: Int) {
        if let equals = expansionEquals {
            let expanded = TrimUtil.expand(start1, start2, end1, end2, equals)
            if !expanded.isEmpty { ranges.append(expanded) }
        } else {
            ranges.append(DiffRange(start1, end1, start2, end2))
        }
    }
}
