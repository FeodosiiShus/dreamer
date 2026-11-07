import Foundation

nonisolated enum MarkdownHeaderLevel {
    private static let maxLevel = 6

    private enum Mode: Sendable {
        case set(Int)
        case up
        case down
    }

    private enum Target: Hashable, Sendable {
        case header(block: Int)
        case paragraph(line: Int)
        case rawLine(line: Int)
    }

    private struct Edit: Sendable {
        let range: Range<Int>
        let text: String
    }

    private struct Plan: Sendable {
        var prefix: [Edit] = []
        var suffix: [Edit] = []
        var settlesAfterSuffix = false
    }

    static func set(level: Int, text: String, selections: [NSRange]) -> MarkdownActionResult? {
        apply(.set(clamped(level)), text: text, selections: selections)
    }

    static func isSelected(level: Int, text: String, selections: [NSRange]) -> Bool {
        guard !selections.isEmpty else { return false }
        let document = MarkdownDocument(text)
        let expected = clamped(level)
        return selections.allSatisfy { selection in
            guard let headerLevel = headerLevel(document: document, selection: selection) else {
                return expected == 0
            }
            return headerLevel == expected
        }
    }

    static func headerUp(text: String, selections: [NSRange]) -> MarkdownActionResult? {
        apply(.up, text: text, selections: selections)
    }

    static func headerDown(text: String, selections: [NSRange]) -> MarkdownActionResult? {
        apply(.down, text: text, selections: selections)
    }

    static func isHeaderUpEnabled(text: String, selections: [NSRange]) -> Bool {
        guard !selections.isEmpty else { return false }
        let document = MarkdownDocument(text)
        return selections.allSatisfy { selection in
            guard case .header = resolve(document: document, selection: selection) else { return false }
            return true
        }
    }

    static func isHeaderDownEnabled(text: String, selections: [NSRange]) -> Bool {
        guard !selections.isEmpty else { return false }
        let document = MarkdownDocument(text)
        return selections.allSatisfy { selection in
            switch resolve(document: document, selection: selection) {
            case .header(let block):
                return document.blocks[block].headingLevel != maxLevel
            case .paragraph:
                return true
            case .rawLine, nil:
                return false
            }
        }
    }

    private static func clamped(_ level: Int) -> Int {
        min(max(level, 0), maxLevel)
    }

    private static func marker(_ level: Int) -> String {
        String(repeating: "#", count: level) + " "
    }

    private static func apply(_ mode: Mode, text: String, selections: [NSRange]) -> MarkdownActionResult? {
        guard !selections.isEmpty else { return nil }
        let document = MarkdownDocument(text)
        var buffer = MarkdownEditBuffer(text)
        var visited = Set<Target>()
        let ordered = selections.sorted { $0.location > $1.location }
        for selection in ordered {
            guard let target = resolve(document: document, selection: selection),
                  visited.insert(target).inserted,
                  let plan = plan(for: target, mode: mode, document: document) else {
                buffer.settleFirst(selection)
                continue
            }
            if !plan.settlesAfterSuffix {
                buffer.settleFirst(selection)
            }
            for edit in plan.suffix {
                buffer.replace(edit.range, with: edit.text)
            }
            if plan.settlesAfterSuffix {
                buffer.settleFirst(selection)
            }
            for edit in plan.prefix {
                buffer.replace(edit.range, with: edit.text)
            }
        }
        let result = buffer.resultWithSettledSelections()
        return result.edits.isEmpty ? nil : result
    }

    private static func lineSpan(document: MarkdownDocument, selection: NSRange) -> (start: Int, end: Int)? {
        let text = document.text
        let endOffset = selection.location + selection.length
        guard selection.location >= 0, selection.length >= 0, endOffset <= text.length else { return nil }
        var startLine = text.lineIndex(containing: selection.location)
        var endLine = text.lineIndex(containing: endOffset)
        if selection.length > 0 {
            if selection.location == text.lines[startLine].contentEnd, startLine + 1 < text.lines.count {
                startLine += 1
            }
            if endOffset == text.lines[endLine].start, endLine > 0 {
                endLine -= 1
            }
        }
        guard startLine <= endLine else { return nil }
        return (startLine, endLine)
    }

    private static func headerLevel(document: MarkdownDocument, selection: NSRange) -> Int? {
        guard let span = lineSpan(document: document, selection: selection),
              let startBlock = document.blockIndexByLine[span.start],
              let endBlock = document.blockIndexByLine[span.end],
              startBlock == endBlock else {
            return nil
        }
        return document.blocks[startBlock].headingLevel
    }

    private static func resolve(document: MarkdownDocument, selection: NSRange) -> Target? {
        guard let span = lineSpan(document: document, selection: selection),
              let startBlock = document.blockIndexByLine[span.start],
              let endBlock = document.blockIndexByLine[span.end],
              startBlock == endBlock else {
            return nil
        }
        let block = document.blocks[startBlock]
        switch block.kind {
        case .atxHeading, .setextHeading:
            return .header(block: startBlock)
        case .paragraph:
            if block.lines.count == 1 {
                return .paragraph(line: block.lines.lowerBound)
            }
            return span.start == span.end ? .rawLine(line: span.start) : nil
        default:
            return nil
        }
    }

    private static func plan(for target: Target, mode: Mode, document: MarkdownDocument) -> Plan? {
        switch target {
        case .header(let block):
            return headerPlan(block: block, mode: mode, document: document)
        case .paragraph(let line):
            let level: Int
            switch mode {
            case .set(let value): level = value
            case .down: level = 1
            case .up: return nil
            }
            guard level > 0 else { return nil }
            let start = document.infos[line].bodyStart
            return Plan(prefix: [Edit(range: start..<start, text: marker(level))])
        case .rawLine(let line):
            guard case .set(let level) = mode, level > 0 else { return nil }
            return rawLinePlan(line: line, level: level, document: document)
        }
    }

    private static func rawLinePlan(line: Int, level: Int, document: MarkdownDocument) -> Plan {
        let text = document.text
        let info = document.infos[line]
        let lineInfo = text.lines[line]
        var quotePrefix = ""
        if info.quoteDepth > 0 {
            var end = info.quoteEnd
            while end > lineInfo.start, MarkdownText.isSpaceOrTab(text.units[end - 1]) { end -= 1 }
            quotePrefix = text.string(lineInfo.start..<end)
        }
        var plan = Plan()
        plan.settlesAfterSuffix = true
        let next = line + 1
        if next < text.lines.count, !document.infos[next].isBlank {
            plan.suffix.append(Edit(range: lineInfo.contentEnd..<lineInfo.contentEnd, text: "\n" + quotePrefix))
        }
        plan.prefix.append(Edit(range: info.bodyStart..<info.bodyStart, text: marker(level)))
        if line > 0, !document.infos[line - 1].isBlank {
            plan.prefix.append(Edit(range: lineInfo.start..<lineInfo.start, text: quotePrefix + "\n"))
        }
        return plan
    }

    private static func headerPlan(block index: Int, mode: Mode, document: MarkdownDocument) -> Plan? {
        let block = document.blocks[index]
        guard let old = block.headingLevel else { return nil }
        let level: Int
        switch mode {
        case .set(let value): level = value
        case .up: level = clamped(old - 1)
        case .down: level = clamped(old + 1)
        }
        guard level != old else { return nil }
        switch block.kind {
        case .atxHeading:
            return atxPlan(line: block.lines.lowerBound, level: level, document: document)
        case .setextHeading:
            return setextPlan(block: block, oldLevel: old, level: level, mode: mode, document: document)
        default:
            return nil
        }
    }

    private static func atxPlan(line: Int, level: Int, document: MarkdownDocument) -> Plan? {
        guard let content = document.atxContentRange(line: line), !content.isEmpty else { return nil }
        let lineEnd = document.text.lines[line].contentEnd
        let bodyStart = document.infos[line].bodyStart
        let replacement = level == 0 ? "" : marker(level)
        var plan = Plan(prefix: [Edit(range: bodyStart..<content.lowerBound, text: replacement)])
        if content.upperBound < lineEnd {
            plan.suffix.append(Edit(range: content.upperBound..<lineEnd, text: ""))
        }
        return plan
    }

    private static func setextPlan(
        block: MarkdownBlock,
        oldLevel: Int,
        level: Int,
        mode: Mode,
        document: MarkdownDocument
    ) -> Plan? {
        let text = document.text
        let underline = block.lines.upperBound - 1
        let isStep: Bool
        switch mode {
        case .set: isStep = false
        case .up, .down: isStep = true
        }
        if isStep, level != 0, (oldLevel == 1 && level == 2) || (oldLevel == 2 && level == 1) {
            let runStart = document.infos[underline].bodyStart
            let lineEnd = text.lines[underline].contentEnd
            var runEnd = runStart
            while runEnd < lineEnd, text.units[runEnd] == text.units[runStart] { runEnd += 1 }
            let character = level == 1 ? "=" : "-"
            let run = String(repeating: character, count: runEnd - runStart)
            return Plan(suffix: [Edit(range: runStart..<runEnd, text: run)])
        }
        let lastContentLine = underline - 1
        let firstStart = document.infos[block.lines.lowerBound].bodyStart
        var contentEnd = text.lines[lastContentLine].contentEnd
        while contentEnd > document.infos[lastContentLine].bodyStart,
            MarkdownText.isSpaceOrTab(text.units[contentEnd - 1])
        {
            contentEnd -= 1
        }
        var plan = Plan(suffix: [Edit(range: contentEnd..<text.lines[underline].contentEnd, text: "")])
        if level > 0 {
            plan.prefix.append(Edit(range: firstStart..<firstStart, text: marker(level)))
        }
        return plan
    }
}
