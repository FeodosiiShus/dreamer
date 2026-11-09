import Combine
import Foundation
import SwiftUI
import LanguageServerProtocol

@Observable
@MainActor
final class StructureViewModel {
    private(set) var nodes: [StructureNode] = []
    private(set) var fileURL: URL?
    private(set) var isLoading = false
    private(set) var usesLanguageServer = false
    private(set) var collapsed: Set<String> = []
    private(set) var selection: String?
    private(set) var focusRequests = 0
    private(set) var options: StructureViewOptions
    private(set) var scrollTarget: String?
    private(set) var scrollRequests = 0
    var filterText = ""

    var isFiltering: Bool {
        StructureTreeTransform.isFiltering(filterText)
    }

    var displayNodes: [StructureNode] {
        StructureTreeTransform.display(nodes: nodes, options: options, filter: filterText)
    }

    var rows: [StructureRow] {
        StructureTreeBuilder.rows(nodes: displayNodes, collapsed: collapsed, expandsAll: isFiltering)
    }

    typealias TextReader = @Sendable (URL) async -> String?
    typealias NodeBuilder = @Sendable (String, String) async -> [StructureNode]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored let readText: TextReader
    @ObservationIgnored let buildNodes: NodeBuilder
    @ObservationIgnored private var caretObservation: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        readText: @escaping TextReader = StructureViewModel.readTextFromDisk,
        buildNodes: @escaping NodeBuilder = StructureViewModel.fallbackNodes
    ) {
        self.defaults = defaults
        self.readText = readText
        self.buildNodes = buildNodes
        self.options = StructureViewOptions(defaults: defaults)
    }

    @concurrent
    static func readTextFromDisk(_ url: URL) async -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    @ObservationIgnored private(set) weak var workspace: WorkspaceDocument?
    @ObservationIgnored private weak var observedDocument: CodeFileDocument?
    @ObservationIgnored private var lspService: LSPService?
    @ObservationIgnored private var selectionObservation: Task<Void, Never>?
    @ObservationIgnored private var documentCancellable: AnyCancellable?
    @ObservationIgnored private var documentLoadObservation: Task<Void, Never>?
    @ObservationIgnored private(set) var requestTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    isolated deinit {
        selectionObservation?.cancel()
        caretObservation?.cancel()
        requestTask?.cancel()
        refreshTask?.cancel()
        documentLoadObservation?.cancel()
    }

    func start(workspace: WorkspaceDocument, lspService: LSPService) {
        guard self.workspace == nil else { return }
        self.workspace = workspace
        self.lspService = lspService
        guard let editorManager = workspace.editorManager else { return }
        selectionObservation = Task { [weak self] in
            for await _ in Observations({ editorManager.activeEditor.selectedTab }) {
                self?.scheduleRefresh()
            }
        }
        caretObservation = Task { [weak self] in
            for await _ in Observations({ editorManager.activeEditor.selectedTab?.cursorPositions }) {
                self?.syncSelectionToCaret()
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

    func toggleCollapsed(_ id: String) {
        if collapsed.contains(id) {
            collapsed.remove(id)
        } else {
            collapsed.insert(id)
        }
    }

    func toggleSortsAlphabetically() {
        options.sortsAlphabetically.toggle()
        options.save(to: defaults)
    }

    func toggleGroupsByKind() {
        options.groupsByKind.toggle()
        options.save(to: defaults)
    }

    func toggleAutoscrollFromSource() {
        options.autoscrollsFromSource.toggle()
        options.save(to: defaults)
        if options.autoscrollsFromSource {
            syncSelectionToCaret()
        }
    }

    func toggleAutoscrollToSource() {
        options.autoscrollsToSource.toggle()
        options.save(to: defaults)
    }

    func select(_ node: StructureNode, workspace: WorkspaceDocument) {
        focusRequests += 1
        selection = node.id
        if options.autoscrollsToSource, !node.isGroup {
            navigate(to: node, workspace: workspace)
        }
    }

    func activate(_ node: StructureNode, workspace: WorkspaceDocument) {
        focusRequests += 1
        selection = node.id
        if node.isGroup {
            toggleCollapsed(node.id)
        } else {
            navigate(to: node, workspace: workspace)
        }
    }

    func moveSelection(by delta: Int, workspace: WorkspaceDocument) {
        let visible = rows
        guard !visible.isEmpty else { return }
        let current = selection.flatMap { id in visible.firstIndex { $0.id == id } }
        let index = current.map { min(max($0 + delta, 0), visible.count - 1) } ?? (delta > 0 ? 0 : visible.count - 1)
        select(visible[index].node, workspace: workspace)
        requestScroll(to: visible[index].id)
    }

    func syncSelectionToCaret() {
        guard options.autoscrollsFromSource, let line = caretLine() else { return }
        let path = StructureBreadcrumbs.path(in: nodes, line: line)
        guard let target = path.last, let root = path.first else { return }
        if let selection,
           let selected = StructureTreeTransform.find(selection, in: nodes),
           selected.line == line {
            return
        }
        var expanded = Set(path.dropLast().map(\.id))
        expanded.insert(StructureTreeTransform.groupID(of: root))
        collapsed.subtract(expanded)
        selection = target.id
        requestScroll(to: target.id)
    }

    private func requestScroll(to id: String) {
        scrollTarget = id
        scrollRequests += 1
    }

    func apply(nodes: [StructureNode]) {
        self.nodes = nodes
        syncSelectionToCaret()
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
            documentLoadObservation?.cancel()
            documentLoadObservation = nil
            apply(nodes: [])
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
            apply(nodes: [])
            isLoading = false
            usesLanguageServer = false
            documentLoadObservation?.cancel()
            let file = tab.file
            documentLoadObservation = Task { [weak self] in
                for await loaded in Observations({ file.fileDocument }) where loaded != nil {
                    self?.scheduleRefresh()
                }
            }
            return
        }
        documentLoadObservation?.cancel()
        documentLoadObservation = nil
        loadSymbols(document: document, url: url, lspService: lspService)
    }

    private func loadSymbols(document: CodeFileDocument, url: URL, lspService: LSPService) {
        guard let client = lspService.languageClient(forDocument: url) else {
            usesLanguageServer = false
            isLoading = false
            requestTask = Task { [weak self] in
                await self?.applyFallback(document: document, url: url)
            }
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
                self.apply(nodes: symbols)
            } else {
                await self.applyFallback(document: document, url: url)
            }
        }
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
}
