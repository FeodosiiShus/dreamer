//
//  LanguageServer+SemanticTokens.swift
//  Dreamder
//
//  Created by Abe Malla on 2/7/24.
//

import Foundation
import LanguageServerProtocol

extension LanguageServer {
    var supportsSemanticTokens: Bool {
        serverCapabilities.semanticTokensProvider != nil
    }

    func requestSemanticTokens(
        for documentURI: String,
        flushingPendingEdits: Bool = true
    ) async throws -> SemanticTokensResponse {
        if flushingPendingEdits {
            await flushPendingEdits(for: documentURI)
        }
        do {
            let params = SemanticTokensParams(textDocument: TextDocumentIdentifier(uri: documentURI))
            return try await lspInstance.semanticTokensFull(params)
        } catch {
            logger.warning("requestSemanticTokens full: Error \(error)")
            throw error
        }
    }

    func requestSemanticTokens(
        for documentURI: String,
        previousResultId: String,
        flushingPendingEdits: Bool = true
    ) async throws -> SemanticTokensDeltaResponse {
        if flushingPendingEdits {
            await flushPendingEdits(for: documentURI)
        }
        do {
            let params = SemanticTokensDeltaParams(
                textDocument: TextDocumentIdentifier(uri: documentURI),
                previousResultId: previousResultId
            )
            return try await lspInstance.semanticTokensFullDelta(params)
        } catch {
            logger.warning("requestSemanticTokens versioned: Error \(error)")
            throw error
        }
    }
}
