//
//  ProjectNavigatorViewController+NSOutlineViewDataSource.swift
//  Dreamder
//
//  Created by Khan Winter on 7/13/24.
//

import AppKit

extension ProjectNavigatorViewController: NSOutlineViewDataSource {
    func visibleChildren(of item: CEWorkspaceFile) -> [CEWorkspaceFile] {
        guard let workspace, let children = workspace.workspaceFileManager?.childrenOfFile(item) else { return [] }
        let hidden = hiddenEntryNames
        let shown = children.filter { !hidden.contains($0.name) && isShownByFilter($0) }
        return sorted(shown, in: item, foldersOnTop: workspace.sortFoldersOnTop)
    }

    func outlineChildren(of item: CEWorkspaceFile) -> [CEWorkspaceFile] {
        var children = visibleChildren(of: item)
        if let pendingCreation, pendingCreation.folder == item {
            children.insert(pendingCreation.placeholder, at: 0)
        }
        return children
    }

    private func sorted(
        _ items: [CEWorkspaceFile],
        in folder: CEWorkspaceFile,
        foldersOnTop: Bool
    ) -> [CEWorkspaceFile] {
        let mode = sortModes.mode(for: folder.url)
        return items.sorted {
            ProjectNavigatorSorter.areInIncreasingOrder($0, $1, mode: mode, foldersOnTop: foldersOnTop)
        }
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let item = item as? CEWorkspaceFile {
            return outlineChildren(of: item).count
        }
        return content.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let item = item as? CEWorkspaceFile {
            return outlineChildren(of: item)[index]
        }
        return content[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if let item = item as? CEWorkspaceFile {
            return item.isFolder && item != pendingCreation?.placeholder
        }
        return false
    }

    /// Write dragged file(s) to pasteboard
    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard let fileItem = item as? CEWorkspaceFile else { return nil }
        return fileItem.url as NSURL
    }

    /// Declare valid drop target
    func outlineView(
        _ outlineView: NSOutlineView,
        validateDrop info: NSDraggingInfo,
        proposedItem item: Any?,
        proposedChildIndex index: Int
    ) -> NSDragOperation {
        dropOperation(
            in: outlineView,
            proposedItem: item,
            proposedChildIndex: index,
            sourceOperationMask: info.draggingSourceOperationMask
        )
    }

    func dropOperation(
        in outlineView: NSOutlineView,
        proposedItem item: Any?,
        proposedChildIndex index: Int,
        sourceOperationMask: NSDragOperation
    ) -> NSDragOperation {
        guard let fileItem = item as? CEWorkspaceFile else { return [] }
        // -1 index indicates that we are hovering over a row in outline view (folder or file)
        if index == -1 {
            if !fileItem.isFolder {
                outlineView.setDropItem(fileItem.parent, dropChildIndex: index)
            }
            return sourceOperationMask == .copy ? .copy : .move
        }
        return []
    }

    /// Handle successful or unsuccessful drop
    func outlineView(
        _ outlineView: NSOutlineView,
        acceptDrop info: NSDraggingInfo,
        item: Any?,
        childIndex index: Int
    ) -> Bool {
        acceptDrop(
            of: info.draggingPasteboard.readObjects(forClasses: [NSURL.self])?.compactMap { $0 as? URL },
            sourceOperationMask: info.draggingSourceOperationMask,
            onto: item
        )
    }

    func acceptDrop(of droppedURLs: [URL]?, sourceOperationMask: NSDragOperation, onto item: Any?) -> Bool {
        guard let fileItemURLS = droppedURLs else { return false }

        guard let fileItemDestination = item as? CEWorkspaceFile else { return false }
        guard let manager = workspace?.workspaceFileManager else { return false }
        let destParentURL = fileItemDestination.url
        let copies = sourceOperationMask == .copy

        for fileItemURL in fileItemURLS {
            let destURL = destParentURL.appending(path: fileItemURL.lastPathComponent)
            if Self.url(fileItemURL, isWithin: destURL) || Self.url(destParentURL, isWithin: fileItemURL) {
                return false
            }

            let srcFileItem = manager.getFile(fileItemURL.path)
                ?? CEWorkspaceFile(url: URL(fileURLWithPath: fileItemURL.path))

            if manager.fileManager.fileExists(atPath: destURL.path) {
                let shouldReplace = confirmReplace?(fileItemURL.lastPathComponent)
                    ?? replaceFileDialog(fileName: fileItemURL.lastPathComponent)
                guard shouldReplace else {
                    return false
                }
                let replacement = DropReplacement(
                    file: srcFileItem,
                    source: fileItemURL,
                    destination: destURL,
                    copying: copies
                )
                guard replaceItem(replacement, manager: manager) else {
                    return false
                }
            } else if copies {
                self.copyFile(file: srcFileItem, to: destURL)
            } else {
                self.moveFile(file: srcFileItem, to: destURL)
            }
        }
        return true
    }

    struct DropReplacement {
        let file: CEWorkspaceFile
        let source: URL
        let destination: URL
        let copying: Bool
    }

    private func replaceItem(_ replacement: DropReplacement, manager: CEWorkspaceFileManager) -> Bool {
        let backup: URL
        do {
            backup = try ProjectNavigatorItemReplacement.setAside(replacement.destination, using: fileOperations)
        } catch {
            Self.logger.error("Failed to set the existing item aside: \(error.localizedDescription)")
            return false
        }
        if replacement.copying {
            copyFile(file: replacement.file, to: replacement.destination)
            finishReplacement(replacement, backup: backup, manager: manager)
        } else {
            Task.immediate { [self] in
                await performMove(file: replacement.file, to: replacement.destination, manager: manager)
                finishReplacement(replacement, backup: backup, manager: manager)
            }
        }
        return true
    }

    private func finishReplacement(_ replacement: DropReplacement, backup: URL, manager: CEWorkspaceFileManager) {
        let fileManager = manager.fileManager
        let transferred = replacement.copying
            ? fileManager.fileExists(atPath: replacement.destination.path)
            : !fileManager.fileExists(atPath: replacement.source.path)
        if transferred {
            ProjectNavigatorItemReplacement.discard(backup, using: fileOperations)
        } else {
            ProjectNavigatorItemReplacement.restore(backup, to: replacement.destination, using: fileOperations)
        }
        if let error = refresh(directories: [replacement.destination.deletingLastPathComponent()], in: manager) {
            showErrorAlert(error)
        }
    }

    func replaceFileDialog(fileName: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = """
        A file or folder with the name \(fileName) already exists in the destination folder. Do you want to replace it?
        """
        alert.informativeText = "This action is irreversible!"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
