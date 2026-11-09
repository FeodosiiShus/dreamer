//
//  FindNavigatorListViewController.swift
//  Dreamder
//
//  Created by Khan Winter on 7/7/22.
//

import SwiftUI

final class FindOutlineView: NSOutlineView {
    static let returnKeyCodes: Set<UInt16> = [36, 76]

    var onReturn: (NSEvent.ModifierFlags) -> Void = { _ in }

    override func keyDown(with event: NSEvent) {
        guard Self.returnKeyCodes.contains(event.keyCode) else {
            super.keyDown(with: event)
            return
        }
        onReturn(event.modifierFlags.intersection(.deviceIndependentFlagsMask))
    }

    override func moveDown(_ sender: Any?) {
        moveSelection(by: 1)
    }

    override func moveUp(_ sender: Any?) {
        moveSelection(by: -1)
    }

    private func moveSelection(by delta: Int) {
        guard numberOfRows > 0 else { return }
        let origin = selectedRow >= 0 ? selectedRow : (delta > 0 ? -1 : numberOfRows)
        let target = min(max(origin + delta, 0), numberOfRows - 1)
        selectRowIndexes(IndexSet([target]), byExtendingSelection: false)
        scrollRowToVisible(target)
    }
}

final class FindNavigatorListViewController: NSViewController {

    public var workspace: WorkspaceDocument
    public var selectedItem: Any?

    private var searchItems: [SearchResultModel] = []
    private let scrollView = NSScrollView()
    private let outlineView = FindOutlineView()
    private var isRestoringSelection = false

    var rowHeight: Double = Double(Islands.listRowHeight) {
        didSet {
            outlineView.reloadData()
        }
    }

    /// Setup the `scrollView` and `outlineView`
    override func loadView() {
        self.scrollView.drawsBackground = false
        self.view = scrollView
        self.view.wantsLayer = true

        self.outlineView.dataSource = self
        self.outlineView.delegate = self
        self.outlineView.onReturn = { [weak self] modifiers in
            self?.handleReturn(modifiers)
        }
        self.outlineView.headerView = nil
        self.outlineView.lineBreakMode = .byTruncatingTail
        self.outlineView.style = .plain
        self.outlineView.backgroundColor = .clear
        self.outlineView.appearance = NSAppearance(named: .darkAqua)
        self.outlineView.rowHeight = Islands.listRowHeight
        self.outlineView.rowSizeStyle = .custom
        self.outlineView.intercellSpacing = NSSize(width: 0, height: 0)
        self.outlineView.indentationPerLevel = 14
        self.outlineView.usesAlternatingRowBackgroundColors = false
        self.outlineView.selectionHighlightStyle = .regular

        let column = NSTableColumn(identifier: .init(rawValue: "Cell"))
        column.title = "Cell"
        outlineView.addTableColumn(column)

        self.scrollView.documentView = outlineView
        self.scrollView.contentView.drawsBackground = false
        self.scrollView.contentView.automaticallyAdjustsContentInsets = false
        self.scrollView.contentView.contentInsets = .init(top: 4, left: 0, bottom: 4, right: 0)
    }

    init(workspace: WorkspaceDocument) {
        self.workspace = workspace
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { true }

    private var state: WorkspaceDocument.SearchState? {
        workspace.searchState
    }

    /// Sets the search items for the view without loading anything.
    /// - Parameter searchItems: The search items to set.
    public func setSearchResults(_ searchItems: [SearchResultModel]) {
        self.searchItems = searchItems
    }

    /// Updates the view with new search results and updates the UI.
    /// - Parameter searchItems: The search items to set.
    public func updateNewSearchResults(_ searchItems: [SearchResultModel]) {
        self.searchItems = searchItems
        isRestoringSelection = true
        defer { isRestoringSelection = false }
        outlineView.reloadData()
        outlineView.expandItem(nil, expandChildren: true)

        if let selectedItem {
            selectSearchResult(selectedItem)
        }
    }

    func focusResults() {
        guard outlineView.numberOfRows > 0 else { return }
        view.window?.makeFirstResponder(outlineView)
        if outlineView.selectedRow < 0 {
            outlineView.selectRowIndexes(IndexSet([0]), byExtendingSelection: false)
        }
    }

    func openSelection(focusEditor: Bool) {
        guard let item = outlineView.item(atRow: outlineView.selectedRow) else { return }
        open(item)
        if focusEditor {
            let workspace = workspace
            Task { await FindNavigatorOpener.focusEditor(in: workspace) }
        }
    }

    func handleReturn(_ modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains([.option, .shift]) {
            replaceAll()
        } else if modifiers.contains(.command), state?.selectedMode.isReplaceMode == true {
            replaceSelected()
        } else {
            openSelection(focusEditor: true)
        }
    }

    private func replaceAll() {
        guard let state else { return }
        Task { await state.replaceAll() }
    }

    private func replaceSelected() {
        guard let state else { return }
        Task { await state.replaceSelected() }
    }

    private func open(_ item: Any) {
        if let match = item as? SearchResultMatchModel {
            FindNavigatorOpener.open(match, in: workspace)
        } else if let result = item as? SearchResultModel {
            FindNavigatorOpener.open(result.file, in: workspace)
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.charactersIgnoringModifiers == String(NSEvent.SpecialKey.delete.unicodeScalar) {
            if let state, state.selectedMode.isReplaceMode {
                state.toggleSkipSelected()
            } else {
                deleteSelectedItem()
            }
        }
        super.keyUp(with: event)
    }

    /// Removes the selected item, called in response to an action like the backspace
    /// character
    private func deleteSelectedItem() {
        let selectedRow = outlineView.selectedRow
        guard selectedRow >= 0,
              let selectedItem = outlineView.item(atRow: selectedRow) else { return }

        if selectedItem is SearchResultMatchModel {
            guard let parent = outlineView.parent(forItem: selectedItem) else { return }

            // Remove the item from the search results
            let parentIndex = outlineView.childIndex(forItem: parent)
            let childIndex = outlineView.childIndex(forItem: selectedItem)
            searchItems[parentIndex].lineMatches.remove(at: childIndex)

            // If this was the last child, we need to remove the parent or we'll
            // hit an exception
            if searchItems[parentIndex].lineMatches.isEmpty {
                searchItems.remove(at: parentIndex)
                outlineView.removeItems(at: IndexSet([parentIndex]), inParent: nil)
            } else {
                outlineView.reloadItem(parent, reloadChildren: true)
            }
        } else {
            let index = outlineView.childIndex(forItem: selectedItem)
            searchItems.remove(at: index)
            outlineView.removeItems(at: IndexSet([index]), inParent: nil)
        }

        outlineView.selectRowIndexes(IndexSet([selectedRow]), byExtendingSelection: false)
    }

    public func selectSearchResult(_ selectedItem: Any) {
        let index = outlineView.row(forItem: selectedItem)
        guard index >= 0 && index != outlineView.selectedRow else { return }
        outlineView.selectRowIndexes(IndexSet([index]), byExtendingSelection: false)
    }
}

// MARK: - NSOutlineViewDataSource

extension FindNavigatorListViewController: NSOutlineViewDataSource {

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let item = item as? SearchResultModel {
            return item.lineMatches.count
        }
        return searchItems.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let item = item as? SearchResultModel {
            return item.lineMatches[index]
        }
        return searchItems[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if item is SearchResultModel {
            return true
        }
        return false
    }

}

// MARK: - NSOutlineViewDelegate

extension FindNavigatorListViewController: NSOutlineViewDelegate {

    func outlineView(
        _ outlineView: NSOutlineView,
        shouldShowCellExpansionFor tableColumn: NSTableColumn?,
        item: Any
    ) -> Bool {
        item is SearchResultModel
    }

    func outlineView(_ outlineView: NSOutlineView, shouldShowOutlineCellForItem item: Any) -> Bool {
        true
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        NavigatorTableRowView()
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let tableColumn else { return nil }
        if let item = item as? SearchResultMatchModel {
            let frameRect = NSRect(x: 0, y: 0, width: tableColumn.width, height: outlineView.rowHeight)
            return FindNavigatorListMatchCell(frame: frameRect, matchItem: item)
        }
        let frameRect = NSRect(x: 0, y: 0, width: tableColumn.width, height: Islands.listRowHeight)
        guard let result = item as? SearchResultModel else { return nil }
        return FindNavigatorListFileCell(frame: frameRect, result: result, projectRoot: workspace.fileURL)
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !isRestoringSelection, let outlineView = notification.object as? NSOutlineView else {
            return
        }

        let item = outlineView.item(atRow: outlineView.selectedRow)
        let isNewSelection = (selectedItem as? AnyObject) !== (item as? AnyObject)
        if let match = item as? SearchResultMatchModel {
            state?.resultSelection = .match(match)
            if isNewSelection { open(match) }
            selectedItem = match
        } else if let result = item as? SearchResultModel {
            state?.resultSelection = .file(result)
            if isNewSelection { open(result) }
            selectedItem = result
        } else {
            state?.resultSelection = nil
        }
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        if let matchItem = item as? SearchResultMatchModel {
            guard let column = outlineView.tableColumns.first else {
                return rowHeight
            }
            let columnWidth = column.width
            let indentationLevel = outlineView.level(forItem: item)
            let indentationSpace = CGFloat(indentationLevel) * outlineView.indentationPerLevel
            let horizontalPaddingAndFixedElements: CGFloat = 24.0

            let availableWidth = columnWidth - indentationSpace - horizontalPaddingAndFixedElements

            guard availableWidth > 0 else {
                // Not enough space to display anything, return minimum height
                return rowHeight
            }

            let attributedString = FindNavigatorListMatchCell.attributedString(for: matchItem)

            let tempView = NSTextField()
            tempView.allowsEditingTextAttributes = true
            tempView.attributedStringValue = attributedString

            tempView.isEditable = false
            tempView.isBordered = false
            tempView.drawsBackground = false
            tempView.alignment = .natural

            tempView.cell?.wraps = true
            tempView.cell?.usesSingleLineMode = false
            tempView.lineBreakMode = .byWordWrapping
            tempView.maximumNumberOfLines = FindNavigatorListMatchCell.maximumLines(for: matchItem)
            tempView.preferredMaxLayoutWidth = availableWidth

            var calculatedHeight = tempView.sizeThatFits(
                NSSize(width: availableWidth, height: .greatestFiniteMagnitude)
            ).height

            // Total vertical padding (top + bottom) within the cell around the text
            let verticalPaddingInCell: CGFloat = 8.0
            calculatedHeight += verticalPaddingInCell
            return max(calculatedHeight, self.rowHeight)
        }
        // For parent items
        return Islands.listRowHeight
    }

    func outlineViewColumnDidResize(_ notification: Notification) {
        // Disable animations temporarily
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0

        var rowsToUpdate = IndexSet()
        for row in 0..<outlineView.numberOfRows {
            if let item = outlineView.item(atRow: row), item is SearchResultMatchModel {
                rowsToUpdate.insert(row)
            }
        }
        if !rowsToUpdate.isEmpty {
            outlineView.noteHeightOfRows(withIndexesChanged: rowsToUpdate)
        }

        NSAnimationContext.endGrouping()
        outlineView.layoutSubtreeIfNeeded()
    }
}

// MARK: - NSMenuDelegate

extension FindNavigatorListViewController: NSMenuDelegate {

}
