import AppKit
import CodeEditLanguages
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import Testing
@testable import Dreamder

@MainActor
final class MarkdownHighlightHookGate {
    private(set) var arrivals = 0
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func pass() async {
        arrivals += 1
        guard !isOpen else { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func open() {
        isOpen = true
        let released = waiting
        waiting = []
        for continuation in released {
            continuation.resume()
        }
    }
}

@MainActor
final class MarkdownHighlightOutcomeRecorder {
    private(set) var results: [Result<[HighlightRange], Error>] = []

    func record(_ result: Result<[HighlightRange], Error>) {
        results.append(result)
    }

    var cancelledCount: Int {
        results.filter { result in
            if case .failure(let error) = result, let providing = error as? HighlightProvidingError {
                return providing == .operationCancelled
            }
            return false
        }.count
    }

    var runs: [[Int]] {
        results.flatMap { result -> [[Int]] in
            if case .success(let ranges) = result {
                return ranges.map { [$0.range.location, $0.range.length] }
            }
            return []
        }
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct MarkdownHighlightProviderRaceTests {
    private static let timeout = Duration.seconds(20)
    private static let largeText = String(repeating: "# Header\n\n", count: 6_000)
    private static let queryRange = NSRange(location: 0, length: 20)

    private func start(
        _ provider: MarkdownHighlightProvider,
        _ textView: TextView,
        into recorder: MarkdownHighlightOutcomeRecorder
    ) {
        provider.queryHighlightsFor(textView: textView, range: Self.queryRange) { result in
            recorder.record(result)
        }
    }

    private func typeLeadingCharacter(_ provider: MarkdownHighlightProvider, _ textView: TextView) {
        textView.replaceCharacters(in: NSRange(location: 0, length: 0), with: "x")
        provider.applyEdit(textView: textView, range: NSRange(location: 0, length: 0), delta: 1) { _ in }
    }

    @Test
    func anEditWhileTheLexHasNotFinishedCancelsTheStaleQuery() async throws {
        let gate = MarkdownHighlightHookGate()
        let provider = MarkdownHighlightProvider(beforeLex: { await gate.pass() })
        let textView = TextView(string: Self.largeText)
        provider.setUp(textView: textView, codeLanguage: .markdown)
        let recorder = MarkdownHighlightOutcomeRecorder()

        start(provider, textView, into: recorder)
        try await eventually(timeout: Self.timeout) { gate.arrivals == 1 }
        typeLeadingCharacter(provider, textView)
        gate.open()
        try await eventually(timeout: Self.timeout) { recorder.results.count == 1 }

        #expect(recorder.cancelledCount == 1)
        #expect(recorder.runs.isEmpty)
    }

    @Test
    func anEditAfterTheLexFinishedButBeforeDeliveryCancelsTheStaleQuery() async throws {
        let gate = MarkdownHighlightHookGate()
        let provider = MarkdownHighlightProvider(beforeDelivery: { await gate.pass() })
        let textView = TextView(string: Self.largeText)
        provider.setUp(textView: textView, codeLanguage: .markdown)
        let recorder = MarkdownHighlightOutcomeRecorder()

        start(provider, textView, into: recorder)
        try await eventually(timeout: Self.timeout) { gate.arrivals == 1 }
        typeLeadingCharacter(provider, textView)
        gate.open()
        try await eventually(timeout: Self.timeout) { recorder.results.count == 1 }

        #expect(recorder.cancelledCount == 1)
        #expect(recorder.runs.isEmpty)
    }

    @Test
    func aQueryAfterTheEditGetsTheNewTextWhileTheStaleOneIsCancelled() async throws {
        let gate = MarkdownHighlightHookGate()
        let provider = MarkdownHighlightProvider(beforeLex: { await gate.pass() })
        let textView = TextView(string: Self.largeText)
        provider.setUp(textView: textView, codeLanguage: .markdown)
        let stale = MarkdownHighlightOutcomeRecorder()
        let fresh = MarkdownHighlightOutcomeRecorder()

        start(provider, textView, into: stale)
        try await eventually(timeout: Self.timeout) { gate.arrivals == 1 }
        typeLeadingCharacter(provider, textView)
        start(provider, textView, into: fresh)
        try await eventually(timeout: Self.timeout) { gate.arrivals == 2 }
        gate.open()
        try await eventually(timeout: Self.timeout) { stale.results.count == 1 && fresh.results.count == 1 }

        #expect(stale.cancelledCount == 1)
        #expect(stale.runs.isEmpty)
        #expect(fresh.cancelledCount == 0)
        #expect(fresh.runs == [[11, 1], [13, 6]])
    }

    @Test
    func twoQueriesOfTheSameGenerationShareOneLexAndBothComplete() async throws {
        let gate = MarkdownHighlightHookGate()
        let provider = MarkdownHighlightProvider(beforeLex: { await gate.pass() })
        let textView = TextView(string: Self.largeText)
        provider.setUp(textView: textView, codeLanguage: .markdown)
        let first = MarkdownHighlightOutcomeRecorder()
        let second = MarkdownHighlightOutcomeRecorder()

        start(provider, textView, into: first)
        start(provider, textView, into: second)
        try await eventually(timeout: Self.timeout) { gate.arrivals == 1 }
        gate.open()
        try await eventually(timeout: Self.timeout) { first.results.count == 1 && second.results.count == 1 }

        #expect(gate.arrivals == 1)
        #expect(first.runs == [[0, 1], [2, 6], [10, 1], [12, 6]])
        #expect(second.runs == first.runs)
    }
}
