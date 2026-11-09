import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension IslandsWorkspaceView {
    static func openDroppedFiles(_ providers: [NSItemProvider], in editorManager: EditorManager) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    return
                }

                Task { @MainActor in
                    let file = CEWorkspaceFile(url: url)
                    editorManager.activeEditor.openTab(file: file)
                }
            }
        }
        return true
    }

    static func recordWindowSize(closing object: Any?, window: NSWindow?, in workspace: WorkspaceDocument) {
        if let closingWindow = object as? NSWindow, window == closingWindow {
            workspace.addToWorkspaceState(
                key: .workspaceWindowSize,
                value: NSStringFromRect(closingWindow.frame)
            )
        }
    }

    static func refreshRemotesAndStashes(_ manager: SourceControlManager) async throws {
        try await manager.refreshRemotes()
        try await manager.refreshStashEntries()
    }

    static func refreshGitData(
        enabled: Bool,
        in workspace: WorkspaceDocument,
        refresh: (SourceControlManager) async throws -> Void = IslandsWorkspaceView.refreshRemotesAndStashes
    ) async {
        guard enabled, let sourceControlManager = workspace.sourceControlManager else { return }
        do {
            try await refresh(sourceControlManager)
        } catch {
            await sourceControlManager.showAlertForError(
                title: "Error refreshing Git data",
                error: error
            )
        }
    }

    static func syncCurrentBranch(_ enabled: Bool, in workspace: WorkspaceDocument) async {
        guard let sourceControlManager = workspace.sourceControlManager else { return }
        if enabled {
            await sourceControlManager.refreshCurrentBranch()
        } else {
            sourceControlManager.currentBranch = nil
        }
    }

    static func utilityWindow(showingOutput: Bool) -> ToolWindowID {
        showingOutput ? .run : .terminal
    }

    static func dropHandler(editorManager: EditorManager) -> ([NSItemProvider]) -> Bool {
        { openDroppedFiles($0, in: editorManager) }
    }

    static func branchSync(in workspace: WorkspaceDocument) -> (Bool, Bool) -> Void {
        { _, enabled in
            Task { await syncCurrentBranch(enabled, in: workspace) }
        }
    }
}
