import Foundation
import LanguageServerProtocol

nonisolated struct InlayHintSettings: Codable, Hashable, Sendable {
    enum ParameterNameHints: String, Codable, Hashable, Sendable, CaseIterable {
        case none
        case literals
        case all
    }

    var enabled: Bool = true
    var parameterNames: ParameterNameHints = .literals
    var types: Bool = true
    var returnTypes: Bool = true

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = container.lenient(.enabled, default: true)
        parameterNames = container.lenient(.parameterNames, default: .literals)
        types = container.lenient(.types, default: true)
        returnTypes = container.lenient(.returnTypes, default: true)
    }

    func shows(kind: InlayHintKind?, followsClosingParenthesis: Bool) -> Bool {
        guard enabled else { return false }
        switch kind {
        case .parameter:
            return parameterNames != .none
        case .type:
            return followsClosingParenthesis ? returnTypes : types
        case nil:
            return true
        }
    }
}

nonisolated enum InlayHintServerPreferences {
    static func preferences(for settings: InlayHintSettings) -> LSPAny {
        let parameterNames = settings.enabled ? settings.parameterNames : .none
        let types = settings.enabled && settings.types
        let returnTypes = settings.enabled && settings.returnTypes
        return .hash([
            "includeInlayParameterNameHints": .string(parameterNames.rawValue),
            "includeInlayVariableTypeHints": .bool(types),
            "includeInlayPropertyDeclarationTypeHints": .bool(types),
            "includeInlayFunctionLikeReturnTypeHints": .bool(returnTypes)
        ])
    }

    static func initializationOptions(for settings: InlayHintSettings) -> LSPAny {
        .hash(["preferences": preferences(for: settings)])
    }

    static func configurationSettings(for settings: InlayHintSettings) -> LSPAny {
        let section = LSPAny.hash(["inlayHints": preferences(for: settings)])
        return .hash(["typescript": section, "javascript": section])
    }
}
