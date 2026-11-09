import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct ProjectNavigatorMenuTests {
    typealias Harness = ProjectNavigatorControllerHarness

    private static let folders = ["Sources", "Empty"]
    private static let files = [
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
            let sameParent = harness.buildMenu(clicking: a)
            #expect(harness.menuItem(titled: "Rename", in: sameParent) == nil)
            #expect(harness.menuItem(titled: "New Folder from Selection", in: sameParent) != nil)

            let sources = try harness.file("Sources")
            #expect(main.parent === sources)
            #expect(a.parent === harness.rootFile)
            #expect(harness.row(of: main) >= 0)
            harness.select([a, main])
            let differentParents = harness.buildMenu(clicking: a)
            #expect(differentParents.selectedItems() == [a, main])
            #expect(differentParents.canCreateFolderFromSelection() == false)
            #expect(harness.menuItem(titled: "New Folder from Selection", in: differentParents) == nil)

            harness.select([a])
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

    @Test
    func markingADirectoryExcludesAndCancelsItsExclusion() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let sources = try harness.file("Sources")
            let excluded = try #require(harness.workspace.excludedDirectories)
            let menu = harness.buildMenu(clicking: sources)
            #expect(!excluded.rules.isExclusionRoot(sources.url))

            #expect(try harness.perform("Excluded", in: menu))
            #expect(excluded.rules.isExclusionRoot(sources.url))

            let rebuilt = harness.buildMenu(clicking: sources)
            #expect(harness.menuItem(titled: "Excluded", in: rebuilt) == nil)
            #expect(try harness.perform("Cancel Exclusion", in: rebuilt))
            #expect(!excluded.rules.isExclusionRoot(sources.url))
        }
    }

    @Test
    func itemsWithoutAFileDoNothingWhenMarkingDirectories() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let sources = try harness.file("Sources")
            let menu = harness.buildMenu(clicking: sources)
            let exclude = try #require(harness.menuItem(titled: "Excluded", in: menu))
            let excluded = try #require(harness.workspace.excludedDirectories)
            menu.item = nil
            let action = try #require(exclude.action)
            #expect(NSApplication.shared.sendAction(action, to: exclude.target, from: exclude))
            #expect(!excluded.rules.isExclusionRoot(sources.url))

            menu.item = sources
            let cancelMenu = harness.buildMenu(clicking: sources)
            try harness.perform("Excluded", in: cancelMenu)
            let rebuilt = harness.buildMenu(clicking: sources)
            let cancel = try #require(harness.menuItem(titled: "Cancel Exclusion", in: rebuilt))
            rebuilt.item = nil
            let cancelAction = try #require(cancel.action)
            #expect(NSApplication.shared.sendAction(cancelAction, to: cancel.target, from: cancel))
            #expect(excluded.rules.isExclusionRoot(sources.url))
            rebuilt.item = sources
            try harness.perform("Cancel Exclusion", in: rebuilt)
            #expect(!excluded.rules.isExclusionRoot(sources.url))
        }
    }

    @Test
    func menuCopiesAndDecodesBackIntoAProjectNavigatorMenu() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let fresh = ProjectNavigatorMenu(harness.controller)
            let copy = fresh.copy()
            #expect(copy is ProjectNavigatorMenu)

            let data = try NSKeyedArchiver.archivedData(withRootObject: fresh, requiringSecureCoding: false)
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
            unarchiver.requiresSecureCoding = false
            let decoded = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey)
            unarchiver.finishDecoding()
            #expect(decoded is ProjectNavigatorMenu)
        }
    }

    private func keyEvent(_ character: String, modifiers: NSEvent.ModifierFlags, in harness: Harness) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: 0,
                windowNumber: harness.window.windowNumber,
                context: nil,
                characters: character,
                charactersIgnoringModifiers: character,
                isARepeat: false,
                keyCode: 0
            )
        )
    }

    @Test
    func commandVStartsAnInlineNewFileFromClipboardTextOnlyWhenTheOutlineIsFirstResponder() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files, loadsTree: true) { harness in
            let sources = try harness.file("Sources")
            harness.select([sources])
            harness.click(sources)
            harness.pasteboard.replaceContents(withText: "pasted body")
            #expect(harness.window.makeFirstResponder(nil))
            let event = try keyEvent("v", modifiers: .command, in: harness)
            #expect(!harness.outlineView.performKeyEquivalent(with: event))
            #expect(harness.controller.pendingCreation == nil)

            #expect(harness.window.makeFirstResponder(harness.outlineView))
            #expect(harness.outlineView.performKeyEquivalent(with: event))
            #expect(harness.controller.pendingCreation?.contents == Data("pasted body".utf8))
            #expect(try harness.names(in: "Sources") == ["main.swift"])

            try harness.submitCreation("body.txt")
            #expect(try harness.contents("Sources/body.txt") == "pasted body")
        }
    }

    @Test
    func commandVPastesCopiedFilesIntoTheSelectedFolder() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let sources = try harness.file("Sources")
            harness.writeClipboard(["a.txt"], cut: false)
            harness.select([sources])
            #expect(harness.window.makeFirstResponder(harness.outlineView))

            #expect(harness.outlineView.performKeyEquivalent(with: try keyEvent("v", modifiers: .command, in: harness)))
            await harness.controller.pasteTask?.value

            #expect(harness.exists("Sources/a.txt"))
            #expect(harness.exists("a.txt"))
        }
    }

    @Test
    func commandCAndCommandXPutTheSelectionOnThePasteboard() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let a = try harness.file("a.txt")
            let b = try harness.file("b.md")
            let clipboard = ProjectNavigatorClipboard(pasteboard: harness.pasteboard)
            harness.select([a, b])
            #expect(harness.window.makeFirstResponder(harness.outlineView))

            #expect(harness.outlineView.performKeyEquivalent(with: try keyEvent("c", modifiers: .command, in: harness)))
            #expect(clipboard.fileURLs.map(\.lastPathComponent) == ["a.txt", "b.md"])
            #expect(!clipboard.isCut)

            #expect(harness.outlineView.performKeyEquivalent(with: try keyEvent("x", modifiers: .command, in: harness)))
            #expect(clipboard.fileURLs.map(\.lastPathComponent) == ["a.txt", "b.md"])
            #expect(clipboard.isCut)

            harness.select([harness.rootFile])
            harness.pasteboard.removeAllContents()
            #expect(harness.outlineView.performKeyEquivalent(with: try keyEvent("x", modifiers: .command, in: harness)))
            #expect(!clipboard.hasFiles)

            harness.outlineView.deselectAll(nil)
            #expect(harness.outlineView.performKeyEquivalent(with: try keyEvent("c", modifiers: .command, in: harness)))
            #expect(!clipboard.hasFiles)
        }
    }

    @Test
    func otherKeyEquivalentsAreForwardedToTheSuperclass() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            #expect(harness.window.makeFirstResponder(harness.outlineView))
            let plainV = try keyEvent("v", modifiers: [], in: harness)
            let commandShiftV = try keyEvent("V", modifiers: [.command, .shift], in: harness)
            let commandZ = try keyEvent("z", modifiers: .command, in: harness)
            let commandV = try keyEvent("v", modifiers: .command, in: harness)

            #expect(!harness.outlineView.performKeyEquivalent(with: plainV))
            #expect(!harness.outlineView.performKeyEquivalent(with: commandShiftV))
            #expect(!harness.outlineView.performKeyEquivalent(with: commandZ))

            let delegate = harness.outlineView.delegate
            harness.outlineView.delegate = nil
            #expect(!harness.outlineView.performKeyEquivalent(with: commandV))
            harness.outlineView.delegate = delegate
        }
    }

    @Test
    func clipboardMenuItemsAreValidOnlyWhenTheyCanAct() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let copy = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "")
            let cut = NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "")
            let paste = NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "")
            let fromClipboard = try #require(
                harness.menuItem(titled: "New File from Clipboard", in: harness.buildMenu(clicking: harness.rootFile))
            )
            let other = NSMenuItem(title: "Other", action: #selector(NSResponder.cancelOperation(_:)), keyEquivalent: "")
            harness.pasteboard.removeAllContents()

            harness.outlineView.deselectAll(nil)
            #expect(!harness.outlineView.validateMenuItem(copy))
            #expect(!harness.outlineView.validateMenuItem(cut))
            #expect(!harness.outlineView.validateMenuItem(paste))
            #expect(!harness.outlineView.validateMenuItem(fromClipboard))

            harness.select([try harness.file("a.txt")])
            #expect(harness.outlineView.validateMenuItem(copy))
            #expect(harness.outlineView.validateMenuItem(cut))
            #expect(harness.outlineView.validateMenuItem(fromClipboard))
            #expect(!harness.outlineView.validateMenuItem(other))

            harness.pasteboard.replaceContents(withText: "text")
            #expect(harness.outlineView.validateMenuItem(paste))
            harness.writeClipboard(["b.md"], cut: false)
            #expect(harness.outlineView.validateMenuItem(paste))

            let delegate = harness.outlineView.delegate
            harness.outlineView.delegate = nil
            #expect(!harness.outlineView.validateMenuItem(paste))
            harness.outlineView.delegate = delegate
        }
    }

    @Test
    func clipboardActionsWithoutAControllerLeaveTheClipboardAlone() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            harness.select([try harness.file("a.txt")])
            let delegate = harness.outlineView.delegate
            harness.outlineView.delegate = nil

            harness.outlineView.copy(nil)
            harness.outlineView.cut(nil)
            harness.outlineView.paste(nil)
            harness.outlineView.delegate = delegate

            #expect(!ProjectNavigatorClipboard(pasteboard: harness.pasteboard).hasFiles)
            #expect(ProjectNavigatorClipboard(pasteboard: harness.pasteboard).text == nil)
        }
    }
}
