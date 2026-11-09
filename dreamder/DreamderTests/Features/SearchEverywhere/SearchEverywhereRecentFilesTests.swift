import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct SearchEverywhereRecentFileListTests {
    private func url(_ path: String) -> URL {
        URL(fileURLWithPath: path)
    }

    @Test
    func recordPutsNewestFirst() {
        var list = SearchEverywhereRecentFileList()
        list.record(url("/tmp/a.swift"))
        list.record(url("/tmp/b.swift"))
        list.record(url("/tmp/c.swift"))
        #expect(list.urls.map(\.lastPathComponent) == ["c.swift", "b.swift", "a.swift"])
    }

    @Test
    func recordMovesExistingToFront() {
        var list = SearchEverywhereRecentFileList(
            urls: [url("/tmp/a.swift"), url("/tmp/b.swift"), url("/tmp/c.swift")]
        )
        list.record(url("/tmp/c.swift"))
        #expect(list.urls.map(\.lastPathComponent) == ["c.swift", "a.swift", "b.swift"])
    }

    @Test
    func recordDeduplicatesSeededURLs() {
        let list = SearchEverywhereRecentFileList(
            urls: [url("/tmp/a.swift"), url("/tmp/a.swift"), url("/tmp/b.swift")]
        )
        #expect(list.urls.count == 2)
        #expect(list.urls.map(\.lastPathComponent) == ["a.swift", "b.swift"])
    }

    @Test
    func recordEnforcesLimit() {
        var list = SearchEverywhereRecentFileList(limit: 3)
        for index in 1...5 {
            list.record(url("/tmp/file\(index).swift"))
        }
        #expect(list.urls.map(\.lastPathComponent) == ["file5.swift", "file4.swift", "file3.swift"])
    }

    @Test
    func standardizedURLsCollapseDuplicatePaths() {
        var list = SearchEverywhereRecentFileList()
        list.record(url("/tmp/folder/../folder/a.swift"))
        list.record(url("/tmp/folder/a.swift"))
        #expect(list.urls.count == 1)
    }
}

@MainActor
@Suite(.uiGate)
struct SearchEverywhereActionTitleTests {
    private func action(_ path: String) -> SearchEverywhereAction {
        SearchEverywhereAction(identity: "test:\(path)", path: path, shortcut: "", perform: {})
    }

    @Test
    func menuActionKeepsMenuPath() {
        let item = action("Git | Push\u{2026}")
        #expect(item.title == "Push\u{2026}")
        #expect(item.menuPath == "Git")
    }

    @Test
    func commandActionDropsCommandPrefix() {
        let item = action("Command | Toggle Utility Area")
        #expect(item.title == "Toggle Utility Area")
        #expect(item.menuPath.isEmpty)
    }

    @Test
    func nestedMenuActionUsesFullMenuPath() {
        let item = action("File | Open Recent | Project")
        #expect(item.title == "Project")
        #expect(item.menuPath == "File | Open Recent")
    }
}

@MainActor
@Suite(.uiGate)
struct SearchEverywhereRecentSectionTests {
    @Test
    func allAndFilesTabsLeadWithRecentFiles() {
        #expect(SearchEverywhereTab.all.sections.first == .recent)
        #expect(SearchEverywhereTab.files.sections == [.recent, .files])
        #expect(SearchEverywhereTab.actions.sections == [.actions])
    }

    @Test
    func recentSectionTitle() {
        #expect(SearchEverywhereSectionKind.recent.title == "Recent Files")
    }
}

@MainActor
@Suite(.serialized, .isolatedDefaults, .uiGate)
struct SearchEverywhereRecentFilesStoreTests {
    private func names(_ urls: [URL]) -> [String] {
        urls.map(\.lastPathComponent)
    }

    private func storedNames(_ defaults: UserDefaults, workspace: WorkspaceDocument) -> [String] {
        let key = workspace.fileURL?.standardizedFileURL.path ?? "untitled"
        let paths = defaults.stringArray(forKey: "dreamder.recentFiles.\(key)") ?? []
        return paths.map { URL(fileURLWithPath: $0).lastPathComponent }
    }

    @Test
    func openTabsSeedAnEmptyHistoryAndLaterSelectionsAreRecordedAndPersisted() async throws {
        try await withTempDir { dir in
            let defaults = try IsolatedDefaults.require()
            let workspace = try SearchEverywhereFixtures.makeWorkspace(dir)
            defer { workspace.tearDownFileScope() }
            try SearchEverywhereFixtures.openTab("README.md", in: workspace, dir: dir)
            try SearchEverywhereFixtures.openTab("Sources/AppDelegate.swift", in: workspace, dir: dir)
            let store = SearchEverywhereRecentFilesStore(defaults: defaults)

            store.startTracking(for: workspace)

            #expect(names(store.recentFiles(for: workspace)) == ["AppDelegate.swift", "README.md"])
            #expect(storedNames(defaults, workspace: workspace) == ["AppDelegate.swift", "README.md"])

            try SearchEverywhereFixtures.openTab("Sources/Helpers/StringUtils.swift", in: workspace, dir: dir)
            try await eventually { names(store.recentFiles(for: workspace)).first == "StringUtils.swift" }
            try await eventually { storedNames(defaults, workspace: workspace).first == "StringUtils.swift" }

            try SearchEverywhereFixtures.openTab("README.md", in: workspace, dir: dir)
            try await eventually { names(store.recentFiles(for: workspace)).first == "README.md" }
            #expect(names(store.recentFiles(for: workspace)).count == 3)
        }
    }

    @Test
    func aStoredHistoryIsRestoredWithoutFilesThatNoLongerExist() throws {
        try withTempDir { dir in
            let defaults = try IsolatedDefaults.require()
            let workspace = try SearchEverywhereFixtures.makeWorkspace(dir)
            defer { workspace.tearDownFileScope() }
            try SearchEverywhereFixtures.openTab("README.md", in: workspace, dir: dir)
            try SearchEverywhereFixtures.openTab("Sources/AppDelegate.swift", in: workspace, dir: dir)
            SearchEverywhereRecentFilesStore(defaults: defaults).startTracking(for: workspace)
            #expect(storedNames(defaults, workspace: workspace) == ["AppDelegate.swift", "README.md"])

            let restored = SearchEverywhereRecentFilesStore(defaults: defaults)
            #expect(names(restored.recentFiles(for: workspace)) == ["AppDelegate.swift", "README.md"])

            try FileManager.default.removeItem(at: dir.appending(path: "README.md"))
            let pruned = SearchEverywhereRecentFilesStore(defaults: defaults)
            #expect(names(pruned.recentFiles(for: workspace)) == ["AppDelegate.swift"])
        }
    }
}
