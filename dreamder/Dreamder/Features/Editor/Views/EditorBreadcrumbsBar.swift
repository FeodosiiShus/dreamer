import AppKit
import CodeEditSourceEditor
import Combine
import Observation
import SwiftUI

@Observable
@MainActor
final class EditorBreadcrumbsModel {
    private(set) var crumbs: [StructureNode] = []
    private(set) var hoveredCrumbID: String?

    @ObservationIgnored private var nodes: [StructureNode] = []
    @ObservationIgnored private var line = 1
    @ObservationIgnored private weak var document: CodeFileDocument?
    @ObservationIgnored private var url: URL?
    @ObservationIgnored private var lspService: LSPService?
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private var cursorObservation: Task<Void, Never>?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?

    isolated deinit {
        cursorObservation?.cancel()
        reloadTask?.cancel()
    }

    func hover(_ id: String, isHovering: Bool) {
        if isHovering {
            hoveredCrumbID = id
        } else if hoveredCrumbID == id {
            hoveredCrumbID = nil
        }
    }

    func bind(instance: EditorInstance, document: CodeFileDocument, lspService: LSPService) {
        guard document !== self.document else { return }
        cancellables.removeAll()
        cursorObservation?.cancel()
        reloadTask?.cancel()
        self.document = document
        self.url = instance.file.url.standardizedFileURL
        self.lspService = lspService
        nodes = []
        crumbs = []
        cursorObservation = Task { [weak self, weak instance] in
            let changes = Observations { [weak instance] in instance?.cursorPositions }
            for await positions in changes {
                guard let self, let position = positions?.first else { continue }
                self.line = self.line(for: position)
                self.updateCrumbs()
            }
        }
        document.contentCoordinator.textUpdatePublisher
            .sink { [weak self] _ in
                Task { @MainActor in self?.scheduleReload(delay: .milliseconds(400)) }
            }
            .store(in: &cancellables)
        scheduleReload(delay: .zero)
    }

    private func line(for position: CursorPosition) -> Int {
        if position.start.line > 0 {
            return position.start.line
        }
        guard let text = document?.content?.string else { return 1 }
        return StructureCaretLine.line(offset: position.range.location, in: text)
    }

    private func scheduleReload(delay: Duration) {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else { return }
            await self?.reload()
        }
    }

    private func reload() async {
        guard let document, let url else { return }
        if let client = lspService?.languageClient(forDocument: url), let uri = document.languageServerURI {
            let response = try? await client.requestSymbols(for: uri)
            guard !Task.isCancelled, document === self.document else { return }
            if let response, let symbols = StructureTreeBuilder.nodes(from: response) {
                apply(symbols)
                return
            }
        }
        let text = document.content?.string ?? ""
        let extracted = SymbolExtractor.symbols(in: text, fileExtension: url.pathExtension)
        apply(StructureTreeBuilder.nodes(from: extracted, text: text))
    }

    private func apply(_ nodes: [StructureNode]) {
        self.nodes = nodes
        updateCrumbs()
    }

    private func updateCrumbs() {
        let path = StructureBreadcrumbs.path(in: nodes, line: line)
        if path != crumbs {
            crumbs = path
        }
    }
}

struct EditorBreadcrumbsBar: View {
    private var lspService: LSPService { .shared }

    @Environment(ToolWindowManager.self) private var toolWindowManager

    let editorInstance: EditorInstance
    let codeFile: CodeFileDocument

    @Environment(WorkspaceDocument.self) private var workspace

    var body: some View {
        EditorBreadcrumbsBarContent(
            editorInstance: editorInstance,
            codeFile: codeFile,
            lspService: lspService,
            toolWindowManager: toolWindowManager,
            workspace: workspace
        )
    }
}

struct EditorBreadcrumbsBarContent: View {
    @State private var model: EditorBreadcrumbsModel

    let editorInstance: EditorInstance
    let codeFile: CodeFileDocument
    let lspService: LSPService
    let toolWindowManager: ToolWindowManager
    var pasteboard: any PasteboardAccess
    var workspace: WorkspaceDocument?

    init(
        editorInstance: EditorInstance,
        codeFile: CodeFileDocument,
        lspService: LSPService,
        toolWindowManager: ToolWindowManager,
        pasteboard: any PasteboardAccess = SystemPasteboard(),
        workspace: WorkspaceDocument? = nil,
        model: EditorBreadcrumbsModel = EditorBreadcrumbsModel()
    ) {
        self.editorInstance = editorInstance
        self.codeFile = codeFile
        self.lspService = lspService
        self.toolWindowManager = toolWindowManager
        self.pasteboard = pasteboard
        self.workspace = workspace
        self._model = State(initialValue: model)
    }

    private var items: [EditorBreadcrumbItem] {
        EditorBreadcrumbItem.items(url: editorInstance.file.url, symbols: model.crumbs)
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Image("general/chevronRight")
                        .resizable()
                        .frame(width: 12, height: 12)
                }
                crumb(item, isLast: index == items.count - 1)
            }
            Spacer(minLength: 0)
        }
        .font(Islands.uiFont)
        .padding(.horizontal, 10)
        .frame(height: Islands.statusBarHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Islands.glassBorder)
                .frame(height: 1)
        }
        .contextMenu(menuItems: contextMenuItems)
        .accessibilityIdentifier("EditorBreadcrumbs")
        .onAppear { bindModel() }
        .onChange(of: ObjectIdentifier(codeFile)) { _, _ in bindModel() }
    }

    @ViewBuilder func contextMenuItems() -> some View {
        Button("Show Structure Tool Window", action: showStructure)
        Button("Copy Path", action: copyPath)
    }

    private func crumb(_ item: EditorBreadcrumbItem, isLast: Bool) -> some View {
        Text(item.title)
            .foregroundStyle(isLast ? Islands.foreground : Islands.secondaryForeground)
            .lineLimit(1)
            .padding(.horizontal, 4)
            .frame(height: Islands.statusBarHeight - 8)
            .background(
                RoundedRectangle(cornerRadius: Islands.rowRadius)
                    .fill(model.hoveredCrumbID == item.id ? Islands.hover : Color.clear)
            )
            .contentShape(Rectangle())
            .onHover(perform: hoverAction(for: item))
            .onTapGesture(perform: tapAction(for: item))
            .accessibilityIdentifier("EditorBreadcrumb.\(item.id)")
    }

    func hoverAction(for item: EditorBreadcrumbItem) -> (Bool) -> Void {
        { isHovering in model.hover(item.id, isHovering: isHovering) }
    }

    func tapAction(for item: EditorBreadcrumbItem) -> () -> Void {
        { activate(item) }
    }

    func activate(_ item: EditorBreadcrumbItem) {
        switch item.target {
        case .folder:
            break
        case .file:
            openStructurePopup()
        case .symbol(let node):
            navigate(to: node)
        }
    }

    func navigate(to node: StructureNode) {
        editorInstance.cursorPositions = [CursorPosition(line: node.line, column: node.column)]
    }

    func openStructurePopup() {
        guard let controller = workspace?.windowControllers.compactMap({ $0 as? DreamderWindowController }).first
        else { return }
        StructurePopupHost.shared.show(in: controller)
    }

    func showStructure() {
        toolWindowManager.show(.structure)
    }

    func copyPath() {
        pasteboard.replaceContents(withText: editorInstance.file.url.path(percentEncoded: false))
    }

    func bindModel() {
        model.bind(instance: editorInstance, document: codeFile, lspService: lspService)
    }
}

nonisolated struct EditorBreadcrumbItem: Identifiable, Equatable, Sendable {
    enum Target: Equatable, Sendable {
        case folder
        case file
        case symbol(StructureNode)
    }

    let id: String
    let title: String
    let target: Target

    static func items(url: URL, symbols: [StructureNode]) -> [EditorBreadcrumbItem] {
        var result: [EditorBreadcrumbItem] = []
        let folder = url.deletingLastPathComponent().lastPathComponent
        if !folder.isEmpty, folder != "/" {
            result.append(EditorBreadcrumbItem(id: "path/folder", title: folder, target: .folder))
        }
        result.append(EditorBreadcrumbItem(id: "path/file", title: url.lastPathComponent, target: .file))
        result += symbols.map { EditorBreadcrumbItem(id: $0.id, title: $0.name, target: .symbol($0)) }
        return result
    }
}
