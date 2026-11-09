import Foundation
import Testing
@testable import Dreamder

struct AsyncManagerCoverageTests {
    private typealias TextFile = SearchIndexer.AsyncManager.TextFile

    private func documentURL(_ name: String) -> URL {
        URL(filePath: "/dreamder-async-manager-tests/\(UUID().uuidString)/\(name)")
    }

    private func makeManager() throws -> SearchIndexer.AsyncManager {
        SearchIndexer.AsyncManager(index: try #require(SearchIndexer.Memory.create()))
    }

    @Test
    func addingTextFlushesOnlyWhenAsked() async throws {
        let manager = try makeManager()
        let pending = TextFile(url: documentURL("pending.txt"), text: "alpha")
        let flushed = TextFile(url: documentURL("flushed.txt"), text: "beta")

        let pendingResults = await manager.addText(files: [pending])
        #expect(pendingResults == [true])
        #expect(!manager.index.documentIndexed(pending.url))

        let flushedResults = await manager.addText(files: [flushed], flushWhenComplete: true)
        #expect(flushedResults == [true])
        #expect(manager.index.documentIndexed(flushed.url))
        #expect(manager.index.documentIndexed(pending.url))
    }

    @Test
    func addingFilesFlushesWhenAsked() async throws {
        try await withTempDir { dir in
            let manager = try makeManager()
            let first = dir.appending(path: "first.txt")
            let second = dir.appending(path: "second.txt")
            try "The first document mentions apples.".write(to: first, atomically: true, encoding: .utf8)
            try "The second document mentions pears.".write(to: second, atomically: true, encoding: .utf8)

            let results = await manager.addFiles(urls: [first, second], flushWhenComplete: true)

            #expect(results == [true, true])
            let indexed = Set(manager.index.documents().map(\.standardizedFileURL))
            #expect(indexed == [first.standardizedFileURL, second.standardizedFileURL])
            let applesMatches = manager.index.search("apples").map(\.url.standardizedFileURL)
            #expect(applesMatches == [first.standardizedFileURL])
        }
    }

    @Test
    func searchStreamsEveryChunkAndThenFinishes() async throws {
        let manager = try makeManager()
        let files = (0..<3).map { TextFile(url: documentURL("doc\($0).txt"), text: "needle") }
        _ = await manager.addText(files: files, flushWhenComplete: true)

        var chunks = 0
        var found = Set<URL>()
        for await chunk in await manager.search(query: "needle", 1) {
            chunks += 1
            found.formUnion(chunk.results.map(\.url))
        }

        #expect(chunks > 1)
        #expect(found == Set(files.map(\.url)))
    }
}
