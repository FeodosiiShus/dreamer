import Foundation

nonisolated enum MarkdownListNumberingType: Equatable, Sendable, CaseIterable {
    case sequential
    case ones
    case previousNumber
}

nonisolated struct MarkdownTypingSettings: Equatable, Sendable {
    var smartEnterAndBackspace = true
    var adjustListIndentation = true
    var renumberListsOnType = false
    var listNumberingType: MarkdownListNumberingType = .sequential
    var tabWidth = 4

    init(
        smartEnterAndBackspace: Bool = true,
        adjustListIndentation: Bool = true,
        renumberListsOnType: Bool = false,
        listNumberingType: MarkdownListNumberingType = .sequential,
        tabWidth: Int = 4
    ) {
        self.smartEnterAndBackspace = smartEnterAndBackspace
        self.adjustListIndentation = adjustListIndentation
        self.renumberListsOnType = renumberListsOnType
        self.listNumberingType = listNumberingType
        self.tabWidth = tabWidth
    }
}

nonisolated enum MarkdownListEnter {
    static func edit(
        forEnterIn text: String,
        caret: Int,
        shift: Bool = false,
        settings: MarkdownTypingSettings = MarkdownTypingSettings()
    ) -> MarkdownTypingEdit? {
        edit(forEnterIn: Array(text.utf16), caret: caret, shift: shift, settings: settings)
    }

    static func edit(
        forEnterIn units: [UInt16],
        caret: Int,
        shift: Bool = false,
        settings: MarkdownTypingSettings = MarkdownTypingSettings()
    ) -> MarkdownTypingEdit? {
        guard caret >= 0, caret <= units.count else { return nil }
        let context = Context(units: units, caret: caret, settings: settings)
        let result = shift ? shiftEnter(context) : enter(context)
        return result.map { MarkdownTypingEdit.between(units, and: $0) }
    }

    static func edit(
        forBackspaceIn text: String,
        caret: Int,
        settings: MarkdownTypingSettings = MarkdownTypingSettings()
    ) -> MarkdownTypingEdit? {
        edit(forBackspaceIn: Array(text.utf16), caret: caret, settings: settings)
    }

    static func edit(
        forBackspaceIn units: [UInt16],
        caret: Int,
        settings: MarkdownTypingSettings = MarkdownTypingSettings()
    ) -> MarkdownTypingEdit? {
        guard caret > 0, caret <= units.count else { return nil }
        let context = Context(units: units, caret: caret, settings: settings)
        return backspace(context).map { MarkdownTypingEdit.between(units, and: $0) }
    }

    private nonisolated struct Context {
        let units: [UInt16]
        let caret: Int
        let settings: MarkdownTypingSettings
        let structure: MarkdownListStructure
        let line: Int

        init(units: [UInt16], caret: Int, settings: MarkdownTypingSettings) {
            self.units = units
            self.caret = caret
            self.settings = settings
            structure = MarkdownListStructure(text: MarkdownTextLines(units: units), tabWidth: settings.tabWidth)
            line = structure.text.lineIndex(containing: caret)
        }

        var text: MarkdownTextLines {
            structure.text
        }

        var lineStart: Int {
            text.lines[line].start
        }

        var lineEnd: Int {
            text.lines[line].contentEnd
        }

        var eol: [UInt16] {
            Array(text.lineEnding.utf16)
        }

        var state: MarkdownTextState {
            MarkdownTextState(units: units, caret: caret)
        }
    }

    private nonisolated enum ListOutcome {
        case edit(MarkdownTextState)
        case passThrough
    }

    private static func enter(_ context: Context) -> MarkdownTextState? {
        if context.settings.smartEnterAndBackspace, let state = inlineFenceEnter(context) {
            return state
        }
        if let fence = context.structure.fence(containingCaret: context.caret) {
            return fenceEnter(context, fence: fence)
        }
        if context.settings.smartEnterAndBackspace {
            switch listEnter(context) {
            case .edit(let state): return state
            case .passThrough: break
            }
        }
        return quoteEnter(context)
    }

    private static func inlineFenceEnter(_ context: Context) -> MarkdownTextState? {
        guard context.caret > 0 else { return nil }
        let before = trimmedStart(context.units[context.lineStart..<context.caret])
        let after = trimmedStart(context.units[context.caret..<context.lineEnd])
        let fence: [UInt16] = [96, 96, 96]
        guard before.starts(with: fence), after.starts(with: fence) else { return nil }
        let indent = Array(context.units[context.lineStart..<context.caret].prefix { $0 == 32 || $0 == 9 })
        let insertion = context.eol + indent + context.eol + indent
        var state = context.state
        state.units.insert(contentsOf: insertion, at: context.caret)
        state.caret = context.caret + context.eol.count + indent.count
        return state
    }

    private static func fenceEnter(_ context: Context, fence: MarkdownListStructure.Fence) -> MarkdownTextState? {
        guard !fence.indent.isEmpty else { return nil }
        let run = Array(context.units[context.lineStart..<context.text.indentRunEnd(context.line)])
        let indent = run.starts(with: fence.indent) ? run : fence.indent
        return splitLine(context, caret: context.caret, prefix: indent)
    }

    private static func quoteEnter(_ context: Context) -> MarkdownTextState? {
        guard let prefix = quoteContinuation(context) else { return nil }
        return splitLine(context, caret: context.caret, prefix: prefix)
    }

    private static func quoteContinuation(_ context: Context) -> [UInt16]? {
        let text = context.text
        let structure = context.structure
        let lineStart = context.lineStart
        let runEnd = text.indentRunEnd(context.line)
        var lastQuote = (lineStart..<runEnd).last { context.units[$0] == 62 }
        var replaceUntil = lineStart
        if let item = structure.itemAtLine[context.line], structure.items[item].line == context.line {
            let tokenEnd = lineStart + structure.items[item].prefix.markerTokenEnd
            var cursor = tokenEnd
            while cursor < context.lineEnd, MarkdownTextLines.isIndentUnit(context.units[cursor]) {
                cursor += 1
            }
            if let inContent = (tokenEnd..<cursor).last(where: { context.units[$0] == 62 }) {
                lastQuote = inContent
                replaceUntil = tokenEnd
            }
        }
        guard let quoteEnd = lastQuote, context.caret > quoteEnd else { return nil }
        var prefix: [UInt16] = []
        for index in lineStart...quoteEnd {
            let unit = context.units[index]
            prefix.append(index < replaceUntil && !MarkdownTextLines.isIndentUnit(unit) ? 32 : unit)
        }
        prefix.append(32)
        return prefix
    }

    private static func splitLine(_ context: Context, caret: Int, prefix: [UInt16]) -> MarkdownTextState {
        var state = context.state
        let after = trimmedStart(context.units[caret...])
        state.units = Array(context.units[..<caret]) + context.eol + prefix + after
        state.caret = caret + context.eol.count + prefix.count
        return state
    }

    private static func trimmedStart(_ units: ArraySlice<UInt16>) -> [UInt16] {
        Array(units.drop { $0 == 32 || $0 == 9 })
    }

    private static func listEnter(_ context: Context) -> ListOutcome {
        let structure = context.structure
        let text = context.text
        let line = context.line

        if line > 0 {
            let runEnd = text.indentRunEnd(line)
            let insideIndent = runEnd > context.lineStart && context.caret <= runEnd
            if insideIndent, text.isBlank(line - 1) {
                return .passThrough
            }
        }

        guard let index = structure.itemAtLine[line] else { return .passThrough }
        let item = structure.items[index]

        if structure.isEmpty(item: index) {
            return emptyItemEnter(context, item: index).map { ListOutcome.edit($0) } ?? ListOutcome.passThrough
        }

        if isAtHardLineBreak(context) {
            return .passThrough
        }
        if structure.quoteInsideItem(index, line: line, caret: context.caret) {
            return .passThrough
        }

        let itemStart = structure.lineStart(item.line)
        let markerStart = itemStart + item.prefix.indentLength
        if context.caret <= markerStart {
            return .passThrough
        }

        var caret = context.caret
        let prefixEnd = itemStart + item.prefix.prefixEnd
        if caret < prefixEnd {
            caret = prefixEnd
        }

        let indent = structure.text.expandedIndent(item.line, tabWidth: context.settings.tabWidth)
        let checkbox: [UInt16] = item.prefix.checkbox != nil ? Array("[ ] ".utf16) : []
        let newPrefix = indent + Array(item.prefix.normalizedMarkerText.utf16) + checkbox

        var state = splitLine(context, caret: caret, prefix: newPrefix)
        let newLine = structure.text.lineIndex(containing: caret) + 1
        applyNumbering(&state, newLine: newLine, settings: context.settings)
        return .edit(state)
    }

    private static func isAtHardLineBreak(_ context: Context) -> Bool {
        let caret = context.caret
        return caret == context.lineEnd && caret - 2 >= context.lineStart
            && context.units[caret - 1] == 32 && context.units[caret - 2] == 32
    }

    private static func applyNumbering(_ state: inout MarkdownTextState, newLine: Int, settings: MarkdownTypingSettings) {
        let structure = MarkdownListStructure(text: MarkdownTextLines(units: state.units), tabWidth: settings.tabWidth)
        guard newLine < structure.text.count,
              let newItem = structure.itemAtLine[newLine],
              structure.items[newItem].line == newLine else { return }
        let item = structure.items[newItem]

        if settings.renumberListsOnType, settings.listNumberingType != .previousNumber {
            let replacements = MarkdownListRenumber.replacements(
                in: structure,
                list: item.list,
                recursive: false,
                restart: false,
                sequentially: settings.listNumberingType == .sequential
            )
            state.apply(replacements)
            return
        }

        let siblings = structure.lists[item.list].items
        guard let position = siblings.firstIndex(of: newItem), position > 0,
              let previousNumber = structure.items[siblings[position - 1]].prefix.number,
              case .ordered(_, let delimiter) = item.prefix.marker else { return }
        let number: Int = switch settings.listNumberingType {
        case .sequential: previousNumber + 1
        case .ones: 1
        case .previousNumber: previousNumber
        }
        let lineStart = structure.lineStart(newLine)
        state.apply([MarkdownReplacement(
            start: lineStart + item.prefix.indentLength,
            end: lineStart + item.prefix.markerTokenEnd,
            text: "\(number)\(delimiter) "
        )])
    }

    private static func emptyItemEnter(_ context: Context, item index: Int) -> MarkdownTextState? {
        let structure = context.structure
        let item = structure.items[index]
        if item.parent == nil {
            let itemStart = structure.lineStart(item.line)
            return deleteMarker(
                context,
                item: index,
                range: (itemStart + item.prefix.indentLength)..<(itemStart + item.prefix.contentStart)
            )
        }
        guard context.settings.adjustListIndentation,
              let replacements = structure.unindentReplacements(of: index) else { return nil }
        var state = context.state
        state.apply(replacements)
        if context.settings.renumberListsOnType {
            renumberAfterUnindent(&state, line: item.line, settings: context.settings)
        }
        return state
    }

    private static func renumberAfterUnindent(_ state: inout MarkdownTextState, line: Int, settings: MarkdownTypingSettings) {
        let first = MarkdownListStructure(text: MarkdownTextLines(units: state.units), tabWidth: settings.tabWidth)
        guard line < first.text.count, let item = first.itemAtLine[line] else { return }
        state.apply(MarkdownListRenumber.replacements(
            in: first,
            list: first.items[item].list,
            recursive: false,
            restart: false,
            sequentially: true
        ))
        let second = MarkdownListStructure(text: MarkdownTextLines(units: state.units), tabWidth: settings.tabWidth)
        guard line < second.text.count, let updated = second.itemAtLine[line],
              let sublist = second.sublists(of: updated).first else { return }
        state.apply(MarkdownListRenumber.replacements(
            in: second,
            list: sublist,
            recursive: false,
            restart: true,
            sequentially: true
        ))
    }

    private static func deleteMarker(_ context: Context, item index: Int, range: Range<Int>) -> MarkdownTextState {
        let structure = context.structure
        let item = structure.items[index]
        let splitsList = listWillBeSplit(structure, item: index)
        let nextItemLine = structure.descendantItems(after: index, inList: item.list).first.map { structure.items[$0].line }

        var state = context.state
        state.units.removeSubrange(range)
        state.caret = range.lowerBound

        if let nextItemLine, !splitsList, context.settings.renumberListsOnType {
            let updated = MarkdownListStructure(text: MarkdownTextLines(units: state.units), tabWidth: context.settings.tabWidth)
            if nextItemLine < updated.text.count, let next = updated.itemAtLine[nextItemLine] {
                state.apply(MarkdownListRenumber.replacements(
                    in: updated,
                    list: updated.items[next].list,
                    recursive: false,
                    restart: false,
                    sequentially: true
                ))
            }
        }
        return state
    }

    private static func listWillBeSplit(_ structure: MarkdownListStructure, item index: Int) -> Bool {
        let item = structure.items[index]
        let text = structure.text
        let emptyLineBefore = item.line > 0 && text.isWhitespaceOnly(item.line - 1)
        let emptyLineAfter = item.lastLine + 1 < text.count && item.line + 1 < text.count
            && text.isWhitespaceOnly(item.line + 1)
        let markerEnd = text.lines[item.line].start + item.prefix.markerTokenEnd
        var cursor = max(markerEnd - 1, text.lines[item.line].start)
        while cursor < text.lines[item.line].contentEnd, text.units[cursor] == 32 || text.units[cursor] == 9 {
            cursor += 1
        }
        let onlyMarkerLine = cursor == text.lines[item.line].contentEnd
        let outermost = structure.lists[structure.outermostList(of: index)]
        let hasPreviousItem = outermost.items.first != index
        return hasPreviousItem && (emptyLineBefore || emptyLineAfter) && onlyMarkerLine
    }

    private static func shiftEnter(_ context: Context) -> MarkdownTextState? {
        guard context.settings.smartEnterAndBackspace else { return nil }
        let structure = context.structure
        if structure.fence(coveringOffset: context.caret) != nil { return nil }
        guard let index = structure.itemAtLine[context.line], !structure.isEmpty(item: index) else { return nil }
        let item = structure.items[index]
        var contentIndent = structure.text.expandedIndent(context.line, tabWidth: context.settings.tabWidth)
        if context.line == item.line {
            contentIndent += [UInt16](repeating: 32, count: item.normalizedMarkerLength)
        }
        var state = context.state
        state.units.insert(contentsOf: context.eol + contentIndent, at: context.lineEnd)
        state.caret = context.lineEnd + context.eol.count + contentIndent.count
        return state
    }

    private static func backspace(_ context: Context) -> MarkdownTextState? {
        let structure = context.structure
        let text = context.text
        let line = context.line

        if context.settings.smartEnterAndBackspace,
           structure.fenceAtLine[line] == nil,
           let index = structure.itemAtLine[line], structure.items[index].line == line {
            let prefix = structure.items[index].prefix
            let markerStart = context.lineStart + prefix.indentLength
            let markerEnd = context.lineStart + prefix.markerTokenEnd
            let deleted = context.caret - 1
            if deleted >= markerStart, deleted < markerEnd {
                return deleteMarker(context, item: index, range: markerStart..<markerEnd)
            }
        }

        guard context.settings.adjustListIndentation, line > 0 else { return nil }
        let leading = context.units[context.lineStart..<context.caret]
        guard leading.allSatisfy({ MarkdownTextLines.isIndentUnit($0) }),
              context.units[context.caret - 1] != 62 else { return nil }
        let indentColumn = leading.reduce(0) { $0 + ($1 == 9 ? context.settings.tabWidth : 1) }
        guard indentColumn > 0 else { return nil }

        if let index = structure.itemAtLine[line], structure.items[index].line == line {
            guard let replacements = structure.unindentReplacements(of: index) else { return nil }
            var state = context.state
            state.apply(replacements)
            if context.settings.renumberListsOnType {
                renumberAfterUnindent(&state, line: line, settings: context.settings)
            }
            return state
        }

        guard var above = structure.itemAtLine[line - 1] ?? (line >= 2 ? structure.itemAtLine[line - 2] : nil) else {
            return nil
        }
        var levels: [Int] = []
        while true {
            levels.append(text.expandedIndent(structure.items[above].line, tabWidth: context.settings.tabWidth).count)
            guard let parent = structure.items[above].parent else { break }
            above = parent
        }
        guard let wanted = levels.first(where: { $0 < indentColumn }) else { return nil }
        let full = text.expandedIndent(line, tabWidth: context.settings.tabWidth)
        let replacement = Array(full[..<wanted]) + Array(full[min(indentColumn, full.count)...])
        var state = context.state
        state.units.replaceSubrange(context.lineStart..<text.indentRunEnd(line), with: replacement)
        state.caret = context.lineStart + wanted
        return state
    }
}
