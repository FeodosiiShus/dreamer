//
//  LanguageServer+SelectionRange.swift
//  Dreamder
//
//  Created by Abe Malla on 2/7/24.
//

import Foundation
import LanguageServerProtocol

extension LanguageServer {
    static var selectionRangeMethod: String { "textDocument/selectionRange" }

    var supportsSelectionRange: Bool {
        switch serverCapabilities.selectionRangeProvider {
        case .optionA(let enabled):
            return enabled
        case .optionB, .optionC:
            return true
        case nil:
            return dynamicCapabilities.hasCapability(Self.selectionRangeMethod)
        }
    }

    func requestSelectionRange(for documentURI: String, positions: [Position]) async throws -> SelectionRangeResponse {
        await flushPendingEdits(for: documentURI)
        do {
            let cacheKey = CacheKey(
                uri: documentURI,
                requestType: "selectionRange",
                documentVersion: openFiles.documentVersion(for: documentURI),
                extraData: positions
            )
            if let cachedResponse: SelectionRangeResponse = lspCache.get(key: cacheKey, as: SelectionRangeResponse.self) {
                return cachedResponse
            }
            let params = SelectionRangeParams(
                workDoneToken: nil,
                textDocument: TextDocumentIdentifier(uri: documentURI),
                positions: positions
            )
            let response = try await lspInstance.selectionRange(params)
            lspCache.set(key: cacheKey, value: response)
            return response
        } catch {
            logger.warning("requestSelectionRange: Error \(error)")
            throw error
        }
    }
}
