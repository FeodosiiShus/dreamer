import AppKit

extension ProjectNavigatorViewController {
    struct PendingCreation {
        let kind: NewItemKind
        let folder: CEWorkspaceFile
        let placeholder: CEWorkspaceFile
        let contents: Data?
    }

    static let placeholderName = ".dreamder-new-item"

    func containingFolder(of item: CEWorkspaceFile) -> CEWorkspaceFile? {
        item.isFolder ? item : item.parent
    }

    func beginCreation(kind: NewItemKind, in item: CEWorkspaceFile, contents: Data? = nil) {
        cancelCreation()
        guard let folder = containingFolder(of: item) else { return }
        let placeholder = CEWorkspaceFile(url: folder.url.appending(path: Self.placeholderName))
        placeholder.isFolder = kind == .directory
        placeholder.parent = folder
        pendingCreation = PendingCreation(kind: kind, folder: folder, placeholder: placeholder, contents: contents)

        expandParent(item: folder)
        outlineView.reloadItem(folder, reloadChildren: true)
        focusPendingCreation()
    }

    func focusPendingCreation() {
        guard let pendingCreation else { return }
        let row = outlineView.row(forItem: pendingCreation.placeholder)
        guard row >= 0 else { return }
        outlineView.scrollRowToVisible(row)
        shouldSendSelectionUpdate = false
        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        shouldSendSelectionUpdate = true
        let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: true) as? ProjectNavigatorTableViewCell
        outlineView.window?.makeFirstResponder(cell?.textField)
    }

    func creationErrorMessage(for name: String) -> String? {
        guard let pendingCreation, let validator = creationValidator(for: pendingCreation) else { return nil }
        return validator.errorMessage(for: name)
    }

    func cancelCreation() {
        guard let pendingCreation else { return }
        self.pendingCreation = nil
        outlineView.reloadItem(pendingCreation.folder, reloadChildren: true)
    }

    func commitCreation(named name: String) {
        guard let pending = pendingCreation, let workspace, let fileManager = workspace.workspaceFileManager,
              let validator = creationValidator(for: pending) else { return }
        pendingCreation = nil
        switch validator.plan(for: name) {
        case .failure(let error):
            outlineView.reloadItem(pending.folder, reloadChildren: true)
            presentCreationFailure(error.message(for: pending.kind), kind: pending.kind)
        case .success(let plan):
            do {
                let contents = initialContents(for: plan, pending: pending, rootURL: fileManager.folderUrl)
                let created = try fileManager.create(plan, contents: contents)
                outlineView.reloadItem(pending.folder, reloadChildren: true)
                workspace.listenerModel.highlightedFileItem = created
                if !created.isFolder {
                    workspace.editorManager?.openTab(item: created)
                }
                pendingReveal = created
                revealPendingItem()
            } catch {
                outlineView.reloadItem(pending.folder, reloadChildren: true)
                let alert = NSAlert(error: error)
                alert.addButton(withTitle: "Dismiss")
                alert.runModal()
            }
        }
    }

    private func initialContents(for plan: NewItemPlan, pending: PendingCreation, rootURL: URL) -> Data? {
        guard plan.kind == .file else { return nil }
        return pending.contents ?? FileTemplateStore(rootURL: rootURL).contents(
            forFileNamed: plan.target.lastPathComponent,
            in: plan.containingDirectory
        )
    }

    func revealPendingItem() {
        guard let item = pendingReveal else { return }
        if let parent = item.parent {
            expandParent(item: parent)
        }
        let row = outlineView.row(forItem: item)
        guard row >= 0 else { return }
        pendingReveal = nil
        outlineView.scrollRowToVisible(row)
        shouldSendSelectionUpdate = false
        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        shouldSendSelectionUpdate = true
    }

    func hasLoadingAncestor(_ item: CEWorkspaceFile) -> Bool {
        guard let pendingLoads = workspace?.workspaceFileManager?.pendingLoads else { return false }
        var ancestor = item.parent
        while let current = ancestor {
            if pendingLoads.contains(current.id) { return true }
            ancestor = current.parent
        }
        return false
    }

    private func creationValidator(for pending: PendingCreation) -> NewItemNameValidator? {
        guard let rootURL = workspace?.workspaceFileManager?.folderUrl else { return nil }
        return NewItemNameValidator(rootURL: rootURL, parentURL: pending.folder.url, kind: pending.kind)
    }

    private func presentCreationFailure(_ message: String, kind: NewItemKind) {
        let alert = NSAlert()
        alert.messageText = kind == .file ? "Cannot Create File" : "Cannot Create Directory"
        alert.informativeText = message
        alert.addButton(withTitle: "Dismiss")
        alert.runModal()
    }
}
