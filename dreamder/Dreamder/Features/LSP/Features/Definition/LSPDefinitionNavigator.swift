import CodeEditSourceEditor
import Foundation
import LanguageServerProtocol

nonisolated struct LSPDefinitionTarget: Equatable, Sendable {
    let uri: String
    let range: LSPRange
    let selectionRange: LSPRange
}

nonisolated enum LSPDefinitionMapping {
    typealias LocationResponse = ThreeTypeOption<Location, [Location], [LocationLink]>

    static func targets(from response: LocationResponse?) -> [LSPDefinitionTarget] {
        switch response {
        case .some(.optionA(let location)):
            return [target(from: location.uri, range: location.range)]
        case .some(.optionB(let locations)):
            return locations.map { target(from: $0.uri, range: $0.range) }
        case .some(.optionC(let links)):
            return links.map {
                LSPDefinitionTarget(uri: $0.targetUri, range: $0.targetRange, selectionRange: $0.targetSelectionRange)
            }
        case .none:
            return []
        }
    }

    private static func target(from uri: String, range: LSPRange) -> LSPDefinitionTarget {
        LSPDefinitionTarget(uri: uri, range: range, selectionRange: range)
    }
}

@MainActor
enum LSPDefinitionNavigator {
    static func open(url: URL, position: CursorPosition, in workspace: WorkspaceDocument) {
        guard let editorManager = workspace.editorManager else { return }
        let file = workspace.workspaceFileManager?.getFile(url.path, createIfNotFound: true)
            ?? CEWorkspaceFile(url: url)
        editorManager.openTab(item: file)
        let editor = editorManager.activeEditor
        for tab in editor.tabs where tab.file.url.standardizedFileURL == file.url.standardizedFileURL {
            tab.cursorPositions = [position]
        }
        editor.selectedTab?.cursorPositions = [position]
    }

    static func jump(url: URL, position: CursorPosition) {
        guard let workspace = LSPDiagnosticsPublisher.workspace(containing: url) else { return }
        jump(url: url, position: position, in: workspace)
    }

    static func jump(url: URL, position: CursorPosition, in workspace: WorkspaceDocument) {
        EditorLocationHistoryRecorder.includeCurrentCommandAsNavigation(workspace: workspace)
        open(url: url, position: position, in: workspace)
    }

    static func jump(to destination: LSPNavigationDestination, in workspace: WorkspaceDocument) {
        jump(
            url: destination.fileURL,
            position: CursorPosition(line: destination.line, column: destination.column),
            in: workspace
        )
    }
}
