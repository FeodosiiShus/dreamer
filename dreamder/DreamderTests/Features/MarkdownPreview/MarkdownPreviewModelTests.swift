import Combine
import Foundation
import Synchronization
import Testing
@testable import Dreamder

nonisolated final class MarkdownRenderRecorder: Sendable {
    private let recorded = Mutex<[String]>([])

    var texts: [String] {
        recorded.withLock { $0 }
    }

    func render(_ text: String) -> String {
        recorded.withLock { $0.append(text) }
        return "<p>\(text)</p>"
    }
}

@MainActor
final class MarkdownTextSource {
    var value: String

    init(_ value: String) {
        self.value = value
    }
}

@MainActor
@Suite
struct MarkdownPreviewModelTests {
    @MainActor
    private struct Harness {
        let model: MarkdownPreviewModel
        let recorder: MarkdownRenderRecorder
        let clock: TestClock
        let subject: PassthroughSubject<Void, Never>
        let source: MarkdownTextSource

        func type(_ text: String) {
            source.value = text
            subject.send()
        }
    }

    private func makeHarness(initialText: String = "first") -> Harness {
        let recorder = MarkdownRenderRecorder()
        let clock = TestClock()
        let subject = PassthroughSubject<Void, Never>()
        let source = MarkdownTextSource(initialText)
        let model = MarkdownPreviewModel(
            text: { source.value },
            updates: subject.eraseToAnyPublisher(),
            baseURL: nil,
            debounce: .milliseconds(20),
            clock: clock,
            render: { [recorder] text in recorder.render(text) }
        )
        return Harness(model: model, recorder: recorder, clock: clock, subject: subject, source: source)
    }

    private func settle(_ milliseconds: Int = 150) async throws {
        try await Task.sleep(for: .milliseconds(milliseconds))
    }

    @Test
    func debounceIsTwentyMilliseconds() {
        #expect(MarkdownPreviewModel.defaultDebounce == .milliseconds(20))
    }

    @Test
    func startRendersTheCurrentTextWithoutWaitingForTheDebounce() async throws {
        let harness = makeHarness()
        harness.model.start()
        try await eventually { harness.model.bodyHTML == "<p>first</p>" }
        #expect(harness.recorder.texts == ["first"])
        #expect(harness.clock.pendingSleeperCount == 0)
    }

    @Test
    func startingTwiceSubscribesOnce() async throws {
        let harness = makeHarness()
        harness.model.start()
        harness.model.start()
        try await eventually { harness.model.bodyHTML == "<p>first</p>" }

        harness.type("second")
        try await harness.clock.waitForSleepers()
        harness.clock.advance(by: .milliseconds(20))
        try await eventually { harness.model.bodyHTML == "<p>second</p>" }
        try await settle()
        #expect(harness.recorder.texts == ["first", "second"])
    }

    @Test
    func aTextEditTriggersExactlyOneRenderAfterTheDebounce() async throws {
        let harness = makeHarness()
        harness.model.start()
        try await eventually { harness.model.bodyHTML == "<p>first</p>" }

        harness.type("second")
        try await harness.clock.waitForSleepers()
        #expect(harness.recorder.texts == ["first"])
        harness.clock.advance(by: .milliseconds(19))
        try await settle(50)
        #expect(harness.recorder.texts == ["first"])

        harness.clock.advance(by: .milliseconds(1))
        try await eventually { harness.model.bodyHTML == "<p>second</p>" }
        try await settle()
        #expect(harness.recorder.texts == ["first", "second"])
    }

    @Test
    func aBurstOfEditsCollapsesIntoOneRenderOfTheLatestText() async throws {
        let harness = makeHarness()
        harness.model.start()
        try await eventually { harness.model.bodyHTML == "<p>first</p>" }

        for text in ["a", "ab", "abc", "abcd", "abcde"] {
            harness.type(text)
        }
        try await harness.clock.waitForSleepers()
        try await settle(50)
        #expect(harness.clock.pendingSleeperCount == 1)
        harness.clock.advance(by: .milliseconds(20))
        try await eventually { harness.model.bodyHTML == "<p>abcde</p>" }
        try await settle()
        #expect(harness.recorder.texts == ["first", "abcde"])
    }

    @Test
    func refreshRendersImmediatelyAndCancelsAPendingDebounce() async throws {
        let harness = makeHarness()
        harness.model.start()
        try await eventually { harness.model.bodyHTML == "<p>first</p>" }

        harness.type("second")
        try await harness.clock.waitForSleepers()
        harness.model.refresh()
        try await eventually { harness.model.bodyHTML == "<p>second</p>" }

        harness.clock.advance(by: .milliseconds(100))
        try await settle()
        #expect(harness.recorder.texts == ["first", "second"])
    }

    @Test
    func rendersThatProduceIdenticalHTMLDoNotChangeTheBody() async throws {
        let harness = makeHarness(initialText: "same")
        harness.model.start()
        try await eventually { harness.model.bodyHTML == "<p>same</p>" }

        harness.type("same")
        try await harness.clock.waitForSleepers()
        harness.clock.advance(by: .milliseconds(20))
        try await eventually { harness.recorder.texts.count == 2 }
        #expect(harness.model.bodyHTML == "<p>same</p>")
    }

    @Test
    func noRenderHappensBeforeStart() async throws {
        let harness = makeHarness()
        harness.type("ignored")
        try await settle()
        #expect(harness.recorder.texts.isEmpty)
        #expect(harness.model.bodyHTML.isEmpty)
    }

    @Test
    func defaultRendererProducesBodyHTMLWithSourcePositions() {
        #expect(MarkdownPreviewModel.renderBody("# Hi") == "<h1 id=\"hi\" md-src-pos=\"0..4\">Hi</h1>")
    }

    @Test
    func baseURLIsTheDirectoryOfTheDocument() throws {
        try withTempDir { directory in
            let file = directory.appending(path: "note.md")
            try "# Hi".write(to: file, atomically: true, encoding: .utf8)
            let document = try CodeFileDocument(for: file, withContentsOf: file, ofType: "public.source-code")
            let model = MarkdownPreviewModel(codeFile: document)
            #expect(model.baseURL?.standardizedFileURL.path == directory.standardizedFileURL.path)
        }
    }
}
