//
//  LanguageServer+InlayHint.swift
//  Dreamder
//
//  Created by Abe Malla on 2/7/24.
//

import Foundation
import LanguageServerProtocol

extension LanguageServer {
    /// Compute inlay hints for a given [text document, range] tuple that may be rendered in the
    /// editor in place with other text
    func requestInlayHint(for documentURI: String, _ range: LSPRange) async throws -> InlayHintResponse {
        await flushPendingEdits(for: documentURI)
        do {
            let params = InlayHintParams(
                workDoneToken: nil,
                textDocument: TextDocumentIdentifier(uri: documentURI),
                range: range
            )
            return try await lspInstance.inlayHint(params)
        } catch {
            logger.warning("requestInlayHint: Error \(error)")
            throw error
        }
    }
}
