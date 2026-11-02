import AppKit
import Combine
import Foundation

@MainActor
final class MergeConflictsViewModel: ObservableObject {
    let workspace: WorkspaceDocument
    let repository: MergeConflictRepository

    @Published private(set) var entries: [MergeConflictEntry] = []
    @Published private(set) var context: MergeConflictContext?
    @Published private(set) var selectedPaths: Set<String> = []
    @Published private(set) var primaryPath: String?
    @Published private(set) var isBusy = false
    @Published private(set) var errorMessage: String?

    private var anchorPath: String?

    private let manager: SourceControlManager
    private var cancellable: AnyCancellable?

    init?(workspace: WorkspaceDocument) {
        guard let manager = workspace.sourceControlManager,
              let repository = MergeConflictRepository(workspace: workspace) else {
            return nil
        }
        self.workspace = workspace
        self.manager = manager
        self.repository = repository

        let key = MergeConflictsCenter.workspaceKey(manager.workspaceURL)
        let center = MergeConflictsCenter.shared
        center.monitor(manager)
        cancellable = center.$states
            .receive(on: RunLoop.main)
            .sink { [weak self] states in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let state = states[key]
                    self.entries = state?.entries ?? []
                    if let context = state?.context {
                        self.context = context
                    }
                    self.pruneSelection()
                }
            }

        Task { [weak self] in
            await self?.reload()
        }
    }

    var selectedEntries: [MergeConflictEntry] {
        entries.filter { selectedPaths.contains($0.path) }
    }

    var primaryEntry: MergeConflictEntry? {
        entries.first { $0.path == primaryPath } ?? selectedEntries.first
    }

    func isSelected(_ path: String) -> Bool {
        selectedPaths.contains(path)
    }

    var summary: String {
        if entries.isEmpty {
            return "All conflicts have been resolved"
        }
        return context?.summary ?? "The following files have conflicts:"
    }

    var yoursHeader: String {
        context?.yoursHeader ?? "Yours"
    }

    var theirsHeader: String {
        context?.theirsHeader ?? "Theirs"
    }

    var isEmpty: Bool { entries.isEmpty }

    var canAccept: Bool { !selectedEntries.isEmpty && !isBusy }

    var canMerge: Bool { primaryEntry != nil && !isBusy }

    func detail(for entry: MergeConflictEntry, choice: MergeSideChoice) -> String {
        entry.change(for: choice, swapsSides: context?.swapsSides ?? false).title
    }

    func reload() async {
        await MergeConflictsCenter.shared.refresh(manager: manager)
    }

    func accept(_ choice: MergeSideChoice) async {
        let targets = selectedEntries
        guard !targets.isEmpty, let context else { return }
        isBusy = true
        errorMessage = nil
        for entry in targets {
            do {
                try await repository.accept(choice, entry: entry, context: context)
            } catch {
                errorMessage = MergeToolErrorText.describe(error)
                break
            }
        }
        await reload()
        isBusy = false
    }

    func openMergeWindow() {
        guard let entry = primaryEntry else { return }
        MergeToolPresenter.showMergeRevisions(workspace: workspace, path: entry.path)
    }

    func select(_ path: String?, extending: Bool = false, toggling: Bool = false) {
        guard let path else {
            selectedPaths = []
            primaryPath = nil
            anchorPath = nil
            return
        }
        let index = entries.firstIndex { $0.path == path }
        if toggling {
            if selectedPaths.contains(path) {
                selectedPaths.remove(path)
                if primaryPath == path {
                    primaryPath = entries.first { selectedPaths.contains($0.path) }?.path
                }
            } else {
                selectedPaths.insert(path)
                primaryPath = path
            }
            anchorPath = path
            return
        }
        if extending, let index, let anchorPath,
           let anchorIndex = entries.firstIndex(where: { $0.path == anchorPath }) {
            let range = min(index, anchorIndex)...max(index, anchorIndex)
            selectedPaths = Set(entries[range].map(\.path))
            primaryPath = path
            return
        }
        selectedPaths = [path]
        primaryPath = path
        anchorPath = path
    }

    private func pruneSelection() {
        let paths = Set(entries.map(\.path))
        selectedPaths.formIntersection(paths)
        if let primaryPath, paths.contains(primaryPath) {
            return
        }
        primaryPath = selectedEntries.first?.path ?? entries.first?.path
        if let primaryPath {
            selectedPaths.insert(primaryPath)
            anchorPath = primaryPath
        } else {
            anchorPath = nil
        }
    }
}
