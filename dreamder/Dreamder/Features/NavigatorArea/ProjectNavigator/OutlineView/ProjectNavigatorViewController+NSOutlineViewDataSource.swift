//
//  ProjectNavigatorViewController+NSOutlineViewDataSource.swift
//  Dreamder
//
//  Created by Khan Winter on 7/13/24.
//

import AppKit

extension ProjectNavigatorViewController: NSOutlineViewDataSource {
    func visibleChildren(of item: CEWorkspaceFile) -> [CEWorkspaceFile] {
        let hidden = hiddenEntryNames
        if let cachedChildren = filteredContentChildren[item] {
            return sorted(cachedChildren.filter { !hidden.contains($0.name) }, in: item)
        }

        if let workspace, let children = workspace.workspaceFileManager?.childrenOfFile(item) {
            let visibleChildren = children.filter { !hidden.contains($0.name) }
            if !workspace.navigatorFilter.isEmpty || workspace.sourceControlFilter {
                let filteredChildren = visibleChildren.filter {
                    fileSearchMatches(
                        workspace.navigatorFilter,
                        for: $0,
                        sourceControlFilter: workspace.sourceControlFilter
                    )
                }

                filteredContentChildren[item] = filteredChildren
                return sorted(filteredChildren, in: item)
            }

            return sorted(visibleChildren, in: item)
        }

        return []
    }

    func outlineChildren(of item: CEWorkspaceFile) -> [CEWorkspaceFile] {
        var children = visibleChildren(of: item)
        if let pendingCreation, pendingCreation.folder == item {
            children.insert(pendingCreation.placeholder, at: 0)
        }
        return children
    }

    private func sorted(_ items: [CEWorkspaceFile], in folder: CEWorkspaceFile) -> [CEWorkspaceFile] {
        let mode = sortModes.mode(for: folder.url)
        let foldersOnTop = workspace?.sortFoldersOnTop ?? true
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
        let destParentURL = fileItemDestination.url

        for fileItemURL in fileItemURLS {
            let destURL = destParentURL.appending(path: fileItemURL.lastPathComponent)
            // cancel dropping file item on self or in parent directory
            if fileItemURL == destURL || fileItemURL == destParentURL {
                return false
            }

            // Needs to come before call to .removeItem or else race condition occurs
            let srcFileItem = workspace?.workspaceFileManager?.getFile(fileItemURL.path)
                ?? CEWorkspaceFile(url: URL(fileURLWithPath: fileItemURL.path))

            if CEWorkspaceFile.fileManager.fileExists(atPath: destURL.path) {
                let shouldReplace = confirmReplace?(fileItemURL.lastPathComponent)
                    ?? replaceFileDialog(fileName: fileItemURL.lastPathComponent)
                guard shouldReplace else {
                    return false
                }
                do {
                    try CEWorkspaceFile.fileManager.removeItem(at: destURL)
                } catch {
                    Self.logger.error("Failed to remove existing file: \(error.localizedDescription)")
                    return false
                }
            }
            if sourceOperationMask == .copy {
                self.copyFile(file: srcFileItem, to: destURL)
            } else {
                self.moveFile(file: srcFileItem, to: destURL)
            }
        }
        return true
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
