//
//  SearchIndexer+ProgressiveSearch.swift
//  Dreamder
//
//  Created by Tommy Ludwig on 18.11.23.
//

import Foundation

nonisolated extension SearchIndexer {
    /// Object representing the search results
    nonisolated public final class SearchResult: Sendable {
        /// The identifying url for the document
        let url: URL

        /// The search score for the document, higher means more relevant
        let score: Float

        init(url: URL, score: Float) {
            self.url = url
            self.score = score
        }
    }

    /// Start a progressive search
    public func progressiveSearch(
        query: String,
        options: SKSearchOptions = SKSearchOptions(kSKSearchOptionDefault)
    ) -> ProgressiveSearch {
        return ProgressiveSearch(options: options, index: self, query: query)
    }

    /// A class for creating and managing a progressive search.
    /// A search starts on creation and can be cancelled at any time.
    nonisolated public final class ProgressiveSearch: Sendable {
        /// A class representing the results of a search request.
        nonisolated public final class Results: Sendable {
            /// Create a search result
            ///
            /// - Parameters:
            ///   - moreResultsAvailable: A boolean indicating whether more search results are available
            ///   - results: The partial results for the search request
            public init(moreResultsAvailable: Bool, results: [SearchResult]) {
                self.moreResultsAvailable = moreResultsAvailable
                self.results = results
            }

            /// A boolean indicating whether more search results are available
            public let moreResultsAvailable: Bool

            /// The partial results for the search request
            public let results: [SearchResult]
        }

        private let options: SKSearchOptions
        private let index: SearchIndexer
        private let query: String
        private let searchID: Int?

        init(options: SKSearchOptions, index: SearchIndexer, query: String) {
            self.options = options
            self.index = index
            self.query = query
            self.searchID = index.withState { state -> Int? in
                guard let skIndex = state.index else {
                    return nil
                }
                let search = SKSearchCreate(skIndex, query as CFString, options).takeRetainedValue()
                let id = state.nextSearchID
                state.nextSearchID += 1
                state.searches[id] = search
                return id
            }
        }

        deinit {
            if let searchID {
                index.withState { state in
                    state.searches[searchID] = nil
                }
            }
        }

        /// Retrieves the next chunk of search results in a progressive search.
        ///
        /// - Parameters:
        ///   - limit: The maximum number of results to retrieve in each call. Defaults to 10.
        ///   - timeout: The duration to wait for the search to complete before stopping. Defaults to 1.0 seconds.
        ///
        /// - Returns: A tuple containing search results and information about the progress of the search.
        ///
        /// The function performs a progressive search,
        /// fetching the next set of results based on the specified limit and timeout.
        /// It uses the Search Kit framework to find matches, retrieve document URLs, and their corresponding scores.
        public func getNextSearchResultsChunk(
            limit: Int = 10,
            timeout: TimeInterval = 1.0
        ) -> (ProgressiveSearch.Results) {
            let noResults = Results(moreResultsAvailable: false, results: [])
            guard let searchID else {
                return noResults
            }

            return index.withState { state -> Results in
                guard let skIndex = state.index, let search = state.searches[searchID] else {
                    return noResults
                }

                var scores: [Float] = Array(repeating: 0.0, count: limit)
                var urls: [Unmanaged<CFURL>?] = Array(repeating: nil, count: limit)
                var documentIDs: [SKDocumentID] = Array(repeating: 0, count: limit)
                var foundCount = 0

                let hasMore = SKSearchFindMatches(search, limit, &documentIDs, &scores, timeout, &foundCount)
                SKIndexCopyDocumentURLsForDocumentIDs(skIndex, foundCount, &documentIDs, &urls)

                let partialResult: [SearchResult] = zip(urls[0..<foundCount], scores)
                    .compactMap { (cfurl, score) -> SearchResult? in
                        guard let url  = cfurl?.takeRetainedValue() as URL? else {
                            return nil
                        }

                        return SearchResult(url: url, score: score)
                    }

                return Results(moreResultsAvailable: hasMore, results: partialResult)
            }
        }

        /// Cancel an active search
        public func cancel() {
            guard let searchID else {
                return
            }
            index.withState { state in
                if let search = state.searches[searchID] {
                    SKSearchCancel(search)
                }
            }
        }
    }
}
