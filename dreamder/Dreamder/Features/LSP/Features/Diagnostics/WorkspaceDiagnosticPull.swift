import Foundation
import JSONRPC
import LanguageServerProtocol

nonisolated struct WorkspaceDiagnosticParams: Codable, Equatable, Sendable {
    nonisolated struct PreviousResultId: Codable, Equatable, Sendable {
        let uri: String
        let value: String
    }

    var identifier: String?
    var previousResultIds: [PreviousResultId]

    func lspAny() throws -> LSPAny {
        try JSONDecoder().decode(LSPAny.self, from: JSONEncoder().encode(self))
    }
}

nonisolated struct WorkspaceDocumentDiagnosticReport: Codable, Equatable, Sendable {
    nonisolated enum Kind: String, Codable, Sendable {
        case full
        case unchanged
    }

    let kind: Kind
    let uri: String
    let version: Int?
    let resultId: String?
    let items: [Diagnostic]?
}

nonisolated struct WorkspaceDiagnosticReport: Codable, Equatable, Sendable {
    let items: [WorkspaceDocumentDiagnosticReport]

    static func decode(_ value: LSPAny) throws -> WorkspaceDiagnosticReport {
        try JSONDecoder().decode(WorkspaceDiagnosticReport.self, from: JSONEncoder().encode(value))
    }
}

nonisolated struct WorkspaceDiagnosticPublication: Equatable, Sendable {
    let uri: String
    let diagnostics: [Diagnostic]
}

nonisolated struct WorkspaceDiagnosticsPullState: Sendable {
    private(set) var resultIds: [String: String] = [:]

    func params(identifier: String?) -> WorkspaceDiagnosticParams {
        WorkspaceDiagnosticParams(
            identifier: identifier,
            previousResultIds: resultIds.keys.sorted().compactMap { uri in
                resultIds[uri].map { WorkspaceDiagnosticParams.PreviousResultId(uri: uri, value: $0) }
            }
        )
    }

    mutating func apply(_ report: WorkspaceDiagnosticReport) -> [WorkspaceDiagnosticPublication] {
        var publications: [WorkspaceDiagnosticPublication] = []
        for item in report.items {
            switch item.kind {
            case .full:
                resultIds[item.uri] = item.resultId
                publications.append(WorkspaceDiagnosticPublication(uri: item.uri, diagnostics: item.items ?? []))
            case .unchanged:
                if let resultId = item.resultId {
                    resultIds[item.uri] = resultId
                }
            }
        }
        return publications
    }

    mutating func reset() {
        resultIds.removeAll()
    }
}

nonisolated struct WorkspaceDiagnosticsSupport: Equatable, Sendable {
    static let registrationMethod = "textDocument/diagnostic"
    static let requestMethod = "workspace/diagnostic"

    let identifier: String?

    static func resolve(
        static option: TwoTypeOption<DiagnosticOptions, DiagnosticRegistrationOptions>?,
        dynamic registrations: [DiagnosticRegistrationOptions]
    ) -> WorkspaceDiagnosticsSupport? {
        switch option {
        case .some(.optionA(let options)) where options.workspaceDiagnostics:
            return WorkspaceDiagnosticsSupport(identifier: options.identifier)
        case .some(.optionB(let options)) where options.workspaceDiagnostics:
            return WorkspaceDiagnosticsSupport(identifier: options.identifier)
        default:
            break
        }
        return registrations.first(where: \.workspaceDiagnostics).map {
            WorkspaceDiagnosticsSupport(identifier: $0.identifier)
        }
    }
}
