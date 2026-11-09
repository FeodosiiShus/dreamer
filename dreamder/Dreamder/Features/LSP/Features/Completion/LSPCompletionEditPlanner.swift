import Foundation
import LanguageServerProtocol

nonisolated struct LSPCompletionRequestContext: Sendable, Equatable {
    let position: Position
}

nonisolated struct LSPCompletionEdit: Sendable, Equatable {
    let range: NSRange
    let text: String
}

nonisolated struct LSPCompletionEditPlan: Sendable, Equatable {
    let edits: [LSPCompletionEdit]
    let template: SnippetTemplate?
    let mainStart: Int
    let mainLength: Int

    var caret: Int {
        mainStart + mainLength
    }
}

nonisolated enum LSPCompletionEditPlanner {
    static func plan(
        item: CompletionItem,
        context: LSPCompletionRequestContext,
        current: Position,
        fallbackRange: NSRange,
        variables: SnippetVariableContext,
        allowsSnippet: Bool,
        offsetOf: (Position) -> Int?
    ) -> LSPCompletionEditPlan? {
        let rawRange: LSPRange?
        let rawText: String
        switch item.textEdit {
        case .some(.optionA(let edit)):
            rawRange = edit.range
            rawText = edit.newText
        case .some(.optionB(let edit)):
            rawRange = edit.insert
            rawText = edit.newText
        case .none:
            rawRange = nil
            rawText = item.insertText ?? item.label
        }
        var mainRange = fallbackRange
        if let rawRange {
            let start = adjusted(rawRange.start, isEnd: false, context: context, current: current)
            let end = adjusted(rawRange.end, isEnd: true, context: context, current: current)
            guard let resolved = nsRange(from: start, to: end, offsetOf: offsetOf) else { return nil }
            mainRange = resolved
        }
        let normalized = normalizedLineSeparators(rawText)
        var template: SnippetTemplate?
        var mainText = normalized
        if item.insertTextFormat == .snippet {
            let parsed = SnippetTemplate(parsing: normalized, variables: variables)
            mainText = parsed.text
            template = allowsSnippet ? parsed : nil
        }
        var entries: [(edit: LSPCompletionEdit, sequence: Int)] = []
        for (sequence, additional) in (item.additionalTextEdits ?? []).enumerated() {
            let start = adjusted(additional.range.start, isEnd: false, context: context, current: current)
            let end = adjusted(additional.range.end, isEnd: false, context: context, current: current)
            guard let resolved = nsRange(from: start, to: end, offsetOf: offsetOf),
                  !overlaps(resolved, mainRange) else { continue }
            entries.append(
                (LSPCompletionEdit(range: resolved, text: normalizedLineSeparators(additional.newText)), sequence)
            )
        }
        let mainSequence = item.additionalTextEdits?.count ?? 0
        let shiftBeforeMain = entries
            .filter { NSMaxRange($0.edit.range) <= mainRange.location }
            .reduce(0) { $0 + $1.edit.text.utf16.count - $1.edit.range.length }
        entries.append((LSPCompletionEdit(range: mainRange, text: mainText), mainSequence))
        let ordered = entries.sorted {
            if $0.edit.range.location != $1.edit.range.location {
                return $0.edit.range.location > $1.edit.range.location
            }
            if $0.edit.range.length != $1.edit.range.length {
                return $0.edit.range.length > $1.edit.range.length
            }
            return $0.sequence > $1.sequence
        }
        return LSPCompletionEditPlan(
            edits: ordered.map(\.edit),
            template: template,
            mainStart: mainRange.location + shiftBeforeMain,
            mainLength: mainText.utf16.count
        )
    }

    static func adjusted(
        _ position: Position,
        isEnd: Bool,
        context: LSPCompletionRequestContext,
        current: Position
    ) -> Position {
        guard current.line == context.position.line, position.line == context.position.line else { return position }
        let requested = context.position.character
        guard position.character > requested || (isEnd && position.character == requested) else { return position }
        return Position(line: position.line, character: position.character + current.character - requested)
    }

    private static func nsRange(from start: Position, to end: Position, offsetOf: (Position) -> Int?) -> NSRange? {
        guard let lower = offsetOf(start), let upper = offsetOf(end), upper >= lower else { return nil }
        return NSRange(location: lower, length: upper - lower)
    }

    private static func overlaps(_ lhs: NSRange, _ rhs: NSRange) -> Bool {
        lhs.location < NSMaxRange(rhs) && rhs.location < NSMaxRange(lhs)
    }

    private static func normalizedLineSeparators(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }
}
