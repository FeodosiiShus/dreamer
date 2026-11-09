import Foundation
import LanguageServerProtocol

extension LanguageServer {
    var supportsCompletionResolve: Bool {
        serverCapabilities.completionProvider?.resolveProvider == true
    }

    func resolveCompletionItem(_ item: CompletionItem, for documentURI: String) async throws -> CompletionItem {
        await flushPendingEdits(for: documentURI)
        do {
            return try await lspInstance.completeItemResolve(item)
        } catch {
            logger.warning("resolveCompletionItem: Error \(error)")
            throw error
        }
    }

    func requestCompletion(
        for documentURI: String,
        position: Position,
        triggerCharacter: String? = nil,
        incomplete: Bool = false
    ) async throws -> CompletionResponse {
        await flushPendingEdits(for: documentURI)
        do {
            let usesCache = triggerCharacter == nil && !incomplete
            let cacheKey = CacheKey(
                uri: documentURI,
                requestType: "completion",
                position: position,
                documentVersion: openFiles.documentVersion(for: documentURI)
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
                triggerKind: incomplete ? .triggerForIncompleteCompletions
                    : (triggerCharacter == nil ? .invoked : .triggerCharacter),
                triggerCharacter: incomplete ? nil : triggerCharacter
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
