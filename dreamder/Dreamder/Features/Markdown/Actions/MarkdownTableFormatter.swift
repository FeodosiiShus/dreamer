import Foundation

nonisolated enum MarkdownTableCellContent {
    static let caretMarker: UInt16 = 10

    static func separator(alignment: MarkdownTableAlignment, width: Int, style: MarkdownTableStyle) -> [UInt16] {
        switch style {
        case .compact:
            return units(" " + compactSeparator(alignment) + " ")
        case .tight:
            return units(compactSeparator(alignment))
        case .aligned:
            switch alignment {
            case .none:
                return units(dashes(width))
            case .left:
                return units(":" + dashes(max(width - 1, 1)))
            case .right:
                return units(dashes(max(width - 1, 1)) + ":")
            case .center:
                return units(":" + dashes(max(width - 2, 1)) + ":")
            }
        }
    }

    static func realigned(
        content: [UInt16],
        width wholeWidth: Int,
        alignment: MarkdownTableAlignment,
        style: MarkdownTableStyle,
        startColumn: Int = 0,
        tabSize: Int = 4
    ) -> [UInt16] {
        switch style {
        case .compact:
            return compactCell(content)
        case .tight:
            return content
        case .aligned:
            break
        }
        if content.contains(MarkdownText.tab) {
            return tabbedCell(
                content,
                wholeWidth: wholeWidth,
                alignment: alignment,
                startColumn: startColumn,
                tabSize: tabSize
            )
        }
        let contentWidth = MarkdownTable.displayWidth(units: content)
        let padding = max(wholeWidth - contentWidth, 0)
        switch alignment {
        case .right:
            return spaces(max(padding - 1, 0)) + content + spaces(1)
        case .center:
            let left = padding / 2
            return spaces(left) + content + spaces(padding - left)
        case .left, .none:
            return spaces(1) + content + spaces(max(padding - 1, 0))
        }
    }

    private static func tabbedCell(
        _ content: [UInt16],
        wholeWidth: Int,
        alignment: MarkdownTableAlignment,
        startColumn: Int,
        tabSize: Int
    ) -> [UInt16] {
        let candidates: Range<Int>
        switch alignment {
        case .left, .none:
            candidates = 1..<2
        case .right, .center:
            candidates = 1..<max(wholeWidth, 1)
        }
        var best: (left: Int, right: Int, key: Int)?
        for left in candidates {
            let width = MarkdownTable.displayWidth(units: content, startColumn: startColumn + left, tabSize: tabSize)
            let right = wholeWidth - left - width
            guard right >= 1 else { continue }
            let key: Int
            switch alignment {
            case .right: key = -left
            case .center: key = abs(left - right)
            case .left, .none: key = left
            }
            if let current = best, current.key <= key { continue }
            best = (left, right, key)
        }
        let left = best?.left ?? 1
        let right = best?.right ?? 1
        return spaces(left) + content + spaces(right)
    }

    private static func compactCell(_ content: [UInt16]) -> [UInt16] {
        if content.isEmpty { return spaces(1) }
        if content.allSatisfy({ $0 == caretMarker }) { return spaces(1) + content }
        return spaces(1) + content + spaces(1)
    }

    private static func compactSeparator(_ alignment: MarkdownTableAlignment) -> String {
        switch alignment {
        case .none: "---"
        case .left: ":---"
        case .right: "---:"
        case .center: ":---:"
        }
    }

    private static func dashes(_ count: Int) -> String {
        String(repeating: "-", count: max(count, 0))
    }

    private static func units(_ string: String) -> [UInt16] {
        Array(string.utf16)
    }

    static func spaces(_ count: Int) -> [UInt16] {
        [UInt16](repeating: MarkdownText.space, count: max(count, 0))
    }
}

nonisolated struct MarkdownTableFormatter: Sendable {
    let style: MarkdownTableStyle
    let tabSize: Int
    let trimToMaxContent: Bool
    let preventExpand: Bool

    private struct Plan {
        let lines: Range<Int>
        let prefixLengths: [Int]
        let columnCount: Int
    }

    private struct State {
        var units: [UInt16]
        var tracked: [Int]
    }

    private struct CellState {
        let rowIndex: Int
        let range: Range<Int>
        let startColumn: Int
        let isBlank: Bool
        let contentWithCarets: [UInt16]
        let trimmedWithCarets: [UInt16]
        let trimmedWithoutCarets: [UInt16]
        let caretIndices: [Int]
    }

    func format(text: String, selections: [NSRange], onlyTablesTouchedBySelections: Bool) -> MarkdownActionResult? {
        let original = Array(text.utf16)
        let document = MarkdownDocument(MarkdownText(units: original))
        let tracked = selections.flatMap { selection in
            [selection.location, selection.location + selection.length].map { min(max($0, 0), original.count) }
        }
        var plans: [Plan] = []
        for block in document.blocks where block.kind == .table {
            if onlyTablesTouchedBySelections {
                let touched = tracked.contains { block.lines.contains(document.text.lineIndex(containing: $0)) }
                if !touched { continue }
            }
            guard let layout = MarkdownTableLayout(document: document, block: block),
                  layout.hasBorders,
                  !layout.header.cells.isEmpty,
                  layout.separator.cells.count >= layout.header.cells.count else {
                continue
            }
            plans.append(Plan(
                lines: block.lines,
                prefixLengths: MarkdownTableLayout.prefixLengths(document: document, lines: block.lines),
                columnCount: layout.header.cells.count
            ))
        }
        var state = State(units: original, tracked: tracked)
        for plan in plans.reversed() {
            formatTable(plan, state: &state)
        }
        guard state.units != original else { return nil }
        var resultSelections: [NSRange] = []
        for index in selections.indices {
            let start = state.tracked[index * 2]
            let end = state.tracked[index * 2 + 1]
            resultSelections.append(NSRange(location: start, length: max(end - start, 0)))
        }
        return MarkdownActionResult(original: original, updated: state.units, selections: resultSelections)
    }

    private func formatTable(_ plan: Plan, state: inout State) {
        for column in 0..<plan.columnCount {
            if !formatColumn(column, plan: plan, state: &state) { break }
        }
    }

    private func formatColumn(_ column: Int, plan: Plan, state: inout State) -> Bool {
        let text = MarkdownText(units: state.units)
        guard let layout = MarkdownTableLayout(text: text, lines: plan.lines, prefixLengths: plan.prefixLengths),
              column < layout.header.cells.count,
              column < layout.separator.cells.count else { return false }
        let separatorRange = layout.separator.cells[column]
        var cellStates: [CellState] = []
        for (rowIndex, row) in layout.rows.enumerated() where rowIndex != 1 && column < row.cells.count {
            cellStates.append(cellState(rowIndex: rowIndex, row: row, range: row.cells[column], state: state))
        }

        let maxWidth: Int
        if style == .aligned {
            maxWidth = maxCellWidth(cellStates, separatorRange: separatorRange, tracked: state.tracked)
        } else {
            maxWidth = 0
        }
        let alignment = MarkdownTableAlignment(units: state.units, cell: separatorRange)

        for rowIndex in layout.rows.indices.reversed() {
            if rowIndex == 1 {
                processSeparator(range: separatorRange, alignment: alignment, maxWidth: maxWidth, state: &state)
            } else if let cell = cellStates.first(where: { $0.rowIndex == rowIndex }) {
                processCell(cell, alignment: alignment, maxWidth: maxWidth, state: &state)
            }
        }
        return true
    }

    private func cellState(rowIndex: Int, row: MarkdownTableLayout.Row, range: Range<Int>, state: State) -> CellState {
        let prefix = state.units[row.lineStart..<range.lowerBound]
        let startColumn = MarkdownTable.displayWidth(units: prefix, startColumn: 0, tabSize: tabSize)
        let raw = Array(state.units[range])
        let carets = state.tracked.indices
            .filter { range.lowerBound <= state.tracked[$0] && state.tracked[$0] <= range.upperBound }
            .sorted { left, right in
                state.tracked[left] != state.tracked[right] ? state.tracked[left] < state.tracked[right] : left < right
            }
        var content: [UInt16] = []
        var previous = 0
        for index in carets {
            let relative = state.tracked[index] - range.lowerBound
            content.append(contentsOf: raw[previous..<relative])
            content.append(MarkdownTableCellContent.caretMarker)
            previous = relative
        }
        content.append(contentsOf: raw[previous...])
        let trimmed = Self.trimmed(content)
        return CellState(
            rowIndex: rowIndex,
            range: range,
            startColumn: startColumn,
            isBlank: raw.allSatisfy { MarkdownText.isJavaWhitespace($0) },
            contentWithCarets: content,
            trimmedWithCarets: trimmed,
            trimmedWithoutCarets: trimmed.filter { $0 != MarkdownTableCellContent.caretMarker },
            caretIndices: carets
        )
    }

    private func maxCellWidth(_ cells: [CellState], separatorRange: Range<Int>, tracked: [Int]) -> Int {
        let trim = trimToMaxContent && !cells.allSatisfy { $0.isBlank }
        let widths = cells.map { cell in
            if trim {
                MarkdownTable.displayWidth(
                    units: cell.trimmedWithoutCarets,
                    startColumn: cell.startColumn + 1,
                    tabSize: tabSize
                ) + 2
            } else {
                MarkdownTable.displayWidth(
                    units: cell.contentWithCarets,
                    startColumn: cell.startColumn,
                    tabSize: tabSize
                )
            }
        }
        let separatorHasCaret = tracked.contains { separatorRange.lowerBound <= $0 && $0 <= separatorRange.upperBound }
        return max(widths.reduce(0, max), separatorHasCaret ? separatorRange.count : 1)
    }

    private func processCell(_ cell: CellState, alignment: MarkdownTableAlignment, maxWidth: Int, state: inout State) {
        let expected = MarkdownTableCellContent.realigned(
            content: cell.trimmedWithCarets,
            width: maxWidth,
            alignment: alignment,
            style: style,
            startColumn: cell.startColumn,
            tabSize: tabSize
        )
        let current = Array(state.units[cell.range])
        if style == .aligned, preventExpand {
            let currentWidth = MarkdownTable.displayWidth(
                units: current,
                startColumn: cell.startColumn,
                tabSize: tabSize
            )
            if currentWidth < maxWidth { return }
        }
        let expectedWithoutCarets = expected.filter { $0 != MarkdownTableCellContent.caretMarker }
        guard current != expectedWithoutCarets else { return }
        var positions: [Int] = []
        var markers = 0
        for (index, unit) in expected.enumerated() where unit == MarkdownTableCellContent.caretMarker {
            positions.append(cell.range.lowerBound + index - markers)
            markers += 1
        }
        var moved: [Int: Int] = [:]
        if positions.count == cell.caretIndices.count {
            for (index, position) in zip(cell.caretIndices, positions) {
                moved[index] = position
            }
        }
        Self.replace(cell.range, with: expectedWithoutCarets, moved: moved, state: &state)
    }

    private func processSeparator(
        range: Range<Int>,
        alignment: MarkdownTableAlignment,
        maxWidth: Int,
        state: inout State
    ) {
        if style == .aligned, preventExpand, range.count < maxWidth { return }
        let expected = MarkdownTableCellContent.separator(alignment: alignment, width: maxWidth, style: style)
        Self.replace(range, with: expected, moved: [:], state: &state)
    }

    private static func replace(
        _ range: Range<Int>,
        with replacement: [UInt16],
        moved: [Int: Int],
        state: inout State
    ) {
        let old = Array(state.units[range])
        guard old != replacement else { return }
        let common = min(old.count, replacement.count)
        var prefix = 0
        while prefix < common, old[prefix] == replacement[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < common - prefix, old[old.count - 1 - suffix] == replacement[replacement.count - 1 - suffix] {
            suffix += 1
        }
        let changedStart = range.lowerBound + prefix
        let oldChangedEnd = range.upperBound - suffix
        let newLength = replacement.count - prefix - suffix
        let delta = replacement.count - old.count
        state.units.replaceSubrange(range, with: replacement)
        for index in state.tracked.indices {
            if let position = moved[index] {
                state.tracked[index] = position
                continue
            }
            let offset = state.tracked[index]
            if offset <= changedStart {
                continue
            } else if offset >= oldChangedEnd {
                state.tracked[index] = offset + delta
            } else {
                state.tracked[index] = changedStart + min(offset - changedStart, newLength)
            }
        }
    }

    private static func trimmed(_ content: [UInt16]) -> [UInt16] {
        var lower = 0
        var upper = content.count
        while lower < upper, MarkdownText.isSpaceOrTab(content[lower]) { lower += 1 }
        while upper > lower, MarkdownText.isSpaceOrTab(content[upper - 1]) { upper -= 1 }
        return Array(content[lower..<upper])
    }
}
