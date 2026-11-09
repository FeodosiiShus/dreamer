//
//  LanguageServer+Hover.swift
//  Dreamder
//
//  Created by Abe Malla on 2/7/24.
//

import Foundation
import LanguageServerProtocol

extension LanguageServer {
    func requestHover(for documentURI: String, _ position: Position) async throws -> HoverResponse {
        await flushPendingEdits(for: documentURI)
        do {
            let cacheKey = CacheKey(
                uri: documentURI,
                requestType: "hover",
                position: position,
                documentVersion: openFiles.documentVersion(for: documentURI)
            )
            if let cachedResponse: HoverResponse = lspCache.get(key: cacheKey, as: HoverResponse.self) {
                return cachedResponse
            }
            let params = TextDocumentPositionParams(
                textDocument: TextDocumentIdentifier(uri: documentURI),
                position: position
            )
            let response = try await lspInstance.hover(params)
            lspCache.set(key: cacheKey, value: response)
            return response
        } catch {
            logger.warning("requestHover: Error \(error)")
            throw error
        }
    }
}
