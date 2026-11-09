import Foundation
import Testing
@testable import Dreamder

private func symbol(
    _ name: String,
    _ kind: SearchEverywhereSymbolKind,
    in root: URL,
    path: String,
    line: Int = 1
) -> SearchEverywhereSymbol {
    SearchEverywhereSymbol(name: name, kind: kind, url: root.appending(path: path), line: line)
}

@Suite("SearchEverywhereFileScanner")
struct SearchEverywhereFileScannerTests {
    @Test
    func urlsComeFromTheScopeAndHonorExtensionSizeAndCountFilters() async throws {
        try await withTempDir { root in
            try touch(root, "a.swift", "let a = 1")
            try touch(root, "b.SWIFT", "let b = 2")
            try touch(root, "c.md", "# c")
            try touch(root, "big.swift", String(repeating: "x", count: 5000))
            try touch(root, "node_modules/dep.swift", "let d = 1")
            let scope = WorkspaceFileScope(rootURL: root)

            let all = await SearchEverywhereFileScanner.urls(scope: scope)
            #expect(relativePaths(all, in: root) == ["a.swift", "b.SWIFT", "big.swift", "c.md"])

            let swiftOnly = await SearchEverywhereFileScanner.urls(scope: scope, extensions: ["swift"])
            #expect(relativePaths(swiftOnly, in: root) == ["a.swift", "b.SWIFT", "big.swift"])

            let small = await SearchEverywhereFileScanner.urls(scope: scope, extensions: ["swift"], maxFileSize: 1000)
            #expect(relativePaths(small, in: root) == ["a.swift", "b.SWIFT"])

            let capped = await SearchEverywhereFileScanner.urls(scope: scope, maxCount: 2)
            #expect(capped.count == 2)
        }
    }

    @Test
    func relativePathStripsTheRootAndFallsBackToTheFileName() {
        let root = URL(fileURLWithPath: "/work/project", isDirectory: true)
        #expect(SearchEverywhereFileScanner.relativePath(of: root.appending(path: "a/b.swift"), from: root) == "a/b.swift")
        #expect(SearchEverywhereFileScanner.relativePath(of: URL(fileURLWithPath: "/elsewhere/c.swift"), from: root) == "c.swift")
        #expect(SearchEverywhereFileScanner.relativePath(of: root, from: root) == "project")
    }

    @Test
    func relativePathsPreferTheFastRootPrefix() {
        let root = URL(fileURLWithPath: "/work/project/", isDirectory: true)
        let paths = SearchEverywhereRelativePaths(root: root)
        #expect(paths.relative(URL(fileURLWithPath: "/work/project/a/b.swift")) == "a/b.swift")
        #expect(paths.relative(URL(fileURLWithPath: "/elsewhere/c.swift")) == "c.swift")
    }
}

@Suite("SearchEverywhereProjectSearch")
struct SearchEverywhereProjectSearchTests {
    private let root = URL(fileURLWithPath: "/work/project", isDirectory: true)

    private var urls: [URL] {
        [
            root.appending(path: "Sources/AppDelegate.swift"),
            root.appending(path: "Sources/Helpers/StringUtils.swift"),
            root.appending(path: "Tests/StringUtilsTests.swift"),
            root.appending(path: "README.md")
        ]
    }

    @Test
    func fileHitsAreRankedAndCarryRelativePaths() async {
        let hits = await SearchEverywhereProjectSearch.rankedFileHits(
            text: "strutil",
            urls: urls,
            root: root,
            limit: 10
        )
        #expect(hits.map(\.relative).sorted() == ["Sources/Helpers/StringUtils.swift", "Tests/StringUtilsTests.swift"])
        #expect(hits.allSatisfy { !$0.match.ranges.isEmpty })

        let limited = await SearchEverywhereProjectSearch.rankedFileHits(text: "strutil", urls: urls, root: root, limit: 1)
        #expect(limited.count == 1)
    }

    @Test
    func exactNameMatchesAreFlagged() async {
        let hits = await SearchEverywhereProjectSearch.rankedFileHits(
            text: "README.md",
            urls: urls,
            root: root,
            limit: 10
        )
        #expect(hits.first?.url.lastPathComponent == "README.md")
        #expect(hits.first?.isExactMatch == true)
    }

    @Test
    func queriesThatOnlyMatchTheDirectoryFallBackToThePathWithAPenalty() async throws {
        let direct = try #require(SearchEverywhereProjectSearch.matchFile(
            query: "StringUtils",
            url: urls[1],
            root: root
        ))
        let viaPath = try #require(SearchEverywhereProjectSearch.matchFile(
            query: "helpers",
            url: urls[1],
            root: root
        ))
        #expect(viaPath.ranges.isEmpty)
        #expect(viaPath.score < direct.score)
        #expect(SearchEverywhereProjectSearch.matchFile(query: "zzzz", url: urls[1], root: root) == nil)
    }

    @Test
    func slashQueriesRequireDirectorySegmentsInOrder() {
        let url = urls[1]
        #expect(SearchEverywhereProjectSearch.matchFile(query: "sources/strutil", url: url, root: root) != nil)
        #expect(SearchEverywhereProjectSearch.matchFile(query: "helpers/str", url: url, root: root) != nil)
        #expect(SearchEverywhereProjectSearch.matchFile(query: "sources/helpers/str", url: url, root: root) != nil)
        #expect(SearchEverywhereProjectSearch.matchFile(query: "helpers/sources/str", url: url, root: root) == nil)
        #expect(SearchEverywhereProjectSearch.matchFile(query: "zzz/str", url: url, root: root) == nil)
        #expect(SearchEverywhereProjectSearch.matchFile(query: "sources/zzz", url: url, root: root) == nil)
        #expect(SearchEverywhereProjectSearch.matchFile(query: "/", url: url, root: root) == nil)
    }

    @Test
    func symbolHitsFilterTypesAndRank() async {
        let symbols = [
            symbol("AppDelegate", .classType, in: root, path: "Sources/AppDelegate.swift", line: 3),
            symbol("appDidLaunch", .method, in: root, path: "Sources/AppDelegate.swift", line: 5),
            symbol("AppState", .structType, in: root, path: "Sources/State.swift", line: 1)
        ]

        let classes = await SearchEverywhereProjectSearch.rankedSymbolHits(
            text: "App",
            symbols: symbols,
            root: root,
            classesOnly: true,
            limit: 10
        )
        #expect(Set(classes.map(\.symbol.name)) == ["AppDelegate", "AppState"])
        #expect(classes.first { $0.symbol.name == "AppDelegate" }?.relative == "Sources/AppDelegate.swift")

        let everything = await SearchEverywhereProjectSearch.rankedSymbolHits(
            text: "App",
            symbols: symbols,
            root: root,
            classesOnly: false,
            limit: 10
        )
        #expect(everything.count == 3)

        let exact = await SearchEverywhereProjectSearch.rankedSymbolHits(
            text: "AppState",
            symbols: symbols,
            root: root,
            classesOnly: false,
            limit: 10
        )
        #expect(exact.first?.symbol.name == "AppState")
        #expect(exact.first?.isExactMatch == true)
    }

    @Test
    func cancelledMatchingReturnsNothing() async {
        let candidates = self.urls
        let projectRoot = self.root
        let symbols = [symbol("AppDelegate", .classType, in: projectRoot, path: "a.swift")]
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            let files = await SearchEverywhereProjectSearch.rankedFileHits(
                text: "a",
                urls: candidates,
                root: projectRoot,
                limit: 5
            )
            let hits = await SearchEverywhereProjectSearch.rankedSymbolHits(
                text: "App",
                symbols: symbols,
                root: projectRoot,
                classesOnly: false,
                limit: 5
            )
            return (files.count, hits.count)
        }
        task.cancel()
        let counts = await task.value
        #expect(counts.0 == 0)
        #expect(counts.1 == 0)
    }

    @Test
    func textMatchesScanProjectTextFilesThroughTheScope() async throws {
        try await withTempDir { root in
            try touch(root, "a.txt", (1...8).map { "needle \($0)" }.joined(separator: "\n"))
            try touch(root, "b.md", "  \tindented needle\n\nnothing here\r\nNEEDLE again\n")
            try touch(root, "long.txt", "needle " + String(repeating: "y", count: 400))
            try touch(root, "data.bin", "needle")
            try touch(root, "node_modules/x.txt", "needle")
            let scope = WorkspaceFileScope(rootURL: root)

            let matches = await SearchEverywhereProjectSearch.textMatches(
                pattern: "needle",
                caseSensitive: false,
                scope: scope
            )
            let perFile = Dictionary(grouping: matches, by: { $0.url.lastPathComponent }).mapValues(\.count)
            #expect(perFile == ["a.txt": 5, "b.md": 2, "long.txt": 1])
            #expect(matches.first { $0.url.lastPathComponent == "b.md" }?.text == "indented needle")
            #expect(matches.first { $0.url.lastPathComponent == "long.txt" }?.text.count == 200)

            let sensitive = await SearchEverywhereProjectSearch.textMatches(
                pattern: "needle",
                caseSensitive: true,
                scope: scope
            )
            #expect(sensitive.filter { $0.url.lastPathComponent == "b.md" }.count == 1)

            let limited = await SearchEverywhereProjectSearch.textMatches(
                pattern: "needle",
                caseSensitive: false,
                scope: scope,
                limit: 3,
                perFileLimit: 2
            )
            #expect(limited.count == 3)

            let invalid = await SearchEverywhereProjectSearch.textMatches(
                pattern: "(",
                caseSensitive: false,
                scope: scope
            )
            #expect(invalid.isEmpty)
        }
    }

    @Test
    func previewShowsContextAroundTheTargetLine() async throws {
        try await withTempDir { root in
            let text = (1...30).map { "line \($0)" }.joined(separator: "\r\n")
            try touch(root, "p.txt", text)
            let url = root.appending(path: "p.txt")

            let preview = await SearchEverywhereProjectSearch.preview(url: url, targetLine: 15, context: 2)
            #expect(preview?.title == "p.txt")
            #expect(preview?.subtitle == "Line 15 of 30")
            #expect(preview?.lines.map(\.number) == [13, 14, 15, 16, 17])
            #expect(preview?.lines.first { $0.isTarget }?.text == "line 15")

            let clamped = await SearchEverywhereProjectSearch.preview(url: url, targetLine: 999, context: 1)
            #expect(clamped?.lines.map(\.number) == [29, 30])
            let negative = await SearchEverywhereProjectSearch.preview(url: url, targetLine: -4, context: 1)
            #expect(negative?.lines.map(\.number) == [1, 2])
        }
    }

    @Test
    func previewTruncatesLongLinesAndRejectsUnreadableOrOversizedFiles() async throws {
        try await withTempDir { root in
            try touch(root, "long.txt", String(repeating: "z", count: 500))
            let long = await SearchEverywhereProjectSearch.preview(
                url: root.appending(path: "long.txt"),
                targetLine: 1
            )
            #expect(long?.lines.first?.text.count == 240)

            try Data([0xFF, 0xFE, 0xFD]).write(to: root.appending(path: "bad.txt"))
            #expect(await SearchEverywhereProjectSearch.preview(url: root.appending(path: "bad.txt"), targetLine: 1) == nil)
            #expect(await SearchEverywhereProjectSearch.preview(url: root.appending(path: "missing"), targetLine: 1) == nil)

            let big = Data(repeating: 0x61, count: WorkspaceFileScope.maxIndexableTextSize + 1)
            try big.write(to: root.appending(path: "big.txt"))
            #expect(await SearchEverywhereProjectSearch.preview(url: root.appending(path: "big.txt"), targetLine: 1) == nil)

            try touch(root, "empty.txt", "")
            let empty = await SearchEverywhereProjectSearch.preview(url: root.appending(path: "empty.txt"), targetLine: 1)
            #expect(empty?.lines.count == 1)
        }
    }
}

@Suite("SearchEverywhereSymbolScanner")
struct SearchEverywhereSymbolScannerTests {
    @Test
    func scanReadsSupportedSourceFilesOnly() async throws {
        try await withTempDir { root in
            try touch(root, "Sources/App.swift", "class AppDelegate {\n    func launch() {}\n}\n")
            try touch(root, "notes.md", "class NotASymbol {}")
            try touch(root, "node_modules/dep.swift", "class Dep {}")
            try touch(root, "Sources/Broken.swift", "class Broken {}")
            try Data([0xFF, 0xFE]).write(to: root.appending(path: "Sources/Broken.swift"))
            let scope = WorkspaceFileScope(rootURL: root)

            let symbols = await SearchEverywhereSymbolScanner.scan(scope: scope)

            #expect(Set(symbols.map(\.name)) == ["AppDelegate", "launch"])
            #expect(symbols.allSatisfy { $0.url.lastPathComponent == "App.swift" })

            let limited = await SearchEverywhereSymbolScanner.scan(scope: scope, limit: 1)
            #expect(limited.count <= 2)
        }
    }

    @Test
    func changedFilesAreFilteredByExtensionSizeAndTextContent() async throws {
        try await withTempDir { root in
            try touch(root, "ok.swift", "struct Fine {}")
            try touch(root, "readme.md", "struct Ignored {}")
            try touch(root, "huge.swift", "struct Huge {}\n" + String(repeating: "// pad\n", count: 80_000))
            try Data([0x73, 0x74, 0x00, 0x72]).write(to: root.appending(path: "nul.swift"))
            let scope = WorkspaceFileScope(rootURL: root)
            let urls = ["ok.swift", "readme.md", "huge.swift", "nul.swift", "gone.swift"].map { root.appending(path: $0) }

            let symbols = await SearchEverywhereSymbolScanner.symbols(inChanged: urls, scope: scope)

            #expect(symbols.map(\.name) == ["Fine"])
        }
    }
}

@MainActor
@Suite("SearchEverywhereSymbolIndex", .uiGate)
struct SearchEverywhereSymbolIndexTests {
    private func names(_ index: SearchEverywhereSymbolIndex) -> Set<String> {
        Set(index.symbols.map(\.name))
    }

    @Test
    func buildsLazilyOnceAndFollowsFileChanges() async throws {
        try await withTempDir { root in
            try touch(root, "A.swift", "struct Alpha {}")
            let scope = WorkspaceFileScope(rootURL: root)
            let index = SearchEverywhereSymbolIndex(scope: scope)
            #expect(index.symbols.isEmpty)
            #expect(!index.isBuilding)

            index.ensureIndexed()
            #expect(index.isBuilding)
            try await eventually { !index.isBuilding && names(index) == ["Alpha"] }
            index.ensureIndexed()
            #expect(names(index) == ["Alpha"])

            try touch(root, "B.swift", "struct Beta {}")
            scope.handle(events: [fsEvent(root.appending(path: "B.swift"), .itemCreated)])
            try await eventually { names(index) == ["Alpha", "Beta"] }

            try touch(root, "B.swift", "struct Gamma {}")
            scope.handle(events: [fsEvent(root.appending(path: "B.swift"), .itemModified)])
            try await eventually { names(index) == ["Alpha", "Gamma"] }

            try FileManager.default.removeItem(at: root.appending(path: "B.swift"))
            scope.handle(events: [fsEvent(root.appending(path: "B.swift"), .itemRemoved)])
            try await eventually { names(index) == ["Alpha"] }

            try touch(root, "pkg/C.swift", "struct Delta {}")
            scope.handle(events: [fsEvent(root.appending(path: "pkg"), .itemCreated)])
            try await eventually { names(index) == ["Alpha", "Delta"] }
            try FileManager.default.removeItem(at: root.appending(path: "pkg"))
            scope.handle(events: [fsEvent(root.appending(path: "pkg"), .itemRemoved)])
            try await eventually { names(index) == ["Alpha"] }
        }
    }

    @Test
    func unsupportedFilesInABatchDoNotPolluteTheIndex() async throws {
        try await withTempDir { root in
            try touch(root, "A.swift", "struct Alpha {}")
            let scope = WorkspaceFileScope(rootURL: root)
            let index = SearchEverywhereSymbolIndex(scope: scope)
            index.ensureIndexed()
            try await eventually { names(index) == ["Alpha"] }

            try touch(root, "notes.md", "struct NotASymbol {}")
            try touch(root, "Z.swift", "struct Zed {}")
            scope.handle(events: [
                fsEvent(root.appending(path: "notes.md"), .itemCreated),
                fsEvent(root.appending(path: "Z.swift"), .itemCreated)
            ])

            try await eventually { names(index) == ["Alpha", "Zed"] }
        }
    }

    @Test
    func resetsAndExplicitRebuildsRescanTheScope() async throws {
        try await withTempDir { root in
            try touch(root, "A.swift", "struct Alpha {}")
            try touch(root, "B.swift", "struct Beta {}")
            let scope = WorkspaceFileScope(rootURL: root)
            let index = SearchEverywhereSymbolIndex(scope: scope)
            index.ensureIndexed()
            try await eventually { names(index) == ["Alpha", "Beta"] }

            scope.setIgnoreGlobs(["B.swift"])
            try await eventually { names(index) == ["Alpha"] }

            scope.setIgnoreGlobs([])
            try await eventually { names(index) == ["Alpha", "Beta"] }

            index.rebuild()
            try await eventually { !index.isBuilding && names(index) == ["Alpha", "Beta"] }
        }
    }
}
