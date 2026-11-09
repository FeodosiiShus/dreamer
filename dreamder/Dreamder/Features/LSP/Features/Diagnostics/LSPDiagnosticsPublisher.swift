import Foundation
import LanguageServerProtocol

nonisolated enum LSPDiagnosticMapping {
    static func workspaceDiagnostic(from diagnostic: Diagnostic, fileURL: URL) -> WorkspaceDiagnostic {
        WorkspaceDiagnostic(
            fileURL: fileURL,
            startLine: diagnostic.range.start.line,
            startColumn: diagnostic.range.start.character,
            endLine: diagnostic.range.end.line,
            endColumn: diagnostic.range.end.character,
            severity: severity(from: diagnostic.severity),
            message: diagnostic.message,
            source: diagnostic.source,
            code: code(from: diagnostic.code)
        )
    }

    static func workspaceDiagnostics(from diagnostics: [Diagnostic], fileURL: URL) -> [WorkspaceDiagnostic] {
        diagnostics.map { workspaceDiagnostic(from: $0, fileURL: fileURL) }
    }

    static func severity(from severity: DiagnosticSeverity?) -> WorkspaceDiagnostic.Severity {
        switch severity {
        case .error:
            return .error
        case .warning:
            return .warning
        case .information:
            return .information
        case .hint:
            return .hint
        case nil:
            return .error
        }
    }

    static func code(from code: DiagnosticCode?) -> String? {
        switch code {
        case .some(.optionA(let number)):
            return String(number)
        case .some(.optionB(let text)):
            return text
        case .none:
            return nil
        }
    }

    static func fileURL(fromDocumentURI uri: String) -> URL? {
        guard let url = URL(string: uri), url.isFileURL else { return nil }
        return url.standardizedFileURL
    }
}

@MainActor
enum LSPDiagnosticsPublisher {
    static func publish(_ diagnostics: [Diagnostic], forDocument uri: String, workspacePath: String? = nil) {
        guard let fileURL = LSPDiagnosticMapping.fileURL(fromDocumentURI: uri),
              let workspace = workspace(containing: fileURL, workspacePath: workspacePath) else {
            return
        }
        workspace.diagnosticsStore.replace(
            LSPDiagnosticMapping.workspaceDiagnostics(from: diagnostics, fileURL: fileURL),
            for: fileURL
        )
    }

    static func clear(_ uri: String, workspacePath: String? = nil) {
        guard let fileURL = LSPDiagnosticMapping.fileURL(fromDocumentURI: uri),
              let workspace = workspace(containing: fileURL, workspacePath: workspacePath) else {
            return
        }
        workspace.diagnosticsStore.clear(fileURL)
    }

    static func clear(documentsAtURIs uris: [String], workspacePath: String? = nil) {
        for uri in uris {
            clear(uri, workspacePath: workspacePath)
        }
    }

    static func workspace(containing fileURL: URL, workspacePath: String? = nil) -> WorkspaceDocument? {
        let workspaces = DreamderDocumentController.shared.documents.compactMap { $0 as? WorkspaceDocument }
        if let workspacePath {
            let standardizedPath = URL(fileURLWithPath: workspacePath).standardizedFileURL.path
            if let match = workspaces.first(where: { $0.fileURL?.standardizedFileURL.path == standardizedPath }) {
                return match
            }
        }
        let path = fileURL.standardizedFileURL.path
        let rooted = workspaces.compactMap { workspace in
            workspace.fileURL.map { (workspace, $0.standardizedFileURL.path) }
        }
        return rooted.first { isPath(path, within: $0.1) }?.0
    }

    nonisolated static func isPath(_ path: String, within root: String) -> Bool {
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return path == root || path.hasPrefix(prefix)
    }
}
