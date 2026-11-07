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
    static func open(url: URL, position: CursorPosition) {
        guard let workspace = LSPDiagnosticsPublisher.workspace(containing: url) else { return }
        open(url: url, position: position, in: workspace)
    }

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
}

@MainActor
enum LSPNavigationCommands {
    static func goToDefinition(workspace: WorkspaceDocument?, typeDeclaration: Bool) {
        guard let workspace,
              let editorManager = workspace.editorManager,
              let tab = editorManager.activeEditor.selectedTab,
              let cursor = tab.cursorPositions.first,
              let lspService = ServiceContainer.resolve(.singleton, LSPService.self) else {
            return
        }
        let fileURL = tab.file.url
        guard let client = lspService.languageClient(forDocument: fileURL) else { return }
        let documentURI = fileURL.lspURI
        let position = Position(
            line: max(cursor.start.line, 1) - 1,
            character: max(cursor.start.column, 1) - 1
        )
        Task { @MainActor in
            var targets: [LSPDefinitionTarget] = []
            if typeDeclaration {
                let response = (try? await client.requestTypeDefinition(
                    for: documentURI,
                    position
                )) ?? nil
                targets = LSPDefinitionMapping.targets(from: response)
            }
            if targets.isEmpty {
                let response = (try? await client.requestGoToDefinition(
                    for: documentURI,
                    position: position
                )) ?? nil
                targets = LSPDefinitionMapping.targets(from: response)
            }
            guard let target = targets.first else { return }
            let targetURL = LSPDiagnosticMapping.fileURL(fromDocumentURI: target.uri) ?? fileURL
            let targetPosition = CursorPosition(
                line: Int(target.selectionRange.start.line) + 1,
                column: Int(target.selectionRange.start.character) + 1
            )
            LSPDefinitionNavigator.open(url: targetURL, position: targetPosition, in: workspace)
        }
    }
}
