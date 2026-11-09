import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
private final class MenuOpenLog {
    var urls: [URL] = []
}

@MainActor
@Suite(.uiGate)
struct RecentProjectsMenuTests {
    private func makeManager(
        _ defaults: UserDefaults,
        directories: [String],
        files: [String]
    ) -> RecentProjectsManager {
        let manager = RecentProjectsManager(defaults: defaults)
        for path in files.reversed() {
            manager.markRecent(at: URL(filePath: path), isDirectory: false)
        }
        for path in directories.reversed() {
            manager.markRecent(at: URL(filePath: path), isDirectory: true)
        }
        return manager
    }

    private func titles(of menu: NSMenu) -> [String] {
        menu.items.map { item in
            if item.isSeparatorItem { return "-" }
            return item.attributedTitle?.string ?? item.title
        }
    }

    private func send(_ item: NSMenuItem) throws -> Bool {
        let action = try #require(item.action)
        return NSApp.sendAction(action, to: item.target, from: item)
    }

    @Test
    func listsDirectoriesThenFilesBetweenSeparatorsEndingWithClearMenu() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let manager = makeManager(
            defaults,
            directories: ["/work/alpha", "/other/beta"],
            files: ["/work/notes.txt"]
        )
        let menu = RecentProjectsMenu(manager: manager, open: { _ in }).makeMenu()

        #expect(menu.title == "Open Recent")
        #expect(titles(of: menu) == [
            "alpha", "alpha /work",
            "beta", "beta /other",
            "-",
            "notes.txt", "notes.txt /work",
            "-",
            "Clear Menu"
        ])
        #expect(menu.items[1].isAlternate)
        #expect(menu.items[1].keyEquivalentModifierMask == [.option])
        #expect(menu.items[0].isAlternate == false)
    }

    @Test
    func anEmptyListOnlyOffersClearMenu() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let menu = RecentProjectsMenu(manager: RecentProjectsManager(defaults: defaults), open: { _ in }).makeMenu()

        #expect(titles(of: menu) == ["-", "-", "Clear Menu"])
    }

    @Test
    func duplicateNamesShowTheirParentFolder() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let manager = makeManager(defaults, directories: ["/a/app", "/b/app", "/c/solo"], files: [])
        let menu = RecentProjectsMenu(manager: manager, open: { _ in }).makeMenu()

        #expect(menu.items[0].attributedTitle?.string == "app /a")
        #expect(menu.items[2].attributedTitle?.string == "app /b")
        #expect(menu.items[4].attributedTitle == nil)
        #expect(menu.items[4].title == "solo")
    }

    @Test
    func eachSectionShowsAtMostTenEntries() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let manager = makeManager(
            defaults,
            directories: (0..<12).map { "/work/dir\($0)" },
            files: (0..<12).map { "/work/file\($0).txt" }
        )
        let menu = RecentProjectsMenu(manager: manager, open: { _ in }).makeMenu()

        #expect(menu.items.count == 20 + 1 + 20 + 1 + 1)
        #expect(menu.items[18].title == "dir9")
    }

    @Test
    func choosingAnEntryOpensItsURL() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let manager = makeManager(defaults, directories: ["/work/alpha"], files: ["/work/notes.txt"])
        let log = MenuOpenLog()
        let recentMenu = RecentProjectsMenu(manager: manager, open: { log.urls.append($0) })
        defer { withExtendedLifetime(recentMenu) {} }
        let menu = recentMenu.makeMenu()

        let primary = menu.items[0]
        let alternate = menu.items[1]
        let file = menu.items[3]
        #expect(try send(primary))
        #expect(try send(alternate))
        #expect(try send(file))

        #expect(log.urls == [
            URL(filePath: "/work/alpha", directoryHint: .isDirectory),
            URL(filePath: "/work/alpha", directoryHint: .isDirectory),
            URL(filePath: "/work/notes.txt")
        ])
    }

    @Test
    func anItemWithoutAURLDoesNothing() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let manager = makeManager(defaults, directories: ["/work/alpha"], files: [])
        let log = MenuOpenLog()
        let recentMenu = RecentProjectsMenu(manager: manager, open: { log.urls.append($0) })
        defer { withExtendedLifetime(recentMenu) {} }
        let menu = recentMenu.makeMenu()
        let item = menu.items[0]
        item.representedObject = "not a url"

        #expect(try send(item))

        #expect(log.urls.isEmpty)
    }

    @Test
    func clearMenuEmptiesTheManagerAndTheMenu() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let manager = makeManager(defaults, directories: ["/work/alpha"], files: ["/work/notes.txt"])
        let recentMenu = RecentProjectsMenu(manager: manager, open: { _ in })
        defer { withExtendedLifetime(recentMenu) {} }
        let menu = recentMenu.makeMenu()
        let clear = try #require(menu.items.last)

        #expect(try send(clear))

        #expect(manager.allProjects.isEmpty)
        #expect(titles(of: menu) == ["-", "-", "Clear Menu"])
    }

    @Test
    func openingTheMenuRebuildsItAndDropsMissingProjectsInTheBackground() async throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        try await withTempDir { directory in
            let manager = RecentProjectsManager(defaults: defaults)
            manager.markRecent(at: URL(filePath: "/dreamder-menu-missing/gone"), isDirectory: true)
            manager.markRecent(at: directory, isDirectory: true)
            let recentMenu = RecentProjectsMenu(manager: manager, open: { _ in })
            let menu = recentMenu.makeMenu()
            let initialItemCount = 7
            #expect(menu.items.count == initialItemCount)

            recentMenu.menuNeedsUpdate(menu)
            for _ in 0..<60 where manager.recentProjects.count > 1 {
                try await Task.sleep(for: .milliseconds(50))
            }

            #expect(manager.recentProjects.count == 1)
            recentMenu.menuNeedsUpdate(menu)
            let expectedItemCount = 5
            #expect(menu.items.count == expectedItemCount)
        }
    }

    @Test
    func theDefaultOpenerReportsAMissingFileThroughTheSharedController() async throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let manager = makeManager(
            defaults,
            directories: [],
            files: ["/dreamder-menu-missing/\(UUID().uuidString).txt"]
        )
        let recentMenu = RecentProjectsMenu(manager: manager)
        defer { withExtendedLifetime(recentMenu) {} }
        let menu = recentMenu.makeMenu()
        let item = menu.items[1]
        let before = DreamderHeadless.suppressedModals.count

        #expect(try send(item))
        try await eventually(timeout: .seconds(30)) { DreamderHeadless.suppressedModals.count > before }
    }
}
