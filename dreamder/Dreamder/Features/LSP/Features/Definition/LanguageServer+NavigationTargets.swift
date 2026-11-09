import Foundation
import LanguageServerProtocol

extension LanguageServer {
    func navigationTargets(
        for kind: LSPNavigationKind,
        uri documentURI: String,
        position: Position
    ) async -> [LSPDefinitionTarget] {
        switch kind {
        case .declaration:
            let definition = LSPDefinitionMapping.targets(
                from: try? await requestGoToDefinition(for: documentURI, position: position)
            )
            if !definition.isEmpty {
                return definition
            }
            return LSPDefinitionMapping.targets(
                from: try? await requestGoToDeclaration(for: documentURI, position: position)
            )
        case .implementation:
            return LSPDefinitionMapping.targets(
                from: try? await requestImplementation(for: documentURI, position)
            )
        case .typeDeclaration:
            return LSPDefinitionMapping.targets(
                from: try? await requestTypeDefinition(for: documentURI, position)
            )
        }
    }
}
