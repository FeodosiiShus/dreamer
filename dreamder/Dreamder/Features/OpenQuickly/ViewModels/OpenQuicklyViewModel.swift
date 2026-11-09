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
    @ObservationIgnored let scope: WorkspaceFileScope
    @ObservationIgnored var runningTask: Task<Void, Never>?
    @ObservationIgnored private var searchGeneration = 0

    init(fileURL: URL, scope: WorkspaceFileScope? = nil) {
        self.fileURL = fileURL
        if let scope {
            self.scope = scope
        } else {
            let ownedScope = WorkspaceFileScope(rootURL: fileURL)
            ownedScope.startWatching()
            self.scope = ownedScope
        }
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

        let scope = scope
        runningTask = Task(priority: .userInitiated) { [self] in
            let results = await Self.search(scope: scope, query: trimmedQuery)
            guard !Task.isCancelled, generation == searchGeneration else { return }
            searchResults = results
        }
    }

    @concurrent
    private nonisolated static func search(scope: WorkspaceFileScope, query: String) async -> [SearchResult] {
        let files = await scope.enumerateFiles(limit: nil)
        guard !Task.isCancelled else { return [] }
        return await files.fuzzySearch(query: query).concurrentMap {
            SearchResult(fileURL: $0.item, matchedCharacters: $0.result.matchedParts)
        }
    }
}
