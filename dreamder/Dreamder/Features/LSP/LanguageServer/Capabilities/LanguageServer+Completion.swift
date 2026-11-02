import Foundation
import LanguageServerProtocol

extension LanguageServer {
    func requestCompletion(
        for documentURI: String,
        position: Position,
        triggerCharacter: String? = nil
    ) async throws -> CompletionResponse {
        do {
            let usesCache = triggerCharacter == nil
            let cacheKey = CacheKey(
                uri: documentURI,
                requestType: "completion",
                extraData: position
            )
            if usesCache, let cachedResponse: CompletionResponse = lspCache.get(
                key: cacheKey,
                as: CompletionResponse.self
            ) {
                return cachedResponse
            }
            let completionParams = CompletionParams(
                uri: documentURI,
                position: position,
                triggerKind: triggerCharacter == nil ? .invoked : .triggerCharacter,
                triggerCharacter: triggerCharacter
            )
            let response = try await lspInstance.completion(completionParams)

            if usesCache {
                lspCache.set(key: cacheKey, value: response)
            }
            return response
        } catch {
            logger.warning("requestCompletion: Error \(error)")
            throw error
        }
    }
}
