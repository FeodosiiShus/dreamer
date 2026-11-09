import Foundation
import LanguageServerProtocol

nonisolated enum LSPCodeActionMapping {
    static func groups(from response: CodeActionResponse, diagnostics: [Diagnostic]) -> [IntentionGroup] {
        guard let response else { return [] }
        var order: [String] = []
        var buckets: [String: (category: IntentionCategory, title: String, actions: [IntentionAction])] = [:]

        for (index, item) in response.enumerated() {
            guard let action = intention(from: item, index: index, diagnostics: diagnostics) else { continue }
            let title = groupTitle(for: action, diagnostics: diagnostics)
            let key = "\(action.category.rawValue):\(title)"
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = (action.category, title, [])
            }
            buckets[key]?.actions.append(action)
        }

        let groups = order.compactMap { key -> IntentionGroup? in
            guard let bucket = buckets[key] else { return nil }
            return IntentionGroup(
                id: key,
                category: bucket.category,
                title: bucket.title,
                actions: preferredFirst(bucket.actions)
            )
        }
        return groups.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.category != rhs.element.category {
                    return lhs.element.category < rhs.element.category
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    static func category(forKind kind: CodeActionKind?, hasDiagnostics: Bool) -> IntentionCategory {
        guard let kind, !kind.isEmpty else {
            return hasDiagnostics ? .quickFix : .refactoring
        }
        if isKind(kind, under: CodeActionKind.Quickfix) {
            return .quickFix
        }
        if isKind(kind, under: CodeActionKind.Source) {
            return .source
        }
        if isKind(kind, under: CodeActionKind.Refactor) {
            return .refactoring
        }
        return hasDiagnostics ? .quickFix : .refactoring
    }

    private static func isKind(_ kind: CodeActionKind, under base: CodeActionKind) -> Bool {
        kind == base || kind.hasPrefix(base + ".")
    }

    private static func intention(
        from item: TwoTypeOption<LSPCommand, CodeAction>,
        index: Int,
        diagnostics: [Diagnostic]
    ) -> IntentionAction? {
        switch item {
        case .optionA(let command):
            let category = category(forKind: nil, hasDiagnostics: !diagnostics.isEmpty)
            return IntentionAction(
                id: identifier(category: category, index: index, title: command.title),
                title: command.title,
                category: category,
                isPreferred: false,
                payload: .command(command)
            )
        case .optionB(let action):
            guard action.disabled == nil else { return nil }
            let hasDiagnostics = !(action.diagnostics ?? diagnostics).isEmpty
            let category = category(forKind: action.kind, hasDiagnostics: hasDiagnostics)
            return IntentionAction(
                id: identifier(category: category, index: index, title: action.title),
                title: action.title,
                category: category,
                isPreferred: action.isPreferred ?? false,
                payload: .codeAction(action)
            )
        }
    }

    private static func identifier(category: IntentionCategory, index: Int, title: String) -> String {
        "\(category.rawValue).\(index).\(title)"
    }

    private static func groupTitle(for action: IntentionAction, diagnostics: [Diagnostic]) -> String {
        guard action.category == .quickFix else { return action.category.title }
        if case .codeAction(let codeAction) = action.payload,
           let message = codeAction.diagnostics?.first?.message {
            return message
        }
        if diagnostics.count == 1, let message = diagnostics.first?.message {
            return message
        }
        return action.category.title
    }

    private static func preferredFirst(_ actions: [IntentionAction]) -> [IntentionAction] {
        actions.filter(\.isPreferred) + actions.filter { !$0.isPreferred }
    }
}

nonisolated enum LSPCodeActionDiagnostics {
    static func diagnostics(
        in diagnostics: [WorkspaceDiagnostic],
        intersecting range: LSPRange
    ) -> [Diagnostic] {
        diagnostics.compactMap { diagnostic in
            let diagnosticRange = self.range(of: diagnostic)
            guard touches(diagnosticRange, range) else { return nil }
            return lspDiagnostic(from: diagnostic)
        }
    }

    static func diagnostics(in diagnostics: [WorkspaceDiagnostic], onLine line: Int) -> [Diagnostic] {
        diagnostics.compactMap { diagnostic in
            guard diagnostic.startLine <= line, diagnostic.endLine >= line else { return nil }
            return lspDiagnostic(from: diagnostic)
        }
    }

    static func range(covering diagnostics: [Diagnostic]) -> LSPRange? {
        guard let first = diagnostics.first else { return nil }
        return diagnostics.dropFirst().reduce(first.range) { partial, diagnostic in
            LSPRange(
                start: min(partial.start, diagnostic.range.start),
                end: max(partial.end, diagnostic.range.end)
            )
        }
    }

    static func lspDiagnostic(from diagnostic: WorkspaceDiagnostic) -> Diagnostic {
        Diagnostic(
            range: range(of: diagnostic),
            severity: DiagnosticSeverity(rawValue: diagnostic.severity.rawValue),
            code: diagnostic.code.map(diagnosticCode(from:)),
            source: diagnostic.source,
            message: diagnostic.message
        )
    }

    private static func range(of diagnostic: WorkspaceDiagnostic) -> LSPRange {
        LSPRange(
            start: Position(line: diagnostic.startLine, character: diagnostic.startColumn),
            end: Position(line: diagnostic.endLine, character: diagnostic.endColumn)
        )
    }

    private static func diagnosticCode(from code: String) -> DiagnosticCode {
        if let number = Int(code) {
            return DiagnosticCode.optionA(number)
        }
        return DiagnosticCode.optionB(code)
    }

    private static func touches(_ lhs: LSPRange, _ rhs: LSPRange) -> Bool {
        lhs.start <= rhs.end && rhs.start <= lhs.end
    }
}
