//
//  AsyncIndexingTests.swift
//  DreamderTests
//
//  Created by Tommy Ludwig on 09.12.23.
//

import XCTest
@testable import Dreamder

final class AsyncIndexingTests: XCTestCase {
    func testAddDocuments() throws {
        guard let index = SearchIndexer.Memory.create() else {
            XCTFail("Failed to create an index")
            return
        }

        let asyncManager = SearchIndexer.AsyncManager(index: index)
        let expectation = XCTestExpectation(description: "Async operations completed")
        let first = TemporaryFile()
        let second = TemporaryFile()
        try "The first document mentions apples.".write(to: first.url, atomically: true, encoding: .utf8)
        try "The second document mentions pears.".write(to: second.url, atomically: true, encoding: .utf8)

        Task {
            let results = await asyncManager.addFiles(urls: [first.url, second.url])
            XCTAssertEqual(results, [true, true], "Unexpected indexing results.")
            asyncManager.index.flush()
            let documents = asyncManager.index.documents()
            XCTAssertEqual(Set(documents), [first.url, second.url])
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 10)
        withExtendedLifetime((first, second)) {}
    }

    func testSearchDocuments() {
        guard let index = SearchIndexer.Memory.create() else {
            XCTFail("Failed to create an index")
            return
        }

        let asyncManager = SearchIndexer.AsyncManager(index: index)
        let expectation = XCTestExpectation(description: "Async operations completed")

        let tempFile1 = SearchIndexer.AsyncManager.TextFile(
            url: TemporaryFile().url,
            text: "Itaque ratione asperiores."
        )
        let tempFile2 = SearchIndexer.AsyncManager.TextFile(
            url: TemporaryFile().url,
            text: "Perspiciatis perspiciatis rerum ex asperiores."
        )

        Task {
            var searchResults = [URL]()
            let results = await asyncManager.addText(files: [tempFile1, tempFile2])
            XCTAssertEqual(results.count, 2, "Unexpected indexing results.")
            asyncManager.index.flush()
            let searchStream = await asyncManager.search(query: "asperiores", 10)
            for try await result in searchStream {
                let urls: [(URL, Float)] = result.results.compactMap {
                    ($0.url, $0.score)
                }

                for (url, _) in urls {
                    searchResults.append(url)
                }
            }

            XCTAssertEqual(searchResults.count, 2)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2)
    }

}
