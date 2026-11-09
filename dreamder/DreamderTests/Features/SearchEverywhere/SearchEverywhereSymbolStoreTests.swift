import Foundation
import Synchronization
import Testing
@testable import Dreamder

private final class PathKeyCounter: Sendable {
    private let count = Mutex(0)

    var calls: Int {
        count.withLock { $0 }
    }

    func key(for url: URL) -> String {
        count.withLock { $0 += 1 }
        return url.workspacePathKey
    }

    func reset() {
        count.withLock { $0 = 0 }
    }
}

private let storeRoot = URL(fileURLWithPath: "/work/project", isDirectory: true)

private func storeFileURL(_ path: String) -> URL {
    storeRoot.appending(path: path)
}

private func storeSymbol(_ name: String, in path: String, line: Int = 1) -> SearchEverywhereSymbol {
    SearchEverywhereSymbol(name: name, kind: .function, url: storeFileURL(path), line: line)
}

private func symbolNames(_ symbols: [SearchEverywhereSymbol]) -> [String] {
    symbols.map(\.name)
}

private func storeNames(_ store: SearchEverywhereSymbolStore) -> Set<String> {
    Set(store.symbolsByFile.values.flatMap { symbolNames($0) })
}

private func namesInFile(_ path: String, of store: SearchEverywhereSymbolStore) -> [String] {
    store.symbolsByFile["/work/project/" + path].map(symbolNames) ?? []
}

@Suite("SearchEverywhereSymbolStore")
struct SearchEverywhereSymbolStoreTests {
    private func seeded(files: Int, counter: PathKeyCounter) -> SearchEverywhereSymbolStore {
        var store = SearchEverywhereSymbolStore(pathKey: { counter.key(for: $0) })
        var symbols: [SearchEverywhereSymbol] = []
        for index in 0..<files {
            symbols.append(storeSymbol("first\(index)", in: "Sources/File\(index).swift"))
            symbols.append(storeSymbol("second\(index)", in: "Sources/File\(index).swift", line: 2))
        }
        store.replace(with: symbols)
        return store
    }

    @Test
    func replaceGroupsSymbolsByFileAndMergesRunsOfTheSameFile() async {
        var store = SearchEverywhereSymbolStore()
        let scanned = [
            storeSymbol("B1", in: "b.swift"),
            storeSymbol("B2", in: "b.swift", line: 2),
            storeSymbol("A1", in: "a.swift"),
            storeSymbol("B3", in: "b.swift", line: 3)
        ]

        store.replace(with: scanned)
        let flattened = await store.flattened()

        #expect(store.symbolsByFile.keys.sorted() == ["/work/project/a.swift", "/work/project/b.swift"])
        #expect(namesInFile("b.swift", of: store) == ["B1", "B2", "B3"])
        #expect(symbolNames(flattened) == ["A1", "B1", "B2", "B3"])
    }

    @Test
    func replaceDropsEverythingStoredBeforeAndCountsRevisions() {
        var store = SearchEverywhereSymbolStore()
        #expect(store.revision == 0)

        store.replace(with: [storeSymbol("Old", in: "old.swift")])
        store.replace(with: [storeSymbol("New", in: "new.swift")])

        #expect(storeNames(store) == ["New"])
        #expect(store.revision == 2)

        store.replace(with: [])

        #expect(store.symbolsByFile.isEmpty)
        #expect(store.revision == 3)
    }

    @Test
    func aDeltaForOneFileDoesWorkIndependentOfTheNumberOfIndexedFiles() {
        var callsBySize: [Int: Int] = [:]
        for files in [10, 4000] {
            let counter = PathKeyCounter()
            var store = seeded(files: files, counter: counter)
            counter.reset()

            store.apply(
                scanned: [storeSymbol("replaced", in: "Sources/File7.swift")],
                updated: [storeFileURL("Sources/File7.swift")],
                removed: []
            )

            callsBySize[files] = counter.calls
            #expect(namesInFile("Sources/File7.swift", of: store) == ["replaced"])
            #expect(namesInFile("Sources/File8.swift", of: store) == ["first8", "second8"])
            #expect(store.symbolsByFile.count == files)
        }
        #expect(callsBySize == [10: 2, 4000: 2])
    }

    @Test
    func updatedFilesLoseTheirOldSymbolsEvenWhenTheyYieldNone() {
        var store = SearchEverywhereSymbolStore()
        store.replace(with: [storeSymbol("Keep", in: "keep.swift"), storeSymbol("Gone", in: "gone.swift")])

        store.apply(scanned: [], updated: [storeFileURL("gone.swift")], removed: [])

        #expect(storeNames(store) == ["Keep"])
        #expect(store.revision == 2)
    }

    @Test
    func removingAFileDropsOnlyThatFile() {
        var store = SearchEverywhereSymbolStore()
        store.replace(with: [storeSymbol("A", in: "a.swift"), storeSymbol("B", in: "b.swift")])

        store.apply(scanned: [], updated: [], removed: [storeFileURL("a.swift")])

        #expect(storeNames(store) == ["B"])
    }

    @Test
    func removingADirectoryDropsEveryFileBeneathItButNotSiblingsSharingThePrefix() {
        var store = SearchEverywhereSymbolStore()
        store.replace(with: [
            storeSymbol("InPackage", in: "pkg/a.swift"),
            storeSymbol("Nested", in: "pkg/deep/b.swift"),
            storeSymbol("Sibling", in: "pkgx/c.swift"),
            storeSymbol("Top", in: "top.swift")
        ])

        store.apply(scanned: [], updated: [], removed: [storeFileURL("pkg")])

        #expect(storeNames(store) == ["Sibling", "Top"])
    }

    @Test
    func aDeltaCombinesRemovalsUpdatesAndNewSymbols() async {
        var store = SearchEverywhereSymbolStore()
        store.replace(with: [
            storeSymbol("Old", in: "edit.swift"),
            storeSymbol("Doomed", in: "dir/a.swift"),
            storeSymbol("Stable", in: "stable.swift")
        ])

        store.apply(
            scanned: [storeSymbol("Fresh", in: "edit.swift"), storeSymbol("Born", in: "new.swift")],
            updated: [storeFileURL("edit.swift"), storeFileURL("new.swift")],
            removed: [storeFileURL("dir")]
        )
        let flattened = await store.flattened()

        #expect(symbolNames(flattened) == ["Fresh", "Born", "Stable"])
    }

    @Test
    func flattenedSymbolsFollowTheSortedPathOrder() async {
        var store = SearchEverywhereSymbolStore()
        store.replace(with: [
            storeSymbol("Z", in: "z.swift"),
            storeSymbol("M", in: "m.swift"),
            storeSymbol("A", in: "a.swift")
        ])

        let flattened = await store.flattened()

        #expect(symbolNames(flattened) == ["A", "M", "Z"])
    }
}

@MainActor
@Suite("SearchEverywhereSymbolIndexDeltas", .serialized, .uiGate)
struct SearchEverywhereSymbolIndexDeltaTests {
    @Test
    func aSavedFileRekeysOnlyItself() async throws {
        try await withTempDir { root in
            for index in 0..<20 {
                try touch(root, "Sources/File\(index).swift", "struct Type\(index) {}")
            }
            let scope = WorkspaceFileScope(rootURL: root)
            let counter = PathKeyCounter()
            let index = SearchEverywhereSymbolIndex(
                scope: scope,
                store: SearchEverywhereSymbolStore(pathKey: { counter.key(for: $0) })
            )
            index.ensureIndexed()
            try await eventually(timeout: .seconds(20)) { !index.isBuilding && index.store.symbolsByFile.count == 20 }
            counter.reset()
            let revisionBefore = index.store.revision

            try touch(root, "Sources/File3.swift", "struct Renamed {}")
            scope.handle(events: [fsEvent(root.appending(path: "Sources/File3.swift"), .itemModified)])
            try await eventually(timeout: .seconds(20)) { storeNames(index.store).contains("Renamed") }

            #expect(!storeNames(index.store).contains("Type3"))
            #expect(storeNames(index.store).count == 20)
            #expect(counter.calls == 2)
            #expect(index.store.revision == revisionBefore + 1)
        }
    }

    @Test
    func theBuildPublishesOneRevisionForTheResetAndOneForTheScan() async throws {
        try await withTempDir { root in
            try touch(root, "A.swift", "struct Alpha {}")
            let index = SearchEverywhereSymbolIndex(scope: WorkspaceFileScope(rootURL: root))
            #expect(index.store.revision == 0)

            index.ensureIndexed()
            #expect(index.store.revision == 1)
            try await eventually(timeout: .seconds(20)) { !index.isBuilding }

            #expect(index.store.revision == 2)
            #expect(storeNames(index.store) == ["Alpha"])
        }
    }
}
