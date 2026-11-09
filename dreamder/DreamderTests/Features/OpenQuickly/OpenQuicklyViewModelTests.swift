import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct OpenQuicklyViewModelTests {
    private func touch(_ root: URL, _ relativePath: String) throws {
        let file = root.appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("x".utf8).write(to: file)
    }

    private func makeProject(_ root: URL) throws {
        try touch(root, "alpha.txt")
        try touch(root, "beta.txt")
        try touch(root, "src/gamma.swift")
        try touch(root, "src/deep/alphabet.md")
        try touch(root, "alpha-dir/inner.bin")
        try touch(root, ".env")
        try touch(root, ".hidden/secret.txt")
    }

    private func search(_ model: OpenQuicklyViewModel, _ query: String) async -> [String] {
        model.query = query
        model.fetchResults()
        await model.runningTask?.value
        return model.searchResults.map { $0.fileURL.lastPathComponent }
    }

    @Test
    func resultsContainOnlyRegularFilesMatchingTheQuery() async throws {
        try await withTempDir { root in
            try makeProject(root)
            let model = OpenQuicklyViewModel(fileURL: root)

            let names = await search(model, "alpha")

            #expect(Set(names) == ["alpha.txt", "alphabet.md"])
        }
    }

    @Test
    func directoriesAreNeverReturnedEvenWhenTheirNameMatches() async throws {
        try await withTempDir { root in
            try makeProject(root)
            let model = OpenQuicklyViewModel(fileURL: root)

            let names = await search(model, "alpha-dir")

            #expect(names.isEmpty)
        }
    }

    @Test
    func filesInNestedDirectoriesAreFoundWithTheirFullLocation() async throws {
        try await withTempDir { root in
            try makeProject(root)
            let model = OpenQuicklyViewModel(fileURL: root)

            let names = await search(model, "gamma")

            #expect(names == ["gamma.swift"])
            let result = try #require(model.searchResults.first)
            #expect(result.fileURL.deletingLastPathComponent().lastPathComponent == "src")
            let resultPath = result.fileURL.resolvingSymlinksInPath().path(percentEncoded: false)
            let rootPath = root.resolvingSymlinksInPath().path(percentEncoded: false)
            #expect(resultPath.hasPrefix(rootPath))
        }
    }

    @Test
    func hiddenFilesAndFilesInHiddenDirectoriesAreIncluded() async throws {
        try await withTempDir { root in
            try makeProject(root)
            let model = OpenQuicklyViewModel(fileURL: root)

            let hiddenFile = await search(model, "env")
            let fileInHiddenDirectory = await search(model, "secret")

            #expect(hiddenFile == [".env"])
            #expect(fileInHiddenDirectory == ["secret.txt"])
        }
    }

    @Test
    func filesInsidePackagesAreSkipped() async throws {
        try await withTempDir { root in
            try touch(root, "visible.txt")
            try touch(root, "Thing.app/Contents/packaged.txt")
            let model = OpenQuicklyViewModel(fileURL: root)

            let inPackage = await search(model, "packaged")
            let outside = await search(model, "visible")

            #expect(inPackage.isEmpty)
            #expect(outside == ["visible.txt"])
        }
    }

    @Test
    func matchingIsFuzzySubsequenceAndIgnoresCase() async throws {
        try await withTempDir { root in
            try makeProject(root)
            let model = OpenQuicklyViewModel(fileURL: root)

            let subsequence = await search(model, "gma")
            let uppercase = await search(model, "ALPHA")

            #expect(subsequence == ["gamma.swift"])
            #expect(Set(uppercase) == ["alpha.txt", "alphabet.md"])
        }
    }

    @Test
    func lettersOutOfOrderDoNotMatch() async throws {
        try await withTempDir { root in
            try makeProject(root)
            let model = OpenQuicklyViewModel(fileURL: root)

            let names = await search(model, "pla")

            #expect(names.isEmpty)
        }
    }

    @Test
    func queryMatchesTheFileNameNotTheDirectoryPath() async throws {
        try await withTempDir { root in
            try makeProject(root)
            let model = OpenQuicklyViewModel(fileURL: root)

            let names = await search(model, "deep")

            #expect(names.isEmpty)
        }
    }

    @Test
    func matchedCharactersReportTheHighlightedRanges() async throws {
        try await withTempDir { root in
            try makeProject(root)
            let model = OpenQuicklyViewModel(fileURL: root)

            _ = await search(model, "alpha")
            let prefixMatch = try #require(model.searchResults.first { $0.fileURL.lastPathComponent == "alpha.txt" })
            _ = await search(model, "gma")
            let scattered = try #require(model.searchResults.first)

            #expect(prefixMatch.matchedCharacters == [NSRange(location: 0, length: 5)])
            #expect(scattered.matchedCharacters == [
                NSRange(location: 0, length: 1),
                NSRange(location: 2, length: 1),
                NSRange(location: 4, length: 1)
            ])
        }
    }

    @Test
    func contiguousMatchesRankBeforeScatteredOnes() async throws {
        try await withTempDir { root in
            try touch(root, "axb.txt")
            try touch(root, "ab.txt")
            try touch(root, "unrelated.txt")
            let model = OpenQuicklyViewModel(fileURL: root)

            let names = await search(model, "ab")

            #expect(names == ["ab.txt", "axb.txt"])
        }
    }

    @Test
    func queryIsTrimmedOfSurroundingSpaces() async throws {
        try await withTempDir { root in
            try makeProject(root)
            let model = OpenQuicklyViewModel(fileURL: root)

            let names = await search(model, "  alpha  ")

            #expect(Set(names) == ["alpha.txt", "alphabet.md"])
        }
    }

    @Test
    func whitespaceOnlyQueryProducesNoResultsAndReplacesOldOnes() async throws {
        try await withTempDir { root in
            try makeProject(root)
            let model = OpenQuicklyViewModel(fileURL: root)
            let initial = await search(model, "alpha")
            #expect(initial.isEmpty == false)

            let names = await search(model, "   ")

            #expect(names.isEmpty)
        }
    }

    @Test
    func emptyQueryClearsExistingResultsImmediately() async throws {
        try await withTempDir { root in
            try makeProject(root)
            let model = OpenQuicklyViewModel(fileURL: root)
            let initial = await search(model, "alpha")
            #expect(initial.isEmpty == false)

            model.query = ""
            model.fetchResults()

            #expect(model.searchResults.isEmpty)
        }
    }

    @Test
    func queryWithoutMatchesYieldsNoResults() async throws {
        try await withTempDir { root in
            try makeProject(root)
            let model = OpenQuicklyViewModel(fileURL: root)

            let names = await search(model, "zzzzzz")

            #expect(names.isEmpty)
        }
    }

    @Test
    func emptyProjectYieldsNoResults() async throws {
        try await withTempDir { root in
            let model = OpenQuicklyViewModel(fileURL: root)

            let names = await search(model, "a")

            #expect(names.isEmpty)
        }
    }

    @Test
    func newQueryCancelsThePreviousSearchAndReplacesItsResults() async throws {
        try await withTempDir { root in
            try makeProject(root)
            let model = OpenQuicklyViewModel(fileURL: root)

            model.query = "alpha"
            model.fetchResults()
            let firstTask = model.runningTask
            model.query = "gamma"
            model.fetchResults()

            #expect(firstTask?.isCancelled == true)

            await waitForExpectation(timeout: .seconds(15), {
                model.searchResults.map { $0.fileURL.lastPathComponent } == ["gamma.swift"]
            }, onTimeout: {
                Issue.record("searchResults never settled on the latest query")
            })
            try await Task.sleep(for: .milliseconds(200))

            let names = model.searchResults.map { $0.fileURL.lastPathComponent }
            #expect(names == ["gamma.swift"])
        }
    }

    @Test
    func laterSearchRepopulatesAfterBeingCleared() async throws {
        try await withTempDir { root in
            try makeProject(root)
            let model = OpenQuicklyViewModel(fileURL: root)
            _ = await search(model, "alpha")
            model.query = ""
            model.fetchResults()
            #expect(model.searchResults.isEmpty)

            let names = await search(model, "beta")

            #expect(names == ["beta.txt"])
        }
    }

    @Test
    func excludedDirectoriesAndGitignoredFilesAreNeverListed() async throws {
        try await withTempDir { root in
            try Data("zz-ignored.txt\n".utf8).write(to: root.appending(path: ".gitignore"))
            try touch(root, "zz-real.txt")
            try touch(root, "zz-ignored.txt")
            try touch(root, "node_modules/pkg/zz-dep.js")
            try touch(root, ".git/zz-object")
            try touch(root, "build/zz-artifact")
            let model = OpenQuicklyViewModel(fileURL: root)

            let names = await search(model, "zz")

            #expect(names == ["zz-real.txt"])
        }
    }

    @Test
    func aFileCreatedAfterTheFirstSearchIsFoundOnceTheScopeSeesIt() async throws {
        try await withTempDir { root in
            try touch(root, "first.txt")
            let model = OpenQuicklyViewModel(fileURL: root)
            _ = await search(model, "first")
            try await Task.sleep(for: .milliseconds(300))

            try touch(root, "late-arrival.txt")

            try await eventually {
                await search(model, "late-arrival") == ["late-arrival.txt"]
            }
        }
    }

    @Test
    func theWorkspaceScopeIsSharedAndItsCachedListIsReused() async throws {
        try await withTempDir { root in
            try touch(root, "a/one.txt")
            try touch(root, "b/two.txt")
            let fileSystem = RecordingFileSystem()
            let scope = WorkspaceFileScope(rootURL: root, fileSystem: fileSystem)
            let model = OpenQuicklyViewModel(fileURL: root, scope: scope)
            #expect(model.scope === scope)

            let first = await search(model, "one")
            let listingsAfterFirst = fileSystem.listings
            let second = await search(model, "two")

            #expect(first == ["one.txt"])
            #expect(second == ["two.txt"])
            #expect(listingsAfterFirst == 3)
            #expect(fileSystem.listings == listingsAfterFirst)
            #expect(fileSystem.mainThreadListings == 0)
        }
    }
}

@MainActor
@Suite(.uiGate)
struct OpenQuicklySearchResultTests {
    private let file = URL(filePath: "/project/src/main.swift")

    @Test
    func resultsAreEqualWhenTheirFileURLMatchRegardlessOfHighlights() {
        let first = OpenQuicklyViewModel.SearchResult(fileURL: file, matchedCharacters: [NSRange(location: 0, length: 2)])
        let second = OpenQuicklyViewModel.SearchResult(fileURL: file, matchedCharacters: [])

        #expect(first == second)
        #expect(first.hashValue == second.hashValue)
    }

    @Test
    func resultsWithDifferentFileURLsAreDifferent() {
        let first = OpenQuicklyViewModel.SearchResult(fileURL: file, matchedCharacters: [])
        let second = OpenQuicklyViewModel.SearchResult(
            fileURL: URL(filePath: "/project/src/other.swift"),
            matchedCharacters: []
        )

        #expect(first != second)
    }

    @Test
    func setsDeduplicateResultsByFileURL() {
        let results = [
            OpenQuicklyViewModel.SearchResult(fileURL: file, matchedCharacters: [NSRange(location: 0, length: 1)]),
            OpenQuicklyViewModel.SearchResult(fileURL: file, matchedCharacters: [NSRange(location: 3, length: 2)]),
            OpenQuicklyViewModel.SearchResult(fileURL: URL(filePath: "/project/b.swift"), matchedCharacters: [])
        ]

        #expect(Set(results).count == 2)
    }

    @Test
    func identifierIsTheAbsoluteFileURLString() {
        let result = OpenQuicklyViewModel.SearchResult(fileURL: file, matchedCharacters: [])

        #expect(result.id == file.absoluteString)
    }
}
