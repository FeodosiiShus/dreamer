import Foundation
import Observation

@Observable
@MainActor
final class SearchEverywhereSymbolIndex {
    private(set) var symbols: [SearchEverywhereSymbol] = []
    private(set) var isBuilding = false

    @ObservationIgnored private let scope: WorkspaceFileScope
    @ObservationIgnored private var task: Task<Void, Never>?

    init(scope: WorkspaceFileScope) {
        self.scope = scope
    }

    isolated deinit {
        task?.cancel()
    }

    func ensureIndexed() {
        guard task == nil else { return }
        start()
    }

    func rebuild() {
        task?.cancel()
        start()
    }

    private func start() {
        let scope = scope
        let changes = scope.changes()
        symbols = []
        isBuilding = true
        task = Task { [weak self] in
            let scanned = await SearchEverywhereSymbolScanner.scan(scope: scope)
            guard !Task.isCancelled else { return }
            self?.finishBuild(with: scanned)
            for await change in changes {
                guard !Task.isCancelled, let self else { return }
                switch change {
                case .reset:
                    self.rebuild()
                    return
                case .delta(let updated, let removed):
                    await self.apply(updated: updated, removed: removed)
                }
            }
        }
    }

    private func finishBuild(with scanned: [SearchEverywhereSymbol]) {
        symbols = scanned
        isBuilding = false
    }

    private func apply(updated: [URL], removed: [URL]) async {
        let changed = await SearchEverywhereSymbolScanner.symbols(inChanged: updated, scope: scope)
        guard !Task.isCancelled else { return }
        let removedPaths = WorkspaceRemovedPaths(removed)
        let updatedKeys = Set(updated.map(\.workspacePathKey))
        symbols.removeAll { removedPaths.covers($0.url) || updatedKeys.contains($0.url.workspacePathKey) }
        symbols.append(contentsOf: changed)
    }
}
