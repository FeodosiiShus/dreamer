//
//  LanguageServer+FoldingRange.swift
//  Dreamder
//
//  Created by Abe Malla on 2/7/24.
//

import Foundation
import LanguageServerProtocol

extension LanguageServer {
    static var foldingRangeMethod: String { "textDocument/foldingRange" }

    var supportsFoldingRange: Bool {
        switch serverCapabilities.foldingRangeProvider {
        case .optionA(let enabled):
            return enabled
        case .optionB, .optionC:
            return true
        case nil:
            return dynamicCapabilities.hasCapability(Self.foldingRangeMethod)
        }
    }

    func requestFoldingRange(for documentURI: String) async throws -> FoldingRangeResponse {
        await flushPendingEdits(for: documentURI)
        let cacheKey = CacheKey(
            uri: documentURI,
            requestType: "foldingRange",
            documentVersion: openFiles.documentVersion(for: documentURI)
        )
        if let cachedRanges: [FoldingRange] = lspCache.get(key: cacheKey, as: [FoldingRange].self) {
            return cachedRanges
        }
        do {
            let params = FoldingRangeParams(textDocument: TextDocumentIdentifier(uri: documentURI))
            let response = try await lspInstance.foldingRange(params)
            if let ranges = response {
                lspCache.set(key: cacheKey, value: ranges)
            }
            return response
        } catch {
            logger.warning("requestFoldingRange: Error \(error)")
            throw error
        }
    }
}
