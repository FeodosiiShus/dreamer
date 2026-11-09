import Foundation

nonisolated enum MergeLineStyle: Equatable, Sendable {
    case unchanged
    case changed
    case inserted
    case conflict
    case resolved
}

nonisolated struct MergePaneChip: Equatable, Sendable {
    nonisolated enum Kind: Equatable, Sendable {
        case acceptLeft
        case acceptRight
        case ignore
    }

    let kind: Kind
    let blockID: Int

    var symbol: String {
        switch kind {
        case .acceptLeft: return "\u{00BB}"
        case .acceptRight: return "\u{00AB}"
        case .ignore: return "\u{00D7}"
        }
    }
}

nonisolated struct MergePaneContent: Equatable, Sendable {
    var lines: [String] = []
    var styles: [MergeLineStyle] = []
    var chips: [Int: [MergePaneChip]] = [:]

    static let empty = MergePaneContent()

    var text: String { lines.joined(separator: "\n") }
}

nonisolated struct ThreeWayMerge: Equatable, Sendable {
    nonisolated enum BlockKind: Equatable, Sendable {
        case ours
        case theirs
        case both
        case conflict
    }

    nonisolated enum Resolution: Equatable, Sendable {
        case unresolved
        case left
        case right
        case ignored
        case merged
    }

    nonisolated enum NonConflictingMode: Equatable, Sendable {
        case left
        case all
        case right
    }

    nonisolated struct Block: Equatable, Identifiable, Sendable {
        let id: Int
        let kind: BlockKind
        let baseRange: Range<Int>
        let baseLines: [String]
        let leftRange: Range<Int>
        let leftLines: [String]
        let rightRange: Range<Int>
        let rightLines: [String]
        var resolution: Resolution
        var autoResolvedLines: [String]
        let canBeResolved: Bool

        var inserted: Bool { baseRange.isEmpty }
    }

    let baseText: String
    let leftText: String
    let rightText: String
    let baseLines: [String]
    let leftLines: [String]
    let rightLines: [String]
    let lineEnding: LineEnding
    private(set) var blocks: [Block]

    init(base: String, ours: String, theirs: String, policy: ComparisonPolicy = .default) {
        baseText = base
        leftText = ours
        rightText = theirs
        baseLines = TextDiff.lines(in: base)
        leftLines = TextDiff.lines(in: ours)
        rightLines = TextDiff.lines(in: theirs)
        lineEnding = LineEnding.dominant(in: ours)
            ?? LineEnding.dominant(in: base)
            ?? LineEnding.dominant(in: theirs)
            ?? .lineFeed
        blocks = Self.buildBlocks(
            baseLines: baseLines,
            leftLines: leftLines,
            rightLines: rightLines,
            policy: policy
        )
    }

    init(baseLines: [String], leftLines: [String], rightLines: [String]) {
        self.init(
            base: baseLines.joined(separator: "\n"),
            ours: leftLines.joined(separator: "\n"),
            theirs: rightLines.joined(separator: "\n")
        )
    }

    var conflictCount: Int {
        blocks.filter { $0.kind == .conflict && $0.resolution == .unresolved }.count
    }

    var changeCount: Int {
        blocks.filter { $0.kind != .conflict && $0.resolution != .ignored }.count
    }

    var isFullyResolved: Bool { conflictCount == 0 }

    var summary: String {
        let changes = "\(changeCount) \(changeCount == 1 ? "change" : "changes")"
        let conflicts = "\(conflictCount) \(conflictCount == 1 ? "conflict" : "conflicts")"
        return "\(changes), \(conflicts)"
    }

    mutating func resolve(_ blockID: Int, with resolution: Resolution) {
        guard let index = blocks.firstIndex(where: { $0.id == blockID }) else { return }
        if resolution == .merged && !blocks[index].canBeResolved { return }
        blocks[index].resolution = resolution
    }

    mutating func applyNonConflicting(_ mode: NonConflictingMode) {
        for index in blocks.indices {
            switch blocks[index].kind {
            case .ours:
                blocks[index].resolution = mode == .right ? .ignored : .left
            case .theirs:
                blocks[index].resolution = mode == .left ? .ignored : .right
            case .both:
                blocks[index].resolution = mode == .right ? .right : .left
            case .conflict:
                continue
            }
        }
    }

    var resolvableConflictCount: Int {
        blocks.filter { $0.kind == .conflict && $0.resolution == .unresolved && $0.canBeResolved }.count
    }

    var hasResolvableConflicts: Bool { resolvableConflictCount > 0 }

    mutating func resolveSimpleConflicts() {
        for index in blocks.indices where blocks[index].kind == .conflict
            && blocks[index].resolution == .unresolved
            && blocks[index].canBeResolved {
            blocks[index].resolution = .merged
        }
    }

    func hasApplicableNonConflictingChanges(_ mode: NonConflictingMode) -> Bool {
        blocks.contains { block in
            guard block.kind != .conflict else { return false }
            switch mode {
            case .all:
                return true
            case .left:
                return block.kind == .ours || block.kind == .both
            case .right:
                return block.kind == .theirs || block.kind == .both
            }
        }
    }

    func resultLines(for block: Block) -> [String] {
        switch block.resolution {
        case .left:
            return block.leftLines
        case .right:
            return block.rightLines
        case .merged:
            return block.autoResolvedLines
        case .unresolved, .ignored:
            return block.baseLines
        }
    }

    var resultLines: [String] {
        var lines: [String] = []
        var cursor = 0
        for block in blocks {
            if block.baseRange.lowerBound > cursor {
                lines.append(contentsOf: baseLines[cursor..<block.baseRange.lowerBound])
            }
            lines.append(contentsOf: resultLines(for: block))
            cursor = block.baseRange.upperBound
        }
        if cursor < baseLines.count {
            lines.append(contentsOf: baseLines[cursor...])
        }
        return lines
    }

    var leftPane: MergePaneContent { paneContent(.left) }

    var rightPane: MergePaneContent { paneContent(.right) }

    private func paneContent(_ side: PaneSide) -> MergePaneContent {
        let lines = side == .left ? leftLines : rightLines
        var content = MergePaneContent()
        var cursor = 0
        var pending: [MergePaneChip] = []

        for block in blocks {
            let range = side == .left ? block.leftRange : block.rightRange
            let blockLines = side == .left ? block.leftLines : block.rightLines
            if range.lowerBound > cursor && range.lowerBound <= lines.count {
                let appendStart = content.lines.count
                content.lines.append(contentsOf: lines[cursor..<range.lowerBound])
                content.styles.append(contentsOf: Array(
                    repeating: MergeLineStyle.unchanged,
                    count: range.lowerBound - cursor
                ))
                if !pending.isEmpty {
                    content.chips[appendStart] = pending
                    pending = []
                }
            }
            if blockLines.isEmpty {
                pending.append(contentsOf: chips(for: block, side: side))
            } else {
                let start = content.lines.count
                for line in blockLines {
                    content.lines.append(line)
                    content.styles.append(side == .left ? leftStyle(for: block) : rightStyle(for: block))
                }
                content.chips[start] = pending + chips(for: block, side: side)
                pending = []
            }
            cursor = max(cursor, range.upperBound)
        }

        if cursor < lines.count {
            let appendStart = content.lines.count
            content.lines.append(contentsOf: lines[cursor...])
            content.styles.append(contentsOf: Array(
                repeating: MergeLineStyle.unchanged,
                count: lines.count - cursor
            ))
            if !pending.isEmpty {
                content.chips[appendStart] = pending
                pending = []
            }
        }

        if !pending.isEmpty, !content.lines.isEmpty {
            let last = content.lines.count - 1
            content.chips[last] = pending + (content.chips[last] ?? [])
        }
        return content
    }

    var resultPane: MergePaneContent {
        var content = MergePaneContent()
        var cursor = 0
        for block in blocks {
            if block.baseRange.lowerBound > cursor {
                content.lines.append(contentsOf: baseLines[cursor..<block.baseRange.lowerBound])
                content.styles.append(contentsOf: Array(
                    repeating: MergeLineStyle.unchanged,
                    count: block.baseRange.lowerBound - cursor
                ))
            }
            let blockLines = resultLines(for: block)
            content.lines.append(contentsOf: blockLines)
            content.styles.append(contentsOf: Array(repeating: resultStyle(for: block), count: blockLines.count))
            cursor = block.baseRange.upperBound
        }
        if cursor < baseLines.count {
            content.lines.append(contentsOf: baseLines[cursor...])
            content.styles.append(contentsOf: Array(
                repeating: MergeLineStyle.unchanged,
                count: baseLines.count - cursor
            ))
        }
        return content
    }

    private nonisolated enum PaneSide {
        case left
        case right
    }

    private func leftStyle(for block: Block) -> MergeLineStyle {
        switch block.kind {
        case .conflict:
            return .conflict
        case .ours, .both:
            return block.inserted ? .inserted : .changed
        case .theirs:
            return .unchanged
        }
    }

    private func rightStyle(for block: Block) -> MergeLineStyle {
        switch block.kind {
        case .conflict:
            return .conflict
        case .theirs, .both:
            return block.inserted ? .inserted : .changed
        case .ours:
            return .unchanged
        }
    }

    private func resultStyle(for block: Block) -> MergeLineStyle {
        if block.kind == .conflict {
            switch block.resolution {
            case .unresolved:
                return .conflict
            case .ignored:
                return .unchanged
            case .left, .right, .merged:
                return .resolved
            }
        }
        switch block.resolution {
        case .unresolved, .ignored:
            return .unchanged
        case .left, .right, .merged:
            return block.inserted ? .inserted : .changed
        }
    }

    private func chips(for block: Block, side: PaneSide) -> [MergePaneChip] {
        var chips: [MergePaneChip] = [
            MergePaneChip(
                kind: side == .left ? .acceptLeft : .acceptRight,
                blockID: block.id
            )
        ]
        if block.kind == .conflict {
            chips.append(MergePaneChip(kind: .ignore, blockID: block.id))
        }
        return chips
    }

    private static func buildBlocks(
        baseLines: [String],
        leftLines: [String],
        rightLines: [String],
        policy: ComparisonPolicy
    ) -> [Block] {
        let mergeBlocks: [LineMergeBlock]
        do {
            mergeBlocks = try ComparisonManager.mergeBlocks(
                left: leftLines,
                base: baseLines,
                right: rightLines,
                policy: policy
            )
        } catch {
            mergeBlocks = coarseMergeBlocks(baseLines: baseLines, leftLines: leftLines, rightLines: rightLines, policy: policy)
        }

        var blocks: [Block] = []
        blocks.reserveCapacity(mergeBlocks.count)
        for mergeBlock in mergeBlocks {
            let range = mergeBlock.range
            let baseRange = range.range(.base)
            let leftRange = range.range(.left)
            let rightRange = range.range(.right)

            let type = mergeBlock.type
            let kind: BlockKind
            if type.kind == .conflict {
                kind = .conflict
            } else if type.isLeftChange && type.isRightChange {
                kind = .both
            } else if type.isRightChange {
                kind = .theirs
            } else {
                kind = .ours
            }

            let resolution: Resolution
            switch kind {
            case .ours, .both:
                resolution = .left
            case .theirs:
                resolution = .right
            case .conflict:
                resolution = .unresolved
            }

            blocks.append(Block(
                id: blocks.count,
                kind: kind,
                baseRange: baseRange,
                baseLines: Array(baseLines[baseRange]),
                leftRange: leftRange,
                leftLines: Array(leftLines[leftRange]),
                rightRange: rightRange,
                rightLines: Array(rightLines[rightRange]),
                resolution: resolution,
                autoResolvedLines: mergeBlock.resolvedLines ?? [],
                canBeResolved: mergeBlock.resolvedLines != nil
            ))
        }
        return blocks
    }

    private static func coarseMergeBlocks(
        baseLines: [String],
        leftLines: [String],
        rightLines: [String],
        policy: ComparisonPolicy
    ) -> [LineMergeBlock] {
        let minCount = min(baseLines.count, min(leftLines.count, rightLines.count))
        var prefix = 0
        while prefix < minCount && baseLines[prefix] == leftLines[prefix] && baseLines[prefix] == rightLines[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < minCount - prefix
            && baseLines[baseLines.count - 1 - suffix] == leftLines[leftLines.count - 1 - suffix]
            && baseLines[baseLines.count - 1 - suffix] == rightLines[rightLines.count - 1 - suffix] {
            suffix += 1
        }
        let range = MergeRange(
            prefix,
            leftLines.count - suffix,
            prefix,
            baseLines.count - suffix,
            prefix,
            rightLines.count - suffix
        )
        if range.isEmpty { return [] }
        let type = MergeConflictType(.conflict, leftChange: true, rightChange: true, resolutionStrategy: nil)
        return [LineMergeBlock(range: range, type: type, resolvedLines: nil)]
    }
}
