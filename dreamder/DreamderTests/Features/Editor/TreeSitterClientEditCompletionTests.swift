import CodeEditLanguages
@preconcurrency import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import Synchronization
import Testing

private final class EditCompletionProbe: Sendable {
    struct Observation: Sendable {
        let onMainThread: Bool
        let succeeded: Bool
    }

    private let state = Mutex<Observation?>(nil)

    var observation: Observation? {
        state.withLock { $0 }
    }

    func record(_ result: Result<IndexSet, any Error>) {
        var succeeded = false
        if case .success = result {
            succeeded = true
        }
        let observation = Observation(onMainThread: Thread.isMainThread, succeeded: succeeded)
        state.withLock { $0 = observation }
    }
}

@MainActor
@Suite(.uiGate)
struct TreeSitterClientEditCompletionTests {
    private static let line = "let value = 1\n"
    private static let waitTimeout = Duration.seconds(60)

    private func makeText(longerThan length: Int) -> String {
        String(repeating: Self.line, count: length / Self.line.utf16.count + 4)
    }

    private func applyEdit(
        _ client: TreeSitterClient,
        in textView: TextView,
        range: NSRange
    ) -> EditCompletionProbe {
        let probe = EditCompletionProbe()
        let record: @Sendable (Result<IndexSet, any Error>) -> Void = { result in
            probe.record(result)
        }
        client.willApplyEdit(textView: textView, range: range)
        client.applyEdit(textView: textView, range: range, delta: 0, completion: record)
        return probe
    }

    @Test
    func theCompletionOfALongEditIsDeliveredOnTheMainThread() async throws {
        let threshold = TreeSitterClient.Constants.maxSyncEditLength
        let text = makeText(longerThan: threshold + 1)
        let textView = TextView(string: text)
        let client = TreeSitterClient()
        defer { withExtendedLifetime((textView, client)) {} }
        client.setUp(textView: textView, codeLanguage: .swift)
        let range = NSRange(location: 0, length: threshold + 1)
        try #require(NSMaxRange(range) <= text.utf16.count)

        let probe = applyEdit(client, in: textView, range: range)
        try await eventually(timeout: Self.waitTimeout) { probe.observation != nil }

        let observation = try #require(probe.observation)
        #expect(observation.onMainThread)
        #expect(observation.succeeded)
    }

    @Test
    func theCompletionOfAShortEditAfterSetUpIsDeliveredOnTheMainThread() async throws {
        let text = makeText(longerThan: 64)
        let textView = TextView(string: text)
        let client = TreeSitterClient()
        defer { withExtendedLifetime((textView, client)) {} }
        client.setUp(textView: textView, codeLanguage: .swift)

        let probe = applyEdit(client, in: textView, range: NSRange(location: 0, length: 4))
        try await eventually(timeout: Self.waitTimeout) { probe.observation != nil }

        let observation = try #require(probe.observation)
        #expect(observation.onMainThread)
    }
}
