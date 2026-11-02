import Foundation

struct GitLineChange: Equatable {
    enum Kind: Equatable {
        case added
        case modified
        case deleted
    }

    let kind: Kind
    let oldLines: ClosedRange<Int>?
    let newLines: ClosedRange<Int>?
    let anchorLine: Int

    init(kind: Kind, oldLines: ClosedRange<Int>?, newLines: ClosedRange<Int>?, anchorLine: Int) {
        self.kind = kind
        self.oldLines = oldLines
        self.newLines = newLines
        self.anchorLine = anchorLine
    }

    init?(hunk: GitDiffParser.Hunk) {
        guard hunk.oldCount >= 0, hunk.newCount >= 0, hunk.oldCount + hunk.newCount > 0 else { return nil }
        guard hunk.oldCount == 0 || hunk.oldStart >= 1 else { return nil }
        guard hunk.newCount == 0 || hunk.newStart >= 1 else { return nil }

        let oldRange = hunk.oldCount > 0 ? hunk.oldStart...(hunk.oldStart + hunk.oldCount - 1) : nil
        let newRange = hunk.newCount > 0 ? hunk.newStart...(hunk.newStart + hunk.newCount - 1) : nil

        if newRange == nil {
            self.init(kind: .deleted, oldLines: oldRange, newLines: nil, anchorLine: hunk.newStart)
        } else if oldRange == nil {
            self.init(kind: .added, oldLines: nil, newLines: newRange, anchorLine: hunk.newStart)
        } else {
            self.init(kind: .modified, oldLines: oldRange, newLines: newRange, anchorLine: hunk.newStart)
        }
    }

    static func markers(inDiff output: String) -> [GitLineChange] {
        GitDiffParser.hunks(inDiff: output).compactMap { GitLineChange(hunk: $0) }
    }

    static func markers(from diff: TextDiff) -> [GitLineChange] {
        diff.hunks.compactMap { hunk in
            let oldStart = hunk.leftLines.lowerBound + 1
            let newStart = hunk.rightLines.lowerBound + 1
            switch hunk.kind {
            case .inserted:
                guard !hunk.rightLines.isEmpty else { return nil }
                return GitLineChange(
                    kind: .added,
                    oldLines: nil,
                    newLines: newStart...hunk.rightLines.upperBound,
                    anchorLine: newStart
                )
            case .deleted:
                guard !hunk.leftLines.isEmpty else { return nil }
                return GitLineChange(
                    kind: .deleted,
                    oldLines: oldStart...hunk.leftLines.upperBound,
                    newLines: nil,
                    anchorLine: hunk.rightLines.lowerBound
                )
            case .modified:
                guard !hunk.leftLines.isEmpty, !hunk.rightLines.isEmpty else { return nil }
                return GitLineChange(
                    kind: .modified,
                    oldLines: oldStart...hunk.leftLines.upperBound,
                    newLines: newStart...hunk.rightLines.upperBound,
                    anchorLine: newStart
                )
            }
        }
    }

    static func wholeFileAdded(lineCount: Int) -> [GitLineChange] {
        guard lineCount > 0 else { return [] }
        return [GitLineChange(kind: .added, oldLines: nil, newLines: 1...lineCount, anchorLine: 1)]
    }
}
