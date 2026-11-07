//
//  SearchIndexer+File.swift
//  Dreamder
//
//  Created by Tommy Ludwig on 18.11.23.
//

import Foundation

nonisolated extension SearchIndexer {
    /// A file based index
    nonisolated public enum File {
        /// Open an index from a file url.
        ///
        /// - Parameters:
        ///   - fileURL: The file url to open
        ///   - writable: should the index be modifiable?
        /// - Returns: A new index object if successful, nil otherwise
        public static func openIndex(fileURL: URL, writeable: Bool) -> SearchIndexer? {
            guard let skIndex = SKIndexOpenWithURL(fileURL as CFURL, nil, writeable) else {
                return nil
            }
            return SearchIndexer(state: State(index: skIndex.takeUnretainedValue(), fileURL: fileURL))
        }

        /// Create an indexer using a new data container for the store
        ////
        /// - Parameters:
        ///    - fileURL: the file URL to store the index at.  url must be a non-existent file
        ///    - properties: the properties for index creation
        /// - Returns: A new index object if successful, nil otherwise. Returns nil if the file already exists at url.
        public static func create(
            fileURL: URL,
            properties: CreateProperties = CreateProperties()
        ) -> SearchIndexer? {
            guard !FileManager.default.fileExists(atPath: fileURL.absoluteString),
                  let skIndex = SKIndexCreateWithURL(
                    fileURL as CFURL,
                    nil,
                    properties.indexType,
                    properties.properties()
                  ) else {
                return nil
            }
            return SearchIndexer(state: State(index: skIndex.takeUnretainedValue(), fileURL: fileURL))
        }
    }
}
