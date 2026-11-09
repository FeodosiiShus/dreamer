import Combine
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct MarkdownPreviewModelCoverageTests {
    @Test
    func aRenderThatIsCancelledWhileRunningNeverPublishesItsResult() async throws {
        let subject = PassthroughSubject<Void, Never>()
        let source = MarkdownTextSource("slow")
        let model = MarkdownPreviewModel(
            text: { source.value },
            updates: subject.eraseToAnyPublisher(),
            baseURL: nil,
            render: { text in
                if text == "slow" {
                    let clock = ContinuousClock()
                    let deadline = clock.now.advanced(by: .seconds(30))
                    while !Task.isCancelled, clock.now < deadline {}
                    return "<p>stale</p>"
                }
                return "<p>\(text)</p>"
            }
        )

        model.start()
        source.value = "fast"
        model.refresh()

        try await eventually { model.bodyHTML == "<p>fast</p>" }
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.bodyHTML == "<p>fast</p>")
    }

    @Test
    func aSupersededDebounceNeverRenders() async throws {
        let subject = PassthroughSubject<Void, Never>()
        let clock = TestClock()
        let source = MarkdownTextSource("first")
        let recorder = MarkdownRenderRecorder()
        let model = MarkdownPreviewModel(
            text: { source.value },
            updates: subject.eraseToAnyPublisher(),
            baseURL: nil,
            debounce: .milliseconds(20),
            clock: clock,
            render: { [recorder] text in recorder.render(text) }
        )
        model.start()
        try await eventually { model.bodyHTML == "<p>first</p>" }

        source.value = "second"
        subject.send()
        try await clock.waitForSleepers(1)
        source.value = "third"
        subject.send()
        try await Task.sleep(for: .milliseconds(100))
        try await clock.waitForSleepers(1)
        clock.advance(by: .milliseconds(20))

        try await eventually { model.bodyHTML == "<p>third</p>" }
        try await Task.sleep(for: .milliseconds(100))
        #expect(recorder.texts == ["first", "third"])
    }

    @Test
    func deallocatingTheModelCancelsItsPendingWork() async throws {
        weak var weakModel: MarkdownPreviewModel?
        let subject = PassthroughSubject<Void, Never>()
        let clock = TestClock()
        do {
            let model = MarkdownPreviewModel(
                text: { "text" },
                updates: subject.eraseToAnyPublisher(),
                baseURL: nil,
                clock: clock,
                render: { "<p>\($0)</p>" }
            )
            weakModel = model
            model.start()
            try await eventually { model.bodyHTML == "<p>text</p>" }
            subject.send()
            try await clock.waitForSleepers(1)
        }

        try await eventually { weakModel == nil }
        subject.send()
        try await Task.sleep(for: .milliseconds(50))
        #expect(weakModel == nil)
    }

    @Test
    func theDefaultRendererTurnsMarkdownIntoHTML() async throws {
        let subject = PassthroughSubject<Void, Never>()
        let model = MarkdownPreviewModel(
            text: { "# Hi" },
            updates: subject.eraseToAnyPublisher(),
            baseURL: nil
        )

        model.start()

        try await eventually { model.bodyHTML.contains("<h1") }
        #expect(model.bodyHTML.contains("Hi"))
    }

    @Test
    func aDocumentWithoutContentRendersEmptyText() async throws {
        let document = CodeFileDocument()
        document.content = nil
        let recorder = MarkdownRenderRecorder()
        let model = MarkdownPreviewModel(codeFile: document, render: { [recorder] in recorder.render($0) })

        model.start()

        try await eventually { recorder.texts == [""] }
        #expect(document.content == nil)
    }
}
