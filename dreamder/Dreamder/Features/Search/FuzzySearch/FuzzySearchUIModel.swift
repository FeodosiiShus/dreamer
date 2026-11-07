//
//  FuzzySearchUIModel.swift
//  Dreamder
//
//  Created by Khan Winter on 8/14/25.
//

import Foundation
import AsyncAlgorithms
import Observation

@Observable
@MainActor
final class FuzzySearchUIModel<Element: FuzzySearchable> {
    var items: [Element]?

    @ObservationIgnored private var allItems: [Element] = []
    @ObservationIgnored private var textStream: AsyncStream<String>
    @ObservationIgnored private var textStreamContinuation: AsyncStream<String>.Continuation
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    init(debounceTime: Duration = .milliseconds(50)) {
        (textStream, textStreamContinuation) = AsyncStream<String>.makeStream()

        searchTask = Task { [weak self] in
            guard let self else { return }

            for await text in textStream.debounce(for: debounceTime) {
                await performSearch(query: text)
            }
        }
    }

    func searchTextUpdated(searchText: String, allItems: [Element]) {
        self.allItems = allItems
        textStreamContinuation.yield(searchText)
    }

    private func performSearch(query: String) async {
        guard !query.isEmpty else {
            items = nil
            return
        }

        let results = await allItems.fuzzySearch(query: query)
        items = results.map { $0.item }
    }

    deinit {
        textStreamContinuation.finish()
        searchTask?.cancel()
    }
}
