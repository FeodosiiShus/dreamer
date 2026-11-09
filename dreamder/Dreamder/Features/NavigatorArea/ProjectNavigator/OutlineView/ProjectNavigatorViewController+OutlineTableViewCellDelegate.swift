//
//  OutlintViewController+OutlineTableViewCellDelegate.swift
//  Dreamder
//
//  Created by Ziyuan Zhao on 2023/2/5.
//

import Foundation
import AppKit

// MARK: - OutlineTableViewCellDelegate

extension ProjectNavigatorViewController: OutlineTableViewCellDelegate {
    func moveFile(file: CEWorkspaceFile, to destination: URL) {
        guard let manager = workspace?.workspaceFileManager else { return }
        Task.immediate { [self] in
            do {
                let sourceURL = file.url
                let moved = try await manager.move(file: file, to: destination)
                outlineView.reloadItem(file.parent, reloadChildren: true)
                retargetTabs(from: sourceURL, to: destination)
                let destinationPath = destination.path(percentEncoded: false)
                guard let newFile = moved ?? manager.getFile(destinationPath, createIfNotFound: true),
                      !newFile.isFolder else {
                    return
                }
                workspace?.listenerModel.highlightedFileItem = newFile
                workspace?.editorManager?.openTab(item: newFile)
            } catch {
                let alert = NSAlert(error: error)
                alert.addButton(withTitle: "Dismiss")
                alert.runModal()
            }
        }
    }

    func copyFile(file: CEWorkspaceFile, to destination: URL) {
        do {
            try workspace?.workspaceFileManager?.copy(file: file, to: destination)
        } catch {
            let alert = NSAlert(error: error)
            alert.addButton(withTitle: "Dismiss")
            alert.runModal()
        }
    }

    func cellDidFinishEditing() {
        guard shouldReloadAfterDoneEditing else { return }
        outlineView.reloadData()
    }
}
