//
//  OpenQuicklyViewModel.swift
//  DreamderModules/QuickOpen
//
//  Created by Marco Carnevali on 05/04/22.
//

import Foundation
import CollectionConcurrencyKit

@Observable
final class OpenQuicklyViewModel {
    var query: String = ""
    var searchResults: [SearchResult] = []

    let fileURL: URL
    @ObservationIgnored var runningTask: Task<Void, Never>?
    @ObservationIgnored private var searchGeneration = 0

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// This is used to populate the ``OpenQuicklyListItemView`` view which shows the search results to the user.
    ///
    /// ``OpenQuicklyPreviewView`` also uses this to load the `fileUrl` for preview.
    struct SearchResult: Identifiable, Hashable {
        var id: String { fileURL.id }
        let fileURL: URL
        let matchedCharacters: [NSRange]

        // This custom Hashable implementation prevents the highlighted
        // selection from flickering when searching in 'Open Quickly'.
        // Before commit 0e28b382f59184b7ebe5a7c3295afa3655b7d4e7, only the fileURL
        // was retrieved from the search results and it worked as expected.
        //
        static func == (lhs: Self, rhs: Self) -> Bool { lhs.fileURL == rhs.fileURL }
        func hash(into hasher: inout Hasher) { hasher.combine(fileURL) }
    }

    func fetchResults() {
        searchGeneration += 1
        let generation = searchGeneration
        runningTask?.cancel()
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
        guard !trimmedQuery.isEmpty else {
            runningTask = nil
            searchResults = []
            return
        }

        let root = fileURL
        runningTask = Task.detached(priority: .userInitiated) {
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsPackageDescendants]
            )
            guard let filePaths = enumerator?.allObjects as? [URL], !Task.isCancelled else { return }
            let filteredFiles = filePaths.filter { url in
                (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
            }
            let fuzzySearchResults = await filteredFiles.fuzzySearch(query: trimmedQuery).concurrentMap {
                SearchResult(fileURL: $0.item, matchedCharacters: $0.result.matchedParts)
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard generation == self.searchGeneration else { return }
                self.searchResults = fuzzySearchResults
            }
        }
    }
}
