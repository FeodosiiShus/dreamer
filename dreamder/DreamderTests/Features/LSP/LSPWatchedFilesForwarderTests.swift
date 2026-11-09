import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@MainActor
final class LSPWatchedFilesRecorder {
    private(set) var batches: [DidChangeWatchedFilesParams] = []

    var events: [FileEvent] {
        batches.flatMap(\.changes)
    }

    func record(_ params: DidChangeWatchedFilesParams) {
        batches.append(params)
    }
}

@MainActor
final class LSPWatchedFilesStampLog {
    private(set) var calls: [[String]] = []

    func record(_ paths: [String]) {
        calls.append(paths)
    }
}

@MainActor
@Suite("LSP watched files forwarder", .uiGate)
struct LSPWatchedFilesForwarderTests {
    func makeFileManager(_ directory: URL) -> CEWorkspaceFileManager {
        let manager = CEWorkspaceFileManager(
            folderUrl: directory,
            ignoredFilesAndFolders: [],
            sourceControlManager: nil
        )
        manager.fsEventStream = nil
        manager.eventBatcher = nil
        return manager
    }

    func makeForwarder(
        _ manager: CEWorkspaceFileManager,
        directory: URL,
        recorder: LSPWatchedFilesRecorder,
        watchers: [FileSystemWatcher]
    ) -> LSPWatchedFilesForwarder {
        LSPWatchedFilesForwarder(
            fileManager: manager,
            workspacePath: directory.path,
            watchers: { watchers },
            send: { params in recorder.record(params) }
        )
    }

    func notify(_ manager: CEWorkspaceFileManager, _ forwarder: LSPWatchedFilesForwarder) async throws {
        try manager.rebuildFiles(fromItem: manager.workspaceItem)
        manager.notifyObservers(updatedItems: [manager.workspaceItem])
        await forwarder.settle()
    }

    func event(_ directory: URL, _ name: String, _ type: FileChangeType) -> FileEvent {
        FileEvent(uri: URL(fileURLWithPath: directory.appending(path: name).path).absoluteString, type: type)
    }

    @Test
    func forwardsCreatedChangedAndDeletedFilesMatchingTheWatchers() async throws {
        try await withTempDir { dir in
            try "a".write(to: dir.appending(path: "existing.swift"), atomically: true, encoding: .utf8)
            try "b".write(to: dir.appending(path: "other.txt"), atomically: true, encoding: .utf8)
            let manager = makeFileManager(dir)
            let recorder = LSPWatchedFilesRecorder()
            let forwarder = makeForwarder(
                manager,
                directory: dir,
                recorder: recorder,
                watchers: [FileSystemWatcher(globPattern: "**/*.swift")]
            )
            forwarder.start()
            await forwarder.settle()

            try "c".write(to: dir.appending(path: "created.swift"), atomically: true, encoding: .utf8)
            try "d".write(to: dir.appending(path: "created.txt"), atomically: true, encoding: .utf8)
            try await notify(manager, forwarder)
            #expect(recorder.batches.count == 1)
            #expect(recorder.events == [event(dir, "created.swift", .created)])

            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: 1_000_000_000)],
                ofItemAtPath: dir.appending(path: "existing.swift").path
            )
            try await notify(manager, forwarder)
            #expect(recorder.batches.count == 2)
            #expect(recorder.batches.last?.changes == [event(dir, "existing.swift", .changed)])

            try FileManager.default.removeItem(at: dir.appending(path: "existing.swift"))
            try await notify(manager, forwarder)
            #expect(recorder.batches.count == 3)
            #expect(recorder.batches.last?.changes == [event(dir, "existing.swift", .deleted)])

            try await notify(manager, forwarder)
            #expect(recorder.batches.count == 3)

            forwarder.stop()
            try "e".write(to: dir.appending(path: "late.swift"), atomically: true, encoding: .utf8)
            try await notify(manager, forwarder)
            #expect(recorder.batches.count == 3)
        }
    }

    @Test
    func withoutWatchersNothingIsSent() async throws {
        try await withTempDir { dir in
            let manager = makeFileManager(dir)
            let recorder = LSPWatchedFilesRecorder()
            let forwarder = makeForwarder(manager, directory: dir, recorder: recorder, watchers: [])
            forwarder.start()
            await forwarder.settle()

            try "c".write(to: dir.appending(path: "created.swift"), atomically: true, encoding: .utf8)
            try await notify(manager, forwarder)

            #expect(recorder.batches.isEmpty)
            forwarder.stop()
        }
    }

    @Test
    func updatesForDirectoriesThatAreNotLoadedAreIgnored() async throws {
        try await withTempDir { dir in
            let manager = makeFileManager(dir)
            let recorder = LSPWatchedFilesRecorder()
            let forwarder = makeForwarder(
                manager,
                directory: dir,
                recorder: recorder,
                watchers: [FileSystemWatcher(globPattern: "**/*")]
            )
            forwarder.start()
            forwarder.fileManagerUpdated(updatedItems: [CEWorkspaceFile(url: dir.appending(path: "not-loaded"))])
            await forwarder.settle()

            #expect(recorder.batches.isEmpty)
            forwarder.stop()
        }
    }

    @Test
    func aForwarderOutlivingItsFileManagerDoesNothing() async throws {
        try await withTempDir { dir in
            var manager: CEWorkspaceFileManager? = makeFileManager(dir)
            let recorder = LSPWatchedFilesRecorder()
            let forwarder = try makeForwarder(
                #require(manager),
                directory: dir,
                recorder: recorder,
                watchers: [FileSystemWatcher(globPattern: "**/*")]
            )
            manager = nil

            forwarder.start()
            forwarder.fileManagerUpdated(updatedItems: [CEWorkspaceFile(url: dir)])
            await forwarder.settle()
            forwarder.stop()

            #expect(recorder.batches.isEmpty)
        }
    }
}
