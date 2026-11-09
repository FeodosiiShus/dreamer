import Foundation

nonisolated enum FoldRegionKind: Sendable, Hashable {
    case imports
    case comment
    case region
    case block
}

nonisolated struct FoldRegion: Sendable, Hashable {
    let startLine: Int
    let endLine: Int
    let kind: FoldRegionKind

    func containsLine(_ line: Int) -> Bool {
        line >= startLine && line <= endLine
    }

    static func sortedOuterFirst(_ regions: [FoldRegion]) -> [FoldRegion] {
        regions.sorted { lhs, rhs in
            if lhs.startLine != rhs.startLine {
                return lhs.startLine < rhs.startLine
            }
            return lhs.endLine > rhs.endLine
        }
    }
}

nonisolated struct FoldLineIndex: Sendable, Equatable {
    private static let lineFeed: UInt16 = 0x0A
    private static let carriageReturn: UInt16 = 0x0D

    private let starts: [Int]
    private let contentEnds: [Int]

    init(text: String) {
        self.init(units: Array(text.utf16))
    }

    init(units: [UInt16]) {
        var starts: [Int] = [0]
        var contentEnds: [Int] = []
        var previous: UInt16 = 0
        for (offset, unit) in units.enumerated() {
            if unit == Self.lineFeed {
                if previous == Self.carriageReturn {
                    starts[starts.count - 1] = offset + 1
                } else {
                    contentEnds.append(offset)
                    starts.append(offset + 1)
                }
            } else if unit == Self.carriageReturn {
                contentEnds.append(offset)
                starts.append(offset + 1)
            }
            previous = unit
        }
        contentEnds.append(units.count)
        self.starts = starts
        self.contentEnds = contentEnds
    }

    var lineCount: Int {
        starts.count
    }

    var lineRanges: [Range<Int>] {
        zip(starts, contentEnds).map { $0..<$1 }
    }

    func start(ofLine line: Int) -> Int? {
        starts.indices.contains(line) ? starts[line] : nil
    }

    func contentEnd(ofLine line: Int) -> Int? {
        contentEnds.indices.contains(line) ? contentEnds[line] : nil
    }

    func line(containing offset: Int) -> Int {
        var low = 0
        var high = starts.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if starts[middle] <= offset {
                low = middle
            } else {
                high = middle - 1
            }
        }
        return low
    }

    func hiddenRange(of region: FoldRegion) -> NSRange? {
        guard region.endLine > region.startLine,
              let lower = contentEnd(ofLine: region.startLine),
              let upper = contentEnd(ofLine: region.endLine) else {
            return nil
        }
        return NSRange(location: lower, length: upper - lower)
    }

    func textRange(of region: FoldRegion) -> NSRange? {
        guard let lower = start(ofLine: region.startLine),
              let upper = contentEnd(ofLine: region.endLine),
              upper >= lower else {
            return nil
        }
        return NSRange(location: lower, length: upper - lower)
    }
}
