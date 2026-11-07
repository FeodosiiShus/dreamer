import Foundation

nonisolated enum DiffRowKind: Sendable, Equatable {
    case context
    case inserted
    case deleted
    case modified
}

nonisolated struct DiffRow: Sendable, Equatable {
    let leftLine: Int?
    let rightLine: Int?
    let kind: DiffRowKind
}

nonisolated enum DiffHunkKind: Sendable, Equatable {
    case inserted
    case deleted
    case modified
}

nonisolated struct DiffHunk: Sendable, Equatable, Identifiable {
    let id: Int
    let kind: DiffHunkKind
    let leftLines: Range<Int>
    let rightLines: Range<Int>
    let rows: Range<Int>
}

nonisolated struct DiffOptions: Sendable, Equatable {
    var policy: ComparisonPolicy = .default

    var ignoresWhitespace: Bool {
        get { policy == .ignoreWhitespaces }
        set { policy = newValue ? .ignoreWhitespaces : .default }
    }

    init(ignoresWhitespace: Bool = false) {
        policy = ignoresWhitespace ? .ignoreWhitespaces : .default
    }

    init(policy: ComparisonPolicy) {
        self.policy = policy
    }

    static let `default` = DiffOptions()
}

nonisolated struct HunkInnerFragments: Sendable, Equatable {
    let leftText: String
    let rightText: String
    let blocks: [LineFragment]
}

nonisolated struct TextDiff: Sendable, Equatable {
    let leftLines: [String]
    let rightLines: [String]
    let hunks: [DiffHunk]
    let rows: [DiffRow]

    init(left: String, right: String, options: DiffOptions = .default) {
        self.init(leftLines: Self.lines(in: left), rightLines: Self.lines(in: right), options: options)
    }

    init(leftLines: [String], rightLines: [String], options: DiffOptions = .default) {
        let changes: [DiffRange]
        do {
            changes = try Self.changedRanges(leftLines: leftLines, rightLines: rightLines, policy: options.policy)
        } catch {
            changes = Self.coarseChangedRanges(leftLines: leftLines, rightLines: rightLines)
        }
        self.init(leftLines: leftLines, rightLines: rightLines, changes: changes)
    }

    static func compute(leftLines: [String], rightLines: [String], options: DiffOptions = .default) throws -> TextDiff {
        let changes = try changedRanges(leftLines: leftLines, rightLines: rightLines, policy: options.policy)
        return TextDiff(leftLines: leftLines, rightLines: rightLines, changes: changes)
    }

    static func compute(left: String, right: String, options: DiffOptions = .default) throws -> TextDiff {
        try compute(leftLines: lines(in: left), rightLines: lines(in: right), options: options)
    }

    private init(leftLines: [String], rightLines: [String], changes: [DiffRange]) {
        var hunks: [DiffHunk] = []
        var rows: [DiffRow] = []

        var leftIndex = 0
        var rightIndex = 0
        for change in changes {
            while leftIndex < change.start1 && rightIndex < change.start2 {
                rows.append(DiffRow(leftLine: leftIndex, rightLine: rightIndex, kind: .context))
                leftIndex += 1
                rightIndex += 1
            }
            Self.appendHunk(
                leftRange: change.start1..<change.end1,
                rightRange: change.start2..<change.end2,
                hunks: &hunks,
                rows: &rows
            )
            leftIndex = change.end1
            rightIndex = change.end2
        }
        while leftIndex < leftLines.count && rightIndex < rightLines.count {
            rows.append(DiffRow(leftLine: leftIndex, rightLine: rightIndex, kind: .context))
            leftIndex += 1
            rightIndex += 1
        }

        self.leftLines = leftLines
        self.rightLines = rightLines
        self.hunks = hunks
        self.rows = rows
    }

    var differenceCount: Int { hunks.count }

    func innerFragments(
        for hunk: DiffHunk,
        policy: ComparisonPolicy = .default,
        fragmentsPolicy: InnerFragmentsPolicy = .words
    ) throws -> HunkInnerFragments {
        let leftSlice = Array(leftLines[hunk.leftLines])
        let rightSlice = Array(rightLines[hunk.rightLines])
        let leftText = leftSlice.joined(separator: "\n")
        let rightText = rightSlice.joined(separator: "\n")

        let leftUnits = Array(leftText.utf16)
        let rightUnits = Array(rightText.utf16)
        let offsets1 = LineOffsets(lines: leftSlice.map { Array($0.utf16) })
        let offsets2 = LineOffsets(lines: rightSlice.map { Array($0.utf16) })

        let fragment = ComparisonManager.createLineFragment(
            0,
            leftSlice.count,
            0,
            rightSlice.count,
            offsets1,
            offsets2
        )
        let blocks = try ComparisonManager.createInnerFragments(
            [fragment],
            leftUnits,
            rightUnits,
            policy,
            fragmentsPolicy
        )
        return HunkInnerFragments(leftText: leftText, rightText: rightText, blocks: blocks)
    }

    static func lines(in text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var normalized = text
        if normalized.utf8.contains(13) {
            normalized = (normalized as NSString).replacingOccurrences(of: "\r\n", with: "\n")
            normalized = (normalized as NSString).replacingOccurrences(of: "\r", with: "\n")
        }
        var lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if normalized.hasSuffix("\n") {
            lines.removeLast()
        }
        return lines
    }

    private static func changedRanges(leftLines: [String], rightLines: [String], policy: ComparisonPolicy) throws -> [DiffRange] {
        if leftLines == rightLines { return [] }
        do {
            return try ComparisonManager.compareLineRanges(leftLines, rightLines, policy: policy)
        } catch is DiffTooBigError {
            return coarseChangedRanges(leftLines: leftLines, rightLines: rightLines)
        }
    }

    private static func coarseChangedRanges(leftLines: [String], rightLines: [String]) -> [DiffRange] {
        let minCount = min(leftLines.count, rightLines.count)
        var prefix = 0
        while prefix < minCount && leftLines[prefix] == rightLines[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < minCount - prefix && leftLines[leftLines.count - 1 - suffix] == rightLines[rightLines.count - 1 - suffix] {
            suffix += 1
        }
        let range = DiffRange(prefix, leftLines.count - suffix, prefix, rightLines.count - suffix)
        return range.isEmpty ? [] : [range]
    }

    private static func appendHunk(
        leftRange: Range<Int>,
        rightRange: Range<Int>,
        hunks: inout [DiffHunk],
        rows: inout [DiffRow]
    ) {
        let startRow = rows.count
        let kind: DiffHunkKind
        if !leftRange.isEmpty && !rightRange.isEmpty {
            kind = .modified
        } else if !leftRange.isEmpty {
            kind = .deleted
        } else {
            kind = .inserted
        }

        let paired = min(leftRange.count, rightRange.count)
        for offset in 0..<paired {
            rows.append(DiffRow(
                leftLine: leftRange.lowerBound + offset,
                rightLine: rightRange.lowerBound + offset,
                kind: .modified
            ))
        }
        for offset in paired..<leftRange.count {
            rows.append(DiffRow(
                leftLine: leftRange.lowerBound + offset,
                rightLine: nil,
                kind: .deleted
            ))
        }
        for offset in paired..<rightRange.count {
            rows.append(DiffRow(
                leftLine: nil,
                rightLine: rightRange.lowerBound + offset,
                kind: .inserted
            ))
        }

        hunks.append(DiffHunk(
            id: hunks.count,
            kind: kind,
            leftLines: leftRange,
            rightLines: rightRange,
            rows: startRow..<rows.count
        ))
    }
}
