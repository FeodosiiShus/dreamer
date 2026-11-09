import AppKit
import Foundation

@Observable
@MainActor
final class MergeConflictsCenter {
    static let shared = MergeConflictsCenter()

    struct WorkspaceState: Equatable {
        var entries: [MergeConflictEntry]
        var context: MergeConflictContext?
    }

    private(set) var states: [String: WorkspaceState] = [:]

    private final class Monitor {
        var observation: Task<Void, Never>?
        var task: Task<Void, Never>?
        var hasLoaded = false
        var lastHadConflicts = false
    }

    @ObservationIgnored private var monitors: [String: Monitor] = [:]
    @ObservationIgnored private let makeRepository: @MainActor (SourceControlManager) -> MergeConflictRepository

    init(
        makeRepository: @escaping @MainActor (SourceControlManager) -> MergeConflictRepository = {
            MergeConflictRepository(gitClient: $0.gitClient, rootURL: $0.repositoryURL)
        }
    ) {
        self.makeRepository = makeRepository
    }

    func monitor(_ manager: SourceControlManager) {
        let key = Self.workspaceKey(manager.workspaceURL)
        guard monitors[key] == nil else { return }

        let monitor = Monitor()
        monitor.observation = Task { [weak self, weak manager] in
            for await _ in Observations({ [weak manager] in _ = manager?.changedFiles }) {
                guard let self, let manager else { return }
                scheduleRefresh(manager: manager, allowAutoOpen: true)
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
        let repository = makeRepository(manager)
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
            && monitor?.hasLoaded == true
            && monitor?.lastHadConflicts != true
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
        monitors[key]?.task?.cancel()
        monitors[key]?.task = Task { [weak self, weak manager] in
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
