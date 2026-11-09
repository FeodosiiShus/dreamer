import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct CEWorkspaceFileManagerRescanTests {
    private func makeManager(_ dir: URL, recorder: DiagnosticsRecorder) -> CEWorkspaceFileManager {
        let manager = CEWorkspaceFileManager(
            folderUrl: dir,
            ignoredFilesAndFolders: [],
            sourceControlManager: nil,
            diagnostics: recorder.diagnostics
        )
        manager.fsEventStream?.cancel()
        return manager
    }

    private func itemID(_ manager: CEWorkspaceFileManager, _ relative: String) -> String {
        "\(manager.workspaceItem.id)/\(relative)"
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: url, atomically: false, encoding: .utf8)
    }

    private func load(_ manager: CEWorkspaceFileManager, _ relative: String) async throws {
        let file = try #require(manager.getFile(itemID(manager, relative)))
        await manager.loadChildren(of: file)
    }

    private func rescan(_ manager: CEWorkspaceFileManager, _ relative: String? = nil) -> DirectoryEventStream.Event {
        let root = manager.exclusionPolicy().canonicalRootPath
        return DirectoryEventStream.Event(
            path: relative.map { "\(root)/\($0)" } ?? root,
            eventType: .mustRescan
        )
    }

    private func makeNestedTree(_ dir: URL) throws {
        try write("x", to: dir.appending(path: "root.txt"))
        try write("x", to: dir.appending(path: "sub/a.txt"))
        try write("x", to: dir.appending(path: "sub/deep/b.txt"))
        try write("x", to: dir.appending(path: "sub2/c.txt"))
        try write("x", to: dir.appending(path: "other/d.txt"))
    }

    private func writeSilentChanges(_ dir: URL) throws {
        try write("x", to: dir.appending(path: "new-root.txt"))
        try write("x", to: dir.appending(path: "sub/new-sub.txt"))
        try write("x", to: dir.appending(path: "sub/deep/new-deep.txt"))
        try write("x", to: dir.appending(path: "sub2/new-sub2.txt"))
    }

    @Test
    func aRescanOfTheRootRebuildsEveryLoadedDirectoryEvenWithoutAnyItemEvent() async throws {
        try await withTempDir { dir in
            try makeNestedTree(dir)
            let recorder = DiagnosticsRecorder()
            let manager = makeManager(dir, recorder: recorder)
            try await load(manager, "sub")
            try await load(manager, "sub/deep")
            try await load(manager, "sub2")
            let observer = RecordingObserver()
            manager.addObserver(observer)
            try writeSilentChanges(dir)
            recorder.reset()

            await manager.processFileSystemEvents([rescan(manager)])

            #expect(Set(recorder.rebuilds) == [
                manager.workspaceItem.id,
                itemID(manager, "sub"),
                itemID(manager, "sub/deep"),
                itemID(manager, "sub2")
            ])
            #expect(manager.getFile(itemID(manager, "new-root.txt")) != nil)
            #expect(manager.getFile(itemID(manager, "sub/new-sub.txt")) != nil)
            #expect(manager.getFile(itemID(manager, "sub/deep/new-deep.txt")) != nil)
            #expect(manager.getFile(itemID(manager, "sub2/new-sub2.txt")) != nil)
            #expect(observer.updates.flatMap { $0 }.count == 4)
        }
    }

    @Test
    func aRescanOfASubdirectoryRebuildsOnlyThatDirectoryAndItsLoadedDescendants() async throws {
        try await withTempDir { dir in
            try makeNestedTree(dir)
            let recorder = DiagnosticsRecorder()
            let manager = makeManager(dir, recorder: recorder)
            try await load(manager, "sub")
            try await load(manager, "sub/deep")
            try await load(manager, "sub2")
            try writeSilentChanges(dir)
            recorder.reset()

            await manager.processFileSystemEvents([rescan(manager, "sub")])

            #expect(Set(recorder.rebuilds) == [itemID(manager, "sub"), itemID(manager, "sub/deep")])
            #expect(manager.getFile(itemID(manager, "sub/new-sub.txt")) != nil)
            #expect(manager.getFile(itemID(manager, "sub/deep/new-deep.txt")) != nil)
            #expect(manager.getFile(itemID(manager, "new-root.txt")) == nil)
            #expect(manager.getFile(itemID(manager, "sub2/new-sub2.txt")) == nil)
        }
    }

    @Test
    func aRescanDropsEntriesThatVanishedWhileEventsWereLost() async throws {
        try await withTempDir { dir in
            try makeNestedTree(dir)
            let recorder = DiagnosticsRecorder()
            let manager = makeManager(dir, recorder: recorder)
            try await load(manager, "sub")
            try await load(manager, "sub/deep")
            try FileManager.default.removeItem(at: dir.appending(path: "sub/deep"))
            try FileManager.default.removeItem(at: dir.appending(path: "sub/a.txt"))

            await manager.processFileSystemEvents([rescan(manager)])

            #expect(manager.getFile(itemID(manager, "sub/deep")) == nil)
            #expect(manager.getFile(itemID(manager, "sub/deep/b.txt")) == nil)
            #expect(manager.getFile(itemID(manager, "sub/a.txt")) == nil)
            #expect(manager.childrenMap[itemID(manager, "sub")] == [])
        }
    }

    @Test
    func aRescanOfADirectoryThatIsNotLoadedListsNothing() async throws {
        try await withTempDir { dir in
            try makeNestedTree(dir)
            let recorder = DiagnosticsRecorder()
            let manager = makeManager(dir, recorder: recorder)
            recorder.reset()

            await manager.processFileSystemEvents([rescan(manager, "other")])

            #expect(recorder.rebuilds.isEmpty)
        }
    }

    @Test
    func loadedDirectoriesCombineTheDirtyParentsWithTheRescanSubtrees() async throws {
        try await withTempDir { dir in
            try makeNestedTree(dir)
            let recorder = DiagnosticsRecorder()
            let manager = makeManager(dir, recorder: recorder)
            try await load(manager, "sub")
            try await load(manager, "sub/deep")
            try await load(manager, "sub2")
            let rootID = manager.workspaceItem.id
            let sub = itemID(manager, "sub")
            let deep = itemID(manager, "sub/deep")
            let sibling = itemID(manager, "sub2")
            let other = itemID(manager, "other")

            let none = manager.loadedDirectories(among: [], rescanning: [])
            let parentsOnly = manager.loadedDirectories(among: [sibling], rescanning: [])
            let subtree = manager.loadedDirectories(among: [], rescanning: [sub])
            let combined = manager.loadedDirectories(among: [sibling], rescanning: [deep])
            let unloaded = manager.loadedDirectories(among: [other], rescanning: [other])
            let everything = manager.loadedDirectories(among: [], rescanning: [rootID])

            #expect(none.isEmpty)
            #expect(Set(parentsOnly.keys) == [sibling])
            #expect(Set(subtree.keys) == [sub, deep])
            #expect(Set(combined.keys) == [sibling, deep])
            #expect(unloaded.isEmpty)
            #expect(Set(everything.keys) == [rootID, sub, deep, sibling])
        }
    }
}
