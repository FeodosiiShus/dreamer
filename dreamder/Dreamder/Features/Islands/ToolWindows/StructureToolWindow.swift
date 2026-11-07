import AppKit
import SwiftUI

struct StructureToolWindow: View {
    @Environment(WorkspaceDocument.self) private var workspace
    @Environment(ToolWindowManager.self) private var toolWindowManager

    @Service private var lspService: LSPService

    @State private var model = StructureViewModel()
    @State private var collapsed: Set<String> = []
    @State private var selection: String?
    @FocusState private var isFocused: Bool

    init() {}

    private var rows: [StructureRow] {
        StructureTreeBuilder.rows(nodes: model.nodes, collapsed: collapsed)
    }

    var body: some View {
        VStack(spacing: 0) {
            ToolWindowHeader(title: "Structure") {
                EmptyView()
            } actions: {
                ToolWindowActionButton(icon: "general/hide", help: "Hide") {
                    toolWindowManager.hide(.structure)
                }
            }

            if rows.isEmpty {
                emptyState
            } else {
                tree
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .onAppear {
            model.start(workspace: workspace, lspService: lspService)
        }
    }

    private var tree: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row in
                    symbolRow(row)
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
        VStack(spacing: 4) {
            Text(emptyTitle)
                .font(Islands.uiFont)
                .foregroundStyle(Islands.secondaryForeground)
            if let emptyMessage {
                Text(emptyMessage)
                    .font(Islands.smallFont)
                    .foregroundStyle(Islands.disabledForeground)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyTitle: String {
        if model.fileURL == nil {
            return "No file in editor"
        }
        if model.isLoading {
            return "Loading Symbols…"
        }
        return "No symbols found"
    }

    private var emptyMessage: String? {
        guard model.fileURL == nil else {
            guard !model.isLoading, !model.usesLanguageServer else { return nil }
            return "No language server is running for this file"
        }
        return "Open a file to see its structure"
    }

    private func symbolRow(_ row: StructureRow) -> some View {
        let node = row.node
        let isCollapsed = collapsed.contains(node.id)
        let isSelected = selection == node.id
        return HStack(spacing: 5) {
            if node.children.isEmpty {
                Color.clear
                    .frame(width: 12, height: 12)
            } else {
                Image(isCollapsed ? "general/chevronRight" : "general/chevronDown")
                    .resizable()
                    .frame(width: 12, height: 12)
                    .opacity(0.7)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        toggleCollapsed(node.id)
                    }
            }
            Image(node.kind.iconName)
                .resizable()
                .frame(width: 16, height: 16)
            Text(node.name)
                .font(Islands.uiFont)
                .foregroundStyle(Islands.foreground)
                .lineLimit(1)
            if let detail = node.detail, !detail.isEmpty {
                Text(detail)
                    .font(Islands.smallFont)
                    .foregroundStyle(Islands.secondaryForeground)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 4)
            Text("\(node.line)")
                .font(Islands.smallFont)
                .foregroundStyle(Islands.disabledForeground)
        }
        .padding(.leading, CGFloat(8 + row.depth * 14))
        .padding(.trailing, 8)
        .frame(height: Islands.listRowHeight)
        .background(
            RoundedRectangle(cornerRadius: Islands.rowRadius)
                .fill(isSelected ? Islands.selection : Color.clear)
                .padding(.horizontal, 4)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            isFocused = true
            selection = node.id
            navigate(to: node)
        }
    }

    private func toggleCollapsed(_ id: String) {
        if collapsed.contains(id) {
            collapsed.remove(id)
        } else {
            collapsed.insert(id)
        }
    }

    private func activateSelection() {
        guard let selection, let node = findNode(selection, in: model.nodes) else { return }
        navigate(to: node)
    }

    private func findNode(_ id: String, in nodes: [StructureNode]) -> StructureNode? {
        for node in nodes {
            if node.id == id {
                return node
            }
            if let match = findNode(id, in: node.children) {
                return match
            }
        }
        return nil
    }

    private func navigate(to node: StructureNode) {
        guard let fileURL = model.fileURL else { return }
        EditorLocationNavigation.open(
            fileURL: fileURL,
            line: node.line,
            column: node.column,
            workspace: workspace
        )
    }
}
