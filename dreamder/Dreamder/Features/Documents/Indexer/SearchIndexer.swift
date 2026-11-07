//
//  SearchIndexer.swift
//  Dreamder
//
//  Created by Tom Ludwig on 18.11.23.
//

import Foundation
import Synchronization

/// Indexer using SKIndex
nonisolated public final class SearchIndexer: Sendable {
    struct State {
        var index: SKIndex?
        var store: NSMutableData?
        var fileURL: URL?
        var searches: [Int: SKSearch] = [:]
        var nextSearchID = 0
    }

    private let state: Mutex<State>

    init(state: sending State) {
        self.state = Mutex(state)
    }

    deinit {
        self.close()
    }

    func withState<R: Sendable>(_ body: (inout State) -> R) -> R {
        state.withLock { body(&$0) }
    }

    /// The file url where the index is located, nil for in-memory indexes
    public var fileURL: URL? {
        withState { $0.fileURL }
    }

    /// Returns a copy of the index as data, nil for indexes that are not memory based
    public func getAsData() -> Data? {
        flush()
        return withState { state -> Data? in
            state.store?.copy() as? Data
        }
    }

    /// Flush, compact, i.e. apply all changes and write the content of a file based index to the file
    public func save() {
        guard fileURL != nil else { return }
        flush()
        compact()
    }

    /// Flush any pending commands to the search index. Flush should always be called before performing a search
    public func flush() {
        withState { state in
            if let index = state.index {
                _ = SKIndexFlush(index)
            }
        }
    }

    /// Reduce the size of index where possible
    ///
    /// - Warning: Do NOT call on the main thread
    public func compact() {
        withState { state in
            if let index = state.index {
                _ = SKIndexCompact(index)
            }
        }
    }

    /// Remove any documents that have no search terms
    public func cleanUp() -> Int {
        let emptyDocumentURLs = self.fullDocuments(termState: .empty).map(\.url)
        var removedCount = 0
        for url in emptyDocumentURLs {
            _ = self.removeDocument(url: url)
            removedCount += 1
        }
        return removedCount
    }

    /// Close the index
    public func close() {
        withState { state in
            if let index = state.index {
                state.searches.removeAll()
                SKIndexClose(index)
                state.index = nil
            }
        }
    }

    private static let extractorsLoaded: Bool = {
        SKLoadDefaultExtractorPlugIns()
        return true
    }()

    /// Call  once at application launch to tell Search Kit to use the Spotlight metadata importers.
    var dataExtractorLoaded: Bool {
        Self.extractorsLoaded
    }

    /// Stop words for the index, 
    /// these are common words which should be ignored because they are not useful for searching
    static func stopWords(of index: SKIndex) -> Set<String> {
        guard let properties = SKIndexGetAnalysisProperties(index).takeUnretainedValue() as? [String: Any],
              let stopWords = properties[kSKStopWords as String] as? Set<String> else {
            return []
        }
        return stopWords
    }

    nonisolated public enum IndexType: UInt32 {
        /// Unknown index type (kSKIndexUnknown)
        case unknown = 0
        /// Inverted index, mapping terms to documents (kSKIndexInverted)
        case inverted = 1
        /// Vector index, mapping documents to terms (kSKIndexVector)
        case vector = 2
        /// Index type with all the capabilities of an inverted and a vector index (kSKIndexInvertedVector)
        case invertedVector = 3
    }

    /// A class for creating properties used in the creation of a Search Kit index.
    /// **Available Options:**
    /// - `indexType`: The type of the index to be created.
    ///     Options include `.unknown`, `.inverted`, `.vector` or `.invertedVector`
    /// - `proximityIndexing`: A Boolean flag indicating whether or not Search Kit should use proximity indexing.
    /// - `stopWords`: A set of stop-words — words not to index.
    /// - `minTermLength`: The minimum term length to index (defaults to 1).
    nonisolated public struct CreateProperties: Sendable {
        /// The type of the index to be created
        private(set) var indexType: SKIndexType = kSKIndexInverted
        /// Whether the index should use proximity indexing
        private(set) var proximityIndexing: Bool = false
        /// The stop words for the index
        private(set) var stopWords: Set<String> = Set<String>()
        /// The minimum size of word to add to the index
        private(set) var minTermLength: UInt = 1

        /// Create a properties object with the specified creation parameters
        ///
        /// - Parameters:
        ///   - indexType: The type of index
        ///   - proximityIndexing: A Boolean flag indicating whether or not Search Kit should use proximity indexing
        ///   - stopWords: A set of stop-words — words not to index
        ///   - minTermLength: The minimum term length to index (defaults to 1)
        public init(
            indexType: SearchIndexer.IndexType = .inverted,
            proximityIndexing: Bool = false,
            stopWords: Set<String> = [],
            minTermLength: UInt = 1
        ) {
            self.indexType = SKIndexType(indexType.rawValue)
            self.proximityIndexing = proximityIndexing
            self.stopWords = stopWords
            self.minTermLength = minTermLength
        }

        /// Returns a CFDictionary object to use for the call to SKIndexCreate
        func properties() -> CFDictionary {
            let properties: [CFString: Any] = [
                kSKProximityIndexing: self.proximityIndexing,
                kSKStopWords: self.stopWords,
                kSKMinTermLength: self.minTermLength,
            ]
            return properties as CFDictionary
        }
    }

}
