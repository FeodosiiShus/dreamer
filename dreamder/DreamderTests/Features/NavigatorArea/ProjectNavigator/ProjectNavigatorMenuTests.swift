import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct ProjectNavigatorMenuTests {
    typealias Harness = ProjectNavigatorControllerHarness

    static let folders = ["Sources", "Empty"]
    static let files = [
        "a.txt", "b.md", "Sources/main.swift", "Config.plist", "Main.xib", "Fake.xcassets", "Fake.xcodeproj",
        "data.bin", "noextension"
    ]

    private func openAsTitles(_ harness: Harness, _ menu: NSMenu) throws -> [String] {
        let openAs = try #require(harness.menuItem(titled: "Open As", in: menu))
        let submenu = try #require(openAs.submenu)
        return harness.titles(of: submenu)
    }

    @Test
    func menuNeedsUpdateTracksTheClickedRow() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let a = try harness.file("a.txt")

            let outside = harness.buildMenu(clicking: nil)
            #expect(outside.item == nil)
            #expect(outside.items.isEmpty)
            #expect(outside.workspace === harness.workspace)

            let onFile = harness.buildMenu(clicking: a)
            #expect(onFile.item == a)
            #expect(!onFile.items.isEmpty)

            harness.outlineView.clickedRowOverride = 9_999
            harness.controller.menuNeedsUpdate(harness.menu)
            #expect(harness.menu.item == nil)
            #expect(harness.menu.items.isEmpty)

            harness.click(a)
            harness.controller.menuNeedsUpdate(NSMenu(title: "Foreign"))
            #expect(harness.menu.item == nil)
        }
    }

    @Test
    func fileMenuListsEveryItemInOrder() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let a = try harness.file("a.txt")

            let menu = harness.buildMenu(clicking: a)

            #expect(harness.titles(of: menu) == [
                "Show in Finder", "Open in Tab", "Open in New Window", "Open with External Editor", "Open As",
                "Cut", "Copy", "Paste", "Copy Path", "Copy Relative Path", "New File...",
                "New File from Clipboard", "New Folder", "New Folder from Selection", "Rename", "Move to Trash",
                "Delete Immediately...", "Duplicate File", "Sort by Name", "Sort by Type", "Source Control"
            ])
            for (title, key) in [("Cut", "x"), ("Copy", "c"), ("Paste", "v")] {
                let item = try #require(harness.menuItem(titled: title, in: menu))
                #expect(item.keyEquivalent == key)
                #expect(item.keyEquivalentModifierMask == [.command])
            }
            let fromClipboard = try #require(harness.menuItem(titled: "New File from Clipboard", in: menu))
            #expect(fromClipboard.keyEquivalent == "")
            #expect(harness.menuItem(titled: "Show File Inspector", in: menu) == nil)
            let delete = try #require(harness.menuItem(titled: "Delete Immediately...", in: menu))
            #expect(delete.isAlternate)
            #expect(delete.keyEquivalentModifierMask == .option)
            #expect(delete.action != nil)
            let trash = try #require(harness.menuItem(titled: "Move to Trash", in: menu))
            #expect(trash.action != nil)
            let sortByName = try #require(harness.menuItem(titled: "Sort by Name", in: menu))
            #expect(!sortByName.isEnabled)
            #expect(harness.menuItem(titled: "Sort by Type", in: menu)?.isEnabled == false)
            #expect(harness.menuItem(titled: "Open in New Window", in: menu)?.isEnabled == true)
            let sourceControl = try #require(harness.menuItem(titled: "Source Control", in: menu))
            let submenu = try #require(sourceControl.submenu)
            #expect(harness.titles(of: submenu) == ["Show History", "Annotate with Git Blame", "Rollback…"])
            #expect(submenu.items.allSatisfy { !$0.isEnabled })
        }
    }

    @Test
    func folderMenuOffersSortingAndExclusion() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let sources = try harness.file("Sources")

            let menu = harness.buildMenu(clicking: sources)

            #expect(harness.menuItem(titled: "Duplicate Folder", in: menu) != nil)
            #expect(harness.menuItem(titled: "Sort by Name", in: menu)?.isEnabled == true)
            #expect(harness.menuItem(titled: "Sort by Type", in: menu)?.isEnabled == true)
            #expect(harness.menuItem(titled: "Mark Directory as", in: menu) != nil)
            #expect(harness.menuItem(titled: "Excluded", in: menu) != nil)
            #expect(harness.menuItem(titled: "Excluded", in: menu)?.image != nil)
            #expect(try openAsTitles(harness, menu) == ["<None>"])
            let none = try #require(harness.menuItem(titled: "<None>", in: menu))
            #expect(!none.isEnabled)
        }
    }

    @Test
    func rootMenuCannotTrashDeleteOrBeMarkedAsExcluded() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let menu = harness.buildMenu(clicking: harness.rootFile)

            let trash = try #require(harness.menuItem(titled: "Move to Trash", in: menu))
            let delete = try #require(harness.menuItem(titled: "Delete Immediately...", in: menu))
            #expect(trash.action == nil)
            #expect(delete.action == nil)
            #expect(harness.menuItem(titled: "Mark Directory as", in: menu) == nil)
            #expect(harness.menuItem(titled: "New Folder from Selection", in: menu) == nil)
            #expect(harness.menuItem(titled: "Rename", in: menu) != nil)
        }
    }

    @Test
    func multipleSelectionHidesRenameAndOffersGroupingOnlyWithinOneParent() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files, loadsTree: true) { harness in
            let a = try harness.file("a.txt")
            let b = try harness.file("b.md")
            try harness.expand("Sources")
            let main = try harness.file("Sources/main.swift")

            harness.select([a, b])
            try await eventually { harness.outlineView.selectedRowIndexes.count == 2 }
            let sameParent = harness.buildMenu(clicking: a)
            #expect(harness.menuItem(titled: "Rename", in: sameParent) == nil)
            #expect(harness.menuItem(titled: "New Folder from Selection", in: sameParent) != nil)

            let sources = try harness.file("Sources")
            #expect(main.parent === sources)
            #expect(a.parent === harness.rootFile)
            try await eventually { harness.row(of: main) >= 0 }
            harness.select([a, main])
            try await eventually { harness.outlineView.selectedRowIndexes.count == 2 }
            let differentParents = harness.buildMenu(clicking: a)
            #expect(differentParents.selectedItems() == [a, main])
            #expect(differentParents.canCreateFolderFromSelection() == false)
            #expect(harness.menuItem(titled: "New Folder from Selection", in: differentParents) == nil)

            harness.select([a])
            try await eventually { harness.outlineView.selectedRowIndexes.count == 1 }
            let clickedOutsideSelection = harness.buildMenu(clicking: b)
            #expect(clickedOutsideSelection.selectedItems() == [b])
            #expect(harness.menuItem(titled: "Rename", in: clickedOutsideSelection) != nil)
        }
    }

    @Test
    func openAsSubmenuDependsOnTheContentType() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files, loadsTree: true) { harness in
            try harness.expand("Sources")
            let swift = harness.buildMenu(clicking: try harness.file("Sources/main.swift"))
            let swiftTitles = try openAsTitles(harness, swift)
            #expect(swiftTitles.first == "Source Code")
            #expect(swiftTitles.contains("Hex"))
            #expect(swiftTitles.contains("ASCII Property List"))
            #expect(swiftTitles.contains("Quick Look"))
            let swiftOpenAs = try #require(swift.items.first { $0.title == "Open As" }?.submenu)
            #expect(swiftOpenAs.items.contains { $0.isSeparatorItem })

            let plist = harness.buildMenu(clicking: try harness.file("Config.plist"))
            #expect(try openAsTitles(harness, plist).first == "Property List")

            let xib = harness.buildMenu(clicking: try harness.file("Main.xib"))
            #expect(try openAsTitles(harness, xib).contains("Interface Builder XIB Document"))

            let catalog = harness.buildMenu(clicking: try harness.file("Fake.xcassets"))
            #expect(try openAsTitles(harness, catalog).contains("Asset Catalog Document"))

            let project = harness.buildMenu(clicking: try harness.file("Fake.xcodeproj"))
            #expect(try openAsTitles(harness, project).contains("Xcode Project"))

            let binary = harness.buildMenu(clicking: try harness.file("data.bin"))
            #expect(try openAsTitles(harness, binary) == ["Quick Look"])

            let plain = harness.buildMenu(clicking: try harness.file("noextension"))
            #expect(try openAsTitles(harness, plain).contains("Quick Look"))

            let text = harness.buildMenu(clicking: try harness.file("a.txt"))
            #expect(try openAsTitles(harness, text) == ["ASCII Property List", "Hex", "Quick Look"])
        }
    }

    @Test
    func openAsSubmenuOfAMissingFileIsEmptyOfChoices() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            harness.menu.item = CEWorkspaceFile(url: harness.url("missing-for-menu.txt"))
            harness.menu.workspace = harness.workspace

            harness.menu.rebuild()

            let titles = try openAsTitles(harness, harness.menu)
            #expect(titles == ["<None>"])
        }
    }
}
