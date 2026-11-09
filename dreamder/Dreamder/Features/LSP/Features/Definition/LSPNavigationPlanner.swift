import Foundation
import LanguageServerProtocol

nonisolated enum LSPNavigationKind: Equatable, Sendable {
    case declaration
    case implementation
    case typeDeclaration

    var commandName: String {
        switch self {
        case .declaration: "Go to Declaration"
        case .implementation: "Go to Implementation"
        case .typeDeclaration: "Go to Type Declaration"
        }
    }

    var chooserTitle: String {
        switch self {
        case .declaration: "Choose Declaration"
        case .implementation: "Choose Implementation"
        case .typeDeclaration: "Choose Type Declaration"
        }
    }

    var emptyMessage: String? {
        switch self {
        case .declaration: nil
        case .implementation: "No implementations found"
        case .typeDeclaration: "No type declaration found"
        }
    }

    var missingServerMessage: String {
        "\(commandName) needs a language server for this file"
    }
}

nonisolated struct LSPNavigationDestination: Hashable, Sendable {
    let uri: String
    let fileURL: URL
    let range: LSPRange

    var line: Int { range.start.line + 1 }
    var column: Int { range.start.character + 1 }
}

nonisolated struct LSPNavigationOrigin: Equatable, Sendable {
    let fileURL: URL
    let position: Position
}

nonisolated enum LSPNavigationPlan: Equatable, Sendable {
    case showUsages
    case showMessage(String)
    case jump(LSPNavigationDestination)
    case choose([LSPNavigationDestination])
}

nonisolated enum LSPNavigationPlanner {
    static func destinations(from targets: [LSPDefinitionTarget]) -> [LSPNavigationDestination] {
        var seen: Set<LSPNavigationDestination> = []
        var result: [LSPNavigationDestination] = []
        for target in targets {
            guard let fileURL = LSPDiagnosticMapping.fileURL(fromDocumentURI: target.uri) else { continue }
            let destination = LSPNavigationDestination(
                uri: target.uri,
                fileURL: fileURL,
                range: target.selectionRange
            )
            if seen.insert(destination).inserted {
                result.append(destination)
            }
        }
        return result
    }

    static func selfDestination(
        in destinations: [LSPNavigationDestination],
        origin: LSPNavigationOrigin
    ) -> LSPNavigationDestination? {
        let originFile = origin.fileURL.standardizedFileURL
        return destinations.first { destination in
            destination.fileURL == originFile
                && destination.range.start <= origin.position
                && origin.position <= destination.range.end
        }
    }

    static func plan(
        kind: LSPNavigationKind,
        targets: [LSPDefinitionTarget],
        origin: LSPNavigationOrigin
    ) -> LSPNavigationPlan {
        let candidates = destinations(from: targets)
        guard let first = candidates.first else {
            if let message = kind.emptyMessage {
                return .showMessage(message)
            }
            return .showUsages
        }
        if kind == .declaration, selfDestination(in: candidates, origin: origin) != nil {
            return .showUsages
        }
        if candidates.count == 1 {
            return .jump(first)
        }
        return .choose(candidates)
    }

    static func locations(for destinations: [LSPNavigationDestination]) -> [LSPReferenceLocation] {
        destinations.map { destination in
            let sameLine = destination.range.end.line == destination.range.start.line
            return LSPReferenceLocation(
                uri: destination.uri,
                line: destination.range.start.line,
                startCharacter: destination.range.start.character,
                endCharacter: sameLine ? destination.range.end.character : destination.range.start.character
            )
        }
    }
}
