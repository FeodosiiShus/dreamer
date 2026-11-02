import AppKit
import Combine
import Foundation

@MainActor
final class MergeConflictsCenter: ObservableObject {
    static let shared = MergeConflictsCenter()

    struct WorkspaceState: Equatable {
        var entries: [MergeConflictEntry] = []
        var context: MergeConflictContext?
    }

    @Published private(set) var states: [String: WorkspaceState] = [:]

    private final class Monitor {
        var cancellable: AnyCancellable?
        var task: Task<Void, Never>?
        var hasLoaded = false
        var lastHadConflicts = false
    }

    private var monitors: [String: Monitor] = [:]

    private init() {}

    func monitor(_ manager: SourceControlManager) {
        let key = Self.workspaceKey(manager.workspaceURL)
        guard monitors[key] == nil else { return }

        let monitor = Monitor()
        monitor.cancellable = manager.$changedFiles
            .receive(on: RunLoop.main)
            .sink { [weak self, weak manager] _ in
                MainActor.assumeIsolated {
                    guard let self, let manager else { return }
                    self.scheduleRefresh(manager: manager, allowAutoOpen: true)
                }
            }
        monitors[key] = monitor
        scheduleRefresh(manager: manager, allowAutoOpen: false)
    }

    func state(for rootURL: URL) -> WorkspaceState? {
        states[Self.workspaceKey(rootURL)]
    }

    func entries(for rootURL: URL) -> [MergeConflictEntry] {
        state(for: rootURL)?.entries ?? []
    }

    func hasConflicts(rootURL: URL) -> Bool {
        !entries(for: rootURL).isEmpty
    }

    func refresh(manager: SourceControlManager, allowAutoOpen: Bool = false) async {
        let key = Self.workspaceKey(manager.workspaceURL)
        let repository = MergeConflictRepository(gitClient: manager.gitClient, rootURL: manager.repositoryURL)
        let entries = await repository.entries()
        if Task.isCancelled {
            return
        }
        var context: MergeConflictContext?
        if !entries.isEmpty {
            context = await repository.context()
        }
        if Task.isCancelled {
            return
        }

        let monitor = monitors[key]
        let shouldAutoOpen = allowAutoOpen
            && (monitor?.hasLoaded ?? false)
            && (monitor?.lastHadConflicts ?? false) == false
            && !entries.isEmpty

        monitor?.hasLoaded = true
        monitor?.lastHadConflicts = !entries.isEmpty

        states[key] = WorkspaceState(entries: entries, context: context)

        if shouldAutoOpen {
            openConflictsWindow(for: manager)
        }
    }

    private func scheduleRefresh(manager: SourceControlManager, allowAutoOpen: Bool) {
        let key = Self.workspaceKey(manager.workspaceURL)
        guard let monitor = monitors[key] else { return }
        monitor.task?.cancel()
        monitor.task = Task { [weak self, weak manager] in
            guard let self, let manager else { return }
            await self.refresh(manager: manager, allowAutoOpen: allowAutoOpen)
        }
    }

    private func openConflictsWindow(for manager: SourceControlManager) {
        let workspace = NSDocumentController.shared.documents
            .compactMap { $0 as? WorkspaceDocument }
            .first { $0.sourceControlManager === manager }
        guard let workspace else { return }
        MergeToolPresenter.showConflicts(workspace: workspace)
    }

    static func workspaceKey(_ url: URL) -> String {
        url.absoluteURL.standardizedFileURL.path(percentEncoded: false)
    }
}
