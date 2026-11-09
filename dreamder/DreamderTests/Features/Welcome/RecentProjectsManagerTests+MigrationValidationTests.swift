import Foundation
import Testing
@testable import Dreamder

private struct LegacyBookmark: Codable {
    let urlPath: String
    let bookmarkData: Data
}

extension RecentProjectsManagerTests {
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
}
