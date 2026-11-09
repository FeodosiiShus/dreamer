//
//  LanguageServer+Implementation.swift
//  Dreamder
//
//  Created by Abe Malla on 2/7/24.
//

import Foundation
import LanguageServerProtocol

extension LanguageServer {
    /// Resolve the implementation location of a symbol at a given text document position
    func requestImplementation(for documentURI: String, _ position: Position) async throws -> ImplementationResponse {
        await flushPendingEdits(for: documentURI)
        do {
            let cacheKey = CacheKey(
                uri: documentURI,
                requestType: "implementation",
                position: position,
                documentVersion: openFiles.documentVersion(for: documentURI)
            )
            if let cached: ImplementationResponse = lspCache.get(key: cacheKey, as: ImplementationResponse.self) {
                return cached
            }

            let params = TextDocumentPositionParams(
                textDocument: TextDocumentIdentifier(uri: documentURI),
                position: position
            )
            let response = try await lspInstance.implementation(params)

            lspCache.set(key: cacheKey, value: response)
            return response
        } catch {
            logger.warning("requestImplementation: Error \(error)")
            throw error
        }
    }
}
