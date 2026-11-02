import Foundation

enum MergeLineStyle: Equatable {
    case unchanged
    case changed
    case inserted
    case conflict
    case resolved
}

struct MergePaneChip: Equatable {
    enum Kind: Equatable {
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

struct MergePaneContent: Equatable {
    var lines: [String] = []
    var styles: [MergeLineStyle] = []
    var chips: [Int: [MergePaneChip]] = [:]

    static let empty = MergePaneContent()

    var text: String { lines.joined(separator: "\n") }
}

struct ThreeWayMerge: Equatable {
    enum BlockKind: Equatable {
        case ours
        case theirs
        case both
        case conflict
    }

    enum Resolution: Equatable {
        case unresolved
        case left
        case right
        case ignored
    }

    enum NonConflictingMode: Equatable {
        case left
        case all
        case right
    }

    struct Block: Equatable, Identifiable {
        let id: Int
        let kind: BlockKind
        let baseRange: Range<Int>
        let baseLines: [String]
        let leftRange: Range<Int>
        let leftLines: [String]
        let rightRange: Range<Int>
        let rightLines: [String]
        var resolution: Resolution

        var inserted: Bool { baseRange.isEmpty }
    }

    let baseText: String
    let leftText: String
    let rightText: String
    let baseLines: [String]
    let leftLines: [String]
    let rightLines: [String]
    private(set) var blocks: [Block]

    init(base: String, ours: String, theirs: String) {
        baseText = base
        leftText = ours
        rightText = theirs
        baseLines = TextDiff.lines(in: base)
        leftLines = TextDiff.lines(in: ours)
        rightLines = TextDiff.lines(in: theirs)

        let leftDiff = TextDiff(leftLines: baseLines, rightLines: leftLines)
        let rightDiff = TextDiff(leftLines: baseLines, rightLines: rightLines)
        blocks = Self.buildBlocks(
            baseLines: baseLines,
            leftLines: leftLines,
            rightLines: rightLines,
            leftHunks: leftDiff.hunks,
            rightHunks: rightDiff.hunks
        )
    }

    init(baseLines: [String], leftLines: [String], rightLines: [String]) {
        self.init(
            base: baseLines.joined(separator: "\n"),
            ours: leftLines.joined(separator: "\n"),
            theirs: rightLines.joined(separator: "\n")
        )
    }

    var hasTrailingNewline: Bool {
        baseText.hasSuffix("\n") || leftText.hasSuffix("\n") || rightText.hasSuffix("\n")
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

    var resultText: String {
        let text = resultLines.joined(separator: "\n")
        guard hasTrailingNewline, !text.isEmpty else { return text }
        return text + "\n"
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
                var chips = pending + chips(for: block, side: side)
                pending = []
                if let existing = content.chips[start] {
                    chips = existing + chips
                }
                content.chips[start] = chips
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

    private enum PaneSide {
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
            case .left, .right:
                return .resolved
            }
        }
        switch block.resolution {
        case .unresolved, .ignored:
            return .unchanged
        case .left, .right:
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

    private static func sideRanges(
        hunks: [DiffHunk],
        regions: [Range<Int>],
        members: [[Int]]
    ) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var delta = 0
        var hunkIndex = 0
        for (index, baseRange) in regions.enumerated() {
            let memberSet = Set(members[index])
            while hunkIndex < hunks.count,
                  !memberSet.contains(hunkIndex),
                  hunks[hunkIndex].leftLines.upperBound <= baseRange.lowerBound {
                delta += hunks[hunkIndex].rightLines.count - hunks[hunkIndex].leftLines.count
                hunkIndex += 1
            }
            var regionDelta = 0
            while hunkIndex < hunks.count && memberSet.contains(hunkIndex) {
                regionDelta += hunks[hunkIndex].rightLines.count - hunks[hunkIndex].leftLines.count
                hunkIndex += 1
            }
            let start = baseRange.lowerBound + delta
            let length = (baseRange.upperBound - baseRange.lowerBound) + regionDelta
            ranges.append(start..<(start + max(length, 0)))
            delta += regionDelta
        }
        return ranges
    }

    private struct Region {
        var baseRange: Range<Int>
        var leftHunks: [Int] = []
        var rightHunks: [Int] = []
    }

    private static func interacts(_ lhs: Range<Int>, _ rhs: Range<Int>) -> Bool {
        if lhs.isEmpty && rhs.isEmpty {
            return lhs.lowerBound == rhs.lowerBound
        }
        if lhs.isEmpty {
            return rhs.lowerBound < lhs.lowerBound && lhs.lowerBound < rhs.upperBound
        }
        if rhs.isEmpty {
            return lhs.lowerBound < rhs.lowerBound && rhs.lowerBound < lhs.upperBound
        }
        return lhs.lowerBound < rhs.upperBound && rhs.lowerBound < lhs.upperBound
    }

    private static func buildBlocks(
        baseLines: [String],
        leftLines: [String],
        rightLines: [String],
        leftHunks: [DiffHunk],
        rightHunks: [DiffHunk]
    ) -> [Block] {
        struct HunkEntry {
            let range: Range<Int>
            let isLeft: Bool
            let index: Int
        }

        var regions: [Region] = []
        let entries = leftHunks.enumerated().map {
            HunkEntry(range: $0.element.leftLines, isLeft: true, index: $0.offset)
        } + rightHunks.enumerated().map {
            HunkEntry(range: $0.element.leftLines, isLeft: false, index: $0.offset)
        }

        let sorted = entries.sorted { lhs, rhs in
            if lhs.range.lowerBound != rhs.range.lowerBound {
                return lhs.range.lowerBound < rhs.range.lowerBound
            }
            return lhs.range.upperBound < rhs.range.upperBound
        }

        for entry in sorted {
            if let index = regions.indices.last, interacts(regions[index].baseRange, entry.range) {
                regions[index].baseRange = min(regions[index].baseRange.lowerBound, entry.range.lowerBound)
                    ..< max(regions[index].baseRange.upperBound, entry.range.upperBound)
                if entry.isLeft {
                    regions[index].leftHunks.append(entry.index)
                } else {
                    regions[index].rightHunks.append(entry.index)
                }
            } else {
                var region = Region(baseRange: entry.range)
                if entry.isLeft {
                    region.leftHunks = [entry.index]
                } else {
                    region.rightHunks = [entry.index]
                }
                regions.append(region)
            }
        }

        let leftRanges = sideRanges(
            hunks: leftHunks,
            regions: regions.map(\.baseRange),
            members: regions.map(\.leftHunks)
        )
        let rightRanges = sideRanges(
            hunks: rightHunks,
            regions: regions.map(\.baseRange),
            members: regions.map(\.rightHunks)
        )

        var blocks: [Block] = []
        for (regionIndex, region) in regions.enumerated() {
            let range = region.baseRange
            let leftRange = leftRanges[regionIndex]
            let rightRange = rightRanges[regionIndex]
            let baseSlice = Array(baseLines[range])
            let leftSlice = leftRange.upperBound <= leftLines.count ? Array(leftLines[leftRange]) : []
            let rightSlice = rightRange.upperBound <= rightLines.count ? Array(rightLines[rightRange]) : []

            let kind: BlockKind
            if !region.leftHunks.isEmpty && !region.rightHunks.isEmpty {
                kind = leftSlice == rightSlice ? .both : .conflict
            } else if !region.leftHunks.isEmpty {
                kind = .ours
            } else {
                kind = .theirs
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
                baseRange: range,
                baseLines: baseSlice,
                leftRange: leftRange,
                leftLines: leftSlice,
                rightRange: rightRange,
                rightLines: rightSlice,
                resolution: resolution
            ))
        }
        return blocks
    }
}
