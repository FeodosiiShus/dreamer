import AppKit
import CodeEditLanguages
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct MarkdownHighlightProviderQueryTests {
    private func query(
        _ provider: MarkdownHighlightProvider,
        _ textView: TextView,
        range: NSRange
    ) async -> Result<[HighlightRange], Error> {
        await withCheckedContinuation { continuation in
            provider.queryHighlightsFor(textView: textView, range: range) { result in
                continuation.resume(returning: result)
            }
        }
    }

    private func applyEdit(
        _ provider: MarkdownHighlightProvider,
        _ textView: TextView,
        range: NSRange,
        delta: Int
    ) async -> IndexSet {
        await withCheckedContinuation { continuation in
            provider.applyEdit(textView: textView, range: range, delta: delta) { result in
                switch result {
                case .success(let invalidated):
                    continuation.resume(returning: invalidated)
                case .failure:
                    continuation.resume(returning: IndexSet())
                }
            }
        }
    }

    private func locations(_ result: Result<[HighlightRange], Error>) -> [[Int]] {
        switch result {
        case .success(let runs):
            runs.map { [$0.range.location, $0.range.length] }
        case .failure:
            []
        }
    }

    @Test func smallDocumentIsLexedSynchronously() async {
        let provider = MarkdownHighlightProvider()
        let textView = TextView(string: "# Title `code`")
        provider.setUp(textView: textView, codeLanguage: .markdown)

        let result = await query(provider, textView, range: NSRange(location: 0, length: 14))

        #expect(locations(result) == [[0, 1], [2, 6], [8, 1], [9, 4], [13, 1]])
    }

    @Test func largeDocumentIsLexedOffTheMainActorAndServedFromTheCache() async {
        let provider = MarkdownHighlightProvider()
        let text = String(repeating: "# Header\n\n", count: 6_000)
        #expect(text.utf16.count > MarkdownHighlightProvider.synchronousLexLimit)
        let textView = TextView(string: text)
        provider.setUp(textView: textView, codeLanguage: .markdown)

        let first = await query(provider, textView, range: NSRange(location: 0, length: 20))
        let cached = await query(provider, textView, range: NSRange(location: 10, length: 10))

        #expect(locations(first) == [[0, 1], [2, 6], [10, 1], [12, 6]])
        #expect(locations(cached) == [[10, 1], [12, 6]])
    }

    @Test func editInvalidatesTheWholeDocumentAndRelexesTheNewText() async {
        let provider = MarkdownHighlightProvider()
        let textView = TextView(string: "Plain")
        provider.setUp(textView: textView, codeLanguage: .markdown)
        let before = await query(provider, textView, range: NSRange(location: 0, length: 5))
        #expect(locations(before).isEmpty)

        textView.replaceCharacters(in: NSRange(location: 5, length: 0), with: "\n=====")
        let invalidated = await applyEdit(provider, textView, range: NSRange(location: 5, length: 0), delta: 6)
        let after = await query(provider, textView, range: NSRange(location: 0, length: 11))

        #expect(invalidated == IndexSet(integersIn: 0..<11))
        #expect(locations(after) == [[0, 5], [6, 5]])
    }

    @Test func editWhileLexingAsynchronouslyCancelsTheStaleQuery() async {
        let provider = MarkdownHighlightProvider()
        let text = String(repeating: "# Header\n\n", count: 6_000)
        let textView = TextView(string: text)
        provider.setUp(textView: textView, codeLanguage: .markdown)

        async let stale = query(provider, textView, range: NSRange(location: 0, length: 20))
        await Task.yield()
        textView.replaceCharacters(in: NSRange(location: 0, length: 0), with: "x")
        _ = await applyEdit(provider, textView, range: NSRange(location: 0, length: 0), delta: 1)
        let outcome = await stale

        var wasCancelled = false
        if case .failure(let error) = outcome, let providing = error as? HighlightProvidingError {
            wasCancelled = providing == .operationCancelled
        }
        #expect(wasCancelled)
    }
}
