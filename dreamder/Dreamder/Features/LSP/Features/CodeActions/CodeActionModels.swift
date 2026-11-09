import Foundation
import LanguageServerProtocol

typealias LSPCommand = LanguageServerProtocol.Command

nonisolated enum IntentionCategory: Int, Comparable, CaseIterable, Sendable {
    case quickFix
    case refactoring
    case source

    static func < (lhs: IntentionCategory, rhs: IntentionCategory) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var title: String {
        switch self {
        case .quickFix: "Quick Fixes"
        case .refactoring: "Refactorings"
        case .source: "Source Actions"
        }
    }
}

nonisolated struct IntentionAction: Identifiable, Equatable, Sendable {
    enum Payload: Equatable, Sendable {
        case codeAction(CodeAction)
        case command(LSPCommand)
    }

    let id: String
    let title: String
    let category: IntentionCategory
    let isPreferred: Bool
    let payload: Payload
}

nonisolated struct IntentionGroup: Identifiable, Equatable, Sendable {
    let id: String
    let category: IntentionCategory
    let title: String
    let actions: [IntentionAction]
}

nonisolated extension [IntentionGroup] {
    var hasQuickFixes: Bool {
        contains { $0.category == .quickFix && !$0.actions.isEmpty }
    }

    var allActions: [IntentionAction] {
        flatMap(\.actions)
    }
}
