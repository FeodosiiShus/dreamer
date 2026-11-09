//
//  LanguageServer+TypeDefinition.swift
//  Dreamder
//
//  Created by Abe Malla on 2/7/24.
//

import Foundation
import LanguageServerProtocol

extension LanguageServer {
    /// Resolve the type definition location of a symbol at a given text document position
    func requestTypeDefinition(for documentURI: String, _ position: Position) async throws -> TypeDefinitionResponse {
        await flushPendingEdits(for: documentURI)
        do {
            let cacheKey = CacheKey(
                uri: documentURI,
                requestType: "typeDefinition",
                position: position,
                documentVersion: openFiles.documentVersion(for: documentURI)
            )
            if let cached: TypeDefinitionResponse = lspCache.get(key: cacheKey, as: TypeDefinitionResponse.self) {
                return cached
            }

            let params = TextDocumentPositionParams(
                textDocument: TextDocumentIdentifier(uri: documentURI),
                position: position
            )
            let response = try await lspInstance.typeDefinition(params)

            lspCache.set(key: cacheKey, value: response)
            return response
        } catch {
            logger.warning("requestTypeDefinition: Error \(error)")
            throw error
        }
    }
}
