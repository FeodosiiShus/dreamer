import Foundation
import Testing
@testable import Dreamder

extension RecentProjectsManagerTests {
    private func stateKey(_ path: String) -> String {
        WorkspaceDocument.workspaceStateKey(for: URL(filePath: path, directoryHint: .isDirectory))
    }

    @Test
    func removingARecentProjectDiscardsItsPersistedWorkspaceStateOnly() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let manager = makeManager(defaults)
        manager.markRecent(at: url("/work/a"), isDirectory: true)
        manager.markRecent(at: url("/work/b"), isDirectory: true)
        defaults.set(["window": "a"], forKey: stateKey("/work/a"))
        defaults.set(["window": "b"], forKey: stateKey("/work/b"))

        manager.removeRecentProject(path: "/work/a")

        #expect(stateKey("/work/a") == "workspaceState-file:///work/a/")
        #expect(defaults.object(forKey: stateKey("/work/a")) == nil)
        #expect(defaults.object(forKey: stateKey("/work/b")) != nil)
    }

    @Test
    func clearingTheRecentProjectsDiscardsEveryPersistedWorkspaceState() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let manager = makeManager(defaults)
        manager.markRecent(at: url("/work/a"), isDirectory: true)
        manager.markRecent(at: url("/work/b"), isDirectory: true)
        defaults.set(["window": "a"], forKey: stateKey("/work/a"))
        defaults.set(["window": "b"], forKey: stateKey("/work/b"))

        manager.clear()

        #expect(defaults.object(forKey: stateKey("/work/a")) == nil)
        #expect(defaults.object(forKey: stateKey("/work/b")) == nil)
    }

    @Test
    func projectsEvictedFromTheListLoseTheirPersistedWorkspaceState() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let manager = makeManager(defaults)
        for index in 0..<RecentProjectsManager.maxRecentProjects {
            manager.markRecent(at: url("/work/project\(index)"), isDirectory: true)
        }
        defaults.set(["window": "oldest"], forKey: stateKey("/work/project0"))
        defaults.set(["window": "next"], forKey: stateKey("/work/project1"))

        manager.markRecent(at: url("/work/newest"), isDirectory: true)

        #expect(defaults.object(forKey: stateKey("/work/project0")) == nil)
        #expect(defaults.object(forKey: stateKey("/work/project1")) != nil)
    }

    @Test
    func projectsThatNoLongerExistLoseTheirPersistedWorkspaceStateWhenValidated() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let manager = makeManager(defaults)
        manager.markRecent(at: url("/work/gone"), isDirectory: true)
        manager.markRecent(at: url("/work/kept"), isDirectory: true)
        defaults.set(["window": "gone"], forKey: stateKey("/work/gone"))
        defaults.set(["window": "kept"], forKey: stateKey("/work/kept"))

        manager.applyValidation(
            kinds: ["/work/kept": true],
            checkedPaths: ["/work/gone", "/work/kept"]
        )

        #expect(defaults.object(forKey: stateKey("/work/gone")) == nil)
        #expect(defaults.object(forKey: stateKey("/work/kept")) != nil)
    }
}
