import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct ProjectNavigatorFilterScopeTests {
    typealias Harness = ProjectNavigatorControllerHarness

    private static let folders = ["src/deep", "node_modules/pkg", "lib"]
    private static let files = ["a.txt", "src/deep/y.js", "src/util.js", "node_modules/pkg/i.js", "lib/main.swift"]

    @Test
    func changingTheFilterReturnsBeforeAnyTreeWorkAndAppliesTheResultLater() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            harness.workspace.navigatorFilter = "main"

            harness.controller.handleFilterChange()

            #expect(harness.controller.filterMatches == .inactive)
            #expect(harness.childNames(of: harness.rootFile).contains("a.txt"))

            await harness.controller.filterTask?.value

            #expect(harness.controller.filterMatches.text == "main")
            #expect(harness.childNames(of: harness.rootFile) == ["lib"])
        }
    }

    @Test
    func aNewerFilterChangeSupersedesAnOlderOne() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            harness.workspace.navigatorFilter = "main"
            harness.controller.handleFilterChange()
            let older = try #require(harness.controller.filterTask)
            harness.workspace.navigatorFilter = "zzz-no-such-file"
            harness.controller.handleFilterChange()
            let newer = try #require(harness.controller.filterTask)

            await older.value
            await newer.value

            #expect(older.isCancelled)
            #expect(harness.controller.filterMatches.text == "zzz-no-such-file")
            #expect(harness.childNames(of: harness.rootFile).isEmpty)
            #expect(!harness.controller.noResultsLabel.isHidden)
        }
    }

    @Test
    func filteringNeverDescendsIntoExcludedFolders() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            harness.workspace.navigatorFilter = ".js"

            await harness.applyFilter()
            try await harness.settleOutline()

            let manager = harness.fileManager
            #expect(!manager.pendingLoads.contains { $0.contains("/node_modules/pkg") })
            #expect(!manager.childrenMap.keys.contains { $0.contains("/node_modules/pkg") })
            #expect(harness.childNames(of: harness.rootFile) == ["src"])
        }
    }

    @Test
    func aFilterReloadKeepsTheSelectionOfItemsThatStayVisible() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let kept = try harness.file("a.txt")
            harness.select([kept])
            harness.workspace.navigatorFilter = "a.txt"

            await harness.applyFilter()

            #expect(harness.outlineView.selectedRow == harness.row(of: kept))
            #expect(harness.outlineView.selectedRow >= 0)
            #expect(harness.controller.shouldSendSelectionUpdate)
        }
    }

    @Test
    func aFilterReloadDropsTheSelectionOfItemsThatBecomeHidden() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            harness.select([try harness.file("a.txt")])
            harness.workspace.navigatorFilter = "main"

            await harness.applyFilter()

            #expect(harness.outlineView.selectedRow == -1)
        }
    }

    @Test
    func foldersThatAreNotIndexedYetAreListedOnceTheirChildrenLoad() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            harness.workspace.navigatorFilter = "y.js"

            await harness.applyFilter()

            let src = try harness.file("src")
            try await eventually(timeout: .seconds(20)) { harness.childNames(of: src) == ["deep"] }
            let deep = try harness.file("src/deep")
            try await eventually(timeout: .seconds(20)) { harness.childNames(of: deep) == ["y.js"] }
        }
    }

    @Test
    func aBlankFilterKeepsEverythingVisibleAndRestoresTheExpandedState() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            harness.workspace.navigatorFilter = "   "

            await harness.applyFilter()

            #expect(harness.controller.filterMatches == .inactive)
            #expect(harness.outlineView.autosaveExpandedItems)
            #expect(harness.childNames(of: harness.rootFile).contains("a.txt"))
            #expect(harness.controller.noResultsLabel.isHidden)
        }
    }

    @Test
    func anActiveFilterWithoutAFileManagerFallsBackToTheUnfilteredState() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            harness.workspace.navigatorFilter = "main"
            harness.workspace.workspaceFileManager = nil

            await harness.applyFilter()

            #expect(harness.controller.filterMatches == .inactive)
            #expect(harness.controller.content.isEmpty)
        }
    }

    @Test
    func withoutAFileScopeTheFilterStillFindsMatches() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            harness.workspace.tearDownFileScope()
            harness.workspace.navigatorFilter = "main"

            await harness.applyFilter()

            #expect(harness.childNames(of: harness.rootFile) == ["lib"])
            #expect(harness.controller.noResultsLabel.isHidden)
        }
    }

    @Test
    func changedFilesStayReachableThroughTheirFolders() async throws {
        let folders = ["Sources/Deep", "Other"]
        let files = ["Sources/Deep/x.txt", "Sources/Deep/y.txt", "Other/z.txt", "a.txt"]
        try await Harness.run(folders: folders, files: files, loadsTree: true) { harness in
            let changed = try harness.file("Sources/Deep/x.txt")
            let untouched = try harness.file("Sources/Deep/y.txt")
            let unchanged = try harness.file("a.txt")
            changed.gitStatus = .modified
            unchanged.gitStatus = GitStatus.none
            harness.fileManager.statusCarriers.formUnion([changed.id, unchanged.id])
            harness.workspace.sourceControlFilter = true

            await harness.applyFilter()

            #expect(harness.childNames(of: harness.rootFile) == ["Sources"])
            #expect(harness.childNames(of: try harness.file("Sources")) == ["Deep"])
            #expect(harness.childNames(of: try harness.file("Sources/Deep")) == ["x.txt"])
            #expect(harness.outlineView.isItemExpanded(try harness.file("Sources/Deep")))
            #expect(!harness.controller.isShownByFilter(untouched))
        }
    }

    @Test
    func changedFilesNarrowedByNameKeepOnlyTheMatchingOnes() async throws {
        let files = ["Sources/x.txt", "Sources/y.txt"]
        try await Harness.run(folders: ["Sources"], files: files, loadsTree: true) { harness in
            let first = try harness.file("Sources/x.txt")
            let second = try harness.file("Sources/y.txt")
            first.gitStatus = .modified
            second.gitStatus = .modified
            harness.fileManager.statusCarriers.formUnion([first.id, second.id])
            harness.workspace.sourceControlFilter = true
            harness.workspace.navigatorFilter = "y.t"

            await harness.applyFilter()

            #expect(harness.childNames(of: try harness.file("Sources")) == ["y.txt"])
        }
    }

    @Test
    func childrenAreEmptyWithoutAWorkspaceOrAFileManager() async throws {
        let orphan = ProjectNavigatorViewController()
        #expect(orphan.visibleChildren(of: CEWorkspaceFile(url: URL(filePath: "/tmp/dreamder-orphan"))).isEmpty)

        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            harness.workspace.workspaceFileManager = nil

            #expect(harness.controller.visibleChildren(of: harness.rootFile).isEmpty)
        }
    }
}
