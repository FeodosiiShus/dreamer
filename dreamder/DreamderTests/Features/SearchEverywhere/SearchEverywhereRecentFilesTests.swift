import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite
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
@Suite
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
@Suite
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
