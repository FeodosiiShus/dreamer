import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct ProjectNavigatorFilterRefreshTests {
    typealias Harness = ProjectNavigatorControllerHarness
    typealias Coordinator = ProjectNavigatorOutlineView.Coordinator

    private static let folders = ["src", "docs"]
    private static let files = ["src/a.txt", "docs/guide.md", "readme.txt"]

    private func addIndexedFolder(_ path: String, to harness: Harness) throws {
        try harness.makeDirectory(path)
        try harness.fileManager.refresh(directoryAt: harness.url("src"))
    }

    @Test
    func aNewMatchingNestedFolderAppearsWithoutRetypingTheFilter() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files, loadsTree: true) { harness in
            harness.workspace.navigatorFilter = "widget"
            await harness.applyFilter()
            #expect(!harness.controller.noResultsLabel.isHidden)
            #expect(harness.childNames(of: harness.rootFile).isEmpty)

            try addIndexedFolder("src/inner/widgets", to: harness)
            harness.controller.refreshFilterAfterFileChanges()
            await harness.controller.filterTask?.value

            #expect(harness.controller.noResultsLabel.isHidden)
            #expect(harness.childNames(of: harness.rootFile) == ["src"])
        }
    }

    @Test
    func refreshingAnInactiveFilterDoesNothing() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            harness.controller.refreshFilterAfterFileChanges()

            #expect(harness.controller.filterTask == nil)
            #expect(harness.controller.filterMatches == .inactive)
        }
    }

    @Test
    func aRefreshKeepsTheExpansionOfAPendingFilterChange() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files, loadsTree: true) { harness in
            harness.workspace.navigatorFilter = "readme"
            await harness.applyFilter()
            let src = try harness.file("src")
            #expect(!harness.outlineView.isItemExpanded(src))

            harness.workspace.navigatorFilter = "a.txt"
            harness.controller.handleFilterChange()
            let typed = try #require(harness.controller.filterTask)
            harness.controller.refreshFilterAfterFileChanges()
            let refreshed = try #require(harness.controller.filterTask)
            await typed.value
            await refreshed.value

            #expect(typed.isCancelled)
            #expect(harness.outlineView.isItemExpanded(src))
            #expect(!harness.controller.filterResolutionExpands)
        }
    }

    @Test
    func aRefreshLeavesTheExpansionAloneWhenNothingIsPending() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files, loadsTree: true) { harness in
            harness.workspace.navigatorFilter = "a.txt"
            await harness.applyFilter()
            let src = try harness.file("src")
            #expect(harness.outlineView.isItemExpanded(src))
            harness.outlineView.collapseItem(src)
            try await harness.settleOutline()

            harness.controller.refreshFilterAfterFileChanges()
            await harness.controller.filterTask?.value

            #expect(!harness.outlineView.isItemExpanded(src))
            #expect(harness.childNames(of: src) == ["a.txt"])
        }
    }

    @Test
    func theCoordinatorRefreshesAnActiveFilterWhenTheFileSystemChanges() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files, loadsTree: true) { harness in
            harness.workspace.navigatorFilter = "widget"
            await harness.applyFilter()
            let coordinator = Coordinator(harness.workspace)
            coordinator.controller = harness.controller
            try await eventually(timeout: .seconds(20)) { coordinator.filterReload != nil }
            await coordinator.filterReload?.value
            await harness.controller.filterTask?.value
            #expect(harness.childNames(of: harness.rootFile).isEmpty)

            try addIndexedFolder("src/widgets", to: harness)
            coordinator.fileManagerUpdated(updatedItems: [try harness.file("src")])
            let superseded = try #require(coordinator.filterRefresh)
            coordinator.fileManagerUpdated(updatedItems: [try harness.file("src")])

            try await eventually(timeout: .seconds(20)) { harness.childNames(of: harness.rootFile) == ["src"] }
            #expect(superseded.isCancelled)
            #expect(harness.controller.filterMatches.text == "widget")
        }
    }

    @Test
    func theCoordinatorIgnoresFileSystemChangesWhileNoFilterIsActive() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let coordinator = Coordinator(harness.workspace)
            coordinator.controller = harness.controller

            coordinator.fileManagerUpdated(updatedItems: [harness.rootFile])

            #expect(coordinator.filterRefresh == nil)
        }
    }
}
