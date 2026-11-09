import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .isolatedDefaults, .uiGate)
struct SearchEverywhereRecentFilesCleanupTests {
    private func recentFilesKey(of workspace: WorkspaceDocument) throws -> String {
        let location = try #require(workspace.fileURL)
        return SearchEverywhereRecentFilesStore.defaultsKey(forProjectPath: location.standardizedFileURL.path)
    }

    @Test
    func theStoredHistoryLivesUnderTheKeyThatTheRecentProjectsDiscard() throws {
        try withTempDir { dir in
            let defaults = try IsolatedDefaults.require()
            let workspace = try SearchEverywhereFixtures.makeWorkspace(dir)
            defer { workspace.tearDownFileScope() }
            try SearchEverywhereFixtures.openTab("README.md", in: workspace, dir: dir)
            SearchEverywhereRecentFilesStore(defaults: defaults).startTracking(for: workspace)
            let key = try recentFilesKey(of: workspace)
            #expect(defaults.stringArray(forKey: key)?.isEmpty == false)

            let location = try #require(workspace.fileURL)
            let manager = RecentProjectsManager(defaults: defaults)
            manager.markRecent(at: location, isDirectory: true)
            manager.removeRecentProject(path: RecentProjectsManager.normalizedPath(of: location))

            #expect(defaults.object(forKey: key) == nil)
        }
    }

    @Test
    func clearingTheRecentProjectsDiscardsTheStoredHistoryOfEveryProject() throws {
        try withTempDir { dir in
            let defaults = try IsolatedDefaults.require()
            let workspace = try SearchEverywhereFixtures.makeWorkspace(dir)
            defer { workspace.tearDownFileScope() }
            try SearchEverywhereFixtures.openTab("README.md", in: workspace, dir: dir)
            SearchEverywhereRecentFilesStore(defaults: defaults).startTracking(for: workspace)
            let key = try recentFilesKey(of: workspace)
            let location = try #require(workspace.fileURL)
            let manager = RecentProjectsManager(defaults: defaults)
            manager.markRecent(at: location, isDirectory: true)

            manager.clear()

            #expect(defaults.object(forKey: key) == nil)
        }
    }
}
