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

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var caretObservation: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.options = StructureViewOptions(defaults: defaults)
    }

    @ObservationIgnored private weak var workspace: WorkspaceDocument?
    @ObservationIgnored private weak var observedDocument: CodeFileDocument?
    @ObservationIgnored private var lspService: LSPService?
    @ObservationIgnored private var selectionObservation: Task<Void, Never>?
    @ObservationIgnored private var documentCancellable: AnyCancellable?
    @ObservationIgnored private var documentLoadObservation: Task<Void, Never>?
    @ObservationIgnored private var requestTask: Task<Void, Never>?
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

    @discardableResult
    func activateSelection(workspace: WorkspaceDocument) -> KeyPress.Result {
        let displayed = displayNodes
        let selected = selection.flatMap { StructureTreeTransform.find($0, in: displayed) }
        let firstMatch = isFiltering ? rows.first { !$0.node.isGroup }?.node : nil
        if let node = selected ?? firstMatch {
            activate(node, workspace: workspace)
        }
        return .handled
    }

    func submission(workspace: WorkspaceDocument, then completion: @escaping () -> Void = {}) -> () -> Void {
        {
            self.activateSelection(workspace: workspace)
            completion()
        }
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

    private func caretLine() -> Int? {
        guard let tab = workspace?.editorManager?.activeEditor.selectedTab,
              tab.file.url.standardizedFileURL == fileURL,
              let position = tab.cursorPositions.first else { return nil }
        if position.start.line > 0 {
            return position.start.line
        }
        let text = tab.file.fileDocument?.content?.string ?? ""
        return StructureCaretLine.line(offset: position.range.location, in: text)
    }

    private func apply(nodes: [StructureNode]) {
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
            apply(nodes: fallbackNodes(document: document, url: url))
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
                self.apply(nodes: self.fallbackNodes(document: document, url: url))
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

    private func navigate(to node: StructureNode, workspace: WorkspaceDocument) {
        guard let fileURL else { return }
        EditorLocationNavigation.open(
            fileURL: fileURL,
            line: node.line,
            column: node.column,
            workspace: workspace
        )
    }
}
