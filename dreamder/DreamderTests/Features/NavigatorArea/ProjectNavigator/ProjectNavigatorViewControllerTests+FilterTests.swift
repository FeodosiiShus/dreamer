import AppKit
import Foundation
import Testing
@testable import Dreamder

extension ProjectNavigatorViewControllerTests {
    @Test
    func filterShowsMatchingItemsAndExpandsEverything() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files, loadsTree: true) { harness in
            harness.workspace.navigatorFilter = "main"

            await harness.applyFilter()

            #expect(!harness.controller.filterIsEmpty)
            #expect(!harness.outlineView.autosaveExpandedItems)
            #expect(harness.controller.noResultsLabel.isHidden)
            #expect(harness.childNames(of: harness.rootFile) == ["Sources"])
            let sources = try harness.file("Sources")
            #expect(harness.childNames(of: sources) == ["main.swift"])
            #expect(harness.outlineView.isItemExpanded(sources))
        }
    }

    @Test
    func aFolderNameMatchShowsEveryChildOfTheFolder() async throws {
        let folders = Self.folders + ["Sources/Deep"]
        let files = Self.files + ["Sources/Deep/x.txt"]
        try await Harness.run(folders: folders, files: files, loadsTree: true) { harness in
            harness.workspace.navigatorFilter = "Sources"

            await harness.applyFilter()

            let sources = try harness.file("Sources")
            #expect(harness.childNames(of: sources) == ["Deep", "main.swift", "util.swift"])
            let deep = try harness.file("Sources/Deep")
            #expect(harness.childNames(of: deep) == ["x.txt"])
        }
    }

    @Test
    func filterWithoutMatchesShowsTheNoResultsLabel() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            harness.workspace.navigatorFilter = "zzz-no-such-file"

            await harness.applyFilter()

            #expect(!harness.controller.noResultsLabel.isHidden)
            #expect(harness.childNames(of: harness.rootFile).isEmpty)
        }
    }

    @Test
    func clearingAFilterWithoutMatchesHidesTheNoResultsLabelAgain() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            harness.workspace.navigatorFilter = "zzz-no-such-file"
            await harness.applyFilter()
            #expect(!harness.controller.noResultsLabel.isHidden)

            harness.workspace.navigatorFilter = ""
            await harness.applyFilter()

            #expect(harness.controller.noResultsLabel.isHidden)
        }
    }

    @Test
    func aFilterWithMatchesHidesTheNoResultsLabelAgain() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files, loadsTree: true) { harness in
            harness.workspace.navigatorFilter = "zzz-no-such-file"
            await harness.applyFilter()
            #expect(!harness.controller.noResultsLabel.isHidden)

            harness.workspace.navigatorFilter = "main"
            await harness.applyFilter()

            #expect(harness.controller.noResultsLabel.isHidden)
            #expect(harness.childNames(of: harness.rootFile) == ["Sources"])
        }
    }

    @Test
    func sourceControlFilterKeepsOnlyChangedFiles() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let changed = try harness.file("a.txt")
            changed.gitStatus = .modified
            harness.fileManager.statusCarriers.insert(changed.id)
            harness.workspace.sourceControlFilter = true

            await harness.applyFilter()

            #expect(harness.childNames(of: harness.rootFile) == ["a.txt"])
            #expect(harness.controller.noResultsLabel.isHidden)
        }
    }

    @Test
    func clearingTheFilterRestoresTheExpandedFolders() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let sources = try harness.file("Sources")
            try harness.expand("Sources")
            #expect(harness.controller.expandedItems.contains(sources))

            harness.workspace.navigatorFilter = "main"
            await harness.applyFilter()
            harness.workspace.navigatorFilter = ""
            await harness.applyFilter()

            #expect(harness.outlineView.autosaveExpandedItems)
            #expect(harness.outlineView.isItemExpanded(sources))
            #expect(harness.outlineView.isItemExpanded(harness.rootFile))
            #expect(harness.controller.expandedItems.contains(sources))
        }
    }

    @Test
    func itemsAreShownByNameByAnAncestorOrByChangedStatus() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files, loadsTree: true) { harness in
            let topFile = try harness.file("a.txt")
            let main = try harness.file("Sources/main.swift")
            let util = try harness.file("Sources/util.swift")
            let sources = try harness.file("Sources")
            #expect(harness.controller.isShownByFilter(topFile))

            harness.workspace.navigatorFilter = "main"
            await harness.applyFilter()
            #expect(!harness.controller.isShownByFilter(topFile))
            #expect(harness.controller.isShownByFilter(sources))
            #expect(harness.controller.isShownByFilter(main))
            #expect(!harness.controller.isShownByFilter(util))

            harness.workspace.navigatorFilter = ""
            topFile.gitStatus = .modified
            harness.fileManager.statusCarriers.insert(topFile.id)
            harness.workspace.sourceControlFilter = true
            await harness.applyFilter()
            #expect(harness.controller.isShownByFilter(topFile))
            #expect(!harness.controller.isShownByFilter(main))
            topFile.gitStatus = GitStatus.none
            #expect(!harness.controller.isShownByFilter(topFile))

            topFile.gitStatus = .modified
            harness.workspace.navigatorFilter = "unrelated"
            await harness.applyFilter()
            #expect(!harness.controller.isShownByFilter(topFile))
        }
    }
}
