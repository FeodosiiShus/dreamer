import Foundation

nonisolated enum FoldCommandPlanner {
    static func regionStarting(atLine line: Int, in regions: [FoldRegion]) -> FoldRegion? {
        let starting = regions.filter { $0.startLine == line }
        return starting.count == 1 ? starting.first : nil
    }

    static func regionsContaining(line: Int, in regions: [FoldRegion]) -> [FoldRegion] {
        regions
            .filter { $0.containsLine(line) }
            .sorted { lhs, rhs in
                if lhs.startLine != rhs.startLine {
                    return lhs.startLine > rhs.startLine
                }
                return lhs.endLine < rhs.endLine
            }
    }

    static func regionToCollapse(
        regions: [FoldRegion],
        caretLine: Int,
        isCollapsed: (FoldRegion) -> Bool
    ) -> FoldRegion? {
        let caretIsHidden = regions.contains { region in
            region.startLine < caretLine && caretLine <= region.endLine && isCollapsed(region)
        }
        if caretIsHidden {
            return nil
        }
        if let starting = regionStarting(atLine: caretLine, in: regions), !isCollapsed(starting) {
            return starting
        }
        return regionsContaining(line: caretLine, in: regions).first { !isCollapsed($0) }
    }

    static func regionToExpand(
        regions: [FoldRegion],
        caretLine: Int,
        isCollapsed: (FoldRegion) -> Bool
    ) -> FoldRegion? {
        if let starting = regionStarting(atLine: caretLine, in: regions), isCollapsed(starting) {
            return starting
        }
        return regionsContaining(line: caretLine, in: regions).reversed().first { isCollapsed($0) }
    }

    static func regionsForSelection(
        regions: [FoldRegion],
        selection: NSRange?,
        index: FoldLineIndex
    ) -> [FoldRegion] {
        guard let selection, selection.length > 0 else { return regions }
        let selected = regions.filter { region in
            guard let range = index.textRange(of: region) else { return false }
            return range.location >= selection.location && range.upperBound <= selection.upperBound
        }
        return selected.isEmpty ? regions : selected
    }

    static func regionsToCollapse(scope: [FoldRegion], isCollapsed: (FoldRegion) -> Bool) -> [FoldRegion] {
        scope.filter { !isCollapsed($0) }
    }

    static func commentRegions(in regions: [FoldRegion], isCollapsed: (FoldRegion) -> Bool) -> [FoldRegion] {
        regions.filter { $0.kind == .comment && !isCollapsed($0) }
    }
}

nonisolated enum FoldCaretRelocator {
    static func relocated(_ selections: [NSRange], hiding hiddenRanges: [NSRange]) -> [NSRange]? {
        var changed = false
        let result = selections.map { selection -> NSRange in
            for hidden in hiddenRanges {
                let hidesLocation = selection.location > hidden.location && selection.location < hidden.upperBound
                let hidesEnd = selection.upperBound > hidden.location && selection.upperBound < hidden.upperBound
                if hidesLocation || hidesEnd {
                    changed = true
                    return NSRange(location: hidden.location, length: 0)
                }
            }
            return selection
        }
        return changed ? result : nil
    }
}

nonisolated enum FoldAttachmentRelation {
    static func foldsRegion(attachment: NSRange, hidden: NSRange) -> Bool {
        guard attachment.length > 0 else { return false }
        let intersects = attachment.location < hidden.upperBound && hidden.location < attachment.upperBound
        guard intersects else { return false }
        let containedInRegion = attachment.location >= hidden.location && attachment.upperBound <= hidden.upperBound
        return !containedInRegion || attachment == hidden
    }
}

nonisolated struct FoldSnapshot: Sendable, Equatable {
    nonisolated struct CollapsedFold: Sendable, Equatable {
        let region: FoldRegion
        let range: NSRange
    }

    let index: FoldLineIndex
    let attachmentRanges: [NSRange]

    func isCollapsed(_ region: FoldRegion) -> Bool {
        guard let hidden = index.hiddenRange(of: region) else { return false }
        return attachmentRanges.contains { FoldAttachmentRelation.foldsRegion(attachment: $0, hidden: hidden) }
    }

    var collapsedFolds: [CollapsedFold] {
        attachmentRanges
            .filter { $0.length > 0 }
            .map { range in
                CollapsedFold(
                    region: FoldRegion(
                        startLine: index.line(containing: range.location),
                        endLine: index.line(containing: range.upperBound),
                        kind: .block
                    ),
                    range: range
                )
            }
    }
}
