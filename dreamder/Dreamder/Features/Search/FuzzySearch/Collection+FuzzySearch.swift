//
//  Collection+FuzzySearch.swift
//  Dreamder
//
//  Created by Tommy Ludwig on 03.02.24.
//

import Foundation

nonisolated extension Collection where Iterator.Element: FuzzySearchable {
    /// Asynchronously performs a fuzzy search on a collection of elements conforming to FuzzySearchable.
    ///
    /// - Parameter query: The query string to match against the elements.
    ///
    /// - Returns: An array of tuples containing FuzzySearchMatchResult and the corresponding element.
    ///
    /// - Note: Because this is an extension on Collection and not only array,
    /// you can also use this on sets.
    @concurrent
    func fuzzySearch(query: String) async -> [(result: FuzzySearchMatchResult, item: Iterator.Element)] {
        let items = Array(self)
        let matches = await withTaskGroup(of: (Int, FuzzySearchMatchResult).self) { group in
            for (index, item) in items.enumerated() {
                group.addTask { (index, item.fuzzyMatch(query: query)) }
            }
            var collected: [(Int, FuzzySearchMatchResult)] = []
            collected.reserveCapacity(items.count)
            for await match in group {
                collected.append(match)
            }
            return collected
        }
        return matches
            .filter { $0.1.weight > 0 }
            .sorted { $0.1.weight > $1.1.weight }
            .map { (result: $0.1, item: items[$0.0]) }
    }
}
