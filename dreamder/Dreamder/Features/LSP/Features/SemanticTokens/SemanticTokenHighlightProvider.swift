//
//  SemanticTokenHighlightProvider.swift
//  Dreamder
//
//  Created by Khan Winter on 12/26/24.
//

import Foundation
import LanguageServerProtocol
@preconcurrency import CodeEditSourceEditor
import CodeEditTextView
import CodeEditLanguages
import OSLog

private let semanticTokenLogger = Logger(
    subsystem: "dev.dreamder.Dreamder",
    category: "SemanticTokenHighlightProvider"
)

/// Provides semantic token information from a language server for a source editor view.
///
/// This class works in tangent with the ``LanguageServer`` class to ensure we don't unnecessarily request new tokens
/// if the document isn't updated. The ``LanguageServer`` will call the
/// ``SemanticTokenHighlightProvider/documentDidChange`` method, which in turn refreshes the semantic token storage.
///
/// That behavior may not be intuitive due to the
/// ``SemanticTokenHighlightProvider/applyEdit(textView:range:delta:completion:)`` method. One might expect this class
/// to respond to that method immediately, but it does not. It instead stores the completion passed in that method until
/// it can respond to the edit with invalidated indices.
final class SemanticTokenHighlightProvider<
    Storage: GenericSemanticTokenStorage,
    DocumentType: LanguageServerDocument
>: HighlightProviding {
    enum HighlightError: Error {
        case lspRangeFailure
    }

    typealias EditCallback = @MainActor (Result<IndexSet, any Error>) -> Void
    typealias HighlightCallback = @MainActor (Result<[HighlightRange], any Error>) -> Void

    private var tokenMap: SemanticTokenMap?
    private var documentURI: String?
    weak var languageServer: LanguageServer<DocumentType>?
    private weak var textView: TextView?

    private var pendingEdit: CheckedContinuation<IndexSet, Never>?
    private var pendingHighlights: [CheckedContinuation<[HighlightRange], any Error>] = []
    private var storage: Storage

    private(set) var latestRefresh: Task<Void, Never>?

    var documentRange: NSRange {
        textView?.documentRange ?? .zero
    }

    init(
        tokenMap: SemanticTokenMap? = nil,
        languageServer: LanguageServer<DocumentType>? = nil,
        documentURI: String? = nil
    ) {
        self.tokenMap = tokenMap
        self.languageServer = languageServer
        self.documentURI = documentURI
        self.storage = Storage()
    }

    func setUp(server: LanguageServer<DocumentType>, document: DocumentType) {
        languageServer = server
        documentURI = document.languageServerURI
        tokenMap = server.highlightMap
        guard textView != nil else { return }
        refreshTokens()
    }

    private func refreshTokens() {
        latestRefresh = Task {
            do {
                try await documentDidChange()
            } catch {
                semanticTokenLogger.error("Semantic token refresh failed: \(error)")
            }
        }
    }

    // MARK: - Language Server Content Lifecycle

    /// Called when the language server finishes sending a document update.
    ///
    /// This method first checks if this object has any semantic tokens. If not, requests new tokens and responds to the
    /// `pendingHighlightCallbacks` queue with cancellation errors, causing the highlighter to re-query those indices.
    ///
    /// If this object already has some tokens, it determines whether or not we can request a token delta and
    /// performs the request.
    func documentDidChange() async throws {
        guard let languageServer, let textView else {
            return
        }
        guard languageServer.supportsSemanticTokens else {
            resolvePendingHighlights(.success([]))
            return
        }

        guard storage.hasReceivedData else {
            // We have no semantic token info, request it!
            try await requestTokens(languageServer: languageServer, textView: textView)
            resolvePendingHighlights(.failure(HighlightProvidingError.operationCancelled))
            return
        }

        // The document was updated. Update our token cache and send the invalidated ranges for the editor to handle.
        if let lastResultId = storage.lastResultId {
            try await requestDeltaTokens(languageServer: languageServer, textView: textView, lastResultId: lastResultId)
            return
        }

        try await requestTokens(languageServer: languageServer, textView: textView)
    }

    // MARK: - LSP Token Requests

    /// Requests and applies a token delta. Requires a previous response identifier.
    private func requestDeltaTokens(
        languageServer: LanguageServer<DocumentType>,
        textView: TextView,
        lastResultId: String
    ) async throws {
        guard let documentURI,
              let response = try await languageServer.requestSemanticTokens(
            for: documentURI,
            previousResultId: lastResultId,
            flushingPendingEdits: false
        ) else {
            return
        }
        switch response {
        case let .optionA(tokenData):
            applyEntireResponse(tokenData)
        case let .optionB(deltaData):
            applyDeltaResponse(deltaData, textView: textView)
        }
    }

    /// Requests and applies tokens for an entire document. This does not require a previous response id, and should be
    /// used in place of `requestDeltaTokens` when that's the case.
    private func requestTokens(languageServer: LanguageServer<DocumentType>, textView: TextView) async throws {
        guard let documentURI,
              let response = try await languageServer.requestSemanticTokens(
                for: documentURI,
                flushingPendingEdits: false
              ) else {
            return
        }
        applyEntireResponse(response)
    }

    // MARK: - Apply LSP Response

    /// Applies a delta response from the LSP to our storage.
    private func applyDeltaResponse(_ data: SemanticTokensDelta, textView: TextView?) {
        let lspRanges = storage.applyDelta(data)
        let ranges = lspRanges.compactMap { textView?.nsRangeFrom($0) }
        takePendingEdit()?.resume(returning: IndexSet(ranges: ranges))
    }

    private func applyEntireResponse(_ data: SemanticTokens) {
        storage.setData(data)
        takePendingEdit()?.resume(returning: IndexSet(integersIn: documentRange))
    }

    // MARK: - Highlight Provider Conformance

    func setUp(textView: TextView, codeLanguage: CodeLanguage) {
        self.textView = textView
        refreshTokens()
    }

    func applyEdit(textView: TextView, range: NSRange, delta: Int, completion: @escaping EditCallback) {
        Task {
            completion(.success(await invalidatedIndicesAfterEdit()))
        }
    }

    func queryHighlightsFor(textView: TextView, range: NSRange, completion: @escaping HighlightCallback) {
        Task {
            do {
                completion(.success(try await highlights(in: range, textView: textView)))
            } catch {
                completion(.failure(error))
            }
        }
    }

    var pendingHighlightCount: Int {
        pendingHighlights.count
    }

    var hasPendingEdit: Bool {
        pendingEdit != nil
    }

    func invalidatedIndicesAfterEdit() async -> IndexSet {
        pendingEdit?.resume(returning: IndexSet())
        return await withCheckedContinuation { continuation in
            pendingEdit = continuation
        }
    }

    func highlights(in range: NSRange, textView: TextView) async throws -> [HighlightRange] {
        guard let languageServer, languageServer.supportsSemanticTokens else {
            return []
        }
        guard storage.hasReceivedData else {
            return try await withCheckedThrowingContinuation { continuation in
                pendingHighlights.append(continuation)
            }
        }

        guard let lspRange = textView.lspRangeFrom(nsRange: range), let tokenMap else {
            throw HighlightError.lspRangeFailure
        }
        let rawTokens = storage.getTokensFor(range: lspRange)
        return tokenMap
            .decode(tokens: rawTokens, using: textView)
            .compactMap { highlightRange -> HighlightRange? in
                // Filter out empty ranges
                guard highlightRange.capture != nil || !highlightRange.modifiers.isEmpty,
                      // Clamp the highlight range to the queried range.
                      let intersection = highlightRange.range.intersection(range),
                      intersection.isEmpty == false else {
                    return nil
                }
                return HighlightRange(
                    range: intersection,
                    capture: highlightRange.capture,
                    modifiers: highlightRange.modifiers
                )
            }
    }

    private func resolvePendingHighlights(_ outcome: Result<[HighlightRange], any Error>) {
        let continuations = pendingHighlights
        pendingHighlights.removeAll()
        for continuation in continuations {
            continuation.resume(with: outcome)
        }
    }

    private func takePendingEdit() -> CheckedContinuation<IndexSet, Never>? {
        defer { pendingEdit = nil }
        return pendingEdit
    }
}
