//
//  DreamderWindowControllerExtensions.swift
//  Dreamder
//
//  Created by Austin Condiff on 10/14/23.
//

import SwiftUI
import Observation

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
            id: "show_terminal_tool_window",
            command: { [weak self] in self?.workspace?.toolWindowManager.show(.terminal) }
        )

        registerTrustProjectCommand()
    }

    internal func listenToDocumentEdited(workspace: WorkspaceDocument) {
        guard let editorManager = workspace.editorManager else { return }
        documentEditedObservation?.cancel()
        documentEditedObservation = Task { [weak self] in
            for await hasEditedDocuments in Observations({ Self.hasEditedDocuments(in: editorManager) }) {
                self?.setDocumentEdited(hasEditedDocuments)
            }
        }
    }

    static func hasEditedDocuments(in editorManager: EditorManager) -> Bool {
        editorManager.editorLayout.gatherOpenFiles().contains { $0.fileDocument?.isEdited == true }
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
            settingsWindow.isReleasedWhenClosed = false
            self.workspaceSettingsWindow = settingsWindow
            let contentView = makeWorkspaceSettingsView()
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

    func makeWorkspaceSettingsView() -> CEWorkspaceSettingsView {
        CEWorkspaceSettingsView(dismiss: { [weak self] in self?.dismissWorkspaceSettings() })
    }

    func dismissWorkspaceSettings() {
        guard let workspaceSettingsWindow else { return }
        window?.endSheet(workspaceSettingsWindow)
    }
}

extension NSToolbarItem.Identifier {
    static let activityViewer: NSToolbarItem.Identifier = NSToolbarItem.Identifier("ActivityViewer")
    static let notificationItem = NSToolbarItem.Identifier("notificationItem")
}
