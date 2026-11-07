//
//  DreamderWindowController+Toolbar.swift
//  Dreamder
//
//  Created by Daniel Zhu on 5/10/24.
//

import AppKit
import SwiftUI

extension DreamderWindowController {
    internal func setupToolbar() {
        configureWindowChrome()
        let toolbar = NSToolbar(identifier: "DreamderMainToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        self.window?.toolbar = toolbar
    }

    private func configureWindowChrome() {
        guard let window else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unifiedCompact
        window.backgroundColor = NSColor(Islands.frame)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .projectWidget,
            .vcsBranchWidget,
            .searchEverywhereWidget,
            .flexibleSpace,
            .runWidget,
            .settingsWidget
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .projectWidget,
            .vcsBranchWidget,
            .searchEverywhereWidget,
            .flexibleSpace,
            .runWidget,
            .settingsWidget
        ]
    }

    func toggleToolbar() {
        toolbarCollapsed.toggle()
        workspace?.addToWorkspaceState(key: .toolbarCollapsed, value: toolbarCollapsed)
        updateToolbarVisibility()
    }

    func updateToolbarVisibility() {
        if toolbarCollapsed {
            window?.titleVisibility = .visible
            window?.title = workspace?.workspaceFileManager?.folderUrl.lastPathComponent ?? "Empty"
            window?.titlebarSeparatorStyle = .none
            window?.backgroundColor = NSColor(Islands.frame)
            window?.toolbar = nil
        } else {
            window?.titleVisibility = .hidden
            setupToolbar()
        }
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case .projectWidget:
            return projectWidgetItem()
        case .vcsBranchWidget:
            return vcsBranchWidgetItem()
        case .searchEverywhereWidget:
            return searchEverywhereWidgetItem()
        case .runWidget:
            return runWidgetItem()
        case .settingsWidget:
            return settingsWidgetItem()
        default:
            return nil
        }
    }

    private func projectWidgetItem() -> NSToolbarItem? {
        guard let workspace else { return nil }
        return toolbarItem(
            identifier: .projectWidget,
            label: "Project",
            view: NSHostingView(rootView: ProjectToolbarWidget(workspace: workspace))
        )
    }

    private func vcsBranchWidgetItem() -> NSToolbarItem? {
        guard let workspace, let sourceControlManager = workspace.sourceControlManager else { return nil }
        return toolbarItem(
            identifier: .vcsBranchWidget,
            label: "Git Branch",
            view: NSHostingView(
                rootView: ToolbarBranchPicker(sourceControlManager: sourceControlManager)
                    .environment(workspace)
            )
        )
    }

    private func searchEverywhereWidgetItem() -> NSToolbarItem? {
        toolbarItem(
            identifier: .searchEverywhereWidget,
            label: "Search Everywhere",
            view: NSHostingView(rootView: SearchEverywhereToolbarWidget())
        )
    }

    private func runWidgetItem() -> NSToolbarItem? {
        guard let workspace, let taskManager = workspace.taskManager else { return nil }
        return toolbarItem(
            identifier: .runWidget,
            label: "Run",
            view: NSHostingView(
                rootView: RunToolbarWidget(taskManager: taskManager)
                    .environment(workspace)
            )
        )
    }

    private func settingsWidgetItem() -> NSToolbarItem? {
        toolbarItem(
            identifier: .settingsWidget,
            label: "Settings",
            view: NSHostingView(rootView: SettingsToolbarWidget())
        )
    }

    private func toolbarItem(
        identifier: NSToolbarItem.Identifier,
        label: String,
        view: NSView
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.isBordered = false
        item.visibilityPriority = .high
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentHuggingPriority(.required, for: .vertical)
        item.view = view
        if #available(macOS 26.0, *) {
            item.style = .plain
        }
        return item
    }
}
