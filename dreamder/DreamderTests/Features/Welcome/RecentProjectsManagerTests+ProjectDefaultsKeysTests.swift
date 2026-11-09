import Foundation
import Testing
@testable import Dreamder

extension RecentProjectsManagerTests {
    private func projectKeys(_ path: String) -> [String] {
        [
            WorkspaceDocument.workspaceStateKey(for: URL(filePath: path, directoryHint: .isDirectory)),
            "dreamder.recentFiles.\(path)",
            "NSOutlineView Items \(path)"
        ]
    }

    private func seedProjectKeys(_ path: String, in defaults: UserDefaults) {
        for key in projectKeys(path) {
            defaults.set(["value"], forKey: key)
        }
    }

    private func presentKeys(_ path: String, in defaults: UserDefaults) -> [String] {
        projectKeys(path).filter { defaults.object(forKey: $0) != nil }
    }

    @Test
    func theProjectKeysAreTheOnesWrittenByTheRecentFilesStoreAndTheOutlineView() {
        let path = "/work/keys"

        #expect(
            SearchEverywhereRecentFilesStore.defaultsKey(forProjectPath: path) == "dreamder.recentFiles./work/keys"
        )
        #expect(
            ProjectNavigatorViewController.expandedItemsDefaultsKey(forProjectPath: path)
                == "NSOutlineView Items /work/keys"
        )
        #expect(projectKeys(path).count == 3)
    }

    @Test
    func removingARecentProjectRemovesEveryPerProjectKeyAndKeepsTheOthers() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let manager = makeManager(defaults)
        manager.markRecent(at: url("/work/a"), isDirectory: true)
        manager.markRecent(at: url("/work/a-sibling"), isDirectory: true)
        seedProjectKeys("/work/a", in: defaults)
        seedProjectKeys("/work/a-sibling", in: defaults)

        manager.removeRecentProject(path: "/work/a")

        #expect(presentKeys("/work/a", in: defaults).isEmpty)
        #expect(presentKeys("/work/a-sibling", in: defaults).count == 3)
    }

    @Test
    func clearingTheRecentProjectsRemovesEveryPerProjectKey() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let manager = makeManager(defaults)
        manager.markRecent(at: url("/work/a"), isDirectory: true)
        manager.markRecent(at: url("/work/b.txt"), isDirectory: false)
        seedProjectKeys("/work/a", in: defaults)
        seedProjectKeys("/work/b.txt", in: defaults)

        manager.clear()

        #expect(presentKeys("/work/a", in: defaults).isEmpty)
        #expect(presentKeys("/work/b.txt", in: defaults).isEmpty)
    }

    @Test
    func evictingAProjectFromTheListRemovesEveryPerProjectKey() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let manager = makeManager(defaults)
        for index in 0..<RecentProjectsManager.maxRecentProjects {
            manager.markRecent(at: url("/work/project\(index)"), isDirectory: true)
        }
        seedProjectKeys("/work/project0", in: defaults)
        seedProjectKeys("/work/project1", in: defaults)

        manager.markRecent(at: url("/work/newest"), isDirectory: true)

        #expect(presentKeys("/work/project0", in: defaults).isEmpty)
        #expect(presentKeys("/work/project1", in: defaults).count == 3)
    }

    @Test
    func aProjectThatNoLongerExistsLosesEveryPerProjectKeyWhenValidated() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let manager = makeManager(defaults)
        manager.markRecent(at: url("/work/gone"), isDirectory: true)
        manager.markRecent(at: url("/work/kept"), isDirectory: true)
        seedProjectKeys("/work/gone", in: defaults)
        seedProjectKeys("/work/kept", in: defaults)

        manager.applyValidation(kinds: ["/work/kept": true], checkedPaths: ["/work/gone", "/work/kept"])

        #expect(presentKeys("/work/gone", in: defaults).isEmpty)
        #expect(presentKeys("/work/kept", in: defaults).count == 3)
    }

    @Test
    func aHiddenProjectKeepsItsPerProjectKeys() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let manager = makeManager(defaults)
        manager.markRecent(at: url("/work/hidden"), isDirectory: true)
        seedProjectKeys("/work/hidden", in: defaults)

        manager.setHidden(true, forPath: "/work/hidden")

        #expect(presentKeys("/work/hidden", in: defaults).count == 3)
    }
}
