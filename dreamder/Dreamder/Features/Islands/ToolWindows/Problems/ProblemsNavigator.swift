import Foundation

@MainActor
enum ProblemsNavigator {
    @discardableResult
    static func navigate(
        _ direction: ProblemsNavigation.Direction,
        workspace: WorkspaceDocument?,
        filter: ProblemsSeverityFilter = ProblemsSeverityFilter()
    ) -> WorkspaceDiagnostic? {
        guard let workspace else { return nil }
        let root = workspace.workspaceFileManager?.folderUrl ?? workspace.fileURL
        let nodes = ProblemsTreeBuilder.instances(
            diagnosticsByFile: workspace.diagnosticsStore.diagnosticsByFile,
            root: root,
            filter: filter
        )
        guard let target = ProblemsNavigation.target(
            direction,
            in: ProblemsNavigation.ordered(nodes),
            from: caret(in: workspace)
        ) else {
            return nil
        }
        EditorLocationNavigation.open(
            fileURL: target.fileURL,
            line: target.startLine + 1,
            column: target.startColumn + 1,
            workspace: workspace
        )
        return target
    }

    static func hasProblems(workspace: WorkspaceDocument?) -> Bool {
        guard let workspace else { return false }
        return !workspace.diagnosticsStore.diagnosticsByFile.isEmpty
    }

    static func caret(in workspace: WorkspaceDocument) -> ProblemCaret? {
        guard let tab = workspace.editorManager?.activeEditor.selectedTab,
              let start = tab.cursorPositions.first?.start,
              start.line > 0, start.column > 0 else {
            return nil
        }
        return ProblemCaret(fileURL: tab.file.url, line: start.line - 1, column: start.column - 1)
    }
}
