import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation

extension SearchResultMatchModel {
    var replacementDisplay: String? {
        usage?.replacement.map { FileMatchSnapshot.displayText(for: $0) }
    }

    var replacementPreviewLine: String? {
        guard let display = replacementDisplay else { return nil }
        var line = lineContent
        line.replaceSubrange(keywordRange, with: display)
        return line
    }
}

@MainActor
enum FindNavigatorOpener {
    static let focusAttempts = 20
    static let focusRetryDelay: Duration = .milliseconds(25)

    static func resolve(_ file: CEWorkspaceFile, in workspace: WorkspaceDocument) -> CEWorkspaceFile {
        workspace.workspaceFileManager?.getFile(file.url.path(percentEncoded: false), createIfNotFound: true) ?? file
    }

    static func open(_ file: CEWorkspaceFile, in workspace: WorkspaceDocument) {
        workspace.editorManager?.openTab(item: resolve(file, in: workspace))
    }

    static func open(_ match: SearchResultMatchModel, in workspace: WorkspaceDocument) {
        guard let editorManager = workspace.editorManager else { return }
        let file = resolve(match.file, in: workspace)
        editorManager.openTab(item: file)
        guard let usage = match.usage else { return }

        let positions = [
            CursorPosition(
                start: CursorPosition.Position(line: usage.start.line, column: usage.start.column),
                end: CursorPosition.Position(line: usage.end.line, column: usage.end.column)
            )
        ]
        let editor = editorManager.activeEditor
        let target = file.url.standardizedFileURL
        if let instance = editor.tabs.first(where: { $0.file.url.standardizedFileURL == target }) {
            instance.cursorPositions = positions
        }
        editor.selectedTab?.cursorPositions = positions
    }

    static func focusEditor(in workspace: WorkspaceDocument) async {
        for _ in 0..<focusAttempts {
            let document = workspace.editorManager?.activeEditor.selectedTab?.file.fileDocument
            if let textView = document?.attachedTextView, let window = textView.window {
                window.makeFirstResponder(textView)
                return
            }
            try? await Task.sleep(for: focusRetryDelay)
        }
    }
}
