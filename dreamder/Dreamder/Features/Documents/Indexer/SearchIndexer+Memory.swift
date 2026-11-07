//
//  SearchIndexer+Memory.swift
//  Dreamder
//
//  Created by Tommy Ludwig on 18.11.23.
//

import Foundation
nonisolated extension SearchIndexer {
    /// Memory based indexing using NSMutable
    nonisolated public enum Memory {
        /// Create an indexer using a new data container for the store
        ///
        /// - Parameter properties: the properties for index creation
        /// - Returns: A new index object if successful, nil otherwise
        public static func create(properties: CreateProperties = CreateProperties()) -> SearchIndexer? {
            let data = NSMutableData()
            guard let skIndex = SKIndexCreateWithMutableData(
                data,
                nil,
                properties.indexType,
                properties.properties()
            ) else {
                return nil
            }
            return SearchIndexer(state: State(index: skIndex.takeUnretainedValue(), store: data))
        }

        /// Create an indexer using the data stored in 'data'.
        ///
        /// **NOTE** Makes a copy of the data first - does not work on a live Data object
        ///
        /// - Parameter data: The data to load as an index
        /// - Returns: A new index object if successful, nil otherwise
        public static func loadFromData(data: Data) -> SearchIndexer? {
            guard let rawData = (data as NSData).mutableCopy() as? NSMutableData,
                  let skIndex = SKIndexOpenWithMutableData(rawData, nil) else {
                return nil
            }
            return SearchIndexer(state: State(index: skIndex.takeUnretainedValue(), store: rawData))
        }
    }
}
