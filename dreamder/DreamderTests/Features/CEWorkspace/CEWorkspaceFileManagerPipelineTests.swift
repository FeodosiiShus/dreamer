import Foundation
import Synchronization
import Testing
@testable import Dreamder

nonisolated final class DiagnosticsRecorder: Sendable {
    private let listed = Mutex<[(id: String, onMain: Bool)]>([])
    private let rebuilt = Mutex<[String]>([])

    var diagnostics: FileManagerDiagnostics {
        FileManagerDiagnostics(
            directoryListed: { [self] id, onMain in listed.withLock { $0.append((id, onMain)) } },
            directoryRebuilt: { [self] id in rebuilt.withLock { $0.append(id) } }
        )
    }

    var listings: [(id: String, onMain: Bool)] {
        listed.withLock { $0 }
    }

    var rebuilds: [String] {
        rebuilt.withLock { $0 }
    }

    func reset() {
        listed.withLock { $0.removeAll() }
        rebuilt.withLock { $0.removeAll() }
    }
}

@MainActor
final class RecordingObserver: CEWorkspaceFileManagerObserver {
    private(set) var updates: [Set<CEWorkspaceFile>] = []
    private(set) var modified: [Set<URL>] = []

    func fileManagerUpdated(updatedItems: Set<CEWorkspaceFile>) {
        updates.append(updatedItems)
    }

    func fileManagerModifiedFiles(_ urls: Set<URL>) {
        modified.append(urls)
    }
}

@MainActor
@Suite(.uiGate)
struct CEWorkspaceFileManagerPipelineTests {
    private func makeManager(
        _ dir: URL,
        ignored: Set<String> = [],
        recorder: DiagnosticsRecorder = DiagnosticsRecorder(),
        sourceControlManager: SourceControlManager? = nil,
        watching: Bool = false
    ) -> CEWorkspaceFileManager {
        let manager = CEWorkspaceFileManager(
            folderUrl: dir,
            ignoredFilesAndFolders: ignored,
            sourceControlManager: sourceControlManager,
            diagnostics: recorder.diagnostics
        )
        if !watching {
            manager.fsEventStream?.cancel()
        }
        return manager
    }

    private func id(_ manager: CEWorkspaceFileManager, _ relative: String) -> String {
        "\(manager.workspaceItem.id)/\(relative)"
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: url, atomically: false, encoding: .utf8)
    }

    private func event(
        _ manager: CEWorkspaceFileManager,
        _ relative: String,
        _ type: FSEvent = .itemCreated
    ) -> DirectoryEventStream.Event {
        DirectoryEventStream.Event(
            path: "\(manager.exclusionPolicy().canonicalRootPath)/\(relative)",
            eventType: type
        )
    }

    @Test
    func theRootIsListedWhenTheManagerIsCreated() throws {
        try withTempDir { dir in
            try write("x", to: dir.appending(path: "a.txt"))
            try write("x", to: dir.appending(path: "sub/b.txt"))
            let recorder = DiagnosticsRecorder()

            let manager = makeManager(dir, recorder: recorder)

            #expect(manager.childrenMap[manager.workspaceItem.id] == [id(manager, "sub"), id(manager, "a.txt")])
            #expect(manager.flattenedFileItems.count == 3)
            #expect(recorder.listings.map { $0.id } == [manager.workspaceItem.id])
            #expect(recorder.listings.first?.onMain == true)
            #expect(manager.getFile(id(manager, "sub"))?.isFolder == true)
        }
    }

    @Test
    func anUnreadableRootLeavesTheTreeEmpty() throws {
        try withTempDir { dir in
            let missing = dir.appending(path: "missing", directoryHint: .isDirectory)

            let manager = makeManager(missing)

            #expect(manager.childrenMap.isEmpty)
            #expect(manager.flattenedFileItems.count == 1)
            #expect(manager.workspaceItem.isFolder == false)
        }
    }

    @Test
    func fiveHundredCreationsInOneDirectoryCoalesceIntoFewRebuildsAndNeverListOnTheMainThread() async throws {
        try await withTempDir { dir in
            let recorder = DiagnosticsRecorder()
            let manager = makeManager(dir, recorder: recorder)
            let observer = RecordingObserver()
            manager.addObserver(observer)
            recorder.reset()
            for index in 0..<500 {
                try write("x", to: dir.appending(path: "file\(index).txt"))
            }

            let events = (0..<500).map { event(manager, "file\($0).txt") }
            for start in stride(from: 0, to: events.count, by: 50) {
                manager.eventBatcher?.submit(Array(events[start..<start + 50]))
            }
            try await eventually { manager.flattenedFileItems.count == 501 }

            let rootID = manager.workspaceItem.id
            let rebuilds = recorder.rebuilds.filter { $0 == rootID }.count
            #expect(rebuilds >= 1 && rebuilds <= 3)
            #expect(recorder.listings.isEmpty == false)
            #expect(recorder.listings.allSatisfy { !$0.onMain })
            #expect(observer.updates.count <= 3)
            #expect(manager.childrenMap[rootID]?.count == 500)
        }
    }

    @Test
    func eventsUnderNodeModulesTriggerNeitherARebuildNorAGitStatus() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture(root: dir)
            try fixture.write("a.txt", "one\n")
            try await fixture.commit("initial")
            try FileManager.default.createDirectory(
                at: dir.appending(path: "node_modules/react", directoryHint: .isDirectory),
                withIntermediateDirectories: true
            )
            let sourceControl = SourceControlManager(workspaceURL: dir, editorManager: EditorManager())
            let recorder = DiagnosticsRecorder()
            let manager = makeManager(
                dir,
                recorder: recorder,
                sourceControlManager: sourceControl,
                watching: true
            )
            sourceControl.fileManager = manager
            let nodeModulesID = id(manager, "node_modules")
            let reactID = id(manager, "node_modules/react")
            let nodeModules = try #require(manager.getFile(nodeModulesID))
            await manager.loadChildren(of: nodeModules)
            let react = try #require(manager.getFile(reactID))
            await manager.loadChildren(of: react)
            let gitMetadata = try #require(manager.getFile(id(manager, ".git")))
            await manager.loadChildren(of: gitMetadata)

            try fixture.write(".git/settled.marker", "")
            try await eventually { manager.getFile(id(manager, ".git/settled.marker")) != nil }
            await sourceControl.refreshAllChangedFiles()
            #expect(sourceControl.changedFiles.isEmpty)
            recorder.reset()

            try fixture.write("node_modules/react/index.js", "module.exports = 1\n")
            manager.eventBatcher?.submit([
                event(manager, "node_modules/react/index.js"),
                event(manager, "node_modules/react"),
                event(manager, "node_modules/react/package.json", .itemModified)
            ])
            try await Task.sleep(for: .milliseconds(1500))

            let excludedIDs: Set<String> = [nodeModulesID, reactID]
            #expect(recorder.rebuilds.contains { excludedIDs.contains($0) } == false)
            #expect(recorder.listings.contains { excludedIDs.contains($0.id) } == false)
            #expect(sourceControl.changedFiles.isEmpty)

            try fixture.write("src/main.swift", "print(1)\n")
            try await eventually { sourceControl.changedFiles.count == 2 }

            #expect(sourceControl.changedFiles.map(\.fileURL.lastPathComponent).sorted() == ["node_modules", "src"])
            try await eventually { manager.getFile(id(manager, "src"))?.gitStatus == .untracked }
            #expect(recorder.rebuilds.contains(manager.workspaceItem.id))
            #expect(recorder.listings.allSatisfy { !$0.onMain })
        }
    }

    @Test
    func realFileSystemChangesReachTheTreeThroughTheEventStream() async throws {
        try await withTempDir { dir in
            try write("x", to: dir.appending(path: "keep.txt"))
            let manager = makeManager(dir, watching: true)
            let observer = RecordingObserver()
            manager.addObserver(observer)

            let created = dir.appending(path: "created.txt")
            try write("x", to: created)
            try await eventually { manager.getFile(id(manager, "created.txt")) != nil }

            let renamed = dir.appending(path: "renamed.txt")
            try FileManager.default.moveItem(at: created, to: renamed)
            try await eventually {
                manager.getFile(id(manager, "renamed.txt")) != nil && manager.getFile(id(manager, "created.txt")) == nil
            }

            try FileManager.default.removeItem(at: renamed)
            try await eventually { manager.getFile(id(manager, "renamed.txt")) == nil }

            #expect(manager.childrenMap[manager.workspaceItem.id] == [id(manager, "keep.txt")])
            #expect(observer.updates.isEmpty == false)

            try write("changed", to: dir.appending(path: "keep.txt"))
            let keepURL = URL(fileURLWithPath: id(manager, "keep.txt"))
            try await eventually { observer.modified.contains { $0.contains(keepURL) } }
        }
    }

    @Test
    func fiftyModificationsInOneWindowProduceOneNotificationWithoutStructureUpdates() async throws {
        try await withTempDir { dir in
            try write("x", to: dir.appending(path: "a.txt"))
            let manager = makeManager(dir)
            let observer = RecordingObserver()
            manager.addObserver(observer)

            manager.eventBatcher?.submit(Array(repeating: event(manager, "a.txt", .itemModified), count: 50))

            try await eventually { !observer.modified.isEmpty }
            try await Task.sleep(for: .milliseconds(400))
            #expect(observer.modified == [[URL(fileURLWithPath: id(manager, "a.txt"))]])
            #expect(observer.updates.isEmpty)
        }
    }

    @Test
    func modificationsUnderNodeModulesGitMetadataDirectoriesAndMissingFilesAreNotReported() async throws {
        try await withTempDir { dir in
            try write("x", to: dir.appending(path: "node_modules/dep.js"))
            try write("x", to: dir.appending(path: ".git/index"))
            try write("x", to: dir.appending(path: "sub/inner.txt"))
            try write("x", to: dir.appending(path: "real.txt"))
            let manager = makeManager(dir)
            let observer = RecordingObserver()
            manager.addObserver(observer)

            manager.eventBatcher?.submit([
                event(manager, "node_modules/dep.js", .itemModified),
                event(manager, ".git/index", .itemModified),
                event(manager, "sub", .itemModified),
                event(manager, "ghost.txt", .itemModified),
                event(manager, "real.txt", .itemModified)
            ])

            try await eventually { !observer.modified.isEmpty }
            #expect(observer.modified == [[URL(fileURLWithPath: id(manager, "real.txt"))]])

            manager.eventBatcher?.submit([event(manager, "node_modules/dep.js", .itemModified)])
            try await Task.sleep(for: .milliseconds(400))
            #expect(observer.modified.count == 1)
        }
    }

    @Test
    func observersWithoutAModificationHandlerAreSkippedSilently() async throws {
        try await withTempDir { dir in
            try write("x", to: dir.appending(path: "a.txt"))
            let manager = makeManager(dir)
            let observer = StructureOnlyObserver()
            manager.addObserver(observer)

            manager.eventBatcher?.submit([event(manager, "a.txt", .itemModified)])
            try await Task.sleep(for: .milliseconds(400))

            observer.fileManagerModifiedFiles([])
            #expect(observer.updates == 0)
        }
    }

    @Test
    func eventsInsideASymlinkedRootWithSpacesInItsNameAreRelocatedAndApplied() async throws {
        try await withTempDir { dir in
            let real = dir.appending(path: "my project", directoryHint: .isDirectory)
            try write("x", to: real.appending(path: "first.txt"))
            let link = dir.appending(path: "linked project")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
            let manager = makeManager(link)
            #expect(manager.childrenMap[manager.workspaceItem.id] == [id(manager, "first.txt")])

            try write("x", to: real.appending(path: "new file.txt"))
            manager.eventBatcher?.submit([event(manager, "new file.txt")])

            try await eventually { manager.getFile(id(manager, "new file.txt")) != nil }
            #expect(manager.workspaceItem.id.hasSuffix("/linked project"))
        }
    }

    @Test
    func eventsForUnloadedDirectoriesAndPassiveEventsDoNotListAnything() async throws {
        try await withTempDir { dir in
            try write("x", to: dir.appending(path: "sub/deep/a.txt"))
            let recorder = DiagnosticsRecorder()
            let manager = makeManager(dir, recorder: recorder)
            recorder.reset()

            await manager.processFileSystemEvents([
                event(manager, "sub/deep/b.txt"),
                event(manager, "sub/c.txt", .itemRemoved),
                event(manager, "touched.txt", .itemModified)
            ])

            #expect(recorder.listings.isEmpty)
            #expect(recorder.rebuilds.isEmpty)
        }
    }

    @Test
    func changesInsideALoadedSubdirectoryUpdateOnlyThatDirectory() async throws {
        try await withTempDir { dir in
            try write("x", to: dir.appending(path: "sub/a.txt"))
            let recorder = DiagnosticsRecorder()
            let manager = makeManager(dir, recorder: recorder)
            let sub = try #require(manager.getFile(id(manager, "sub")))
            await manager.loadChildren(of: sub)
            let observer = RecordingObserver()
            manager.addObserver(observer)
            recorder.reset()
            try write("x", to: dir.appending(path: "sub/b.txt"))

            await manager.processFileSystemEvents([event(manager, "sub/b.txt")])

            #expect(recorder.rebuilds == [sub.id])
            #expect(manager.childrenMap[sub.id] == [id(manager, "sub/a.txt"), id(manager, "sub/b.txt")])
            #expect(observer.updates == [[sub]])
        }
    }

    @Test
    func cleaningUpStopsApplyingEvents() async throws {
        try await withTempDir { dir in
            let recorder = DiagnosticsRecorder()
            let manager = makeManager(dir, recorder: recorder)
            manager.cleanUp()
            recorder.reset()
            try write("x", to: dir.appending(path: "late.txt"))

            manager.eventBatcher?.submit([event(manager, "late.txt")])
            try await Task.sleep(for: .milliseconds(400))

            #expect(recorder.rebuilds.isEmpty)
            #expect(manager.getFile(id(manager, "late.txt")) == nil)
        }
    }

    @Test
    func gitMetadataEventsRefreshTheMatchingSourceControlState() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture(root: dir)
            try fixture.write("a.txt", "one\n")
            try await fixture.commit("initial")
            let sourceControl = SourceControlManager(workspaceURL: dir, editorManager: EditorManager())
            let manager = makeManager(dir, sourceControlManager: sourceControl)
            sourceControl.fileManager = manager
            await sourceControl.refreshAllChangedFiles()
            sourceControl.isGitRepository = false
            try fixture.write("new.txt", "new\n")
            #expect(sourceControl.currentBranch == nil)
            #expect(sourceControl.changedFiles.isEmpty)

            await manager.processFileSystemEvents([
                event(manager, ".git/HEAD", .itemModified),
                event(manager, ".git/refs/heads/main", .itemModified),
                event(manager, ".git/refs/stash", .itemModified),
                event(manager, ".git/config", .itemModified),
                event(manager, ".git", .itemCreated),
                event(manager, ".git/index", .itemModified)
            ])

            try await eventually { sourceControl.currentBranch != nil }
            try await eventually { sourceControl.branches.isEmpty == false }
            try await eventually { sourceControl.isGitRepository }
            try await eventually { sourceControl.changedFiles.map(\.fileURL.lastPathComponent) == ["new.txt"] }
        }
    }

    @Test
    func expandingAnUnloadedFolderLoadsItsChildrenAsynchronouslyOffTheMainThread() async throws {
        try await withTempDir { dir in
            try write("x", to: dir.appending(path: "sub/a.txt"))
            try write("x", to: dir.appending(path: "sub/b.txt"))
            let recorder = DiagnosticsRecorder()
            let manager = makeManager(dir, recorder: recorder)
            let observer = RecordingObserver()
            manager.addObserver(observer)
            let sub = try #require(manager.getFile(id(manager, "sub")))
            recorder.reset()

            #expect(manager.childrenOfFile(sub)?.isEmpty == true)
            #expect(manager.pendingLoads.contains(sub.id))
            #expect(manager.childrenOfFile(sub)?.isEmpty == true)

            try await eventually { manager.childrenMap[sub.id] != nil }
            #expect(manager.childrenOfFile(sub)?.map(\.name) == ["a.txt", "b.txt"])
            #expect(manager.pendingLoads.isEmpty)
            #expect(recorder.listings.map { $0.id } == [sub.id])
            #expect(recorder.listings.allSatisfy { !$0.onMain })
            #expect(observer.updates == [[sub]])
        }
    }

    @Test
    func childrenOfAFileAreNotLoadedAndLoadingAVanishedFolderChangesNothing() async throws {
        try await withTempDir { dir in
            try write("x", to: dir.appending(path: "gone/a.txt"))
            try write("x", to: dir.appending(path: "plain.txt"))
            let manager = makeManager(dir)
            let plain = try #require(manager.getFile(id(manager, "plain.txt")))
            let gone = try #require(manager.getFile(id(manager, "gone")))
            let observer = RecordingObserver()
            manager.addObserver(observer)
            try FileManager.default.removeItem(at: dir.appending(path: "gone"))

            #expect(manager.childrenOfFile(plain) == nil)
            await manager.loadChildren(of: gone)

            #expect(manager.childrenMap[gone.id] == nil)
            #expect(observer.updates.isEmpty)
        }
    }

    @Test
    func getFileCreatesIntermediateDirectoriesAndLoadsThemInTheBackground() async throws {
        try await withTempDir { dir in
            try write("x", to: dir.appending(path: "a/b/c/file.txt"))
            let recorder = DiagnosticsRecorder()
            let manager = makeManager(dir, recorder: recorder)
            recorder.reset()
            let path = id(manager, "a/b/c/file.txt")
            #expect(manager.getFile(path) == nil)

            let file = try #require(manager.getFile(path, createIfNotFound: true))

            #expect(file.id == path)
            #expect(file.parent?.id == id(manager, "a/b/c"))
            #expect(file.parent?.parent?.parent?.parent === manager.workspaceItem)
            #expect(manager.getFile(id(manager, "a/b"))?.isFolder == true)
            #expect(manager.childrenMap[id(manager, "a/b")] == nil)
            #expect(recorder.listings.isEmpty)
            #expect(manager.getFile(path, createIfNotFound: true) === file)
            #expect(manager.getFile(path + "/", createIfNotFound: false) === file)

            try await eventually {
                ["a", "a/b", "a/b/c"].allSatisfy { manager.childrenMap[id(manager, $0)] != nil }
            }
            #expect(manager.childrenMap[id(manager, "a/b/c")] == [path])
            #expect(manager.getFile(path, createIfNotFound: true) === file)
            #expect(recorder.listings.allSatisfy { !$0.onMain })
        }
    }

    @Test
    func getFileRejectsMissingIgnoredAndForeignIntermediates() throws {
        try withTempDir { dir in
            try write("x", to: dir.appending(path: "ignored/inner/file.txt"))
            try write("x", to: dir.appending(path: "real/file.txt"))
            try write("x", to: dir.appending(path: "plain.txt"))
            let manager = makeManager(dir, ignored: ["ignored"])

            #expect(manager.getFile(id(manager, "missing/file.txt"), createIfNotFound: true) == nil)
            #expect(manager.getFile(id(manager, "ignored/inner/file.txt"), createIfNotFound: true) == nil)
            #expect(manager.getFile(id(manager, "real/file.txt/more.txt"), createIfNotFound: true) == nil)
            #expect(manager.getFile(id(manager, "plain.txt/more.txt"), createIfNotFound: true) == nil)
            #expect(manager.getFile("/definitely/not/inside/file.txt", createIfNotFound: true) == nil)
            #expect(manager.getFile(id(manager, "real/file.txt"), createIfNotFound: true) != nil)
        }
    }

    @Test
    func getFileAddsNewFilesToAlreadyLoadedParents() throws {
        try withTempDir { dir in
            try write("x", to: dir.appending(path: "a.txt"))
            let manager = makeManager(dir)
            let rootID = manager.workspaceItem.id

            let created = try #require(manager.getFile(id(manager, "not-on-disk-yet.txt"), createIfNotFound: true))

            #expect(manager.childrenMap[rootID]?.last == created.id)
            #expect(manager.childrenOfFile(manager.workspaceItem)?.contains(created) == true)
        }
    }

    @Test
    func rebuildPicksUpAdditionsAndRemovalsInSortedOrder() throws {
        try withTempDir { dir in
            try write("x", to: dir.appending(path: "b.txt"))
            try write("x", to: dir.appending(path: "dir1/inner.txt"))
            let manager = makeManager(dir)
            let rootID = manager.workspaceItem.id
            #expect(manager.childrenMap[rootID] == [id(manager, "dir1"), id(manager, "b.txt")])

            try write("x", to: dir.appending(path: "a.txt"))
            try manager.rebuildFiles(fromItem: manager.workspaceItem)
            #expect(manager.childrenMap[rootID] == [id(manager, "dir1"), id(manager, "a.txt"), id(manager, "b.txt")])

            try FileManager.default.removeItem(at: dir.appending(path: "b.txt"))
            try manager.rebuildFiles(fromItem: manager.workspaceItem)
            #expect(manager.childrenMap[rootID] == [id(manager, "dir1"), id(manager, "a.txt")])
            #expect(manager.getFile(id(manager, "b.txt")) == nil)
        }
    }

    @Test
    func rebuildDropsTheWholeLoadedSubtreeOfARemovedDirectory() async throws {
        try await withTempDir { dir in
            try write("x", to: dir.appending(path: "sub/inner/deep.txt"))
            try write("x", to: dir.appending(path: "keep.txt"))
            let manager = makeManager(dir)
            let sub = try #require(manager.getFile(id(manager, "sub")))
            await manager.loadChildren(of: sub)
            let inner = try #require(manager.getFile(id(manager, "sub/inner")))
            await manager.loadChildren(of: inner)
            #expect(manager.getFile(id(manager, "sub/inner/deep.txt")) != nil)

            try FileManager.default.removeItem(at: dir.appending(path: "sub"))
            try manager.rebuildFiles(fromItem: manager.workspaceItem)

            #expect(manager.flattenedFileItems.keys.sorted() == [manager.workspaceItem.id, id(manager, "keep.txt")])
            #expect(manager.childrenMap.keys.sorted() == [manager.workspaceItem.id])
        }
    }

    @Test
    func unchangedListingsAndUnknownDirectoriesDoNotChangeTheTree() throws {
        try withTempDir { dir in
            try write("x", to: dir.appending(path: "a.txt"))
            let recorder = DiagnosticsRecorder()
            let manager = makeManager(dir, recorder: recorder)
            let rootID = manager.workspaceItem.id
            recorder.reset()

            let same = try DirectoryListing.read(directoryID: rootID, at: dir, ignoring: [])
            #expect(manager.applyListing(same) == nil)
            #expect(recorder.rebuilds == [rootID])

            let unknown = try DirectoryListing.read(directoryID: id(manager, "unknown"), at: dir, ignoring: [])
            #expect(manager.applyListing(unknown) == nil)
            #expect(recorder.rebuilds == [rootID])
        }
    }

    @Test
    func ignoredNamesAreNeverIndexed() throws {
        try withTempDir { dir in
            try write("x", to: dir.appending(path: "keep.txt"))
            try write("x", to: dir.appending(path: ".DS_Store"))
            let manager = makeManager(dir, ignored: [".DS_Store"])
            #expect(manager.childrenMap[manager.workspaceItem.id] == [id(manager, "keep.txt")])

            try write("x", to: dir.appending(path: "more.txt"))
            try manager.rebuildFiles(fromItem: manager.workspaceItem)
            #expect(manager.getFile(id(manager, ".DS_Store")) == nil)
            #expect(manager.childrenMap[manager.workspaceItem.id]?.count == 2)
        }
    }

    @Test
    func rebuildingAnUnloadedOrVanishedDirectoryIsHandledSeparately() async throws {
        try await withTempDir { dir in
            try write("x", to: dir.appending(path: "unloaded/a.txt"))
            try write("x", to: dir.appending(path: "vanishing/a.txt"))
            let recorder = DiagnosticsRecorder()
            let manager = makeManager(dir, recorder: recorder)
            let unloaded = try #require(manager.getFile(id(manager, "unloaded")))
            let vanishing = try #require(manager.getFile(id(manager, "vanishing")))
            await manager.loadChildren(of: vanishing)
            recorder.reset()

            try manager.rebuildFiles(fromItem: unloaded)
            #expect(recorder.listings.isEmpty)

            try FileManager.default.removeItem(at: dir.appending(path: "vanishing"))
            #expect(throws: (any Error).self) { try manager.rebuildFiles(fromItem: vanishing) }
        }
    }

    @Test
    func gitStatusesAreAppliedToLoadedItemsAndTheirUntrackedDescendants() async throws {
        try await withTempDir { dir in
            try write("x", to: dir.appending(path: "a.txt"))
            try write("x", to: dir.appending(path: "b.txt"))
            try write("x", to: dir.appending(path: "newdir/one.txt"))
            try write("x", to: dir.appending(path: "newdir/deep/two.txt"))
            let manager = makeManager(dir)
            let newdir = try #require(manager.getFile(id(manager, "newdir")))
            await manager.loadChildren(of: newdir)
            let deep = try #require(manager.getFile(id(manager, "newdir/deep")))
            await manager.loadChildren(of: deep)
            let observer = RecordingObserver()
            manager.addObserver(observer)

            manager.applyGitStatuses(GitStatusPlan(changedFiles: [
                change("a.txt", .modified, in: dir),
                change("newdir/", .untracked, in: dir),
                change("ghost/", .untracked, in: dir),
                change("not-listed.txt", .added, in: dir)
            ]))

            let names = ["a.txt", "b.txt", "newdir", "newdir/one.txt", "newdir/deep", "newdir/deep/two.txt"]
            let statuses = names.map { manager.getFile(id(manager, $0))?.gitStatus }
            #expect(statuses == [.modified, nil, .untracked, .untracked, .untracked, .untracked])
            #expect(observer.updates.count == 1)
            #expect(observer.updates.first?.count == 5)

            manager.applyGitStatuses(GitStatusPlan())

            let remaining = names.compactMap { manager.getFile(id(manager, $0))?.gitStatus }
            #expect(remaining.isEmpty)
            #expect(observer.updates.count == 2)
            #expect(manager.statusCarriers.isEmpty)
        }
    }

    @Test
    func itemsLoadedAfterAStatusRefreshInheritTheirStatus() async throws {
        try await withTempDir { dir in
            try write("x", to: dir.appending(path: "newdir/one.txt"))
            try write("x", to: dir.appending(path: "tracked/changed.txt"))
            let manager = makeManager(dir)
            manager.applyGitStatuses(GitStatusPlan(changedFiles: [
                change("newdir/", .untracked, in: dir),
                change("tracked/changed.txt", .modified, in: dir)
            ]))

            let newdir = try #require(manager.getFile(id(manager, "newdir")))
            let tracked = try #require(manager.getFile(id(manager, "tracked")))
            await manager.loadChildren(of: newdir)
            await manager.loadChildren(of: tracked)

            #expect(manager.getFile(id(manager, "newdir/one.txt"))?.gitStatus == .untracked)
            #expect(manager.getFile(id(manager, "tracked/changed.txt"))?.gitStatus == .modified)
            #expect(manager.statusCarriers.contains(id(manager, "newdir/one.txt")))
        }
    }

    @Test
    func inheritedStatusesOfUnreachableItemsSurviveUntilTheirDirectoryIsNoLongerUntracked() throws {
        try withTempDir { dir in
            try write("x", to: dir.appending(path: "newdir/deep/two.txt"))
            let manager = makeManager(dir)
            let plan = GitStatusPlan(changedFiles: [change("newdir/", .untracked, in: dir)])
            manager.applyGitStatuses(plan)
            let two = try #require(manager.getFile(id(manager, "newdir/deep/two.txt"), createIfNotFound: true))
            #expect(two.gitStatus == .untracked)
            #expect(manager.childrenMap[id(manager, "newdir")] == nil)

            manager.applyGitStatuses(plan)

            #expect(two.gitStatus == .untracked)
            #expect(manager.statusCarriers.contains(two.id))

            manager.applyGitStatuses(GitStatusPlan())

            #expect(two.gitStatus == nil)
            #expect(manager.statusCarriers.isEmpty)
        }
    }

    @Test
    func statusCarriersForDiscardedItemsAreSkipped() throws {
        try withTempDir { dir in
            try write("x", to: dir.appending(path: "a.txt"))
            let manager = makeManager(dir)
            let observer = RecordingObserver()
            manager.applyGitStatuses(GitStatusPlan(changedFiles: [change("a.txt", .modified, in: dir)]))
            manager.addObserver(observer)
            manager.cleanUp()

            manager.applyGitStatuses(GitStatusPlan())

            #expect(observer.updates.isEmpty)
            #expect(manager.statusCarriers.isEmpty)
        }
    }

    @Test
    func objectsThatAreNotFileManagerObserversAreDroppedWhenObserversAreNotified() throws {
        try withTempDir { dir in
            try write("x", to: dir.appending(path: "a.txt"))
            let manager = makeManager(dir)
            let stranger = NSObject()
            let observer = RecordingObserver()
            manager.observers.add(stranger)
            manager.addObserver(observer)

            manager.notifyObservers(updatedItems: [manager.workspaceItem])

            #expect(manager.observers.allObjects.contains { $0 === stranger } == false)
            #expect(manager.observers.allObjects.contains { $0 === observer })
            #expect(observer.updates == [[manager.workspaceItem]])
        }
    }

    @Test
    func removedObserversStopReceivingNotifications() throws {
        try withTempDir { dir in
            try write("x", to: dir.appending(path: "a.txt"))
            let manager = makeManager(dir)
            let observer = RecordingObserver()
            manager.addObserver(observer)
            manager.removeObserver(observer)

            manager.notifyObservers(updatedItems: [manager.workspaceItem])

            #expect(observer.updates.isEmpty)
        }
    }

    private func change(_ path: String, _ status: GitStatus, in dir: URL) -> GitChangedFile {
        GitChangedFile(
            status: status,
            stagedStatus: .none,
            fileURL: URL(filePath: path, relativeTo: dir),
            originalFilename: nil
        )
    }
}

@MainActor
private final class StructureOnlyObserver: CEWorkspaceFileManagerObserver {
    private(set) var updates = 0

    func fileManagerUpdated(updatedItems: Set<CEWorkspaceFile>) {
        updates += 1
    }
}
