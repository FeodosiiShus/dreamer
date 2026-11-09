import Foundation
import Synchronization
import Testing
@testable import Dreamder

final class RecordingFileSystem: WorkspaceFileSystem {
    private struct Record {
        var listedPaths: [String] = []
        var mainThreadListings = 0
        var hook: (@Sendable () -> Void)?
    }

    private let inner = DiskWorkspaceFileSystem()
    private let record = Mutex(Record())

    var listedPaths: [String] { record.withLock { $0.listedPaths } }
    var listings: Int { record.withLock { $0.listedPaths.count } }
    var mainThreadListings: Int { record.withLock { $0.mainThreadListings } }

    func setHook(_ hook: (@Sendable () -> Void)?) {
        record.withLock { $0.hook = hook }
    }

    func entries(in directory: URL) -> [WorkspaceFileEntry] {
        let hook = record.withLock { record -> (@Sendable () -> Void)? in
            record.listedPaths.append(directory.path(percentEncoded: false))
            if Thread.isMainThread { record.mainThreadListings += 1 }
            return record.hook
        }
        hook?()
        return inner.entries(in: directory)
    }

    func entry(at url: URL) -> WorkspaceFileEntry? {
        inner.entry(at: url)
    }
}

func touch(_ root: URL, _ path: String, _ text: String = "x") throws {
    let url = root.appending(path: path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}

func relativePaths(_ urls: [URL], in root: URL) -> [String] {
    let prefix = root.workspacePathKey + "/"
    return urls.map { $0.workspacePathKey.replacingOccurrences(of: prefix, with: "") }.sorted()
}

func fsEvent(_ url: URL, _ type: FSEvent) -> DirectoryEventStream.Event {
    DirectoryEventStream.Event(path: url.path(percentEncoded: false), eventType: type)
}

@concurrent
func makeScaleTree(root: URL, ignoredFiles: Int, realFiles: Int) async throws {
    let fileManager = FileManager.default
    let packages = ignoredFiles / 100
    for packageIndex in 0..<packages {
        let directory = root.appending(path: "node_modules/pkg\(packageIndex)")
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        for file in 0..<100 {
            let path = directory.appending(path: "f\(file).js").path(percentEncoded: false)
            fileManager.createFile(atPath: path, contents: nil)
        }
    }
    let realDirectories = realFiles / 10
    for directoryIndex in 0..<realDirectories {
        let directory = root.appending(path: "src/d\(directoryIndex)")
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        for file in 0..<10 {
            let path = directory.appending(path: "f\(file).swift").path(percentEncoded: false)
            fileManager.createFile(atPath: path, contents: nil)
        }
    }
}

@Suite("WorkspaceFileScope")
struct WorkspaceFileScopeTests {
    @Test
    func twentyThousandFilesUnderNodeModulesAreNeverVisitedAndTheScanRunsOffTheMainThread() async throws {
        try await withTempDir { root in
            try await makeScaleTree(root: root, ignoredFiles: 20_000, realFiles: 50)
            let fileSystem = RecordingFileSystem()
            let scope = WorkspaceFileScope(rootURL: root, fileSystem: fileSystem)

            let files = await scope.enumerateFiles(limit: nil)

            #expect(files.count == 50)
            #expect(files.allSatisfy { $0.pathExtension == "swift" })
            #expect(fileSystem.mainThreadListings == 0)
            #expect(fileSystem.listings == 7)
            #expect(!fileSystem.listedPaths.contains { $0.contains("node_modules") })
        }
    }

    @Test
    func everyDefaultExcludedDirectoryNameIsPrunedAtAnyDepth() async throws {
        try await withTempDir { root in
            try touch(root, "keep.txt")
            for name in ExclusionRules.defaultExcludedNames {
                try touch(root, "\(name)/inside.txt")
                try touch(root, "nested/\(name)/inside.txt")
            }
            let scope = WorkspaceFileScope(rootURL: root)
            let files = await scope.enumerateFiles(limit: nil)
            #expect(relativePaths(files, in: root) == ["keep.txt"])
            #expect(ExclusionRules.defaultExcludedNames.isSuperset(of: [
                ".git", "node_modules", ".build", "build", "dist", "out", "target", "DerivedData", ".gradle",
                ".idea", ".venv", "venv", "__pycache__", "Pods", "vendor", "coverage", ".next", ".turbo", ".cache"
            ]))
        }
    }

    @Test
    func filesNamedLikeExcludedDirectoriesAndHiddenFilesAreKeptWhileDSStoreIsDropped() async throws {
        try await withTempDir { root in
            try touch(root, "build")
            try touch(root, "target")
            try touch(root, ".env")
            try touch(root, ".hidden/secret.txt")
            try touch(root, ".DS_Store")
            try touch(root, "sub/.DS_Store")
            let scope = WorkspaceFileScope(rootURL: root)
            let files = await scope.enumerateFiles(limit: nil)
            #expect(relativePaths(files, in: root) == [".env", ".hidden/secret.txt", "build", "target"])
        }
    }

    @Test
    func symlinksAndPackagesAreSkipped() async throws {
        try await withTempDir { root in
            try touch(root, "real/a.txt")
            try touch(root, "Thing.app/Contents/packaged.txt")
            try FileManager.default.createSymbolicLink(
                at: root.appending(path: "link-to-file"),
                withDestinationURL: root.appending(path: "real/a.txt")
            )
            try FileManager.default.createSymbolicLink(
                at: root.appending(path: "link-to-dir"),
                withDestinationURL: root.appending(path: "real")
            )
            let scope = WorkspaceFileScope(rootURL: root)
            let files = await scope.enumerateFiles(limit: nil)
            #expect(relativePaths(files, in: root) == ["real/a.txt"])
        }
    }

    @Test @MainActor
    func userExclusionsAndCancelledDefaultsApplyAfterReload() async throws {
        try await withTempDir { root in
            try touch(root, "src/a.swift")
            try touch(root, "generated/out.swift")
            try touch(root, "node_modules/x.js")
            let (defaults, suiteName) = try makeIsolatedDefaults()
            defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
            let model = ExcludedDirectories(rootURL: root, defaults: defaults)
            let scope = WorkspaceFileScope(rootURL: root)

            let initial = await scope.enumerateFiles(limit: nil)
            #expect(relativePaths(initial, in: root) == ["generated/out.swift", "src/a.swift"])

            model.exclude(root.appending(path: "generated"))
            model.cancelExclusion(root.appending(path: "node_modules"))
            scope.reload()
            let reloaded = await scope.enumerateFiles(limit: nil)
            #expect(relativePaths(reloaded, in: root) == ["node_modules/x.js", "src/a.swift"])
        }
    }

    @Test
    func injectedExclusionRulesReplaceTheRegistry() async throws {
        try await withTempDir { root in
            try touch(root, "src/a.swift")
            try touch(root, "skip/b.swift")
            let rules = ExclusionRules(rootURL: root, excluded: ["skip"])
            let scope = WorkspaceFileScope(rootURL: root, exclusionRules: { rules })
            let files = await scope.enumerateFiles(limit: nil)
            #expect(relativePaths(files, in: root) == ["src/a.swift"])
            #expect(scope.isExcluded(root.appending(path: "skip/b.swift")))
        }
    }

    @Test
    func gitignoreChainIsAppliedDuringEnumeration() async throws {
        try await withTempDir { root in
            try touch(root, ".gitignore", "*.log\nlogs/\n")
            try touch(root, "app.swift")
            try touch(root, "debug.log")
            try touch(root, "logs/today.txt")
            try touch(root, "sub/.gitignore", "!keep.log\nlocal.txt\n")
            try touch(root, "sub/keep.log")
            try touch(root, "sub/other.log")
            try touch(root, "sub/local.txt")
            try touch(root, "sub/real.txt")
            try touch(root, ".git/info/exclude", "excluded-by-info.txt\n")
            try touch(root, "excluded-by-info.txt")

            let scope = WorkspaceFileScope(rootURL: root)
            let files = await scope.enumerateFiles(limit: nil)

            #expect(relativePaths(files, in: root) == [
                ".gitignore", "app.swift", "sub/.gitignore", "sub/keep.log", "sub/real.txt"
            ])
        }
    }

    @Test
    func settingsGlobsExcludeFilesAndInvalidateTheCacheOnlyWhenTheyChange() async throws {
        try await withTempDir { root in
            try touch(root, "a.swift")
            try touch(root, "b.tmp")
            try touch(root, "cache/c.swift")
            let scope = WorkspaceFileScope(rootURL: root)
            var changes = scope.changes().makeAsyncIterator()

            let before = await scope.enumerateFiles(limit: nil)
            #expect(relativePaths(before, in: root) == ["a.swift", "b.tmp", "cache/c.swift"])

            scope.setIgnoreGlobs(["*.tmp", "cache/"])
            #expect(await changes.next() == .reset)
            #expect(scope.cachedFiles() == nil)
            let after = await scope.enumerateFiles(limit: nil)
            #expect(relativePaths(after, in: root) == ["a.swift"])

            scope.setIgnoreGlobs(["*.tmp", "cache/"])
            #expect(scope.cachedFiles() != nil)
        }
    }

    @Test
    func isExcludedChecksAncestorsAndDistinguishesFilesFromDirectories() async throws {
        try withTempDir { root in
            try touch(root, ".gitignore", "logs/\n")
            try touch(root, "node_modules/pkg/a.js")
            try touch(root, "src/a.swift")
            try touch(root, "build")
            try touch(root, "tool/build/x.o")
            try touch(root, "logs")
            try touch(root, "nested/logs/x.txt")
            let scope = WorkspaceFileScope(rootURL: root)

            #expect(scope.isExcluded(root.appending(path: "node_modules/pkg/a.js")))
            #expect(scope.isExcluded(root.appending(path: "node_modules")))
            #expect(!scope.isExcluded(root.appending(path: "src/a.swift")))
            #expect(!scope.isExcluded(root.appending(path: "build")))
            #expect(scope.isExcluded(root.appending(path: "tool/build")))
            #expect(scope.isExcluded(root.appending(path: "tool/build/x.o")))
            #expect(scope.isExcluded(root.appending(path: "build"), isDirectory: true))
            #expect(!scope.isExcluded(root.appending(path: "logs")))
            #expect(scope.isExcluded(root.appending(path: "nested/logs")))
            #expect(scope.isExcluded(root.appending(path: "nested/logs/x.txt")))
            #expect(scope.isExcluded(root.appending(path: "tool/build/", directoryHint: .isDirectory)))
            #expect(!scope.isExcluded(root))
            #expect(!scope.isExcluded(URL(fileURLWithPath: "/somewhere/else/node_modules")))
            #expect(!scope.isExcluded(root.appending(path: ".DS_Store"), isDirectory: true))
            #expect(scope.isExcluded(root.appending(path: ".DS_Store"), isDirectory: false))
            #expect(scope.relativePath(of: root.appending(path: "src/a.swift")) == "src/a.swift")
        }
    }

    @Test
    func indexableTextRejectsBinariesOversizedAndUnreadableFiles() throws {
        try withTempDir { root in
            try touch(root, "a.swift", "let x = 1\n")
            try touch(root, "empty.txt", "")
            try Data([0x61, 0x00, 0x62]).write(to: root.appending(path: "nul.dat"))
            try touch(root, "image.PNG", "not really an image")
            let atLimit = Data(repeating: 0x61, count: WorkspaceFileScope.maxIndexableTextSize)
            try atLimit.write(to: root.appending(path: "limit.txt"))
            try Data(count: WorkspaceFileScope.maxIndexableTextSize + 1).write(to: root.appending(path: "big.txt"))
            let nonZero = Data(repeating: 0x61, count: WorkspaceFileScope.maxIndexableTextSize + 1)
            try nonZero.write(to: root.appending(path: "bigtext.txt"))
            let scope = WorkspaceFileScope(rootURL: root)

            #expect(scope.isIndexableText(root.appending(path: "a.swift")))
            #expect(scope.isIndexableText(root.appending(path: "empty.txt")))
            #expect(!scope.isIndexableText(root.appending(path: "nul.dat")))
            #expect(!scope.isIndexableText(root.appending(path: "image.PNG")))
            #expect(scope.isIndexableText(root.appending(path: "limit.txt")))
            #expect(!scope.isIndexableText(root.appending(path: "big.txt")))
            #expect(!scope.isIndexableText(root.appending(path: "bigtext.txt")))
            #expect(!scope.isIndexableText(root.appending(path: "missing.txt")))
        }
    }

    @Test
    func limitedScansStopEarlyAndAreNotCachedWhileFullScansAre() async throws {
        try await withTempDir { root in
            for index in 0..<10 { try touch(root, "f\(index).txt") }
            let fileSystem = RecordingFileSystem()
            let scope = WorkspaceFileScope(rootURL: root, fileSystem: fileSystem)

            let limited = await scope.enumerateFiles(limit: 3)
            #expect(relativePaths(limited, in: root) == ["f0.txt", "f1.txt", "f2.txt"])
            #expect(scope.cachedFiles() == nil)

            let full = await scope.enumerateFiles(limit: nil)
            #expect(full.count == 10)
            #expect(scope.cachedFiles()?.count == 10)
            let listingsAfterFull = fileSystem.listings

            let cachedLimited = await scope.enumerateFiles(limit: 4)
            let cachedFull = await scope.enumerateFiles()
            #expect(cachedLimited.count == 4)
            #expect(cachedFull == full)
            #expect(fileSystem.listings == listingsAfterFull)
        }
    }

    @Test
    func concurrentFullScansShareOneTraversal() async throws {
        try await withTempDir { root in
            for index in 0..<20 { try touch(root, "d\(index)/f.txt") }
            let fileSystem = RecordingFileSystem()
            let scope = WorkspaceFileScope(rootURL: root, fileSystem: fileSystem)

            async let first = scope.enumerateFiles(limit: nil)
            async let second = scope.enumerateFiles(limit: nil)
            let results = await [first, second]

            #expect(results[0].count == 20)
            #expect(results[0] == results[1])
            #expect(fileSystem.listings == 21)
        }
    }

    @Test
    func aScanThatRacesWithAnEventIsRepeatedAndStopsAfterThreeAttempts() async throws {
        try await withTempDir { root in
            try touch(root, "a.txt")
            let fileSystem = RecordingFileSystem()
            let scope = WorkspaceFileScope(rootURL: root, fileSystem: fileSystem)
            let ghost = fsEvent(root.appending(path: "ghost.txt"), .itemRemoved)
            fileSystem.setHook { scope.handle(events: [ghost]) }

            let files = await scope.enumerateFiles(limit: nil)

            #expect(relativePaths(files, in: root) == ["a.txt"])
            #expect(fileSystem.listings == 3)
            #expect(scope.cachedFiles()?.count == 1)
        }
    }

    @Test
    func aCreationDuringAScanTriggersASecondPass() async throws {
        try await withTempDir { root in
            try touch(root, "a.txt")
            let fileSystem = RecordingFileSystem()
            let scope = WorkspaceFileScope(rootURL: root, fileSystem: fileSystem)
            let created = root.appending(path: "late.txt")
            fileSystem.setHook {
                fileSystem.setHook(nil)
                try? Data("x".utf8).write(to: created)
                scope.handle(events: [fsEvent(created, .itemCreated)])
            }

            let files = await scope.enumerateFiles(limit: nil)

            #expect(relativePaths(files, in: root) == ["a.txt", "late.txt"])
            #expect(fileSystem.listings == 2)
        }
    }

    @Test
    func cleanUpEndsSubscriptionsAndDropsTheCache() async throws {
        try await withTempDir { root in
            try touch(root, "a.txt")
            let scope = WorkspaceFileScope(rootURL: root)
            var iterator = scope.changes().makeAsyncIterator()
            _ = scope.changes()
            _ = await scope.enumerateFiles(limit: nil)

            scope.cleanUp()

            #expect(scope.cachedFiles() == nil)
            #expect(await iterator.next() == nil)
            scope.stopWatching()
        }
    }

    @Test
    func cleanUpDuringAScanDiscardsItsResult() async throws {
        try await withTempDir { root in
            try touch(root, "a.txt")
            let fileSystem = RecordingFileSystem()
            let scope = WorkspaceFileScope(rootURL: root, fileSystem: fileSystem)
            fileSystem.setHook {
                fileSystem.setHook(nil)
                scope.cleanUp()
            }

            _ = await scope.enumerateFiles(limit: nil)

            #expect(scope.cachedFiles() == nil)
        }
    }

    @Test
    func eventsOutsideTheRootAreIgnored() async throws {
        try await withTempDir { root in
            try touch(root, "a.txt")
            let scope = WorkspaceFileScope(rootURL: root)
            _ = await scope.enumerateFiles(limit: nil)

            scope.handle(events: [
                fsEvent(URL(fileURLWithPath: "/definitely/not/inside/the/root/b.txt"), .itemCreated),
                fsEvent(URL(fileURLWithPath: "/definitely/not/inside/the/root/c.txt"), .itemRemoved)
            ])

            #expect(relativePaths(scope.cachedFiles() ?? [], in: root) == ["a.txt"])
        }
    }
}

@Suite("DiskWorkspaceFileSystem")
struct DiskWorkspaceFileSystemTests {
    @Test
    func entriesClassifyFilesDirectoriesSymlinksAndPackages() throws {
        try withTempDir { root in
            try touch(root, "file.txt")
            try touch(root, "dir/inner.txt")
            try touch(root, "Thing.app/Contents/x.txt")
            try FileManager.default.createSymbolicLink(
                at: root.appending(path: "link"),
                withDestinationURL: root.appending(path: "file.txt")
            )
            let fileSystem = DiskWorkspaceFileSystem()

            let kinds = Dictionary(
                uniqueKeysWithValues: fileSystem.entries(in: root).map { ($0.name, $0.kind) }
            )

            #expect(kinds == ["file.txt": .file, "dir": .directory, "Thing.app": .other, "link": .other])
            #expect(fileSystem.entry(at: root.appending(path: "file.txt"))?.kind == .file)
            #expect(fileSystem.entry(at: root.appending(path: "dir"))?.name == "dir")
            #expect(fileSystem.entry(at: root.appending(path: "missing")) == nil)
            #expect(fileSystem.entries(in: root.appending(path: "missing")).isEmpty)
        }
    }

    @Test
    func specialFilesAreClassifiedAsOther() throws {
        let fileSystem = DiskWorkspaceFileSystem()
        let entry = fileSystem.entry(at: URL(fileURLWithPath: "/dev/null"))
        #expect(entry?.kind == .other)
    }

    @Test
    func namedPipesAreClassifiedAsOther() throws {
        try withTempDir { root in
            let pipe = root.appending(path: "pipe")
            #expect(mkfifo(pipe.path(percentEncoded: false), 0o600) == 0)
            let fileSystem = DiskWorkspaceFileSystem()

            #expect(fileSystem.entry(at: pipe)?.kind == .other)
            #expect(fileSystem.entries(in: root).map(\.kind) == [.other])
        }
    }
}

@Suite("WorkspacePathKey")
struct WorkspacePathKeyTests {
    @Test
    func trailingSlashesAreTrimmedButTheRootStaysIntact() {
        #expect(URL(fileURLWithPath: "/a/b/", isDirectory: true).workspacePathKey == "/a/b")
        #expect(URL(fileURLWithPath: "/a/b").workspacePathKey == "/a/b")
        #expect(URL(fileURLWithPath: "/").workspacePathKey == "/")
    }

    @Test
    func removedPathsCoverThemselvesAndDescendantsOnly() {
        let removed = WorkspaceRemovedPaths([URL(fileURLWithPath: "/a/b", isDirectory: true)])
        #expect(removed.covers(URL(fileURLWithPath: "/a/b")))
        #expect(removed.covers(URL(fileURLWithPath: "/a/b/c/d.txt")))
        #expect(!removed.covers(URL(fileURLWithPath: "/a/bc")))
        #expect(!removed.covers(URL(fileURLWithPath: "/a")))
        #expect(!removed.covers(URL(fileURLWithPath: "/other/b")))
    }
}
