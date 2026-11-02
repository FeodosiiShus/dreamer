import AppKit
import SwiftUI

struct ProblemsToolWindow: View {
    @EnvironmentObject private var workspace: WorkspaceDocument

    @Service private var lspService: LSPService

    init() {}

    var body: some View {
        ProblemsToolWindowContent(store: workspace.diagnosticsStore, lspService: lspService)
    }
}

struct ProblemsToolWindowContent: View {
    @ObservedObject var store: DiagnosticsStore
    @ObservedObject var lspService: LSPService

    @EnvironmentObject private var workspace: WorkspaceDocument
    @EnvironmentObject private var editorManager: EditorManager
    @EnvironmentObject private var toolWindowManager: ToolWindowManager

    @State private var tab: ProblemsTab = .file
    @State private var activeFileURL: URL?
    @State private var collapsedFiles: Set<URL> = []
    @State private var selection: ProblemsSelection?
    @FocusState private var isFocused: Bool

    private enum ProblemsSelection: Hashable {
        case file(URL)
        case diagnostic(WorkspaceDiagnostic)
    }

    private var root: URL? {
        workspace.workspaceFileManager?.folderUrl ?? workspace.fileURL
    }

    private var fileDiagnostics: [WorkspaceDiagnostic] {
        guard let activeFileURL else { return [] }
        return store.diagnostics(for: activeFileURL)
    }

    private var nodes: [ProblemFileNode] {
        switch tab {
        case .file:
            guard let activeFileURL,
                  let node = ProblemsTreeBuilder.node(
                      url: activeFileURL,
                      diagnostics: store.diagnostics(for: activeFileURL),
                      root: root
                  ) else {
                return []
            }
            return [node]
        case .project:
            return ProblemsTreeBuilder.instances(diagnosticsByFile: store.diagnosticsByFile, root: root)
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
                        isSelected: item == tab
                    ) {
                        tab = item
                    }
                }
            } actions: {
                ToolWindowActionButton(icon: "general/hide", help: "Hide") {
                    toolWindowManager.hide(.bottom)
                }
            }

            if nodes.isEmpty {
                emptyState
            } else {
                tree
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .onAppear {
            activeFileURL = editorManager.activeEditor.selectedTab?.file.url.standardizedFileURL
        }
        .onReceive(editorManager.tabBarTabIdSubject) { selectedTab in
            activeFileURL = selectedTab?.file.url.standardizedFileURL
        }
    }

    private var tree: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(nodes) { node in
                    fileRow(node)
                    if !collapsedFiles.contains(node.url) {
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
        .onKeyPress(.return) {
            activateSelection()
            return .handled
        }
    }

    private var emptyState: some View {
        let state: ProblemsEmptyState
        switch tab {
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
        let isCollapsed = collapsedFiles.contains(node.url)
        let isSelected = selection == .file(node.url)
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
        .onTapGesture(count: 2) {
            selection = .file(node.url)
            toggleCollapsed(node.url)
        }
        .onTapGesture {
            isFocused = true
            selection = .file(node.url)
        }
    }

    private func diagnosticRow(_ diagnostic: WorkspaceDiagnostic, fileURL: URL) -> some View {
        let isSelected = selection == .diagnostic(diagnostic)
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
        .onTapGesture(count: 2) {
            selection = .diagnostic(diagnostic)
            open(diagnostic, fileURL: fileURL)
        }
        .onTapGesture {
            isFocused = true
            selection = .diagnostic(diagnostic)
        }
    }

    private func toggleCollapsed(_ url: URL) {
        if collapsedFiles.contains(url) {
            collapsedFiles.remove(url)
        } else {
            collapsedFiles.insert(url)
        }
    }

    private func count(for tab: ProblemsTab) -> Int {
        switch tab {
        case .file:
            fileDiagnostics.count
        case .project:
            store.diagnosticsByFile.values.reduce(0) { $0 + $1.count }
        }
    }

    private func activateSelection() {
        guard let selection else { return }
        switch selection {
        case .file(let url):
            EditorLocationNavigation.open(fileURL: url, line: 1, column: 1, workspace: workspace)
        case .diagnostic(let diagnostic):
            open(diagnostic, fileURL: diagnostic.fileURL)
        }
    }

    private func open(_ diagnostic: WorkspaceDiagnostic, fileURL: URL) {
        EditorLocationNavigation.open(
            fileURL: fileURL,
            line: diagnostic.startLine + 1,
            column: diagnostic.startColumn + 1,
            workspace: workspace
        )
    }
}
