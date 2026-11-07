//
//  AsyncFileIterator.swift
//  Dreamder
//
//  Created by Khan Winter on 12/4/23.
//

import Foundation

/// Given a list of file URLs, asynchronously fetches their contents and returns them iteratively.
/// Returns files as a ``SearchIndexer/AsyncManager/TextFile`` struct, used to index workspaces.
struct AsyncFileIterator: AsyncSequence, AsyncIteratorProtocol {
    typealias TextFile = SearchIndexer.AsyncManager.TextFile
    typealias Element = (TextFile, Int)

    let fileURLs: [URL]
    var currentIdx = 0

    mutating func next() async -> Element? {
        guard !Task.isCancelled else {
            return nil
        }

        defer {
            currentIdx += 1
        }

        while currentIdx < fileURLs.count {
            let fileURL = fileURLs[currentIdx]
            if let content = try? String(contentsOf: fileURL) {
                return (TextFile(url: fileURL.standardizedFileURL, text: content), currentIdx)
            }
            currentIdx += 1
        }
        return nil
    }

    func makeAsyncIterator() -> AsyncFileIterator {
        self
    }
}
