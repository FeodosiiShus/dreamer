import Foundation
import LanguageServerProtocol

nonisolated enum FoldRegionMapping {
    static func regions(from ranges: [FoldingRange], lineCount: Int) -> [FoldRegion] {
        var seen = Set<Int>()
        var regions: [FoldRegion] = []
        for range in ranges {
            guard range.startLine >= 0, range.startLine < lineCount else { continue }
            let endLine = min(range.endLine, lineCount - 1)
            guard endLine > range.startLine else { continue }
            guard seen.insert(range.startLine * lineCount + endLine).inserted else { continue }
            regions.append(FoldRegion(startLine: range.startLine, endLine: endLine, kind: kind(of: range.kind)))
        }
        return FoldRegion.sortedOuterFirst(regions)
    }

    static func kind(of kind: FoldingRangeKind?) -> FoldRegionKind {
        switch kind {
        case .some(.imports):
            return .imports
        case .some(.comment):
            return .comment
        case .some(.region):
            return .region
        case nil:
            return .block
        }
    }
}

nonisolated enum IndentationFoldComputer {
    private static let space: UInt16 = 0x20
    private static let tab: UInt16 = 0x09

    static func regions(in text: String, tabWidth: Int) -> [FoldRegion] {
        let units = Array(text.utf16)
        let index = FoldLineIndex(units: units)
        let width = max(tabWidth, 1)
        var regions: [FoldRegion] = []
        var open: [(line: Int, indent: Int)] = []
        var lastContentLine = 0

        func close(_ opened: (line: Int, indent: Int)) {
            if lastContentLine > opened.line {
                regions.append(FoldRegion(startLine: opened.line, endLine: lastContentLine, kind: .block))
            }
        }

        for (line, bounds) in index.lineRanges.enumerated() {
            guard let indent = indentColumns(of: bounds, units: units, tabWidth: width) else { continue }
            while let top = open.last, top.indent >= indent {
                open.removeLast()
                close(top)
            }
            open.append((line: line, indent: indent))
            lastContentLine = line
        }
        while let top = open.popLast() {
            close(top)
        }
        return FoldRegion.sortedOuterFirst(regions)
    }

    private static func indentColumns(of bounds: Range<Int>, units: [UInt16], tabWidth: Int) -> Int? {
        var column = 0
        var offset = bounds.lowerBound
        while offset < bounds.upperBound {
            let unit = units[offset]
            if unit == space {
                column += 1
            } else if unit == tab {
                column += tabWidth - column % tabWidth
            } else {
                return column
            }
            offset += 1
        }
        return nil
    }
}

nonisolated enum FoldRegionResolver {
    @concurrent
    static func regions(serverRanges: [FoldingRange]?, text: String, tabWidth: Int) async -> [FoldRegion] {
        if let serverRanges {
            let mapped = FoldRegionMapping.regions(from: serverRanges, lineCount: FoldLineIndex(text: text).lineCount)
            if !mapped.isEmpty {
                return mapped
            }
        }
        return IndentationFoldComputer.regions(in: text, tabWidth: tabWidth)
    }
}
