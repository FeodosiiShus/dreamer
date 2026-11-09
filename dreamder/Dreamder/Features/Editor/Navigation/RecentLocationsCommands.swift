import Foundation

@MainActor
enum EditorLocationHistoryRecorder {
    static func includeCurrentCommandAsNavigation(workspace: WorkspaceDocument?) {
        guard let workspace else { return }
        RecentLocationsStore.shared.history(for: workspace).includeCurrentCommandAsNavigation()
    }
}

@MainActor
enum EditorLocationHistoryCommands {
    static func canGoBack(workspace: WorkspaceDocument?) -> Bool {
        guard let workspace else { return false }
        return RecentLocationsStore.shared.history(for: workspace).isBackAvailable
    }

    static func canGoForward(workspace: WorkspaceDocument?) -> Bool {
        guard let workspace else { return false }
        return RecentLocationsStore.shared.history(for: workspace).isForwardAvailable
    }

    static func goBack(workspace: WorkspaceDocument?) {
        guard let workspace else { return }
        RecentLocationsStore.shared.history(for: workspace).goBack()
    }

    static func goForward(workspace: WorkspaceDocument?) {
        guard let workspace else { return }
        RecentLocationsStore.shared.history(for: workspace).goForward()
    }
}
