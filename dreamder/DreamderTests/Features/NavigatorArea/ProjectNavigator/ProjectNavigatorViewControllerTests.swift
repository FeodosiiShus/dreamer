import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct ProjectNavigatorViewControllerTests {
    typealias Harness = ProjectNavigatorControllerHarness

    static let folders = ["Sources", "Empty"]
    static let files = ["a.txt", "b.md", "Sources/main.swift", "Sources/util.swift"]

    private func selectInOutline(_ harness: Harness, _ files: CEWorkspaceFile...) {
        let rows = IndexSet(files.map { harness.row(of: $0) })
        harness.outlineView.selectRowIndexes(rows, byExtendingSelection: false)
    }

    private func makeDiscardedController(_ workspace: WorkspaceDocument) -> ProjectNavigatorWeakController {
        let controller = ProjectNavigatorViewController()
        controller.workspace = workspace
        _ = controller.view
        return ProjectNavigatorWeakController(controller: controller)
    }

    @Test
    func loadViewConfiguresTheOutlineAndExpandsTheRoot() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            #expect(harness.outlineView.isItemExpanded(harness.rootFile))
            #expect(harness.controller.expandedItems.contains(harness.rootFile))
            #expect(harness.controller.noResultsLabel.isHidden)
            #expect(harness.outlineView.allowsMultipleSelection)
            #expect(harness.outlineView.accessibilityIdentifier() == "ProjectNavigator")
            #expect(harness.outlineView.registeredDraggedTypes.contains(.fileURL))
            #expect(harness.controller.content == [harness.rootFile])
            let names = harness.childNames(of: harness.rootFile)
            #expect(["Empty", "Sources", "a.txt", "b.md"].allSatisfy { names.contains($0) })
        }
    }

    @Test
    func controllerWithoutAWorkspaceHasNoContent() async throws {
        let controller = ProjectNavigatorViewController()
        _ = controller.view
        #expect(controller.content.isEmpty)
        #expect(controller.hiddenEntryNames == [".git"])
        #expect(controller.filterIsEmpty == false)
        controller.handleFilterChange()
        #expect(controller.sortModes.mode(for: URL(filePath: "/tmp/dreamder-no-workspace")) == .name)
    }

    @Test
    func coderInitializerIsUnavailable() {
        #expect(ProjectNavigatorViewController(coder: NSCoder()) == nil)
    }

    @Test
    func outlineAutosavesTheExpandedFoldersUnderTheProjectPath() async throws {
        try withTempDir { directory in
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            let controller = ProjectNavigatorViewController()
            controller.workspace = workspace
            _ = controller.view
            let name = try #require(controller.outlineView.autosaveName)
            defer { UserDefaults.standard.removeObject(forKey: "NSOutlineView Items \(name)") }

            #expect(name == workspace.workspaceFileManager?.folderUrl.path)
            #expect(controller.outlineView.autosaveExpandedItems)
        }
    }

    @Test
    func contentIsEmptyWhenTheRootIsNoLongerIndexed() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            #expect(harness.controller.content == [harness.rootFile])

            harness.fileManager.flattenedFileItems.removeAll()

            #expect(harness.controller.content.isEmpty)
        }
    }

    @Test
    func clearSearchFieldFocusWorksWithoutAWorkspace() async throws {
        let controller = ProjectNavigatorViewController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        defer {
            window.contentViewController = nil
            window.close()
        }
        let field = NSTextField(string: "")
        field.frame = NSRect(x: 0, y: 0, width: 100, height: 20)
        window.contentView?.addSubview(field)
        #expect(window.makeFirstResponder(field))
        #expect(window.firstResponder is NSTextView)

        controller.clearSearchFieldFocus()

        #expect(window.firstResponder === controller.outlineView)
    }

    @Test
    func controllerDeallocatesOnceItsMenuIsReleased() async throws {
        try await withTempDir { directory in
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            let released = makeDiscardedController(workspace)
            try await eventually(timeout: .seconds(60)) { released.controller == nil }
        }
    }

    @Test
    func iconColorAndRowHeightApplyOnlyWhenTheyChange() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            harness.controller.iconColor = .monochrome
            harness.controller.iconColor = .monochrome
            #expect(harness.controller.iconColor == .monochrome)
            harness.controller.rowHeight = 31
            harness.controller.rowHeight = 31
            #expect(harness.outlineView.rowHeight == 31)
            let height = harness.controller.outlineView(
                harness.outlineView,
                heightOfRowByItem: harness.rootFile
            )
            #expect(height == 31)
        }
    }

    @Test
    func revealFileSelectsTheActiveTabAndExpandsItsParents() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let main = try harness.file("Sources/main.swift")
            let sources = try harness.file("Sources")
            harness.editor.openTab(file: main, asTemporary: false)

            harness.controller.revealFile(nil)

            #expect(harness.outlineView.isItemExpanded(sources))
            #expect(harness.outlineView.selectedRow == harness.row(of: main))
        }
    }

    @Test
    func revealFileWithoutAnActiveTabClearsTheSelection() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            harness.select([try harness.file("a.txt")])
            #expect(harness.outlineView.selectedRow >= 0)

            harness.controller.revealFile(nil)

            #expect(harness.outlineView.selectedRow == -1)
        }
    }

    @Test
    func revealItemRevealsFilesByIdAndIgnoresOtherSenders() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let util = try harness.file("Sources/util.swift")

            harness.controller.revealItem(42)
            #expect(harness.outlineView.selectedRow == -1)

            harness.controller.revealItem("/outside/of/the/workspace.txt")
            #expect(harness.outlineView.selectedRow == -1)

            harness.controller.revealItem(util.id)
            #expect(harness.outlineView.selectedRow == harness.row(of: util))
        }
    }

    @Test
    func revealingAFileMissingFromTheOutlinePresentsAnAlert() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let ghost = CEWorkspaceFile(url: harness.url("ghost-outline-file.txt"))
            let rowBefore = harness.outlineView.selectedRow

            harness.controller.reveal(ghost)

            #expect(DreamderHeadless.suppressedModals.contains("Could not find file"))
            #expect(harness.outlineView.selectedRow == rowBefore)
        }
    }

    @Test
    func revealScrollsToFilesOutsideTheVisibleRect() async throws {
        let names = (0..<40).map { String(format: "f%02d.txt", $0) }
        try await Harness.run(files: names, windowHeight: 160) { harness in
            let top = try harness.file("f00.txt")
            let bottom = try harness.file("f39.txt")

            harness.controller.reveal(top)
            #expect(harness.outlineView.selectedRow == harness.row(of: top))

            harness.controller.reveal(bottom)
            #expect(harness.outlineView.selectedRow == harness.row(of: bottom))
            let bottomRow = harness.row(of: bottom)
            #expect(harness.outlineView.rows(in: harness.outlineView.visibleRect).contains(bottomRow))
        }
    }

    @Test
    func updateSelectionSelectsKnownFilesAndIgnoresUnknownOnes() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let a = try harness.file("a.txt")

            harness.controller.updateSelection(itemID: a.id)
            #expect(harness.outlineView.selectedRow == harness.row(of: a))

            harness.controller.updateSelection(itemID: "/outside/of/the/workspace.txt")
            #expect(harness.outlineView.selectedRow == harness.row(of: a))

            harness.controller.updateSelection(itemID: nil)
            #expect(harness.outlineView.selectedRow == -1)

            harness.controller.select(by: .extensionInstallation(UUID()), forcesReveal: false)
            #expect(harness.outlineView.selectedRow == -1)
        }
    }

    @Test
    func expandAllAndCollapseAllToggleEveryFolder() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files, loadsTree: true) { harness in
            let sources = try harness.file("Sources")

            harness.controller.expandAll(nil)
            #expect(harness.outlineView.isItemExpanded(sources))
            try await harness.settleOutline()

            harness.controller.collapseAll(nil)
            try await eventually(timeout: .seconds(30)) { !harness.outlineView.isItemExpanded(sources) }
        }
    }

    @Test
    func clearSearchFieldFocusReturnsFocusToAnEmptyFieldEditor() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let field = NSTextField(string: "")
            field.frame = NSRect(x: 0, y: 0, width: 100, height: 20)
            harness.window.contentView?.addSubview(field)
            #expect(harness.window.makeFirstResponder(field))
            #expect(harness.window.firstResponder is NSTextView)

            harness.controller.clearSearchFieldFocus()

            #expect(harness.window.firstResponder === harness.outlineView)
        }
    }

    @Test
    func clearSearchFieldFocusKeepsFocusWhenTheFieldHasTextOrTheFilterIsActive() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let field = NSTextField(string: "typed")
            field.frame = NSRect(x: 0, y: 0, width: 100, height: 20)
            harness.window.contentView?.addSubview(field)
            #expect(harness.window.makeFirstResponder(field))

            harness.controller.clearSearchFieldFocus()
            #expect(harness.window.firstResponder is NSTextView)

            field.stringValue = ""
            harness.workspace.navigatorFilter = "main"
            harness.controller.clearSearchFieldFocus()
            #expect(harness.window.firstResponder is NSTextView)

            #expect(harness.window.makeFirstResponder(harness.outlineView))
            harness.controller.clearSearchFieldFocus()
            #expect(harness.window.firstResponder === harness.outlineView)
        }
    }

    @Test
    func clearSearchFieldFocusWithoutAWindowDoesNothing() async throws {
        let controller = ProjectNavigatorViewController()
        _ = controller.view
        controller.clearSearchFieldFocus()
    }

    @Test
    func doubleClickTogglesFoldersAndOpensFiles() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files, loadsTree: true) { harness in
            let action = try #require(harness.outlineView.doubleAction)
            let sources = try harness.file("Sources")
            let a = try harness.file("a.txt")

            harness.select([sources])
            harness.click(sources)
            _ = harness.controller.tryToPerform(action, with: harness.outlineView)
            #expect(harness.outlineView.isItemExpanded(sources))
            try await harness.settleOutline()

            _ = harness.controller.tryToPerform(action, with: harness.outlineView)
            try await eventually(timeout: .seconds(30)) { !harness.outlineView.isItemExpanded(sources) }

            harness.select([a])
            harness.click(a)
            _ = harness.controller.tryToPerform(action, with: harness.outlineView)
            #expect(harness.editor.tabs.contains { $0.file == a })
        }
    }

    @Test
    func doubleClickIgnoresMultipleSelectionAndEmptyClicks() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let action = try #require(harness.outlineView.doubleAction)
            let sources = try harness.file("Sources")
            let b = try harness.file("b.md")

            harness.select([sources, b])
            harness.click(sources)
            _ = harness.controller.tryToPerform(action, with: harness.outlineView)
            #expect(!harness.outlineView.isItemExpanded(sources))

            harness.select([b])
            harness.click(nil)
            _ = harness.controller.tryToPerform(action, with: harness.outlineView)
            #expect(!harness.editor.tabs.contains { $0.file == b })
        }
    }

    @Test
    func childrenFollowTheFolderOrderSetting() async throws {
        try await Harness.run(folders: ["zeta"], files: ["alpha.txt", "zeta/inner.txt"]) { harness in
            harness.workspace.sortFoldersOnTop = true
            #expect(harness.childNames(of: harness.rootFile).prefix(2) == ["zeta", "alpha.txt"])

            harness.workspace.sortFoldersOnTop = false
            #expect(harness.childNames(of: harness.rootFile).prefix(2) == ["alpha.txt", "zeta"])

            harness.workspace.navigatorFilter = "a"
            await harness.applyFilter()
            harness.workspace.sortFoldersOnTop = true
            #expect(harness.childNames(of: harness.rootFile).prefix(2) == ["zeta", "alpha.txt"])
            harness.workspace.sortFoldersOnTop = false
            #expect(harness.childNames(of: harness.rootFile).prefix(2) == ["alpha.txt", "zeta"])
        }
    }

    @Test
    func dataSourceAnswersForFilesFoldersAndStrangers() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files, loadsTree: true) { harness in
            let a = try harness.file("a.txt")
            let sources = try harness.file("Sources")
            let controller = harness.controller
            let outline = harness.outlineView

            #expect(controller.outlineView(outline, numberOfChildrenOfItem: nil) == 1)
            #expect(controller.outlineView(outline, numberOfChildrenOfItem: a) == 0)
            #expect(controller.outlineView(outline, numberOfChildrenOfItem: sources) == 2)
            #expect(controller.outlineView(outline, child: 0, ofItem: nil) as? CEWorkspaceFile == harness.rootFile)
            #expect(controller.outlineView(outline, isItemExpandable: sources))
            #expect(!controller.outlineView(outline, isItemExpandable: a))
            #expect(!controller.outlineView(outline, isItemExpandable: "stranger"))
            #expect(controller.outlineView(outline, pasteboardWriterForItem: a) as? NSURL == a.url as NSURL)
            #expect(controller.outlineView(outline, pasteboardWriterForItem: "stranger") == nil)
        }
    }

    @Test
    func delegateProvidesRowsAndCellsForItems() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files, loadsTree: true) { harness in
            let sources = try harness.file("Sources")
            let empty = try harness.file("Empty")
            let a = try harness.file("a.txt")
            let controller = harness.controller
            let outline = harness.outlineView
            let column = try #require(outline.tableColumns.first)

            #expect(controller.outlineView(outline, shouldShowCellExpansionFor: column, item: a))
            #expect(outline.frameOfOutlineCell(atRow: 0) == .zero)
            #expect(controller.outlineView(outline, rowViewForItem: a) is NavigatorTableRowView)
            #expect(controller.outlineView(outline, viewFor: nil, item: a) == nil)

            let sourcesCell = try #require(
                controller.outlineView(outline, viewFor: column, item: sources) as? ProjectNavigatorTableViewCell
            )
            #expect(sourcesCell.isExpandable)
            #expect(!sourcesCell.isExpanded)
            sourcesCell.onToggleDisclosure?()
            #expect(outline.isItemExpanded(sources))
            try await harness.settleOutline()
            sourcesCell.onToggleDisclosure?()
            try await eventually(timeout: .seconds(30)) { !outline.isItemExpanded(sources) }

            let emptyCell = try #require(
                controller.outlineView(outline, viewFor: column, item: empty) as? ProjectNavigatorTableViewCell
            )
            #expect(!emptyCell.isExpandable)

            let fileCell = try #require(
                controller.outlineView(outline, viewFor: column, item: a) as? ProjectNavigatorTableViewCell
            )
            #expect(!fileCell.isExpandable)

            let strangerCell = try #require(
                controller.outlineView(outline, viewFor: column, item: "stranger") as? ProjectNavigatorTableViewCell
            )
            #expect(strangerCell.onToggleDisclosure == nil)
        }
    }

    @Test
    func selectingASingleFileOpensItInATemporaryTab() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let a = try harness.file("a.txt")
            let sources = try harness.file("Sources")
            let b = try harness.file("b.md")

            selectInOutline(harness, a)
            #expect(harness.editor.selectedTab?.file == a)
            #expect(harness.controller.shouldSendSelectionUpdate)

            let notification = Notification(
                name: NSOutlineView.selectionDidChangeNotification,
                object: harness.outlineView
            )
            harness.controller.outlineViewSelectionDidChange(notification)
            #expect(harness.editor.selectedTab?.file == a)

            harness.outlineView.selectRowIndexes(
                IndexSet([harness.row(of: sources), harness.row(of: b)]),
                byExtendingSelection: false
            )
            #expect(harness.editor.selectedTab?.file == a)

            selectInOutline(harness, sources)
            #expect(harness.editor.selectedTab?.file == a)

            harness.controller.shouldSendSelectionUpdate = false
            selectInOutline(harness, b)
            #expect(harness.editor.selectedTab?.file == a)
            harness.controller.shouldSendSelectionUpdate = true

            let detached = Notification(name: NSOutlineView.selectionDidChangeNotification)
            harness.controller.outlineViewSelectionDidChange(detached)
            #expect(harness.editor.selectedTab?.file == a)
        }
    }

    @Test
    func expandingAFolderReselectsTheActiveFileInsideIt() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files, loadsTree: true) { harness in
            let sources = try harness.file("Sources")
            let main = try harness.file("Sources/main.swift")
            try harness.expand("Sources")
            harness.editor.openTab(file: main, asTemporary: false)
            let sourcesCell = try #require(harness.cell(for: sources))
            #expect(sourcesCell.isExpanded)

            try await harness.settleOutline()
            harness.outlineView.collapseItem(sources)
            try await eventually(timeout: .seconds(30)) { !harness.controller.expandedItems.contains(sources) }
            harness.outlineView.deselectAll(nil)
            harness.outlineView.expandItem(sources)

            #expect(harness.controller.expandedItems.contains(sources))
            #expect(harness.outlineView.selectedRow == harness.row(of: main))
            #expect(harness.cell(for: sources)?.isExpanded == true)
        }
    }

    @Test
    func expandAndCollapseNotificationsWithoutAnItemOrWithAForeignItemAreHarmless() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let main = try harness.file("Sources/main.swift")
            harness.editor.openTab(file: main, asTemporary: false)
            let foreign = CEWorkspaceFile(url: harness.url("foreign-notification.txt"))

            harness.controller.outlineViewItemDidExpand(
                Notification(name: NSOutlineView.itemDidExpandNotification, object: harness.outlineView)
            )
            harness.controller.outlineViewItemDidExpand(
                Notification(
                    name: NSOutlineView.itemDidExpandNotification,
                    object: harness.outlineView,
                    userInfo: ["NSObject": foreign]
                )
            )
            harness.controller.outlineViewItemDidCollapse(
                Notification(name: NSOutlineView.itemDidCollapseNotification, object: harness.outlineView)
            )
            harness.controller.outlineViewItemDidCollapse(
                Notification(
                    name: NSOutlineView.itemDidCollapseNotification,
                    object: harness.outlineView,
                    userInfo: ["NSObject": foreign]
                )
            )

            #expect(harness.outlineView.selectedRow == -1)
        }
    }

    @Test
    func collapsingWhileFilteringKeepsTheSavedExpandedState() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let sources = try harness.file("Sources")
            try harness.expand("Sources")
            harness.workspace.navigatorFilter = "main"
            harness.controller.expandedItems = [sources]

            harness.controller.outlineViewItemDidCollapse(
                Notification(
                    name: NSOutlineView.itemDidCollapseNotification,
                    object: harness.outlineView,
                    userInfo: ["NSObject": sources]
                )
            )
            harness.controller.outlineViewItemDidExpand(
                Notification(
                    name: NSOutlineView.itemDidExpandNotification,
                    object: harness.outlineView,
                    userInfo: ["NSObject": sources]
                )
            )

            #expect(harness.controller.expandedItems == [sources])
        }
    }

    @Test
    func persistentObjectsRoundTripThroughFileIds() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let a = try harness.file("a.txt")
            let controller = harness.controller
            let outline = harness.outlineView

            let persistent = controller.outlineView(outline, persistentObjectForItem: a) as? String
            #expect(persistent == a.id)
            #expect(controller.outlineView(outline, persistentObjectForItem: "stranger") == nil)
            #expect(controller.outlineView(outline, itemForPersistentObject: a.id) as? CEWorkspaceFile == a)
            #expect(controller.outlineView(outline, itemForPersistentObject: 7) == nil)
            #expect(controller.outlineView(outline, itemForPersistentObject: "/outside/the/workspace") == nil)
        }
    }

    @Test
    func tooltipShowsTheFileName() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let a = try harness.file("a.txt")
            var rect = NSRect.zero

            let named = harness.controller.outlineView(
                harness.outlineView,
                toolTipFor: NSCell(),
                rect: &rect,
                tableColumn: nil,
                item: a,
                mouseLocation: .zero
            )
            let stranger = harness.controller.outlineView(
                harness.outlineView,
                toolTipFor: NSCell(),
                rect: &rect,
                tableColumn: nil,
                item: "stranger",
                mouseLocation: .zero
            )

            #expect(named == "a.txt")
            #expect(stranger == "")
        }
    }
}

@MainActor
@Suite(.uiGate)
struct ProjectNavigatorRevealSettingTests {
    typealias Harness = ProjectNavigatorControllerHarness

    @Test
    func selectionChangesRevealTheFileWhenTheSettingIsOn() async throws {
        try await Harness.run(folders: ["Sources"], files: ["Sources/main.swift"], loadsTree: true) { harness in
            harness.settings.preferences.general.revealFileOnFocusChange = true
            let main = try harness.file("Sources/main.swift")

            harness.controller.updateSelection(itemID: main.id)

            #expect(harness.outlineView.isItemExpanded(try harness.file("Sources")))
            #expect(harness.outlineView.selectedRow == harness.row(of: main))
        }
    }

    @Test
    func selectionChangesDoNotRevealCollapsedFilesWhenTheSettingIsOff() async throws {
        try await Harness.run(folders: ["Sources"], files: ["Sources/main.swift", "a.txt"]) { harness in
            harness.settings.preferences.general.revealFileOnFocusChange = false
            let main = try harness.file("Sources/main.swift")
            harness.select([try harness.file("a.txt")])

            harness.controller.updateSelection(itemID: main.id)

            #expect(!harness.outlineView.isItemExpanded(try harness.file("Sources")))
            #expect(harness.outlineView.selectedRow == -1)
        }
    }
}
