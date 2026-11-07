import Foundation
import Observation

@Observable
@MainActor
final class SearchEverywhereSymbolIndex {
    private(set) var symbols: [SearchEverywhereSymbol] = []
    private(set) var isBuilding = false

    @ObservationIgnored private var indexedRoot: URL?
    @ObservationIgnored private var buildTask: Task<Void, Never>?

    func ensureIndexed(root: URL) {
        if indexedRoot == root {
            return
        }
        rebuild(root: root)
    }

    func rebuild(root: URL) {
        buildTask?.cancel()
        indexedRoot = root
        symbols = []
        isBuilding = true
        buildTask = Task { [weak self] in
            let scanned = await SearchEverywhereSymbolScanner.scan(root: root)
            guard !Task.isCancelled else { return }
            self?.symbols = scanned
            self?.isBuilding = false
        }
    }
}
