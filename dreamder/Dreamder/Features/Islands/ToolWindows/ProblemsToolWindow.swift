import AppKit
import SwiftUI

struct ProblemsToolWindow: View {
    @Environment(WorkspaceDocument.self) private var workspace

    private var lspService: LSPService { .shared }

    init() {}

    var body: some View {
        ProblemsToolWindowContent(store: workspace.diagnosticsStore, lspService: lspService)
    }
}

@Observable
@MainActor
final class ProblemsToolWindowModel {
    enum Selection: Hashable {
        case file(URL)
        case diagnostic(WorkspaceDiagnostic)
    }

    var tab: ProblemsTab = .file
    private(set) var severityFilter = ProblemsSeverityFilter()
    private(set) var collapsedFiles: Set<URL> = []
    private(set) var selection: Selection?
    private(set) var focusRequests = 0

    func select(_ item: ProblemsTab) {
        tab = item
    }

    func toggleSeverity(_ group: ProblemSeverityGroup) {
        severityFilter = severityFilter.toggling(group)
    }

    func activation(workspace: WorkspaceDocument) -> () -> KeyPress.Result {
        { self.activateSelection(workspace: workspace) }
    }

    func opening(_ diagnostic: WorkspaceDiagnostic, fileURL: URL, workspace: WorkspaceDocument) -> () -> Void {
        { self.openDiagnostic(diagnostic, fileURL: fileURL, workspace: workspace) }
    }

    func pullProjectDiagnostics(
        workspace: WorkspaceDocument,
        lspService: LSPService,
        puller: WorkspaceDiagnosticsPuller
    ) async {
        guard tab == .project else { return }
        await puller.pullAll(service: lspService, workspace: workspace)
    }

    func selectFile(_ url: URL) {
        focusRequests += 1
        selection = .file(url)
    }

    func selectDiagnostic(_ diagnostic: WorkspaceDiagnostic) {
        focusRequests += 1
        selection = .diagnostic(diagnostic)
    }

    func toggleFile(_ url: URL) {
        selection = .file(url)
        toggleCollapsed(url)
    }

    func openDiagnostic(_ diagnostic: WorkspaceDiagnostic, fileURL: URL, workspace: WorkspaceDocument) {
        selection = .diagnostic(diagnostic)
        open(diagnostic, fileURL: fileURL, workspace: workspace)
    }

    func toggleCollapsed(_ url: URL) {
        if collapsedFiles.contains(url) {
            collapsedFiles.remove(url)
        } else {
            collapsedFiles.insert(url)
        }
    }

    @discardableResult
    func activateSelection(workspace: WorkspaceDocument) -> KeyPress.Result {
        switch selection {
        case .file(let url):
            EditorLocationNavigation.open(fileURL: url, line: 1, column: 1, workspace: workspace)
        case .diagnostic(let diagnostic):
            open(diagnostic, fileURL: diagnostic.fileURL, workspace: workspace)
        case nil:
            break
        }
        return .handled
    }

    private func open(_ diagnostic: WorkspaceDiagnostic, fileURL: URL, workspace: WorkspaceDocument) {
        EditorLocationNavigation.open(
            fileURL: fileURL,
            line: diagnostic.startLine + 1,
            column: diagnostic.startColumn + 1,
            workspace: workspace
        )
    }
}

struct ProblemsToolWindowContent: View {
    let store: DiagnosticsStore
    let lspService: LSPService
    let puller: WorkspaceDiagnosticsPuller

    @Environment(WorkspaceDocument.self) private var workspace
    @Environment(EditorManager.self) private var editorManager
    @Environment(ToolWindowManager.self) private var toolWindowManager

    @State private var model: ProblemsToolWindowModel
    @FocusState private var isFocused: Bool

    init(
        store: DiagnosticsStore,
        lspService: LSPService,
        model: ProblemsToolWindowModel = ProblemsToolWindowModel(),
        puller: WorkspaceDiagnosticsPuller = .shared
    ) {
        self.store = store
        self.lspService = lspService
        self.puller = puller
        self._model = State(initialValue: model)
    }

    private var activeFileURL: URL? {
        editorManager.activeEditor.selectedTab?.file.url.standardizedFileURL
    }

    private var root: URL? {
        workspace.workspaceFileManager?.folderUrl ?? workspace.fileURL
    }

    private var fileNodes: [ProblemFileNode] {
        guard let activeFileURL,
              let node = ProblemsTreeBuilder.node(
                  url: activeFileURL,
                  diagnostics: store.diagnostics(for: activeFileURL),
                  root: root,
                  filter: model.severityFilter
              ) else {
            return []
        }
        return [node]
    }

    private var projectNodes: [ProblemFileNode] {
        ProblemsTreeBuilder.instances(
            diagnosticsByFile: store.diagnosticsByFile,
            root: root,
            filter: model.severityFilter
        )
    }

    private var nodes: [ProblemFileNode] {
        switch model.tab {
        case .file: fileNodes
        case .project: projectNodes
        }
    }

    private var hasLanguageServer: Bool {
        guard let activeFileURL else { return false }
        return lspService.languageClient(forDocument: activeFileURL) != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            ToolWindowHeader(title: "Problems") {
                ForEach(ProblemsTab.allCases) { item in
                    ToolWindowTab(
                        title: item.title(count: count(for: item)),
                        icon: nil,
                        isSelected: item == model.tab,
                        action: bound(model.select, item)
                    )
                }
            } actions: {
                ForEach(ProblemSeverityGroup.allCases) { group in
                    ProblemSeverityToggle(
                        group: group,
                        isOn: model.severityFilter.isShown(group),
                        action: bound(model.toggleSeverity, group)
                    )
                }
                ToolWindowActionButton(icon: "general/hide", help: "Hide", action: toolWindowManager.hideCallback(for: .problems))
            }

            if nodes.isEmpty {
                emptyState
            } else {
                tree
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .task(id: model.tab) {
            await model.pullProjectDiagnostics(workspace: workspace, lspService: lspService, puller: puller)
        }
    }

    private var tree: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(nodes) { node in
                    fileRow(node)
                    if !model.collapsedFiles.contains(node.url) {
                        ForEach(node.diagnostics) { diagnostic in
                            diagnosticRow(diagnostic, fileURL: node.url)
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(.return, action: model.activation(workspace: workspace))
        .onChange(of: model.focusRequests) { isFocused = true }
    }

    private var emptyState: some View {
        let state: ProblemsEmptyState
        switch model.tab {
        case .file:
            state = ProblemsEmptyState.file(
                hasLanguageServer: hasLanguageServer,
                hasActiveFile: activeFileURL != nil
            )
        case .project:
            state = .project
        }
        return VStack(spacing: 4) {
            Text(state.primary)
                .font(Islands.uiFont)
                .foregroundStyle(Islands.secondaryForeground)
            if let secondary = state.secondary {
                Text(secondary)
                    .font(Islands.smallFont)
                    .foregroundStyle(Islands.disabledForeground)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func fileRow(_ node: ProblemFileNode) -> some View {
        let isCollapsed = model.collapsedFiles.contains(node.url)
        let isSelected = model.selection == .file(node.url)
        return HStack(spacing: 6) {
            Image(isCollapsed ? "general/chevronRight" : "general/chevronDown")
                .resizable()
                .frame(width: 12, height: 12)
                .opacity(0.7)
            Image(IntelliJIcon.fileIcon(for: node.name))
                .resizable()
                .frame(width: 16, height: 16)
            Text(node.name)
                .font(Islands.uiFont)
                .foregroundStyle(Islands.foreground)
                .lineLimit(1)
            if !node.directory.isEmpty {
                Text(node.directory)
                    .font(Islands.smallFont)
                    .foregroundStyle(Islands.secondaryForeground)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 8)
            Text("\(node.counts.total)")
                .font(Islands.smallFont)
                .foregroundStyle(Islands.secondaryForeground)
        }
        .padding(.horizontal, 8)
        .frame(height: Islands.listRowHeight)
        .background(
            RoundedRectangle(cornerRadius: Islands.rowRadius)
                .fill(isSelected ? Islands.selection : Color.clear)
                .padding(.horizontal, 4)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: bound(model.toggleFile, node.url))
        .onTapGesture(perform: bound(model.selectFile, node.url))
    }

    private func diagnosticRow(_ diagnostic: WorkspaceDiagnostic, fileURL: URL) -> some View {
        let isSelected = model.selection == .diagnostic(diagnostic)
        return HStack(spacing: 6) {
            Image(diagnostic.severity.iconName)
                .resizable()
                .frame(width: 14, height: 14)
            Text(diagnostic.message)
                .font(Islands.uiFont)
                .foregroundStyle(Islands.foreground)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Text(ProblemsTreeBuilder.location(for: diagnostic))
                .font(Islands.smallFont)
                .foregroundStyle(Islands.secondaryForeground)
            if let source = diagnostic.source, !source.isEmpty {
                Text(source)
                    .font(Islands.smallFont)
                    .foregroundStyle(Islands.disabledForeground)
                    .lineLimit(1)
            }
        }
        .padding(.leading, 32)
        .padding(.trailing, 8)
        .frame(height: Islands.listRowHeight)
        .background(
            RoundedRectangle(cornerRadius: Islands.rowRadius)
                .fill(isSelected ? Islands.selection : Color.clear)
                .padding(.horizontal, 4)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: model.opening(diagnostic, fileURL: fileURL, workspace: workspace))
        .onTapGesture(perform: bound(model.selectDiagnostic, diagnostic))
    }

    private func count(for tab: ProblemsTab) -> Int {
        let items = switch tab {
        case .file: fileNodes
        case .project: projectNodes
        }
        return items.reduce(0) { $0 + $1.counts.total }
    }
}

struct ProblemSeverityToggle: View {
    let group: ProblemSeverityGroup
    let isOn: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(group.iconName)
                .resizable()
                .frame(width: 14, height: 14)
                .opacity(isOn ? 1 : 0.35)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: Islands.controlRadius)
                        .fill(Self.background(isHovering: isHovering, isOn: isOn))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show \(group.title)")
        .onHover(perform: setHovering)
    }

    static func background(isHovering: Bool, isOn: Bool) -> Color {
        isHovering ? Islands.actionHover : (isOn ? Islands.selection : .clear)
    }

    func setHovering(_ hovering: Bool) {
        isHovering = hovering
    }
}
