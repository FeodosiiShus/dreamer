import AppKit
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct FindNavigatorListViewControllerTests {
    private func deleteKeyUp(in harness: FindNavigatorListHarness) throws -> NSEvent {
        let key = String(NSEvent.SpecialKey.delete.unicodeScalar)
        return try #require(NSEvent.keyEvent(
            with: .keyUp,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: harness.window.windowNumber,
            context: nil,
            characters: key,
            charactersIgnoringModifiers: key,
            isARepeat: false,
            keyCode: 51
        ))
    }

    private func letterKeyUp(in harness: FindNavigatorListHarness) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyUp,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: harness.window.windowNumber,
            context: nil,
            characters: "a",
            charactersIgnoringModifiers: "a",
            isARepeat: false,
            keyCode: 0
        ))
    }

    @Test
    func loadViewConfiguresTheOutlineInsideAScrollView() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searched(in: dir)
            let harness = try FindNavigatorListHarness(workspace: workspace)
            defer { harness.close() }

            #expect(harness.controller.view is NSScrollView)
            #expect(harness.outline.tableColumns.count == 1)
            #expect(harness.outline.tableColumns.first?.identifier.rawValue == "Cell")
            #expect(harness.outline.tableColumns.first?.title == "Cell")
            #expect(harness.outline.headerView == nil)
            #expect(harness.outline.indentationPerLevel == 14)
            #expect(harness.outline.style == .plain)
            #expect(harness.outline.rowHeight == Islands.listRowHeight)
            #expect(harness.controller.acceptsFirstResponder)
            #expect(harness.outline.dataSource === harness.controller)
            #expect(harness.outline.delegate === harness.controller)
        }
    }

    @Test
    func controllerCannotBeDecoded() throws {
        let data = try NSKeyedArchiver.archivedData(withRootObject: NSString(string: "x"), requiringSecureCoding: false)
        let decoder = try NSKeyedUnarchiver(forReadingFrom: data)
        #expect(FindNavigatorListViewController(coder: decoder) == nil)
    }

    @Test
    func settingResultsDoesNotReloadButUpdatingDoes() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searched(in: dir)
            let harness = try FindNavigatorListHarness(workspace: workspace)
            defer { harness.close() }

            harness.controller.setSearchResults(harness.ordered)
            #expect(harness.outline.numberOfRows == 0)

            harness.controller.updateNewSearchResults(harness.ordered)
            #expect(harness.outline.numberOfRows == 5)
            #expect(harness.outline.isItemExpanded(harness.fileA))
            #expect(harness.outline.isItemExpanded(harness.fileB))
        }
    }

    @Test
    func dataSourceDescribesFilesAndTheirMatches() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searched(in: dir)
            let harness = try FindNavigatorListHarness(workspace: workspace)
            defer { harness.close() }
            harness.load()
            let controller = harness.controller
            let outline = harness.outline

            #expect(controller.outlineView(outline, numberOfChildrenOfItem: nil) == 2)
            #expect(controller.outlineView(outline, numberOfChildrenOfItem: harness.fileA) == 2)
            #expect(controller.outlineView(outline, numberOfChildrenOfItem: harness.fileB) == 1)
            let fileBFirstMatch = try harness.fileB.lineMatches.required(at: 0)
            #expect(controller.outlineView(outline, numberOfChildrenOfItem: fileBFirstMatch) == 2)

            let top = controller.outlineView(outline, child: 1, ofItem: nil)
            #expect((top as? SearchResultModel) === harness.fileB)
            let child = controller.outlineView(outline, child: 1, ofItem: harness.fileA)
            let fileASecondMatch = try harness.fileA.lineMatches.required(at: 1)
            #expect((child as? SearchResultMatchModel) === fileASecondMatch)

            #expect(controller.outlineView(outline, isItemExpandable: harness.fileA))
            let fileAFirstMatch = try harness.fileA.lineMatches.required(at: 0)
            #expect(!controller.outlineView(outline, isItemExpandable: fileAFirstMatch))
        }
    }

    @Test
    func delegateBuildsRowsAndCellsPerItemKind() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searched(in: dir)
            let harness = try FindNavigatorListHarness(workspace: workspace)
            defer { harness.close() }
            harness.load()
            let controller = harness.controller
            let outline = harness.outline
            let column = try #require(outline.tableColumns.first)
            let match = try harness.fileA.lineMatches.required(at: 0)

            #expect(controller.outlineView(outline, shouldShowCellExpansionFor: column, item: harness.fileA))
            #expect(!controller.outlineView(outline, shouldShowCellExpansionFor: column, item: match))
            #expect(controller.outlineView(outline, shouldShowOutlineCellForItem: match))
            #expect(controller.outlineView(outline, rowViewForItem: match) is NavigatorTableRowView)

            #expect(controller.outlineView(outline, viewFor: column, item: match) is FindNavigatorListMatchCell)
            #expect(controller.outlineView(outline, viewFor: nil, item: match) == nil)

            let fileCell = try #require(
                controller.outlineView(outline, viewFor: column, item: harness.fileA) as? FindNavigatorListFileCell
            )
            #expect(fileCell.displayedName == "a.swift")
            #expect(fileCell.displayedCount == "2")
            #expect(
                fileCell.displayedDirectory
                    == FindNavigatorListFileCell.relativeDirectory(of: harness.fileA.file.url, in: workspace.fileURL)
            )
            #expect(controller.outlineView(outline, viewFor: column, item: "not a result") == nil)
        }
    }

    @Test
    func selectingAMatchOpensItsFileInTheActiveEditorOnce() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searched(in: dir)
            let harness = try FindNavigatorListHarness(workspace: workspace)
            defer { harness.close() }
            harness.load()
            let editor = try #require(harness.editor)
            let match = try harness.fileA.lineMatches.required(at: 1)

            harness.select(match)
            #expect((harness.controller.selectedItem as? SearchResultMatchModel) === match)
            #expect(editor.selectedTab?.file.url == match.file.url)
            #expect(editor.tabs.count == 1)

            editor.closeTab(file: try #require(editor.selectedTab).file)
            #expect(editor.tabs.isEmpty)
            harness.selectionChanged()
            #expect(editor.tabs.isEmpty)

            let other = try harness.fileB.lineMatches.required(at: 0)
            harness.select(other)
            #expect((harness.controller.selectedItem as? SearchResultMatchModel) === other)
            #expect(editor.selectedTab?.file.url == other.file.url)
        }
    }

    @Test
    func selectingAFileRowOpensItsFileOnce() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searched(in: dir)
            let harness = try FindNavigatorListHarness(workspace: workspace)
            defer { harness.close() }
            harness.load()
            let editor = try #require(harness.editor)

            harness.select(harness.fileB)
            #expect((harness.controller.selectedItem as? SearchResultModel) === harness.fileB)
            #expect(editor.selectedTab?.file.url == harness.fileB.file.url)

            editor.closeTab(file: try #require(editor.selectedTab).file)
            #expect(editor.tabs.isEmpty)
            harness.selectionChanged()
            #expect(editor.tabs.isEmpty)

            harness.select(harness.fileA)
            #expect(editor.selectedTab?.file.url == harness.fileA.file.url)
        }
    }

    @Test
    func selectionChangeWithoutARowOrFromAnotherObjectChangesNothing() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searched(in: dir)
            let harness = try FindNavigatorListHarness(workspace: workspace)
            defer { harness.close() }
            harness.load()
            let editor = try #require(harness.editor)

            harness.outline.deselectAll(nil)
            harness.selectionChanged()
            #expect(harness.controller.selectedItem == nil)

            harness.select(harness.fileA)
            editor.closeTab(file: try #require(editor.selectedTab).file)
            harness.controller.outlineViewSelectionDidChange(
                Notification(name: NSOutlineView.selectionDidChangeNotification, object: NSObject())
            )
            #expect(editor.tabs.isEmpty)
        }
    }

    @Test
    func updatingResultsReselectsThePreviousItem() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searched(in: dir)
            let harness = try FindNavigatorListHarness(workspace: workspace)
            defer { harness.close() }
            harness.load()
            let match = try harness.fileB.lineMatches.required(at: 0)
            harness.select(match)
            harness.outline.deselectAll(nil)
            #expect(harness.outline.selectedRow == -1)

            harness.controller.updateNewSearchResults(harness.ordered)
            #expect(harness.outline.selectedRow == harness.outline.row(forItem: match))
        }
    }

    @Test
    func selectSearchResultIgnoresUnknownAndAlreadySelectedItems() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searched(in: dir)
            let harness = try FindNavigatorListHarness(workspace: workspace)
            defer { harness.close() }
            harness.load()

            let stranger = SearchResultModel(file: harness.fileA.file, score: 0)
            harness.controller.selectSearchResult(stranger)
            #expect(harness.outline.selectedRow == -1)

            let match = try harness.fileA.lineMatches.required(at: 0)
            harness.controller.selectSearchResult(match)
            let row = harness.outline.row(forItem: match)
            #expect(harness.outline.selectedRow == row)

            harness.controller.selectSearchResult(match)
            #expect(harness.outline.selectedRow == row)
        }
    }

    @Test
    func rowHeightsFitTheWrappedMatchText() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searched(in: dir)
            let harness = try FindNavigatorListHarness(workspace: workspace)
            defer { harness.close() }
            harness.load()
            let controller = harness.controller
            let outline = harness.outline
            let match = try harness.fileA.lineMatches.required(at: 0)
            let column = try #require(outline.tableColumns.first)

            #expect(controller.outlineView(outline, heightOfRowByItem: harness.fileA) == Islands.listRowHeight)
            let regular = controller.outlineView(outline, heightOfRowByItem: match)
            #expect(regular >= CGFloat(controller.rowHeight))

            let longLine = String(repeating: "word ", count: 80) + "needle"
            let keyword = try #require(longLine.range(of: "needle"))
            let longMatch = SearchResultMatchModel(
                rangeWithinFile: longLine.startIndex..<longLine.endIndex,
                file: harness.fileA.file,
                lineContent: longLine,
                keywordRange: keyword
            )
            let wrapped = controller.outlineView(outline, heightOfRowByItem: longMatch)
            #expect(wrapped >= regular)

            #expect(controller.outlineView(NSOutlineView(), heightOfRowByItem: match) == CGFloat(controller.rowHeight))

            column.width = 20
            #expect(controller.outlineView(outline, heightOfRowByItem: match) == CGFloat(controller.rowHeight))
        }
    }

    @Test
    func changingTheRowHeightReloadsTheOutline() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searched(in: dir)
            let harness = try FindNavigatorListHarness(workspace: workspace)
            defer { harness.close() }
            harness.load()
            harness.outline.collapseItem(harness.fileA)
            #expect(harness.outline.numberOfRows == 3)

            harness.controller.rowHeight = 40
            #expect(harness.controller.rowHeight == 40)
            #expect(harness.outline.numberOfRows >= 2)
            let match = try harness.fileB.lineMatches.required(at: 0)
            #expect(harness.controller.outlineView(harness.outline, heightOfRowByItem: match) >= 40)
        }
    }

    @Test
    func resizingTheColumnRecomputesMatchRowHeights() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searched(in: dir)
            let harness = try FindNavigatorListHarness(workspace: workspace)
            defer { harness.close() }
            harness.load()
            let column = try #require(harness.outline.tableColumns.first)
            column.width = 200
            harness.controller.outlineViewColumnDidResize(
                Notification(name: NSOutlineView.columnDidResizeNotification, object: harness.outline)
            )
            let firstMatch = try harness.fileA.lineMatches.required(at: 0)
            let matchRow = harness.outline.row(forItem: firstMatch)
            #expect(harness.outline.rect(ofRow: matchRow).height >= CGFloat(harness.controller.rowHeight))

            let bare = SearchResultModel(file: harness.fileA.file, score: 0)
            harness.controller.updateNewSearchResults([bare])
            #expect(harness.outline.numberOfRows == 1)
            harness.controller.outlineViewColumnDidResize(
                Notification(name: NSOutlineView.columnDidResizeNotification, object: harness.outline)
            )
            #expect(harness.outline.numberOfRows == 1)
        }
    }

    @Test
    func deleteKeyRemovesTheSelectedMatchAndThenItsEmptyFile() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searched(in: dir)
            let harness = try FindNavigatorListHarness(workspace: workspace)
            defer { harness.close() }
            harness.load()
            let second = try harness.fileA.lineMatches.required(at: 1)

            try harness.select(harness.fileA.lineMatches.required(at: 0))
            harness.controller.keyUp(with: try deleteKeyUp(in: harness))
            #expect(harness.fileA.lineMatches.count == 1)
            #expect(harness.outline.numberOfRows == 4)
            #expect(harness.outline.selectedRow == 1)
            #expect((harness.outline.item(atRow: 1) as? SearchResultMatchModel) === second)

            harness.controller.keyUp(with: try deleteKeyUp(in: harness))
            #expect(harness.fileA.lineMatches.isEmpty)
            #expect(harness.outline.numberOfRows == 2)
            #expect((harness.outline.item(atRow: 0) as? SearchResultModel) === harness.fileB)
        }
    }

    @Test
    func deleteKeyRemovesTheSelectedFileRow() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searched(in: dir)
            let harness = try FindNavigatorListHarness(workspace: workspace)
            defer { harness.close() }
            harness.load()

            harness.select(harness.fileA)
            harness.controller.keyUp(with: try deleteKeyUp(in: harness))
            #expect(harness.outline.numberOfRows == 2)
            #expect((harness.outline.item(atRow: 0) as? SearchResultModel) === harness.fileB)
        }
    }

    @Test
    func otherKeysAndMissingSelectionLeaveTheResultsAlone() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searched(in: dir)
            let harness = try FindNavigatorListHarness(workspace: workspace)
            defer { harness.close() }
            harness.load()

            try harness.select(harness.fileA.lineMatches.required(at: 0))
            harness.controller.keyUp(with: try letterKeyUp(in: harness))
            #expect(harness.outline.numberOfRows == 5)

            harness.outline.deselectAll(nil)
            harness.controller.keyUp(with: try deleteKeyUp(in: harness))
            #expect(harness.outline.numberOfRows == 5)
            #expect(harness.fileA.lineMatches.count == 2)
        }
    }
}
