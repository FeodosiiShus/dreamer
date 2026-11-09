import Foundation
import Testing
@testable import Dreamder

@Suite("AsyncFileIterator")
struct AsyncFileIteratorTests {
    private func collect(_ iterator: AsyncFileIterator) async -> [(String, Int)] {
        var result: [(String, Int)] = []
        for await (file, index) in iterator {
            result.append((file.url.lastPathComponent, index))
        }
        return result
    }

    @Test
    func yieldsReadableIndexableFilesWithTheirOriginalPosition() async throws {
        try await withTempDir { root in
            try touch(root, "a.txt", "alpha")
            try touch(root, "skipped.bin", "binary-ish")
            try Data([0xFF, 0xFE]).write(to: root.appending(path: "invalid.txt"))
            try touch(root, "d.txt", "delta")
            let urls = ["a.txt", "skipped.bin", "invalid.txt", "missing.txt", "d.txt"].map { root.appending(path: $0) }

            let items = await collect(AsyncFileIterator(fileURLs: urls, isIndexable: { $0.pathExtension == "txt" }))

            #expect(items.map(\.0) == ["a.txt", "d.txt"])
            #expect(items.map(\.1) == [0, 4])
        }
    }

    @Test
    func standardizesTheYieldedURLsAndKeepsTheText() async throws {
        try await withTempDir { root in
            try touch(root, "a.txt", "alpha text")
            var iterator = AsyncFileIterator(fileURLs: [root.appending(path: "./a.txt")], isIndexable: { _ in true })

            let first = await iterator.next()

            #expect(first?.0.text == "alpha text")
            #expect(first?.0.url == root.appending(path: "a.txt").standardizedFileURL)
            #expect(await iterator.next() == nil)
        }
    }

    @Test
    func stopsWhenTheTaskIsCancelled() async throws {
        try await withTempDir { root in
            try touch(root, "a.txt", "alpha")
            let urls = [root.appending(path: "a.txt")]
            let task = Task {
                while !Task.isCancelled { await Task.yield() }
                var iterator = AsyncFileIterator(fileURLs: urls, isIndexable: { _ in true })
                return await iterator.next() == nil
            }
            task.cancel()
            #expect(await task.value)
        }
    }

    @Test
    func emptyInputEndsImmediately() async {
        var iterator = AsyncFileIterator(fileURLs: [], isIndexable: { _ in true })
        #expect(await iterator.next() == nil)
    }
}
