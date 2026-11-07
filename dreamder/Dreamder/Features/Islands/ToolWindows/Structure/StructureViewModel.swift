import Combine
import Foundation
import LanguageServerProtocol

@Observable
@MainActor
final class StructureViewModel {
    private(set) var nodes: [StructureNode] = []
    private(set) var fileURL: URL?
    private(set) var isLoading = false
    private(set) var usesLanguageServer = false

    @ObservationIgnored private weak var workspace: WorkspaceDocument?
    @ObservationIgnored private weak var observedDocument: CodeFileDocument?
    @ObservationIgnored private var lspService: LSPService?
    @ObservationIgnored private var selectionObservation: Task<Void, Never>?
    @ObservationIgnored private var documentCancellable: AnyCancellable?
    @ObservationIgnored private var documentLoadCancellable: AnyCancellable?
    @ObservationIgnored private var requestTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    isolated deinit {
        selectionObservation?.cancel()
        requestTask?.cancel()
        refreshTask?.cancel()
    }

    func start(workspace: WorkspaceDocument, lspService: LSPService) {
        guard self.workspace == nil else { return }
        self.workspace = workspace
        self.lspService = lspService
        guard let editorManager = workspace.editorManager else { return }
        selectionObservation = Task { [weak self] in
            for await _ in Observations({ editorManager.activeEditor.selectedTab }) {
                guard !Task.isCancelled, let self else { return }
                self.scheduleRefresh()
            }
        }
    }

    func scheduleRefresh(delay: Duration = .milliseconds(120)) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    private func refresh() {
        requestTask?.cancel()
        requestTask = nil

        guard let workspace,
              let lspService,
              let editorManager = workspace.editorManager,
              let tab = editorManager.activeEditor.selectedTab else {
            observedDocument = nil
            documentCancellable = nil
            documentLoadCancellable = nil
            nodes = []
            fileURL = nil
            isLoading = false
            usesLanguageServer = false
            return
        }

        let url = tab.file.url.standardizedFileURL
        let document = tab.file.fileDocument
        fileURL = url
        observe(document: document)

        guard let document else {
            nodes = []
            isLoading = false
            usesLanguageServer = false
            documentLoadCancellable = tab.file.fileDocumentPublisher
                .sink { [weak self] loaded in
                    guard loaded != nil else { return }
                    self?.scheduleRefresh()
                }
            return
        }
        documentLoadCancellable = nil
        loadSymbols(document: document, url: url, lspService: lspService)
    }

    private func loadSymbols(document: CodeFileDocument, url: URL, lspService: LSPService) {
        guard let client = lspService.languageClient(forDocument: url) else {
            usesLanguageServer = false
            isLoading = false
            nodes = fallbackNodes(document: document, url: url)
            return
        }

        usesLanguageServer = true
        isLoading = true
        let uri = document.languageServerURI ?? url.lspURI
        requestTask = Task { [weak self] in
            let response = try? await client.requestSymbols(for: uri)
            guard !Task.isCancelled, let self else { return }
            guard self.activeURL() == url else { return }
            self.isLoading = false
            if let response, let symbols = StructureTreeBuilder.nodes(from: response) {
                self.nodes = symbols
            } else {
                self.nodes = self.fallbackNodes(document: document, url: url)
            }
        }
    }

    private func activeURL() -> URL? {
        workspace?.editorManager?.activeEditor.selectedTab?.file.url.standardizedFileURL
    }

    private func observe(document: CodeFileDocument?) {
        guard document !== observedDocument else { return }
        observedDocument = document
        documentCancellable = nil
        guard let document else { return }
        documentCancellable = document.contentCoordinator.textUpdatePublisher
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleRefresh(delay: .milliseconds(400))
                }
            }
    }

    private func fallbackNodes(document: CodeFileDocument, url: URL) -> [StructureNode] {
        let text = document.content?.string ?? (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let extracted = SymbolExtractor.symbols(in: text, fileExtension: url.pathExtension)
        return StructureTreeBuilder.nodes(from: extracted, text: text)
    }
}
