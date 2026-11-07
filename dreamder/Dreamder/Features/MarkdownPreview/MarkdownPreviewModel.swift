import Combine
import Foundation
import Observation

@Observable
final class MarkdownPreviewModel {
    nonisolated static let defaultDebounce: Duration = .milliseconds(20)

    private(set) var bodyHTML = ""

    @ObservationIgnored let baseURL: URL?

    @ObservationIgnored private let readText: () -> String
    @ObservationIgnored private let updates: AnyPublisher<Void, Never>
    @ObservationIgnored private let render: @Sendable (String) -> String
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private var subscription: AnyCancellable?
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var renderTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var isStarted = false

    init(
        text: @escaping () -> String,
        updates: AnyPublisher<Void, Never>,
        baseURL: URL?,
        debounce: Duration = MarkdownPreviewModel.defaultDebounce,
        clock: any Clock<Duration> = ContinuousClock(),
        render: @escaping @Sendable (String) -> String = MarkdownPreviewModel.renderBody
    ) {
        self.readText = text
        self.updates = updates
        self.baseURL = baseURL
        self.debounce = debounce
        self.clock = clock
        self.render = render
    }

    convenience init(
        codeFile: CodeFileDocument,
        render: @escaping @Sendable (String) -> String = MarkdownPreviewModel.renderBody
    ) {
        self.init(
            text: { [weak codeFile] in codeFile?.content?.string ?? "" },
            updates: codeFile.contentCoordinator.textUpdatePublisher,
            baseURL: codeFile.fileURL?.deletingLastPathComponent(),
            render: render
        )
    }

    isolated deinit {
        debounceTask?.cancel()
        renderTask?.cancel()
    }

    nonisolated static func renderBody(_ markdown: String) -> String {
        MarkdownHTMLRenderer.bodyHTML(from: markdown)
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        subscription = updates.sink { [weak self] _ in
            Task { @MainActor in self?.textDidChange() }
        }
        refresh()
    }

    func refresh() {
        debounceTask?.cancel()
        debounceTask = nil
        startRender()
    }

    private func textDidChange() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self, clock, debounce] in
            try? await clock.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            self?.startRender()
        }
    }

    private func startRender() {
        generation += 1
        let generation = generation
        let text = readText()
        let render = render
        renderTask?.cancel()
        renderTask = Task.detached(priority: .userInitiated) { [weak self] in
            let html = render(text)
            guard !Task.isCancelled else { return }
            await self?.apply(html, generation: generation)
        }
    }

    private func apply(_ html: String, generation: Int) {
        guard generation == self.generation, html != bodyHTML else { return }
        bodyHTML = html
    }
}
