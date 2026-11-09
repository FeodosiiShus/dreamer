//
//  CEWorkspaceFileManager+DirectoryEvents.swift
//  Dreamder
//
//  Created by Axel Martinez on 5/8/24.
//

import Foundation

/// This extension handles the file system events triggered by changes in the root folder.
extension CEWorkspaceFileManager {
    func exclusionPolicy() -> WatchExclusionPolicy {
        WatchExclusionPolicy(folderURL: folderUrl, rules: ExcludedDirectories.rules(covering: folderUrl))
    }

    func processFileSystemEvents(_ rawEvents: [DirectoryEventStream.Event]) async {
        let relocated = await Self.relocate(rawEvents, folderPath: workspaceItem.id, policy: exclusionPolicy())
        guard !relocated.events.isEmpty else { return }

        let listings = await Self.readListings(
            of: loadedDirectories(among: relocated.treeParents),
            ignoring: ignoredFilesAndFolders,
            diagnostics: diagnostics
        )

        var updated: Set<CEWorkspaceFile> = []
        for listing in listings {
            if let parent = applyListing(listing) {
                updated.insert(parent)
            }
        }
        if !updated.isEmpty {
            notifyObservers(updatedItems: updated)
        }
        if !relocated.modifiedFiles.isEmpty {
            notifyObservers(modifiedFiles: Set(relocated.modifiedFiles.map { URL(fileURLWithPath: $0) }))
        }

        if Settings.shared.preferences.sourceControl.general.sourceControlIsEnabled &&
            Settings.shared.preferences.sourceControl.general.refreshStatusLocally {
            handleGitEvents(events: relocated.events)
        }
    }

    @concurrent
    static func relocate(
        _ events: [DirectoryEventStream.Event],
        folderPath: String,
        policy: WatchExclusionPolicy
    ) async -> RelocatedFileEvents {
        RelocatedFileEvents(events, folderPath: folderPath, policy: policy)
    }

    @concurrent
    static func readListings(
        of directories: [String: URL],
        ignoring ignoredNames: Set<String>,
        diagnostics: FileManagerDiagnostics
    ) async -> [DirectoryListing] {
        var listings: [DirectoryListing] = []
        listings.reserveCapacity(directories.count)
        for (id, url) in directories.sorted(by: { $0.key < $1.key }) {
            if let listing = try? DirectoryListing.read(
                directoryID: id,
                at: url,
                ignoring: ignoredNames,
                diagnostics: diagnostics
            ) {
                listings.append(listing)
            }
        }
        return listings
    }

    func loadedDirectories(among ids: Set<String>) -> [String: URL] {
        var loaded: [String: URL] = [:]
        for id in ids where childrenMap[id] != nil {
            if let directory = flattenedFileItems[id] {
                loaded[id] = directory.resolvedURL
            }
        }
        return loaded
    }

    func handleGitEvents(events: [DirectoryEventStream.Event]) {
        // Changes excluding .git folder
        let notGitChanges = events.filter({ !$0.path.contains(".git/") })

        // .git folder was changed
        let gitFolderChange = events.first(where: {
            $0.path == "\(self.folderUrl.relativePath)/.git"
        })

        // Change made to git index file, staged/unstaged files
        let gitIndexChange = events.first(where: {
            $0.path == "\(self.folderUrl.relativePath)/.git/index"
        })

        // Change made to git stash
        let gitStashChange = events.first(where: {
            $0.path == "\(self.folderUrl.relativePath)/.git/refs/stash"
        })

        // Changes made to git branches
        let gitBranchChange = events.first(where: {
            $0.path.contains("\(self.folderUrl.relativePath)/.git/refs/heads")
        })

        // Changes made to git HEAD - current branch changed
        let gitHeadChange = events.first(where: {
            $0.path.contains("\(self.folderUrl.relativePath)/.git/HEAD")
        })

        // Change made to remotes by looking at .git/config
        let gitConfigChange = events.first(where: {
            $0.path == "\(self.folderUrl.relativePath)/.git/config"
        })

        // If changes were made to project OR files were staged, refresh changes
        if !notGitChanges.isEmpty || gitIndexChange != nil {
            Task {
                await self.sourceControlManager?.refreshAllChangedFiles(debounced: true)
            }
        }

        // If changes were stashed, refresh stashed entries
        if gitStashChange != nil {
            Task {
                _ = try? await self.sourceControlManager?.refreshStashEntries()
            }
        }

        // If branches were added or removed, refresh branches
        if gitBranchChange != nil {
            Task {
                await self.sourceControlManager?.refreshBranches()
            }
        }

        // If HEAD was changed, refresh the current branch
        if gitHeadChange != nil {
            Task {
                await self.sourceControlManager?.refreshCurrentBranch()
            }
        }

        // If git config changed, refresh remotes
        if gitConfigChange != nil {
            Task {
                _ = try? await self.sourceControlManager?.refreshRemotes()
            }
        }

        // If .git folder was added or removed, check if repository is valid
        if gitFolderChange != nil {
            Task {
                await self.sourceControlManager?.validate()
            }
        }
    }

    /// Creates or deletes children of the ``CEWorkspaceFile`` so that they are accurate with the file system,
    /// instead of creating an entirely new ``CEWorkspaceFile``.
    ///
    /// This method will return immediately if the given file item is not a directory.
    /// This will also only rebuild *already cached* directories.
    /// - Parameters:
    ///   - fileItem: The ``CEWorkspaceFile``  to correct the children of
    func rebuildFiles(fromItem fileItem: CEWorkspaceFile) throws {
        // Do not index directories that are not already loaded.
        guard childrenMap[fileItem.id] != nil else { return }

        let listing = try DirectoryListing.read(
            directoryID: fileItem.id,
            at: fileItem.resolvedURL,
            ignoring: ignoredFilesAndFolders,
            diagnostics: diagnostics
        )
        applyListing(listing)
    }

    @discardableResult
    func applyListing(_ listing: DirectoryListing) -> CEWorkspaceFile? {
        guard let parent = flattenedFileItems[listing.directoryID] else { return nil }
        diagnostics.directoryRebuilt(listing.directoryID)

        let previousIDs = childrenMap[parent.id]
        let currentIDs = listing.entries.map(\.id)
        if previousIDs == currentIDs {
            return nil
        }

        if let previousIDs {
            let currentSet = Set(currentIDs)
            for id in previousIDs where !currentSet.contains(id) {
                removeSubtree(rootedAt: id)
            }
        }
        for entry in listing.entries where flattenedFileItems[entry.id] == nil {
            makeItem(id: entry.id, url: entry.url, parent: parent, isDirectory: entry.isDirectory)
        }
        childrenMap[parent.id] = currentIDs
        return parent
    }

    private func removeSubtree(rootedAt id: String) {
        var pending = [id]
        while let current = pending.popLast() {
            flattenedFileItems.removeValue(forKey: current)
            statusCarriers.remove(current)
            if let children = childrenMap.removeValue(forKey: current) {
                pending.append(contentsOf: children)
            }
        }
    }

    func notifyObservers(modifiedFiles: Set<URL>) {
        observers.allObjects.reversed().forEach { delegate in
            (delegate as? CEWorkspaceFileManagerObserver)?.fileManagerModifiedFiles(modifiedFiles)
        }
    }

    /// Notify observers that an update occurred in the watched files.
    func notifyObservers(updatedItems: Set<CEWorkspaceFile>) {
        observers.allObjects.reversed().forEach { delegate in
            guard let delegate = delegate as? CEWorkspaceFileManagerObserver else {
                observers.remove(delegate)
                return
            }
            delegate.fileManagerUpdated(updatedItems: updatedItems)
        }
    }

    /// Add an observer for file system events.
    /// - Parameter observer: The observer to add.
    func addObserver(_ observer: CEWorkspaceFileManagerObserver) {
        observers.add(observer as AnyObject)
    }

    /// Remove an observer for file system events.
    /// - Parameter observer: The observer to remove.
    func removeObserver(_ observer: CEWorkspaceFileManagerObserver) {
        observers.remove(observer as AnyObject)
    }
}
