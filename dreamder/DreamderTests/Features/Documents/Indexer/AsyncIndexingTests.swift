//
//  AsyncIndexingTests.swift
//  DreamderTests
//
//  Created by Tommy Ludwig on 09.12.23.
//

import XCTest
@testable import Dreamder

final class AsyncIndexingTests: XCTestCase {
    func testAddDocuments() async throws {
        let index = try XCTUnwrap(SearchIndexer.Memory.create(), "Failed to create an index")
        let asyncManager = SearchIndexer.AsyncManager(index: index)
        let first = TemporaryFile()
        let second = TemporaryFile()
        try "The first document mentions apples.".write(to: first.url, atomically: true, encoding: .utf8)
        try "The second document mentions pears.".write(to: second.url, atomically: true, encoding: .utf8)

        let results = await asyncManager.addFiles(urls: [first.url, second.url])
        XCTAssertEqual(results, [true, true], "Unexpected indexing results.")
        asyncManager.index.flush()
        let documents = asyncManager.index.documents()
        XCTAssertEqual(Set(documents), [first.url, second.url])
        withExtendedLifetime((first, second)) {}
    }

    func testSearchDocuments() async throws {
        let index = try XCTUnwrap(SearchIndexer.Memory.create(), "Failed to create an index")
        let asyncManager = SearchIndexer.AsyncManager(index: index)
        let tempFile1 = SearchIndexer.AsyncManager.TextFile(
            url: TemporaryFile().url,
            text: "Itaque ratione asperiores."
        )
        let tempFile2 = SearchIndexer.AsyncManager.TextFile(
            url: TemporaryFile().url,
            text: "Perspiciatis perspiciatis rerum ex asperiores."
        )

        let results = await asyncManager.addText(files: [tempFile1, tempFile2])
        XCTAssertEqual(results.count, 2, "Unexpected indexing results.")
        asyncManager.index.flush()
        var searchResults = [URL]()
        let searchStream = await asyncManager.search(query: "asperiores", 10)
        for try await result in searchStream {
            for url in result.results.map(\.url) {
                searchResults.append(url)
            }
        }
        XCTAssertEqual(searchResults.count, 2)
    }
}
