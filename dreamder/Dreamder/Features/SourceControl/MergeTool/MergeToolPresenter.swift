import AppKit
import Foundation

@MainActor
enum MergeToolPresenter {
    private static var conflictsWindows: [String: MergeConflictsWindowController] = [:]
    private static var revisionsWindows: [String: MergeRevisionsWindowController] = [:]
    private(set) static var lastConflictsKey: String?
    private(set) static var lastRevisionsKey: String?
    private(set) static var lastRevisionsPath: String?

    static var conflictsModel: MergeConflictsViewModel? {
        if let key = lastConflictsKey, let controller = conflictsWindows[key] {
            return controller.model
        }
        return conflictsWindows.values.first?.model
    }

    static var revisionsModel: MergeRevisionsViewModel? {
        if let key = lastRevisionsKey, let controller = revisionsWindows[key] {
            return controller.model
        }
        return revisionsWindows.values.first?.model
    }

    static var conflictsWindow: NSWindow? {
        if let key = lastConflictsKey, let controller = conflictsWindows[key] {
            return controller.window
        }
        return conflictsWindows.values.first?.window
    }

    static var revisionsWindow: NSWindow? {
        if let key = lastRevisionsKey, let controller = revisionsWindows[key] {
            return controller.window
        }
        return revisionsWindows.values.first?.window
    }

    static func conflictsModel(for workspace: WorkspaceDocument) -> MergeConflictsViewModel? {
        guard let manager = workspace.sourceControlManager else { return nil }
        return conflictsWindows[MergeConflictsCenter.workspaceKey(manager.workspaceURL)]?.model
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
            lastConflictsKey = key
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
        lastConflictsKey = key
        controller.place(relativeTo: workspace.windowControllers.first?.window)
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func showMergeRevisions(workspace: WorkspaceDocument, path: String) {
        guard let manager = workspace.sourceControlManager, !path.isEmpty else { return }
        let key = MergeConflictsCenter.workspaceKey(manager.workspaceURL) + "|" + path

        if let controller = revisionsWindows[key], let window = controller.window {
            lastRevisionsKey = key
            lastRevisionsPath = path
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
        lastRevisionsKey = key
        lastRevisionsPath = path
        controller.place(relativeTo: workspace.windowControllers.first?.window)
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
