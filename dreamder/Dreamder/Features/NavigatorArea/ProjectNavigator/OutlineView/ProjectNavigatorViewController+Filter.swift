import AppKit

extension ProjectNavigatorViewController {
    func handleFilterChange() {
        resolveFilter(expanding: true)
    }

    func refreshFilterAfterFileChanges() {
        guard filterMatches.isActive else { return }
        resolveFilter(expanding: false)
    }

    private func resolveFilter(expanding: Bool) {
        filterTask?.cancel()
        guard let workspace else {
            outlineView.reloadData()
            return
        }

        let text = workspace.navigatorFilter
        let wantsChangedFiles = workspace.sourceControlFilter
        guard wantsChangedFiles || !filterIsEmpty, let manager = workspace.workspaceFileManager else {
            filterResolutionExpands = false
            applyFilter(.inactive, expanding: false)
            return
        }

        let candidates: ProjectNavigatorFilterMatches.Candidates = wantsChangedFiles
            ? .changedIDs(changedFileIDs(in: manager))
            : .tree(
                ProjectNavigatorTreeSource(
                    rootURL: manager.folderUrl,
                    fileSystem: DiskWorkspaceFileSystem(),
                    hiddenNames: hiddenEntryNames,
                    scope: workspace.fileScope
                )
            )
        let rootID = manager.workspaceItem.id
        filterResolutionExpands = filterResolutionExpands || expanding
        filterTask = Task { [weak self] in
            let matches = await ProjectNavigatorFilterMatches.resolve(
                text: text,
                rootID: rootID,
                candidates: candidates
            )
            guard !Task.isCancelled, let self else { return }
            applyFilter(matches, expanding: filterResolutionExpands)
            filterResolutionExpands = false
        }
    }

    private func changedFileIDs(in manager: CEWorkspaceFileManager) -> [String] {
        manager.statusCarriers
            .compactMap { manager.flattenedFileItems[$0] }
            .filter { $0.gitStatus != nil && $0.gitStatus != GitStatus.none }
            .map(\.id)
    }

    private func applyFilter(_ matches: ProjectNavigatorFilterMatches, expanding: Bool) {
        let selected = selectedFiles
        filterMatches = matches
        outlineView.reloadData()

        if !matches.isActive {
            restoreExpandedState()
            outlineView.autosaveExpandedItems = true
        } else if expanding {
            outlineView.autosaveExpandedItems = false
            content.forEach(expandIncludedFolders)
        }

        let rows = IndexSet(selected.map { outlineView.row(forItem: $0) }.filter { $0 >= 0 })
        shouldSendSelectionUpdate = false
        outlineView.selectRowIndexes(rows, byExtendingSelection: false)
        shouldSendSelectionUpdate = true

        let hasNoResults = matches.isActive && content.first.map { visibleChildren(of: $0).isEmpty } == true
        noResultsLabel.isHidden = !hasNoResults
        if hasNoResults {
            outlineView.hideRows(at: IndexSet(integer: 0))
        }
    }

    func isShownByFilter(_ item: CEWorkspaceFile) -> Bool {
        guard filterMatches.isActive else { return true }
        if filterMatches.ancestorIDs.contains(item.id) { return true }
        var current: CEWorkspaceFile? = item
        while let candidate = current, !candidate.isRoot {
            if isFilterHit(candidate) { return true }
            current = candidate.parent
        }
        return false
    }

    private func isFilterHit(_ item: CEWorkspaceFile) -> Bool {
        if filterMatches.sourceControl {
            guard item.gitStatus != nil, item.gitStatus != GitStatus.none else { return false }
        }
        return filterMatches.matches(name: item.name)
    }
}
