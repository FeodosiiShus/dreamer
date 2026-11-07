//
//  DreamderWindowControllerExtensions.swift
//  Dreamder
//
//  Created by Austin Condiff on 10/14/23.
//

import SwiftUI
import Combine

extension DreamderWindowController {
    /// These are example items that added as commands to command palette
    func registerCommands() {
        CommandManager.shared.addCommand(
            name: "Quick Open",
            title: "Quick Open",
            id: "quick_open",
            command: { [weak self] in self?.openQuickly(nil) }
        )

        CommandManager.shared.addCommand(
            name: "Toggle Project Tool Window",
            title: "Toggle Project Tool Window",
            id: "toggle_left_sidebar",
            command: { [weak self] in self?.toggleFirstPanel() }
        )

        CommandManager.shared.addCommand(
            name: "Toggle Terminal Tool Window",
            title: "Toggle Terminal Tool Window",
            id: "toggle_terminal_tool_window",
            command: { [weak self] in self?.toggleToolWindow(.terminal) }
        )

        CommandManager.shared.addCommand(
            name: "Hide All Tool Windows",
            title: "Hide All Tool Windows",
            id: "hide_all_tool_windows",
            command: { [weak self] in self?.hideAllToolWindows() }
        )

        CommandManager.shared.addCommand(
            name: "Show Terminal Tool Window",
            title: "Show Terminal Tool Window",
            id: "open.drawer",
            command: { [weak self] in self?.workspace?.toolWindowManager.show(.terminal) }
        )
    }

    // Listen to changes in all tabs/files
    internal func listenToDocumentEdited(workspace: WorkspaceDocument) {
        guard let editorManager = workspace.editorManager else { return }
        documentEditedObservation?.cancel()
        documentEditedObservation = Task { [weak self, weak workspace] in
            for await tabs in Observations({ editorManager.activeEditor.tabs }) {
                guard let self, let workspace else { return }
                self.subscribeToEditedDocuments(in: tabs, workspace: workspace)
                self.updateDocumentEdited(workspace: workspace)
            }
        }
    }

    private func subscribeToEditedDocuments(in tabs: some Sequence<Editor.Tab>, workspace: WorkspaceDocument) {
        cancellables.forEach { $0.cancel() }
        cancellables = tabs.map { tab in
            tab.file.fileDocumentPublisher
                .compactMap { $0?.isDocumentEditedPublisher }
                .switchToLatest()
                .sink { [weak self, weak workspace] isDocumentEdited in
                    guard let self, let workspace else { return }
                    if isDocumentEdited {
                        self.setDocumentEdited(true)
                        return
                    }
                    self.updateDocumentEdited(workspace: workspace)
                }
        }
    }

    // Recalculate documentEdited by checking if any tab/file is edited
    private func updateDocumentEdited(workspace: WorkspaceDocument) {
        let hasEditedDocuments = !(workspace
            .editorManager?
            .editorLayout
            .gatherOpenFiles()
            .filter({ $0.fileDocument?.isDocumentEdited == true })
            .isEmpty ?? true)
        self.setDocumentEdited(hasEditedDocuments)
    }

    @IBAction func openWorkspaceSettings(_ sender: Any) {
        guard let window = window,
              let workspace = workspace,
              let workspaceSettingsManager = workspace.workspaceSettingsManager,
              let taskManager = workspace.taskManager
        else { return }

        if let workspaceSettingsWindow, workspaceSettingsWindow.isVisible {
            workspaceSettingsWindow.makeKeyAndOrderFront(self)
        } else {
            let settingsWindow = NSWindow()
            self.workspaceSettingsWindow = settingsWindow
            let contentView = CEWorkspaceSettingsView(
                dismiss: { [weak self, weak settingsWindow] in
                    guard let settingsWindow else { return }
                    self?.window?.endSheet(settingsWindow)
                 }
            )
            .environment(workspaceSettingsManager)
            .environment(workspace)
            .environment(taskManager)

            settingsWindow.contentView = NSHostingView(rootView: contentView)
            settingsWindow.titlebarAppearsTransparent = true
            settingsWindow.setContentSize(NSSize(width: 515, height: 515))
            settingsWindow.setAccessibilityTitle("Workspace Settings")

            window.beginSheet(settingsWindow, completionHandler: nil)
        }
    }
}

extension NSToolbarItem.Identifier {
    static let toggleFirstSidebarItem: NSToolbarItem.Identifier = NSToolbarItem.Identifier("ToggleFirstSidebarItem")
    static let toggleLastSidebarItem: NSToolbarItem.Identifier = NSToolbarItem.Identifier("ToggleLastSidebarItem")
    static let stopTaskSidebarItem: NSToolbarItem.Identifier = NSToolbarItem.Identifier("StopTaskSidebarItem")
    static let startTaskSidebarItem: NSToolbarItem.Identifier = NSToolbarItem.Identifier("StartTaskSidebarItem")
    static let itemListTrackingSeparator = NSToolbarItem.Identifier("ItemListTrackingSeparator")
    static let branchPicker: NSToolbarItem.Identifier = NSToolbarItem.Identifier("BranchPicker")
    static let activityViewer: NSToolbarItem.Identifier = NSToolbarItem.Identifier("ActivityViewer")
    static let notificationItem = NSToolbarItem.Identifier("notificationItem")

    static let taskSidebarItem: NSToolbarItem.Identifier = NSToolbarItem.Identifier("TaskSidebarItem")
}
