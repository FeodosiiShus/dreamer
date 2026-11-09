import Foundation
import JSONRPC
import LanguageServerProtocol

nonisolated struct RenameTarget: Equatable, Sendable {
    let name: String
    let range: LSPRange?
}

nonisolated enum RenameTargetResolution: Equatable, Sendable {
    case target(RenameTarget)
    case notRenameable
}

nonisolated struct RenameRequest: Equatable, Sendable {
    let documentURI: String
    let position: Position
    let documentText: String
    let symbol: String
}

nonisolated enum RenameTargetMapping {
    static func resolve(
        _ response: PrepareRenameResponse,
        documentText: String,
        symbol: String
    ) -> RenameTargetResolution {
        switch response {
        case .none:
            return .notRenameable
        case .some(.optionA(let range)):
            return target(candidates: [text(in: range, of: documentText), symbol], range: range)
        case .some(.optionB(let withPlaceholder)):
            return target(
                candidates: [withPlaceholder.placeholder, text(in: withPlaceholder.range, of: documentText), symbol],
                range: withPlaceholder.range
            )
        case .some(.optionC(let behavior)):
            return behavior.defaultBehavior ? fallback(symbol: symbol) : .notRenameable
        }
    }

    static func fallback(symbol: String) -> RenameTargetResolution {
        target(candidates: [symbol], range: nil)
    }

    private static func target(candidates: [String], range: LSPRange?) -> RenameTargetResolution {
        guard let name = candidates.first(where: { !$0.isEmpty }) else { return .notRenameable }
        return .target(RenameTarget(name: name, range: range))
    }

    private static func text(in range: LSPRange, of documentText: String) -> String {
        let probe = TextEdit(range: range, newText: "")
        guard let resolved = try? LSPTextEditApplier.resolve([probe], in: documentText).first else { return "" }
        return (documentText as NSString).substring(with: resolved.range)
    }
}

nonisolated enum RenameNameValidation: Equatable, Sendable {
    case valid
    case unchanged
    case empty
    case invalidIdentifier(String)

    var isConfirmable: Bool {
        self == .valid
    }

    var errorMessage: String? {
        switch self {
        case .valid, .unchanged:
            return nil
        case .empty:
            return RenameMessages.emptyName
        case .invalidIdentifier(let name):
            return RenameMessages.invalidIdentifier(name)
        }
    }
}

nonisolated enum RenameNameValidator {
    static func normalized(_ input: String) -> String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func validate(_ input: String, currentName: String) -> RenameNameValidation {
        let name = normalized(input)
        if name.isEmpty {
            return .empty
        }
        if name.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) }) {
            return .invalidIdentifier(name)
        }
        return name == currentName ? .unchanged : .valid
    }
}

nonisolated enum RenameMessages {
    static let notRenameable = "Cannot rename this element"
    static let nothingToRename = "Nothing to rename"
    static let missingServer = "Rename needs a language server for this file"
    static let emptyName = "The name must not be empty"
    static let unknownFailure = "The edit could not be applied"
    static let confirmHint = "Enter to rename, Esc to cancel"

    static func prompt(for name: String) -> String {
        "Rename \(name) and its usages to:"
    }

    static func invalidIdentifier(_ name: String) -> String {
        "'\(name)' is not a valid identifier"
    }

    static func failure(reason: String?) -> String {
        "Cannot rename: \(reason ?? unknownFailure)"
    }

    static func failure(error: any Error) -> String {
        if let rpcError = error as? AnyJSONRPCResponseError {
            return failure(reason: rpcError.message)
        }
        return failure(reason: error.localizedDescription)
    }
}
