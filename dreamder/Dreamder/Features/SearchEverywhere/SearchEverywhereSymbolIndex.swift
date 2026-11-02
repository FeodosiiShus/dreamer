import Combine
import Foundation

@MainActor
final class SearchEverywhereSymbolIndex: ObservableObject {
    @Published private(set) var symbols: [SearchEverywhereSymbol] = []
    @Published private(set) var isBuilding = false

    private var indexedRoot: URL?
    private var buildTask: Task<Void, Never>?

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
