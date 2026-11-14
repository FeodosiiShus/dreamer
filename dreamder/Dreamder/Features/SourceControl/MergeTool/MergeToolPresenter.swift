import AppKit
import Foundation

@MainActor
enum MergeToolPresenter {
    private static var conflictsWindows: [String: MergeConflictsWindowController] = [:]
    private static var revisionsWindows: [String: MergeRevisionsWindowController] = [:]

    private static func conflictsController(for workspace: WorkspaceDocument) -> MergeConflictsWindowController? {
        guard let manager = workspace.sourceControlManager else { return nil }
        return conflictsWindows[MergeConflictsCenter.workspaceKey(manager.workspaceURL)]
    }

    private static func revisionsController(
        for workspace: WorkspaceDocument,
        path: String?
    ) -> MergeRevisionsWindowController? {
        guard let manager = workspace.sourceControlManager else { return nil }
        let prefix = MergeConflictsCenter.workspaceKey(manager.workspaceURL) + "|"
        if let path {
            return revisionsWindows[prefix + path]
        }
        let matches = revisionsWindows.filter { $0.key.hasPrefix(prefix) }
        return matches.count == 1 ? matches.first?.value : nil
    }

    static func conflictsModel(for workspace: WorkspaceDocument) -> MergeConflictsViewModel? {
        conflictsController(for: workspace)?.model
    }

    static func conflictsWindow(for workspace: WorkspaceDocument) -> NSWindow? {
        conflictsController(for: workspace)?.window
    }

    static func revisionsModel(for workspace: WorkspaceDocument, path: String?) -> MergeRevisionsViewModel? {
        revisionsController(for: workspace, path: path)?.model
    }

    static func revisionsWindow(for workspace: WorkspaceDocument, path: String?) -> NSWindow? {
        revisionsController(for: workspace, path: path)?.window
    }

    static func activeWorkspace(
        keyWindow: NSWindow? = NSApp.keyWindow,
        mainWindow: NSWindow? = NSApp.mainWindow,
        orderedWindows: [NSWindow] = NSApp.orderedWindows
    ) -> WorkspaceDocument? {
        let controller = (keyWindow?.windowController as? DreamderWindowController)
            ?? (mainWindow?.windowController as? DreamderWindowController)
            ?? orderedWindows.lazy.compactMap { $0.windowController as? DreamderWindowController }.first
        return controller?.workspace
    }

    static func showConflictsForActiveWorkspace(resolve: () -> WorkspaceDocument?) {
        guard let workspace = resolve() else { return }
        showConflicts(workspace: workspace)
    }

    static func showConflicts(workspace: WorkspaceDocument) {
        guard let manager = workspace.sourceControlManager else { return }
        let key = MergeConflictsCenter.workspaceKey(manager.workspaceURL)

        if let controller = conflictsWindows[key], let window = controller.window {
            controller.reload()
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        guard let model = MergeConflictsViewModel(workspace: workspace) else { return }
        let controller = MergeConflictsWindowController(model: model)
        controller.onClose = {
            conflictsWindows[key] = nil
        }
        conflictsWindows[key] = controller
        controller.place(relativeTo: workspace.windowControllers.first?.window)
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func showMergeRevisions(workspace: WorkspaceDocument, path: String) {
        guard let manager = workspace.sourceControlManager, !path.isEmpty else { return }
        let key = MergeConflictsCenter.workspaceKey(manager.workspaceURL) + "|" + path

        if let controller = revisionsWindows[key], let window = controller.window {
            if !controller.model.isResultEdited {
                let model = controller.model
                Task { await model.load() }
            }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        guard let model = MergeRevisionsViewModel(workspace: workspace, path: path) else { return }
        let controller = MergeRevisionsWindowController(model: model)
        controller.onClose = { [weak manager] in
            revisionsWindows[key] = nil
            guard let manager else { return }
            Task { @MainActor in
                await MergeConflictsCenter.shared.refresh(manager: manager)
            }
        }
        revisionsWindows[key] = controller
        controller.place(relativeTo: workspace.windowControllers.first?.window)
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
