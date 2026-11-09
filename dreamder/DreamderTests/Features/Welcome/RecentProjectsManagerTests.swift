import Foundation
import Observation
import Testing
@testable import Dreamder

private struct LegacyBookmark: Codable {
    let urlPath: String
    let bookmarkData: Data
}

@MainActor
@Suite(.uiGate)
struct RecentProjectsManagerTests {
    private func makeManager(
        _ defaults: UserDefaults,
        timestamp: TimeInterval = 1_000
    ) -> RecentProjectsManager {
        RecentProjectsManager(defaults: defaults, now: { Date(timeIntervalSince1970: timestamp) })
    }

    private func url(_ path: String) -> URL {
        URL(filePath: path)
    }

    @Test
    func startsEmptyWithTheDefaultInitializer() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }

        let manager = RecentProjectsManager(defaults: defaults)

        #expect(manager.recentProjects.isEmpty)
        #expect(manager.recentPaths.isEmpty)
        #expect(RecentProjectsManager.maxRecentProjects == 50)

        manager.markRecent(at: url("/work/clock"), isDirectory: true)
        #expect(try #require(manager.recentProjects.first).projectOpenTimestamp > 0)
    }

    @Test
    func markRecentPutsTheMostRecentFirstAndRecordsNameAndTime() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let manager = makeManager(defaults, timestamp: 12.5)

        manager.markRecent(at: url("/work/alpha"), isDirectory: true)
        manager.markRecent(at: url("/work/notes.txt"), isDirectory: false)

        #expect(manager.recentPaths == ["/work/notes.txt", "/work/alpha"])
        let first = try #require(manager.recentProjects.first)
        #expect(first.displayName == "notes.txt")
        #expect(first.projectOpenTimestamp == 12_500)
        #expect(first.isDirectory == false)
        #expect(first.hidden == false)
        #expect(manager.displayName(forPath: "/work/alpha") == "alpha")
        #expect(manager.displayName(forPath: "/missing") == nil)
        #expect(manager.hasPath("/work/alpha"))
        #expect(manager.hasPath("/missing") == false)
    }

    @Test
    func markingAnExistingPathMovesItToTheFrontWithoutDuplicates() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let manager = makeManager(defaults)

        manager.markRecent(at: url("/work/a"), isDirectory: true)
        manager.markRecent(at: url("/work/b"), isDirectory: true)
        manager.markRecent(at: url("/work/c"), isDirectory: true)
        manager.markRecent(at: url("/work/x/../a"), isDirectory: true)

        #expect(manager.recentPaths == ["/work/a", "/work/c", "/work/b"])
    }

    @Test
    func theListIsLimitedToFiftyAndDropsTheOldest() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let manager = makeManager(defaults)

        for index in 0..<55 {
            manager.markRecent(at: url("/work/project\(index)"), isDirectory: true)
        }

        #expect(manager.recentProjects.count == RecentProjectsManager.maxRecentProjects)
        #expect(manager.recentPaths.first == "/work/project54")
        #expect(manager.recentPaths.last == "/work/project5")
        #expect(manager.hasPath("/work/project4") == false)
    }

    @Test
    func removeRecentProjectDropsOnlyThatPath() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let manager = makeManager(defaults)
        manager.markRecent(at: url("/work/a"), isDirectory: true)
        manager.markRecent(at: url("/work/b"), isDirectory: true)

        manager.removeRecentProject(path: "/work/a")
        manager.removeRecentProject(path: "/work/unknown")

        #expect(manager.recentPaths == ["/work/b"])
        #expect(RecentProjectsManager(defaults: defaults).recentPaths == ["/work/b"])
    }

    @Test
    func clearRemovesEverythingAndPersists() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let manager = makeManager(defaults)
        manager.markRecent(at: url("/work/a"), isDirectory: true)
        manager.markRecent(at: url("/work/b.txt"), isDirectory: false)

        manager.clear()

        #expect(manager.allProjects.isEmpty)
        #expect(RecentProjectsManager(defaults: defaults).allProjects.isEmpty)
    }

    @Test
    func hiddenProjectsLeaveTheListButStayStoredAndCanBeRestored() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let manager = makeManager(defaults)
        manager.markRecent(at: url("/work/a"), isDirectory: true)
        manager.markRecent(at: url("/work/b"), isDirectory: true)

        manager.setHidden(true, forPath: "/work/a")
        manager.setHidden(true, forPath: "/work/a")
        manager.setHidden(true, forPath: "/work/unknown")

        #expect(manager.recentPaths == ["/work/b"])
        #expect(manager.recentDirectoryURLs().count == 1)
        #expect(manager.allProjects.count == 2)
        #expect(RecentProjectsManager(defaults: defaults).recentPaths == ["/work/b"])

        manager.markRecent(at: url("/work/a"), isDirectory: true)
        #expect(manager.recentPaths == ["/work/b"])
        #expect(manager.allProjects.first?.path == "/work/a")

        manager.setHidden(false, forPath: "/work/a")
        #expect(manager.recentPaths == ["/work/a", "/work/b"])
    }

    @Test
    func directoriesAndFilesAreSeparated() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let manager = makeManager(defaults)
        manager.markRecent(at: url("/work/a"), isDirectory: true)
        manager.markRecent(at: url("/work/one.txt"), isDirectory: false)
        manager.markRecent(at: url("/work/b"), isDirectory: true)
        manager.markRecent(at: url("/work/two.txt"), isDirectory: false)

        #expect(manager.recentDirectoryURLs().map { $0.path } == ["/work/b", "/work/a"])
        #expect(manager.recentFileURLs().map { $0.path } == ["/work/two.txt", "/work/one.txt"])
        #expect(manager.recentDirectoryURLs().allSatisfy { $0.hasDirectoryPath })
        #expect(manager.recentFileURLs().allSatisfy { !$0.hasDirectoryPath })
    }

    @Test
    func projectsRoundTripThroughUserDefaults() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let manager = makeManager(defaults, timestamp: 77)
        manager.markRecent(at: url("/work/a"), isDirectory: true)
        manager.markRecent(at: url("/work/b.txt"), isDirectory: false)
        manager.setHidden(true, forPath: "/work/a")

        let reloaded = RecentProjectsManager(defaults: defaults)

        #expect(reloaded.allProjects == manager.allProjects)
    }

    @Test
    func corruptStoredDataLoadsAsEmpty() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        defaults.set(Data("not json".utf8), forKey: RecentProjectsManager.storageKey)

        #expect(RecentProjectsManager(defaults: defaults).allProjects.isEmpty)
    }

    @Test
    func theOldBookmarkListIsMigratedOnceWithoutResolvingBookmarks() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let legacy = [
            LegacyBookmark(urlPath: "/work/newest", bookmarkData: Data([1, 2, 3])),
            LegacyBookmark(urlPath: "/work/middle", bookmarkData: Data()),
            LegacyBookmark(urlPath: "/work/newest", bookmarkData: Data([9])),
            LegacyBookmark(urlPath: "/work/oldest", bookmarkData: Data([4]))
        ]
        defaults.set(try PropertyListEncoder().encode(legacy), forKey: RecentProjectsManager.legacyBookmarksKey)

        let manager = RecentProjectsManager(defaults: defaults)

        #expect(manager.recentPaths == ["/work/newest", "/work/middle", "/work/oldest"])
        let first = try #require(manager.recentProjects.first)
        #expect(first.displayName == "newest")
        #expect(first.projectOpenTimestamp == 0)
        #expect(first.isDirectory)
        #expect(defaults.data(forKey: RecentProjectsManager.legacyBookmarksKey) == nil)
        #expect(defaults.data(forKey: RecentProjectsManager.storageKey) != nil)

        defaults.set(
            try PropertyListEncoder().encode([LegacyBookmark(urlPath: "/work/other", bookmarkData: Data())]),
            forKey: RecentProjectsManager.legacyBookmarksKey
        )
        #expect(RecentProjectsManager(defaults: defaults).recentPaths == manager.recentPaths)
    }

    @Test
    func theMigrationKeepsAtMostFiftyEntries() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let legacy = (0..<80).map { LegacyBookmark(urlPath: "/work/p\($0)", bookmarkData: Data()) }
        defaults.set(try PropertyListEncoder().encode(legacy), forKey: RecentProjectsManager.legacyBookmarksKey)

        let manager = RecentProjectsManager(defaults: defaults)

        #expect(manager.recentProjects.count == 50)
        #expect(manager.recentPaths.first == "/work/p0")
        #expect(manager.recentPaths.last == "/work/p49")
    }

    @Test
    func anUnreadableLegacyListMigratesToEmptyAndIsDiscarded() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        defaults.set(Data("garbage".utf8), forKey: RecentProjectsManager.legacyBookmarksKey)

        let manager = RecentProjectsManager(defaults: defaults)

        #expect(manager.allProjects.isEmpty)
        #expect(defaults.data(forKey: RecentProjectsManager.legacyBookmarksKey) == nil)
    }

    @Test
    func validationRemovesMissingPathsAndCorrectsTheKind() async throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        try await withTempDir { directory in
            let folder = directory.appending(path: "folder", directoryHint: .isDirectory)
            let file = directory.appending(path: "file.txt")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: file)
            let manager = makeManager(defaults)
            manager.markRecent(at: directory.appending(path: "gone", directoryHint: .isDirectory), isDirectory: true)
            manager.markRecent(at: file, isDirectory: true)
            manager.markRecent(at: folder, isDirectory: false)

            await manager.validate()

            #expect(manager.allProjects.count == 2)
            #expect(manager.recentProjects.first { $0.displayName == "folder" }?.isDirectory == true)
            #expect(manager.recentProjects.first { $0.displayName == "file.txt" }?.isDirectory == false)
            let gone = RecentProjectsManager.normalizedPath(of: directory.appending(path: "gone"))
            #expect(manager.hasPath(gone) == false)
            #expect(RecentProjectsManager(defaults: defaults).allProjects == manager.allProjects)
        }
    }

    @Test
    func validatingAnUnchangedListLeavesItAlone() async throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        try await withTempDir { directory in
            let manager = makeManager(defaults)
            manager.markRecent(at: directory, isDirectory: true)
            let before = manager.allProjects

            await manager.validate()

            #expect(manager.allProjects == before)
        }
    }

    @Test
    func validationKeepsProjectsAddedWhileItWasChecking() async throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        try await withTempDir { directory in
            let existing = directory.appending(path: "existing", directoryHint: .isDirectory)
            let added = directory.appending(path: "added", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: added, withIntermediateDirectories: true)
            let manager = makeManager(defaults)
            manager.markRecent(at: existing, isDirectory: true)

            let checkedPaths = manager.allProjects.map(\.path)
            let kinds = await RecentProjectsManager.existingKinds(of: checkedPaths)
            manager.markRecent(at: added, isDirectory: true)
            manager.applyValidation(kinds: kinds, checkedPaths: Set(checkedPaths))

            #expect(manager.recentProjects.count == 2)
            #expect(manager.hasPath(RecentProjectsManager.normalizedPath(of: added)))
        }
    }

    @Test
    func existenceIsCheckedOffTheMainThread() async throws {
        try await withTempDir { directory in
            let kinds = await RecentProjectsManager.existingKinds(of: [
                directory.path,
                directory.appending(path: "missing").path
            ])

            #expect(kinds == [directory.path: true])
        }
    }

    @Test
    func changesAreObservable() async throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let manager = makeManager(defaults)
        var iterator = Observations { manager.recentPaths }.makeAsyncIterator()

        let initial = await iterator.next()
        manager.markRecent(at: url("/work/a"), isDirectory: true)
        let updated = await iterator.next()

        #expect(initial == [])
        #expect(updated == ["/work/a"])
    }

    @Test
    func recentProjectDerivesItsPresentation() {
        let project = RecentProject(
            path: NSHomeDirectory() + "/code/app",
            displayName: "app",
            projectOpenTimestamp: 0,
            isDirectory: true,
            hidden: false
        )

        #expect(project.id == project.path)
        #expect(project.abbreviatedPath == "~/code/app")
        #expect(project.url.hasDirectoryPath)
        #expect(RecentProject.displayName(forPath: "/a/b/c.txt") == "c.txt")
    }
}
