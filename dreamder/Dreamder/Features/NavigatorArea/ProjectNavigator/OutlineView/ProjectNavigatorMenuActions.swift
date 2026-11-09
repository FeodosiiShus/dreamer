//
//  ProjectNavigatorMenuActions.swift
//  Dreamder
//
//  Created by Leonardo Larrañaga on 10/11/24.
//

import AppKit
import SwiftUI

extension ProjectNavigatorMenu {
    /// - Returns: the currently selected `CEWorkspaceFile` items in the outline view.
    func selectedItems() -> Set<CEWorkspaceFile> {
        guard let outlineView = sender?.outlineView else { return [] }
        let selectedItems = Set(outlineView.selectedRowIndexes.compactMap {
            outlineView.item(atRow: $0) as? CEWorkspaceFile
        })

        /// Item that the user brought up the menu with...
        if let menuItem = outlineView.item(atRow: outlineView.clickedRow) as? CEWorkspaceFile {
            /// If the item is not in the set, just like in Xcode, only modify that item.
            if !selectedItems.contains(menuItem) {
                return Set([menuItem])
            }
        }

        return selectedItems
    }

    /// Verify if a folder can be made from selection by getting the amount of parents found in the selected items.
    /// If the amount of parents is equal to one, a folder can be made.
    func canCreateFolderFromSelection() -> Bool {
        var uniqueParents: Set<CEWorkspaceFile> = []
        for file in selectedItems() {
            if let parent = file.parent {
                uniqueParents.insert(parent)
            }
        }

        return uniqueParents.count == 1
    }

    /// Action that opens **Finder** at the items location.
    @objc
    func showInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting(selectedItems().map { $0.url })
    }

    /// Action that opens the item, identical to clicking it.
    @objc
    func openInTab() {
        guard let outlineView = sender?.outlineView else { return }
        let sortedItems = selectedItems().sorted { (item1, item2) -> Bool in
            /// Get the parents of both items.
            let parent1 = outlineView.parent(forItem: item1) as? CEWorkspaceFile
            let parent2 = outlineView.parent(forItem: item2) as? CEWorkspaceFile

            /// Compare by parent.
            if parent1 != parent2 {
                /// If the parents are different, use their row position in the outline view.
                return outlineView.row(forItem: parent1) < outlineView.row(forItem: parent2)
            } else {
                /// If both items have the same parent, sort them by name.
                return item1.name < item2.name
            }
        }

        /// Open the items in order.
        sortedItems.forEach { item in
            workspace?.editorManager?.openTab(item: item)
        }
    }

    @objc
    func openInNewWindow() {
        let files = selectedItems().filter { !$0.isFolder }.sorted { $0.url.path < $1.url.path }
        Task { await openInNewWindows(files) }
    }

    func openInNewWindows(_ files: [CEWorkspaceFile]) async {
        for file in files {
            do {
                try await DreamderDocumentController.shared.openInNewEditorWindow(file)
            } catch {
                presentError(error)
            }
        }
    }

    /// Action that opens in an external editor
    @objc
    func openWithExternalEditor() {
        for item in selectedItems().sorted(by: { $0.url.path < $1.url.path }) {
            guard !opensExternally(item) else { continue }
            let alert = NSAlert()
            alert.messageText = "Cannot open \"\(item.name)\" with an external application"
            alert.informativeText = "No application could open \(item.url.path(percentEncoded: false))."
            alert.addButton(withTitle: "Dismiss")
            alert.runModal()
        }
    }

    @objc
    func cutFiles() {
        sender?.cutToClipboard(selectedItemsInPathOrder())
    }

    @objc
    func copyFiles() {
        sender?.copyToClipboard(selectedItemsInPathOrder())
    }

    @objc
    func pasteFiles() {
        sender?.pasteFromClipboard(into: item)
    }

    @objc
    func newFile() {
        guard let item else { return }
        sender?.beginCreation(kind: .file, in: item)
    }

    /// Opens the rename file dialogue on the cell this was presented from.
    @objc
    func renameFile() {
        guard let newFile = workspace?.listenerModel.highlightedFileItem,
              let outlineView = sender?.outlineView else { return }
        let row = outlineView.row(forItem: newFile)
        guard row > 0,
              let cell = outlineView.view(
                atColumn: 0,
                row: row,
                makeIfNecessary: false
              ) as? ProjectNavigatorTableViewCell else {
            return
        }
        outlineView.window?.makeFirstResponder(cell.textField)
    }

    @objc
    func newFileFromClipboard() {
        guard let item, let text = sender?.clipboard.text else { return }
        sender?.beginCreation(kind: .file, in: item, contents: Data(text.utf8))
    }

    @objc
    func newFolder() {
        guard let item else { return }
        sender?.beginCreation(kind: .directory, in: item)
    }

    /// Creates a new folder with the items selected.
    @objc
    func newFolderFromSelection() {
        guard let workspace, let workspaceFileManager = workspace.workspaceFileManager else { return }

        let selectedItems = selectedItems()
        guard let parent = selectedItems.first?.parent else { return }

        /// Get 'New Folder' name.
        var newFolderURL = parent.url.appendingPathComponent("New Folder With Items", conformingTo: .folder)
        var folderNumber = 0
        while workspaceFileManager.fileManager.fileExists(atPath: newFolderURL.path) {
            folderNumber += 1
            newFolderURL = parent.url.appending(path: "New Folder With Items \(folderNumber)")
        }

        Task.immediate { [self] in
            do {
                for selectedItem in selectedItems where selectedItem.url != newFolderURL {
                    let destination = newFolderURL.appending(path: selectedItem.name)
                    let sourceURL = selectedItem.url
                    try await workspaceFileManager.move(file: selectedItem, to: destination)
                    sender?.retargetTabs(from: sourceURL, to: destination)
                }
            } catch {
                presentError(error)
            }

            reloadData()
        }
    }

    /// Action that moves the item to trash.
    @objc
    func trash() {
        do {
            try selectedItems().forEach { item in
                withAnimation {
                    sender?.closeTabs(under: item.url)
                }
                guard FileManager.default.fileExists(atPath: item.url.path) else {
                    // Was likely already trashed (eg selecting files in a folder and deleting the folder and files)
                    return
                }
                try workspace?.workspaceFileManager?.trash(file: item)
            }
            reloadData()
        } catch {
            presentError(error)
        }
    }

    /// Action that deletes the item immediately.
    @objc
    func delete() {
        do {
            let selectedItems = selectedItems()
            if selectedItems.count == 1 {
                try selectedItems.forEach { item in
                    try workspace?.workspaceFileManager?.delete(file: item, confirmDelete: confirmsDeletion)
                }
            } else {
                try workspace?.workspaceFileManager?.batchDelete(files: selectedItems, confirmDelete: confirmsDeletion)
            }

            withAnimation {
                for item in selectedItems where !item.doesExist {
                    sender?.closeTabs(under: item.url)
                }
            }

            reloadData()
        } catch {
            presentError(error)
        }
    }

    /// Action that duplicates the item
    @objc
    func duplicate() {
        do {
            try selectedItems().forEach { item in
                try workspace?.workspaceFileManager?.duplicate(file: item)
            }
            reloadData()
        } catch {
            presentError(error)
        }
    }

    @objc
    func sortByName() {
        applySort(.name)
    }

    @objc
    func sortByType() {
        applySort(.type)
    }

    @objc
    func showHistory() {
        workspace?.toolWindowManager.show(.git)
    }

    @objc
    func annotate() {
        guard let item, !item.isFolder, let editor = workspace?.editorManager?.activeEditor else { return }
        editor.openTab(file: item, asTemporary: false)
        if let tab = editor.tabs.first(where: { $0.file == item }) {
            toggleBlame(for: tab)
        }
    }

    @objc
    func rollback() {
        guard let item, let sourceControlManager = workspace?.sourceControlManager else { return }
        let url = item.url
        guard sender?.confirmRollback?(url) ?? confirmRollbackDialog(for: url) else { return }
        sourceControlManager.discardChanges(for: url)
    }

    /// Copies the absolute path of the selected files
    @objc
    func copyPath() {
        let paths = selectedItems().map { $0.url.standardizedFileURL.path }
        copyToPasteboard(paths)
    }

    /// Copies the relative path of the selected files
    @objc
    func copyRelativePath() {
        guard let rootPath = workspace?.workspaceFileManager?.folderUrl else {
            return
        }
        let paths = selectedItems().map { item -> String in
            let destinationComponents = item.url.standardizedFileURL.pathComponents
            let baseComponents = rootPath.standardizedFileURL.pathComponents

            // Find common prefix length
            var prefixCount = 0
            while prefixCount < min(destinationComponents.count, baseComponents.count)
                    && destinationComponents[prefixCount] == baseComponents[prefixCount] {
                prefixCount += 1
            }
            // Build the relative path
            let upPath = String(repeating: "../", count: baseComponents.count - prefixCount)
            let downPath = destinationComponents[prefixCount...].joined(separator: "/")
            return upPath + downPath
        }

        copyToPasteboard(paths)
    }

    func isAnnotating(_ file: CEWorkspaceFile) -> Bool {
        guard let tab = workspace?.editorManager?.activeEditor.tabs.first(where: { $0.file == file }) else {
            return false
        }
        return GitBlameCoordinator.coordinator(for: tab)?.isAnnotating == true
    }

    func toggleBlame(for tab: EditorInstance, attempts: Int = 20) {
        if toggleRegisteredBlame(for: tab) { return }
        blameRetry = Task { [self] in
            for _ in 0..<max(attempts, 0) {
                try? await Task.sleep(for: .milliseconds(50))
                if toggleRegisteredBlame(for: tab) { return }
            }
        }
    }

    private func toggleRegisteredBlame(for tab: EditorInstance) -> Bool {
        guard let coordinator = GitBlameCoordinator.coordinator(for: tab) else { return false }
        coordinator.toggleAnnotate()
        return true
    }

    private func applySort(_ mode: FolderSortMode) {
        guard let item, item.isFolder, let sender else { return }
        sender.sortModes.set(mode, for: item.url)
        sender.outlineView.reloadItem(item, reloadChildren: true)
    }

    private func confirmRollbackDialog(for url: URL) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Rollback Changes"
        alert.informativeText = "Revert all changes in \"\(url.lastPathComponent)\" to the last committed version?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Rollback")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func selectedItemsInPathOrder() -> [CEWorkspaceFile] {
        selectedItems().sorted { $0.url.path < $1.url.path }
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.addButton(withTitle: "Dismiss")
        alert.runModal()
    }

    private func copyToPasteboard(_ paths: [String]) {
        sender?.pasteboard.replaceContents(withText: paths.sorted().joined(separator: "\n"))
    }

    private func reloadData() {
        sender?.outlineView.reloadData()
    }
}
