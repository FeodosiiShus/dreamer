import CodeEditSourceEditor
import Foundation

enum EditorLocationNavigation {
    @MainActor
    static func open(fileURL: URL, line: Int, column: Int, workspace: WorkspaceDocument) {
        guard let editorManager = workspace.editorManager else { return }
        let file = workspace.workspaceFileManager?.getFile(fileURL.path, createIfNotFound: true)
            ?? CEWorkspaceFile(url: fileURL)
        editorManager.openTab(item: file)

        let position = CursorPosition(line: max(line, 1), column: max(column, 1))
        let editor = editorManager.activeEditor
        if let instance = editor.tabs.first(where: {
            $0.file.url.standardizedFileURL == file.url.standardizedFileURL
        }) {
            instance.cursorPositions = [position]
        }
        editor.selectedTab?.cursorPositions = [position]
    }
}
