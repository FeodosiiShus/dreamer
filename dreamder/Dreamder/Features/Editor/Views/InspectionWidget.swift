import SwiftUI

struct InspectionWidget: View {
    let editor: Editor

    @Environment(WorkspaceDocument.self) private var workspace

    private var lspService: LSPService { .shared }

    var body: some View {
        InspectionWidgetContent(
            fileURL: editor.selectedTab?.file.url.standardizedFileURL,
            store: workspace.diagnosticsStore,
            lspService: lspService,
            toolWindowManager: workspace.toolWindowManager
        )
    }
}

struct InspectionWidgetContent: View {
    let fileURL: URL?

    let store: DiagnosticsStore
    let lspService: LSPService
    let toolWindowManager: ToolWindowManager

    @State private var isHovering = false

    private var counts: ProblemCounts {
        guard let fileURL else { return ProblemCounts() }
        return ProblemCounts.of(store.diagnostics(for: fileURL))
    }

    private var hasLanguageServer: Bool {
        guard let fileURL else { return false }
        return lspService.languageClient(forDocument: fileURL) != nil
    }

    var body: some View {
        if counts.errors > 0 || counts.warnings > 0 {
            chip {
                if counts.errors > 0 {
                    severity("status/error", count: counts.errors)
                }
                if counts.warnings > 0 {
                    severity("status/warning", count: counts.warnings)
                }
            }
            .onTapGesture(perform: showProblems)
            .help(counts.summary)
        } else if counts.total == 0, hasLanguageServer {
            chip {
                Image("general/greenCheckmark")
                    .resizable()
                    .frame(width: 16, height: 16)
            }
            .help("No problems found")
        }
    }

    private func severity(_ icon: String, count: Int) -> some View {
        HStack(spacing: 3) {
            Image(icon)
                .resizable()
                .frame(width: 14, height: 14)
            Text("\(count)")
                .font(Islands.smallFont)
                .foregroundStyle(Islands.secondaryForeground)
        }
    }

    private func chip(@ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 6, content: content)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: Islands.controlRadius)
                    .fill(isHovering ? Islands.actionHover : Color.white.opacity(0x10 / 255))
            )
            .contentShape(RoundedRectangle(cornerRadius: Islands.controlRadius))
            .onHover(perform: setHovering)
    }

    func showProblems() {
        toolWindowManager.show(.problems)
    }

    func setHovering(_ hovering: Bool) {
        isHovering = hovering
    }
}
