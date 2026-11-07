import AppKit
import CodeEditLanguages
@preconcurrency import CodeEditSourceEditor
import CodeEditTextView
import Foundation

final class MarkdownHighlightProvider: HighlightProviding {
    nonisolated static let synchronousLexLimit = 40_000

    nonisolated static let captureMapping: [MarkdownTokenKind: CaptureName] = {
        var mapping: [MarkdownTokenKind: CaptureName] = [
            .headerMarker: .keyword,
            .blockQuoteMarker: .comment,
            .listMarker: .keyword,
            .horizontalRule: .keyword,
            .codeFenceMarker: .keyword,
            .codeFenceLanguage: .variable,
            .codeFenceContent(hasLanguage: false): .string,
            .codeBlock: .string,
            .tableSeparator: .keyword,
            .frontMatterDelimiter: .keyword,
            .htmlComment: .comment,
            .htmlTagName: .keyword,
            .htmlAttributeValue: .string,
            .codeSpan: .string,
            .codeSpanMarker: .keyword,
            .italicMarker: .keyword,
            .boldMarker: .keyword,
            .highlight: .typeAlternate,
            .inlineLink: .string,
            .linkText: .number,
            .linkLabel: .keyword,
            .linkDestination: .number,
            .linkTitle: .string,
            .autolink: .number
        ]
        for level in 1...6 {
            mapping[.headerContent(level: level)] = .variable
        }
        return mapping
    }()

    typealias EditCallback = @MainActor (Result<IndexSet, any Error>) -> Void
    typealias HighlightCallback = @MainActor (Result<[HighlightRange], any Error>) -> Void

    private var generation = 0
    private var cached: (generation: Int, tokens: [MarkdownToken])?
    private var pending: (generation: Int, task: Task<[MarkdownToken], Never>)?

    init() {}

    func setUp(textView: TextView, codeLanguage: CodeLanguage) {
        invalidateCache()
    }

    func applyEdit(textView: TextView, range: NSRange, delta: Int, completion: @escaping EditCallback) {
        invalidateCache()
        completion(.success(IndexSet(integersIn: 0..<textView.length)))
    }

    func queryHighlightsFor(textView: TextView, range: NSRange, completion: @escaping HighlightCallback) {
        let requested = generation
        if let cached, cached.generation == requested {
            completion(.success(Self.highlights(tokens: cached.tokens, in: range)))
            return
        }
        let text = textView.string
        if text.utf16.count <= Self.synchronousLexLimit {
            let tokens = MarkdownBlockLexer.tokens(in: text)
            cached = (requested, tokens)
            completion(.success(Self.highlights(tokens: tokens, in: range)))
            return
        }
        let task: Task<[MarkdownToken], Never>
        if let pending, pending.generation == requested {
            task = pending.task
        } else {
            task = Task { await Self.lex(text) }
            pending = (requested, task)
        }
        Task { [weak self] in
            let tokens = await task.value
            guard let self, self.generation == requested, !task.isCancelled else {
                completion(.failure(HighlightProvidingError.operationCancelled))
                return
            }
            self.cached = (requested, tokens)
            completion(.success(Self.highlights(tokens: tokens, in: range)))
        }
    }

    private func invalidateCache() {
        generation += 1
        cached = nil
        pending?.task.cancel()
        pending = nil
    }

    @concurrent
    private static func lex(_ text: String) async -> [MarkdownToken] {
        MarkdownBlockLexer.tokens(in: text)
    }

    nonisolated static func highlights(text: String, in range: NSRange) -> [HighlightRange] {
        highlights(tokens: MarkdownBlockLexer.tokens(in: text), in: range)
    }

    nonisolated static func highlights(tokens: [MarkdownToken], in range: NSRange) -> [HighlightRange] {
        guard range.length > 0 else { return [] }
        let upper = range.location + range.length
        var painted = [Int8](repeating: -1, count: range.length)
        var hasPaint = false
        for token in tokens {
            if token.range.location >= upper { break }
            guard let capture = captureMapping[token.kind] else { continue }
            let lower = max(token.range.location, range.location)
            let end = min(token.range.location + token.range.length, upper)
            guard lower < end else { continue }
            for index in (lower - range.location)..<(end - range.location) {
                painted[index] = capture.rawValue
            }
            hasPaint = true
        }
        guard hasPaint else { return [] }
        var result: [HighlightRange] = []
        var index = 0
        while index < painted.count {
            let value = painted[index]
            var end = index + 1
            while end < painted.count, painted[end] == value {
                end += 1
            }
            if value >= 0, let capture = CaptureName(rawValue: value) {
                result.append(
                    HighlightRange(range: NSRange(location: range.location + index, length: end - index), capture: capture)
                )
            }
            index = end
        }
        return result
    }
}
