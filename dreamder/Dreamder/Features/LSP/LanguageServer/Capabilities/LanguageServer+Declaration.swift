//
//  LanguageServer+Declaration.swift
//  Dreamder
//
//  Created by Abe Malla on 2/7/24.
//

import Foundation
import LanguageServerProtocol

extension LanguageServer {
    func requestGoToDeclaration(for documentURI: String, position: Position) async throws -> DeclarationResponse {
        await flushPendingEdits(for: documentURI)
        do {
            let cacheKey = CacheKey(
                uri: documentURI,
                requestType: "declaration",
                position: position,
                documentVersion: openFiles.documentVersion(for: documentURI)
            )
            if let cached: DeclarationResponse = lspCache.get(key: cacheKey, as: DeclarationResponse.self) {
                return cached
            }
            let params = TextDocumentPositionParams(
                textDocument: TextDocumentIdentifier(uri: documentURI),
                position: position
            )
            let response = try await lspInstance.declaration(params)
            lspCache.set(key: cacheKey, value: response)
            return response
        } catch {
            logger.warning("requestGoToDeclaration: Error \(error)")
            throw error
        }
    }
}
