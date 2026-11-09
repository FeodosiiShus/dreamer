import Foundation
import JSONRPC
import LanguageServerProtocol

extension LanguageServer {
    func requestPullDiagnostics(
        document documentURI: String,
        previousResultId: String? = nil
    ) async throws -> DocumentDiagnosticReport {
        do {
            return try await lspInstance.diagnostics(
                DocumentDiagnosticParams(
                    textDocument: TextDocumentIdentifier(uri: documentURI),
                    previousResultId: previousResultId
                )
            )
        } catch {
            logger.warning("requestPullDiagnostics: Error \(error)")
            throw error
        }
    }

    var workspaceDiagnosticsSupport: WorkspaceDiagnosticsSupport? {
        WorkspaceDiagnosticsSupport.resolve(
            static: serverCapabilities.diagnosticProvider,
            dynamic: dynamicCapabilities.registerOptions(
                for: WorkspaceDiagnosticsSupport.registrationMethod,
                as: DiagnosticRegistrationOptions.self
            )
        )
    }

    func requestWorkspaceDiagnostics(_ params: WorkspaceDiagnosticParams) async throws -> WorkspaceDiagnosticReport {
        do {
            let response: LSPAny = try await lspInstance.sendRequest(
                .custom(WorkspaceDiagnosticsSupport.requestMethod, try params.lspAny(), ClientRequest.NullHandler)
            )
            return try WorkspaceDiagnosticReport.decode(response)
        } catch {
            logger.warning("requestWorkspaceDiagnostics: Error \(error)")
            throw error
        }
    }
}
