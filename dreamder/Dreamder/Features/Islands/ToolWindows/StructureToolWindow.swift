import AppKit
import SwiftUI

struct StructureToolWindow: View {
    @Environment(WorkspaceDocument.self) private var workspace
    @Environment(ToolWindowManager.self) private var toolWindowManager

    private var lspService: LSPService { .shared }

    @State private var model: StructureViewModel

    init(model: StructureViewModel = StructureViewModel()) {
        self._model = State(initialValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            ToolWindowHeader(title: "Structure") {
                EmptyView()
            } actions: {
                StructureToggleButton(
                    icon: "general/autoscrollFromSource",
                    help: "Autoscroll from Source",
                    isOn: model.options.autoscrollsFromSource,
                    action: model.toggleAutoscrollFromSource
                )
                StructureToggleButton(
                    icon: "general/autoscrollToSource",
                    help: "Autoscroll to Source",
                    isOn: model.options.autoscrollsToSource,
                    action: model.toggleAutoscrollToSource
                )
                StructureToggleButton(
                    icon: "general/sortBy",
                    help: "Sort Alphabetically",
                    isOn: model.options.sortsAlphabetically,
                    action: model.toggleSortsAlphabetically
                )
                StructureToggleButton(
                    icon: "actions/groupByClass",
                    help: "Group by Kind",
                    isOn: model.options.groupsByKind,
                    action: model.toggleGroupsByKind
                )
                ToolWindowActionButton(icon: "general/hide", help: "Hide", action: toolWindowManager.hideCallback(for: .structure))
            }

            StructureFilterField(model: model, workspace: workspace, onSubmit: model.submission(workspace: workspace))

            if model.rows.isEmpty {
                emptyState
            } else {
                StructureTreeView(model: model, workspace: workspace)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .onAppear { model.start(workspace: workspace, lspService: lspService) }
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

    private var hasOnlyFilteredOutSymbols: Bool {
        model.isFiltering && !model.nodes.isEmpty
    }

    private var emptyTitle: String {
        if model.fileURL == nil {
            return "No file in editor"
        }
        if model.isLoading {
            return "Loading Symbols…"
        }
        if hasOnlyFilteredOutSymbols {
            return "No matching symbols"
        }
        return "No symbols found"
    }

    private var emptyMessage: String? {
        guard model.fileURL == nil else {
            guard !model.isLoading, !model.usesLanguageServer, !hasOnlyFilteredOutSymbols else { return nil }
            return "No language server is running for this file"
        }
        return "Open a file to see its structure"
    }
}
