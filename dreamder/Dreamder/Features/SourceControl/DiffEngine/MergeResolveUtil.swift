import Foundation

nonisolated enum MergeResolveUtil {
    static func tryResolve(left: DiffUnits, base: DiffUnits, right: DiffUnits) -> DiffUnits? {
        do {
            var simple = SimpleResolveHelper(left: left, base: base, right: right)
            if let resolved = try simple.execute(.default) { return resolved }

            var ignoringWhitespaces = SimpleResolveHelper(left: left, base: base, right: right)
            return try ignoringWhitespaces.execute(.ignoreWhitespaces)
        } catch {
            return nil
        }
    }

    static func tryResolve(left: String, base: String, right: String) -> String? {
        guard let resolved = tryResolve(
            left: Array(left.utf16),
            base: Array(base.utf16),
            right: Array(right.utf16)
        ) else { return nil }
        return String(decoding: resolved, as: UTF16.self)
    }
}

nonisolated struct SimpleResolveHelper {
    private let left: DiffUnits
    private let base: DiffUnits
    private let right: DiffUnits
    private var newContent: DiffUnits = []
    private var last1 = 0
    private var last2 = 0
    private var last3 = 0

    init(left: DiffUnits, base: DiffUnits, right: DiffUnits) {
        self.left = left
        self.base = base
        self.right = right
    }

    mutating func execute(_ policy: ComparisonPolicy) throws -> DiffUnits? {
        let changes = try ByWord.compare(left, base, right, policy)

        for fragment in changes {
            let baseRange = nextMergeRange(fragment.start1, fragment.start2, fragment.start3)
            appendBase(baseRange)

            let conflictRange = nextMergeRange(fragment.end1, fragment.end2, fragment.end3)
            if !appendConflict(conflictRange, policy) { return nil }
        }

        let trailingRange = nextMergeRange(left.count, base.count, right.count)
        appendBase(trailingRange)

        return newContent
    }

    private mutating func nextMergeRange(_ end1: Int, _ end2: Int, _ end3: Int) -> MergeRange {
        let range = MergeRange(last1, end1, last2, end2, last3, end3)
        last1 = end1
        last2 = end2
        last3 = end3
        return range
    }

    private mutating func appendBase(_ range: MergeRange) {
        if range.isEmpty { return }

        if isUnchangedRange(range, .default) {
            append(range, .base)
        } else {
            let type = conflictType(range, .default)
            if type.isChange(.left) {
                append(range, .left)
            } else {
                append(range, .right)
            }
        }
    }

    private mutating func appendConflict(_ range: MergeRange, _ policy: ComparisonPolicy) -> Bool {
        let type = conflictType(range, policy)
        if type.kind == .conflict { return false }

        if type.isChange(.left) {
            append(range, .left)
        } else {
            append(range, .right)
        }
        return true
    }

    private mutating func append(_ range: MergeRange, _ side: ThreeSide) {
        switch side {
        case .left: newContent.append(contentsOf: left[range.range(.left)])
        case .base: newContent.append(contentsOf: base[range.range(.base)])
        case .right: newContent.append(contentsOf: right[range.range(.right)])
        }
    }

    private func conflictType(_ range: MergeRange, _ policy: ComparisonPolicy) -> MergeConflictType {
        MergeRangeUtil.wordMergeType(range: range, left: left, base: base, right: right, policy: policy)
    }

    private func isUnchangedRange(_ range: MergeRange, _ policy: ComparisonPolicy) -> Bool {
        MergeRangeUtil.wordContentsEqual(range, left, base, right, policy, .base, .left)
            && MergeRangeUtil.wordContentsEqual(range, left, base, right, policy, .base, .right)
    }
}
