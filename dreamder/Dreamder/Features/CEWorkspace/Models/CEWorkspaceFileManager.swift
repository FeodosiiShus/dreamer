//
//  FileSystemClient.swift
//  Dreamder
//
//  Created by Matthijs Eikelenboom on 04/02/2023.
//

import Foundation
import AppKit
import OSLog

protocol CEWorkspaceFileManagerObserver: AnyObject {
    func fileManagerUpdated(updatedItems: Set<CEWorkspaceFile>)
    func fileManagerModifiedFiles(_ urls: Set<URL>)
}

extension CEWorkspaceFileManagerObserver {
    func fileManagerModifiedFiles(_ urls: Set<URL>) {}
}

/// This class is used to load, modify, and listen to files on a user's machine.
///
/// The workspace file manager provides an API for:
/// - Navigating and loading file items.
/// - Moving and modifying files.
/// - Listening for file system updates and notifying observers.
///
/// File caching in Dreamder is done lazily. the ``CEWorkspaceFileManager`` will only create ``CEWorkspaceFile``s for
/// from files that are needed for some UI component, and ignores all other files. This is done primarily to prevent
/// Dreamder from wasting resources finding and caching a potentially large file tree (eg, a user's home directory).
///
/// When the workspace is first loaded, the file manager will only load the contents of the workspace directory. To find
/// files after this, calls to ``CEWorkspaceFileManager/getFile(_:createIfNotFound:)`` or
/// ``CEWorkspaceFileManager/childrenOfFile(_:)`` can cause the children for a file to be loaded into Dreamder's cache
/// of files.
///
/// Moving and modifying files is done via the methods: ``CEWorkspaceFileManager/addFile(fileName:toFile:)``,
/// ``CEWorkspaceFileManager/addFolder(folderName:toFile:)``, ``CEWorkspaceFileManager/delete(file:)``,
/// ``CEWorkspaceFileManager/copy(file:to:)``, and ``CEWorkspaceFileManager/duplicate(file:)``.
///
/// To listen for updates, the ``CEWorkspaceFileManager`` uses a ``DirectoryEventStream`` to listen to updates for any
/// files under the ``CEWorkspaceFileManager/folderUrl`` url. Those can be passed on to listeners that conform to the
/// ``CEWorkspaceFileManagerObserver`` protocol. Use the ``CEWorkspaceFileManager/addObserver(_:)``
/// and ``CEWorkspaceFileManager/removeObserver(_:)`` to add or remove observers. Observers are kept as weak references.
final class CEWorkspaceFileManager {
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "CEWorkspaceFileManager")
    private(set) var fileManager: FileManager
    private(set) var ignoredFilesAndFolders: Set<String>

    var flattenedFileItems: [String: CEWorkspaceFile]
    /// Maps all directories to it's children's paths.
    var childrenMap: [String: [String]] = [:]
    var fsEventStream: DirectoryEventStream?
    var eventBatcher: FileEventBatcher?
    var gitStatusPlan = GitStatusPlan()
    var statusCarriers: Set<String> = []
    var pendingLoads: Set<String> = []
    let diagnostics: FileManagerDiagnostics
    var observers: NSHashTable<AnyObject> = .weakObjects()

    let folderUrl: URL
    let workspaceItem: CEWorkspaceFile
    weak var sourceControlManager: SourceControlManager?

    /// Create a file  manager object with a root and a set of files to ignore.
    /// - Parameters:
    ///   - folderUrl: The folder to use as the root of the file manager.
    ///   - ignoredFilesAndFolders: A set of files to ignore. These should not be paths, but rather file names
    ///                             like `.DS_Store`
    init(
        folderUrl: URL,
        ignoredFilesAndFolders: Set<String>,
        fileManager: FileManager = FileManager.default,
        sourceControlManager: SourceControlManager?,
        diagnostics: FileManagerDiagnostics = .silent
    ) {
        self.folderUrl = folderUrl
        self.ignoredFilesAndFolders = ignoredFilesAndFolders

        self.workspaceItem = CEWorkspaceFile(url: folderUrl)
        self.flattenedFileItems = [workspaceItem.id: workspaceItem]
        self.sourceControlManager = sourceControlManager
        self.fileManager = fileManager
        self.diagnostics = diagnostics

        if let rootListing = try? DirectoryListing.read(
            directoryID: workspaceItem.id,
            at: workspaceItem.resolvedURL,
            ignoring: ignoredFilesAndFolders,
            diagnostics: diagnostics
        ) {
            applyListing(rootListing)
        }

        let batcher = FileEventBatcher { [weak self] events in
            await self?.processFileSystemEvents(events)
        }
        eventBatcher = batcher
        fsEventStream = DirectoryEventStream(
            directory: self.folderUrl.path,
            exclusionPaths: exclusionPolicy().streamExclusionPaths()
        ) { events in
            batcher.submit(events)
        }

        Task { [weak self] in
            guard let sourceControlManager = self?.sourceControlManager else { return }
            await sourceControlManager.validate()
            await sourceControlManager.refreshAllChangedFiles()
        }
    }

    // MARK: - Public API

    /// A function that, given a file's path, returns a `FileItem` if it exists
    /// within the scope of the `FileSystemClient`. 
    /// - Parameters:
    ///   - path: The file's relative path.
    ///   - createIfNotFound: Set to true if the function should index any intermediate directories to find the file,
    ///                       as well as index the file if it is not already.
    /// - Returns: The file item corresponding to the file
    func getFile(
        _ path: String,
        createIfNotFound: Bool = false
    ) -> CEWorkspaceFile? {
        let path = path.withoutTrailingSlashes
        if let file = flattenedFileItems[path] {
            return file
        }
        guard createIfNotFound else { return nil }

        let url = path.hasPrefix("/") ? URL(filePath: path) : URL(string: path, relativeTo: folderUrl)
        guard let url, folderUrl.containsSubPath(url) else { return nil }

        var current = workspaceItem
        let components = url.pathComponents.dropFirst(folderUrl.pathComponents.count)
        for (offset, component) in components.enumerated() {
            let childURL = DirectoryListing.childURL(of: current.id, named: component)
            let childID = childURL.relativePath
            let isTarget = offset == components.count - 1
            if let existing = flattenedFileItems[childID] {
                current = existing
            } else {
                guard isTarget || isIndexableDirectory(named: component, atPath: childID) else { return nil }
                let child = makeItem(id: childID, url: childURL, parent: current, isDirectory: isTarget ? nil : true)
                childrenMap[current.id]?.append(childID)
                current = child
            }
            if !isTarget {
                guard current.isFolder else { return nil }
                if childrenMap[current.id] == nil {
                    requestChildren(of: current)
                }
            }
        }
        return current
    }

    /// Returns all children for the given file.
    /// - Note: Will find and cache new children if they have not been already, see
    ///         ``CEWorkspaceFileManager/getFile(_:createIfNotFound:)`` to force a file to be loaded.
    /// - Parameter file: The file to find children for.
    /// - Returns: An array of children for the file, or `nil` if the file was not a directory.
    func childrenOfFile(_ file: CEWorkspaceFile) -> [CEWorkspaceFile]? {
        if file.isFolder {
            if childrenMap[file.id] == nil {
                requestChildren(of: file)
            }

            return childrenMap[file.id]?.compactMap { flattenedFileItems[$0] } ?? []
        }

        return nil
    }

    func requestChildren(of file: CEWorkspaceFile) {
        guard pendingLoads.insert(file.id).inserted else { return }
        Task { [weak self] in
            await self?.loadChildren(of: file)
        }
    }

    func loadChildren(of file: CEWorkspaceFile) async {
        defer { pendingLoads.remove(file.id) }
        let listing = await Self.readListing(
            directoryID: file.id,
            at: file.resolvedURL,
            ignoring: ignoredFilesAndFolders,
            diagnostics: diagnostics
        )
        guard let listing, let parent = applyListing(listing) else { return }
        notifyObservers(updatedItems: [parent])
    }

    @concurrent
    static func readListing(
        directoryID: String,
        at url: URL,
        ignoring ignoredNames: Set<String>,
        diagnostics: FileManagerDiagnostics
    ) async -> DirectoryListing? {
        try? DirectoryListing.read(
            directoryID: directoryID,
            at: url,
            ignoring: ignoredNames,
            diagnostics: diagnostics
        )
    }

    @discardableResult
    func makeItem(id: String, url: URL, parent: CEWorkspaceFile, isDirectory: Bool?) -> CEWorkspaceFile {
        let item = CEWorkspaceFile(id: id, url: url)
        item.parent = parent
        if let isDirectory {
            item.isFolder = isDirectory
        }
        if let status = gitStatusPlan.status(forPath: id) {
            item.gitStatus = status
            statusCarriers.insert(id)
        }
        flattenedFileItems[id] = item
        return item
    }

    private func isIndexableDirectory(named name: String, atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return !ignoredFilesAndFolders.contains(name)
            && fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    /// Run when the owner of the ``CEWorkspaceFileManager`` doesn't need it anymore.
    /// This de-inits most functions in the ``CEWorkspaceFileManager``, so that in case it isn't de-init'd it does not
    /// use up significant amounts of RAM, and clears any file system event watchers.
    func cleanUp() {
        fsEventStream?.cancel()
        eventBatcher?.cancel()
        flattenedFileItems = [workspaceItem.id: workspaceItem]
    }

    isolated deinit {
        fsEventStream?.cancel()
        eventBatcher?.cancel()
        observers.removeAllObjects()
    }
}
