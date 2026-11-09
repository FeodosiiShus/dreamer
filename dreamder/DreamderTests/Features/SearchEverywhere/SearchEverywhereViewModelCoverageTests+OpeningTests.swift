import AppKit
import Foundation
import Testing
@testable import Dreamder

extension SearchEverywhereViewModelCoverageTests {
    @Test
    func recentFilesOfAWorkspaceWithoutAFolderMatchByFileName() async throws {
        try await withTempDir { dir in
            let workspace = WorkspaceDocument()
            let file = dir.appending(path: "Standalone.swift")
            try "struct Standalone {}\n".write(to: file, atomically: true, encoding: .utf8)
            let editorManager = try #require(workspace.editorManager)
            editorManager.openTab(item: CEWorkspaceFile(url: file))
            let model = try makeModel(workspace: workspace, mode: .recentFiles)

            model.start(on: .files)

            #expect(model.flatItems.map(\.title) == ["Standalone.swift"])
            #expect(model.flatItems.map(\.detail) == [""])

            model.query = "stand"
            try await eventually { model.flatItems.map(\.title) == ["Standalone.swift"] }

            model.query = "zzzzqqq"
            try await eventually { model.flatItems.isEmpty }
        }
    }

    @Test
    func textResultsOfAScopeWithoutAFolderShowTheBareFileName() async throws {
        try await withTempDir { dir in
            try touch(dir, "Notes.md", "first\nthe needle line\n")
            let workspace = WorkspaceDocument()
            workspace.fileScope = WorkspaceFileScope(rootURL: dir)
            defer { workspace.tearDownFileScope() }
            let model = try makeModel(workspace: workspace)
            model.start(on: .text)

            model.query = "needle"

            try await eventually { !model.flatItems.isEmpty }
            let item = try #require(model.flatItems.first)
            #expect(item.detail == "Notes.md:2")
            #expect(item.kind == .text)
        }
    }

    @Test
    func fileChangesDeliveredAfterTheModelIsReleasedAreDropped() async throws {
        try await withTempDir { dir in
            let workspace = try SearchEverywhereFixtures.makeWorkspace(dir)
            defer { workspace.tearDownFileScope() }
            let scope = try #require(workspace.fileScope)
            var model: SearchEverywhereViewModel? = try makeModel(workspace: workspace)
            weak let released = model
            await Task.yield()
            await Task.yield()
            await Task.yield()

            scope.reload()
            model = nil
            await Task.yield()
            await Task.yield()

            #expect(model == nil)
            #expect(released == nil)
        }
    }

    @Test
    func aWorkspaceWithoutASymbolIndexStillFindsFilesButNoSymbols() async throws {
        try await withTempDir { dir in
            let workspace = try SearchEverywhereFixtures.makeWorkspace(dir)
            defer { workspace.tearDownFileScope() }
            workspace.symbolIndex = nil
            let model = try makeModel(workspace: workspace)
            model.start(on: .all)

            model.query = "AppDelegate"

            try await eventually {
                model.flatItems.contains { $0.kind == .file && $0.title == "AppDelegate.swift" }
            }
            #expect(!model.flatItems.contains { $0.kind == .classSymbol || $0.kind == .symbol })
            #expect(!model.isIndexing)
        }
    }

    @Test
    func anActionMatchingOnlyItsMenuPathListsWithoutHighlightRanges() async throws {
        let toggle = SearchEverywhereFixtures.action("Navigate | Toggle Everything")
        let model = try makeModel(workspace: nil, actions: [toggle])
        model.start(on: .actions)

        model.query = "navig"

        try await eventually { model.flatItems.count == 1 }
        let item = try #require(model.flatItems.first)
        #expect(item.title == "Toggle Everything")
        #expect(item.detail == "Navigate")
        #expect(item.ranges.isEmpty)
    }

    @Test
    func actionItemsOfAMenuPathOnlyMatchHaveNoRangesWhileTitleMatchesDo() throws {
        let pathOnly = SearchEverywhereFixtures.action("Navigate | Toggle Everything")
        let titleMatch = SearchEverywhereFixtures.action("Window | Navigate Back")
        let model = try makeModel(workspace: nil, actions: [pathOnly, titleMatch])

        let items = model.buildActionItems(text: "navig", limit: 8)

        #expect(Set(items.map(\.title)) == ["Toggle Everything", "Navigate Back"])
        let pathOnlyItem = try #require(items.first { $0.title == "Toggle Everything" })
        let titleItem = try #require(items.first { $0.title == "Navigate Back" })
        #expect(pathOnlyItem.ranges.isEmpty)
        #expect(!titleItem.ranges.isEmpty)
    }

    @Test
    func openingAFileWithoutALineOnlyOpensItsTab() async throws {
        try await withTempDir { dir in
            let workspace = try SearchEverywhereFixtures.makeWorkspace(dir)
            defer { workspace.tearDownFileScope() }
            let counter = ActionCounter()
            let model = try makeModel(workspace: workspace)
            model.dismiss = { counter.dismissals += 1 }
            model.start(on: .files)
            model.query = "AppDelegate"
            try await eventually { model.selectedItem?.title == "AppDelegate.swift" }
            #expect(model.selectedItem?.line == nil)

            model.openSelected()

            let tab = try #require(workspace.editorManager?.activeEditor.selectedTab)
            #expect(tab.file.url.lastPathComponent == "AppDelegate.swift")
            #expect(counter.dismissals == 1)
        }
    }

    @Test
    func openingAFileAtALineWithoutAColumnPutsTheCaretInTheFirstColumn() async throws {
        try await withTempDir { dir in
            let workspace = try SearchEverywhereFixtures.makeWorkspace(dir)
            defer { workspace.tearDownFileScope() }
            let model = try makeModel(workspace: workspace)
            model.start(on: .files)
            model.query = "AppDelegate:4"
            try await eventually { model.selectedItem?.title == "AppDelegate.swift" && model.selectedItem?.line == 4 }
            #expect(model.selectedItem?.column == nil)

            model.openSelected()

            let tab = try #require(workspace.editorManager?.activeEditor.selectedTab)
            #expect(tab.file.url.lastPathComponent == "AppDelegate.swift")
            #expect(tab.cursorPositions.first?.start.line == 4)
            #expect(tab.cursorPositions.first?.start.column == 1)
        }
    }

    @Test
    func openingARecentFileOfAWorkspaceWithoutAFolderCreatesTheFileHandleItself() async throws {
        try await withTempDir { dir in
            try touch(dir, "Alpha.swift", "struct Alpha {}\n")
            try touch(dir, "Beta.swift", "struct Beta {}\n")
            let workspace = WorkspaceDocument()
            let editorManager = try #require(workspace.editorManager)
            editorManager.openTab(item: CEWorkspaceFile(url: dir.appending(path: "Alpha.swift")))
            editorManager.openTab(item: CEWorkspaceFile(url: dir.appending(path: "Beta.swift")))
            #expect(editorManager.activeEditor.selectedTab?.file.url.lastPathComponent == "Beta.swift")
            let model = try makeModel(workspace: workspace, mode: .recentFiles)
            model.start(on: .files)
            model.query = "alpha"
            try await eventually { model.flatItems.map(\.title) == ["Alpha.swift"] }

            model.openSelected()

            #expect(editorManager.activeEditor.selectedTab?.file.url.lastPathComponent == "Alpha.swift")
        }
    }

    @Test
    func openingAnItemAfterTheWorkspaceIsGoneOnlyDismisses() async throws {
        try await withTempDir { dir in
            let workspace = try SearchEverywhereFixtures.makeWorkspace(dir)
            defer { workspace.tearDownFileScope() }
            let counter = ActionCounter()
            let model = try makeModel(workspace: workspace)
            model.dismiss = { counter.dismissals += 1 }
            model.start(on: .files)
            model.query = "AppDelegate"
            try await eventually { model.selectedItem?.title == "AppDelegate.swift" }
            model.workspace = nil

            model.openSelected()

            #expect(counter.dismissals == 1)
            #expect(workspace.editorManager?.activeEditor.selectedTab == nil)
        }
    }
}
