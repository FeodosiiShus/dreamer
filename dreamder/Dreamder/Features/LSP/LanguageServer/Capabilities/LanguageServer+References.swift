//
//  LanguageServer+References.swift
//  Dreamder
//
//  Created by Abe Malla on 2/7/24.
//

import Foundation
import LanguageServerProtocol

extension LanguageServer {
    func requestFindReferences(
        for documentURI: String,
        _ position: Position,
        _ includeDeclaration: Bool = false
    ) async throws -> ReferenceResponse {
        await flushPendingEdits(for: documentURI)
        do {
            let cacheKey = CacheKey(
                uri: documentURI,
                requestType: "references",
                position: position,
                documentVersion: openFiles.documentVersion(for: documentURI),
                extraData: includeDeclaration
            )
            if let cachedResponse: ReferenceResponse = lspCache.get(key: cacheKey, as: ReferenceResponse.self) {
                return cachedResponse
            }
            let params = ReferenceParams(
                textDocument: TextDocumentIdentifier(uri: documentURI),
                position: position,
                includeDeclaration: includeDeclaration
            )
            let response = try await lspInstance.references(params)
            lspCache.set(key: cacheKey, value: response)
            return response
        } catch {
            logger.warning("requestFindReferences: Error \(error)")
            throw error
        }
    }
}
