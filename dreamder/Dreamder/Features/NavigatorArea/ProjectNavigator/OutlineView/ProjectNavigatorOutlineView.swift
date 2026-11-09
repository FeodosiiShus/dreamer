//
//  OutlineView.swift
//  Dreamder
//
//  Created by Lukas Pistrol on 05.04.22.
//

import SwiftUI

/// Wraps an ``OutlineViewController`` inside a `NSViewControllerRepresentable`
struct ProjectNavigatorOutlineView: NSViewControllerRepresentable {

    @Environment(WorkspaceDocument.self) private var workspace
    @Environment(EditorManager.self) private var editorManager

    @Environment(\.settingsStore) private var prefs

    var controllerReference: ProjectNavigatorControllerReference?

    typealias NSViewControllerType = ProjectNavigatorViewController

    func makeNSViewController(context: Context) -> ProjectNavigatorViewController {
        let controller = ProjectNavigatorViewController()
        controller.workspace = workspace
        controller.settings = prefs
        controller.iconColor = prefs.preferences.general.fileIconStyle
        controller.editor = editorManager.activeEditor
        workspace.workspaceFileManager?.addObserver(context.coordinator)

        context.coordinator.controller = controller
        controllerReference?.controller = controller

        return controller
    }

    func updateNSViewController(_ nsViewController: ProjectNavigatorViewController, context: Context) {
        nsViewController.iconColor = prefs.preferences.general.fileIconStyle
        nsViewController.rowHeight = Double(Islands.treeRowHeight)
        nsViewController.fileExtensionsVisibility = prefs.preferences.general.fileExtensionsVisibility
        nsViewController.shownFileExtensions = prefs.preferences.general.shownFileExtensions
        nsViewController.hiddenFileExtensions = prefs.preferences.general.hiddenFileExtensions
        /// if the window becomes active from background, it will restore the selection to outline view.
        nsViewController.updateSelection(itemID: workspace.editorManager?.activeEditor.selectedTab?.file.id)
        return
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(workspace)
    }

    class Coordinator: NSObject, CEWorkspaceFileManagerObserver {
        init(_ workspace: WorkspaceDocument) {
            self.workspace = workspace
            super.init()

            highlightObservation = Task { [weak self, weak workspace] in
                let highlightedFileItem = Observations({ [weak workspace] in
                    workspace?.listenerModel.highlightedFileItem
                })
                for await fileItem in highlightedFileItem {
                    guard let fileItem else {
                        continue
                    }
                    self?.controller?.reveal(fileItem)
                }
            }
            selectionObservation = Task { [weak self, weak workspace] in
                let selectedFileID = Observations({ [weak workspace] in
                    workspace?.editorManager?.activeEditor.selectedTab?.file.id
                })
                for await itemID in selectedFileID {
                    self?.controller?.updateSelection(itemID: itemID)
                }
            }
            filterObservation = Task { [weak self, weak workspace] in
                let filters = Observations({ [weak workspace] in
                    FilterState(
                        name: workspace?.navigatorFilter,
                        sourceControl: workspace?.sourceControlFilter,
                        sortFoldersOnTop: workspace?.sortFoldersOnTop
                    )
                })
                for await _ in filters {
                    self?.scheduleFilterReload()
                }
            }
        }

        private struct FilterState: Equatable {
            let name: String?
            let sourceControl: Bool?
            let sortFoldersOnTop: Bool?
        }

        var highlightObservation: Task<Void, Never>?
        var selectionObservation: Task<Void, Never>?
        var filterObservation: Task<Void, Never>?
        var filterReload: Task<Void, Never>?
        weak var workspace: WorkspaceDocument?
        weak var controller: ProjectNavigatorViewController?

        private func scheduleFilterReload() {
            filterReload?.cancel()
            filterReload = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                self?.controller?.handleFilterChange()
            }
        }

        func fileManagerUpdated(updatedItems: Set<CEWorkspaceFile>) {
            guard let outlineView = controller?.outlineView else { return }
            let selectedRows = outlineView.selectedRowIndexes.compactMap({ outlineView.item(atRow: $0) })

            // If some text view inside the outline view is first responder right now, push the update off
            // until editing is finished using the `shouldReloadAfterDoneEditing` flag.
            if outlineView.window?.firstResponder !== outlineView
                && outlineView.window?.firstResponder is NSTextView
                && (outlineView.window?.firstResponder as? NSView)?.isDescendant(of: outlineView) == true {
                controller?.shouldReloadAfterDoneEditing = true
            } else {
                for item in updatedItems {
                    outlineView.reloadItem(item, reloadChildren: true)
                }
            }

            // Restore selected items where the files still exist.
            let selectedIndexes = selectedRows.compactMap({ outlineView.row(forItem: $0) }).filter({ $0 >= 0 })
            controller?.shouldSendSelectionUpdate = false
            outlineView.selectRowIndexes(IndexSet(selectedIndexes), byExtendingSelection: false)
            controller?.shouldSendSelectionUpdate = true
            controller?.revealPendingItem()
        }

        isolated deinit {
            highlightObservation?.cancel()
            selectionObservation?.cancel()
            filterObservation?.cancel()
            filterReload?.cancel()
            workspace?.workspaceFileManager?.removeObserver(self)
        }
    }
}

@Observable
final class ProjectNavigatorControllerReference {
    @ObservationIgnored weak var controller: ProjectNavigatorViewController?
}
