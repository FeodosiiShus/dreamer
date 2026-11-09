import Foundation
import Observation

nonisolated struct SearchEverywhereSymbolStore: Sendable {
    typealias PathKey = @Sendable (URL) -> String

    private(set) var symbolsByFile: [String: [SearchEverywhereSymbol]] = [:]
    private(set) var revision = 0
    private let pathKey: PathKey

    init(pathKey: @escaping PathKey = SearchEverywhereSymbolStore.workspacePathKey(of:)) {
        self.pathKey = pathKey
    }

    static func workspacePathKey(of url: URL) -> String {
        url.workspacePathKey
    }

    mutating func replace(with symbols: [SearchEverywhereSymbol]) {
        symbolsByFile = [:]
        insert(symbols)
        revision += 1
    }

    mutating func apply(scanned symbols: [SearchEverywhereSymbol], updated: [URL], removed: [URL]) {
        if !removed.isEmpty {
            let removedPaths = WorkspaceRemovedPaths(removed)
            for key in symbolsByFile.keys.filter(removedPaths.covers(key:)) {
                symbolsByFile[key] = nil
            }
        }
        for url in updated {
            symbolsByFile[pathKey(url)] = nil
        }
        insert(symbols)
        revision += 1
    }

    @concurrent
    func flattened() async -> [SearchEverywhereSymbol] {
        symbolsByFile.sorted { $0.key < $1.key }.flatMap(\.value)
    }

    private mutating func insert(_ symbols: [SearchEverywhereSymbol]) {
        var start = symbols.startIndex
        while start < symbols.endIndex {
            let url = symbols[start].url
            var end = symbols.index(after: start)
            while end < symbols.endIndex, symbols[end].url == url {
                end = symbols.index(after: end)
            }
            symbolsByFile[pathKey(url), default: []].append(contentsOf: symbols[start..<end])
            start = end
        }
    }
}

@Observable
@MainActor
final class SearchEverywhereSymbolIndex {
    private(set) var store: SearchEverywhereSymbolStore
    private(set) var isBuilding = false

    @ObservationIgnored private let scope: WorkspaceFileScope
    @ObservationIgnored private var task: Task<Void, Never>?

    init(scope: WorkspaceFileScope, store: SearchEverywhereSymbolStore = SearchEverywhereSymbolStore()) {
        self.scope = scope
        self.store = store
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
        store.replace(with: [])
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
        store.replace(with: scanned)
        isBuilding = false
    }

    private func apply(updated: [URL], removed: [URL]) async {
        let changed = await SearchEverywhereSymbolScanner.symbols(inChanged: updated, scope: scope)
        guard !Task.isCancelled else { return }
        store.apply(scanned: changed, updated: updated, removed: removed)
    }
}
