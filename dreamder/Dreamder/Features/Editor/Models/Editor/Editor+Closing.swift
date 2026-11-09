import Foundation

extension Editor {
    func closeConfirmedTab(file: CEWorkspaceFile, fromHistory: Bool) {
        if temporaryTab?.file == file {
            temporaryTab = nil
        }
        if !fromHistory {
            clearFuture()
        }
        if file != selectedTab?.file {
            addToHistory(EditorInstance(workspace: workspace, file: file))
        }
        removeTab(file)
        if let selectedTab {
            addToHistory(selectedTab)
        }
        guard !isDocumentShownElsewhere(file) else { return }
        file.fileDocument?.updateChangeCount(.changeCleared)
        if let codeFile = file.fileDocument {
            codeFile.close()
        }
        file.fileDocument = nil
    }

    private func isShownInAnotherEditor(_ file: CEWorkspaceFile) -> Bool {
        let siblings: [Editor]
        if let managed = workspace?.editorManager?.getFlattened(), managed.contains(where: { $0 === self }) {
            siblings = managed
        } else {
            siblings = parent?.getFlattened() ?? []
        }
        return siblings.contains { other in
            other !== self
                && (other.tabs.contains { $0.file == file } || other.temporaryTab?.file == file)
        }
    }

    func isDocumentShownElsewhere(_ file: CEWorkspaceFile) -> Bool {
        isShownInAnotherEditor(file) || file.fileDocument?.isInUse(outside: workspace) == true
    }
}
