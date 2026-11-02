import Foundation
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
}
