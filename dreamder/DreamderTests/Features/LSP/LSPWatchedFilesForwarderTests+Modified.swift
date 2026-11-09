import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@MainActor
extension LSPWatchedFilesForwarderTests {
    @Test
    func modifiedFilesAreForwardedAsChangedWhenTheyMatchTheGlobs() async throws {
        try await withTempDir { dir in
            let file = dir.appending(path: "a.swift")
            let other = dir.appending(path: "b.txt")
            try "a".write(to: file, atomically: true, encoding: .utf8)
            try "b".write(to: other, atomically: true, encoding: .utf8)
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

            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: 1_000_000_000)],
                ofItemAtPath: file.path
            )
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: 1_000_000_000)],
                ofItemAtPath: other.path
            )
            forwarder.fileManagerModifiedFiles([file, other])
            await forwarder.settle()
            #expect(recorder.batches.count == 1)
            #expect(recorder.events == [event(dir, "a.swift", .changed)])

            forwarder.fileManagerModifiedFiles([file])
            forwarder.fileManagerModifiedFiles([])
            await forwarder.settle()
            #expect(recorder.batches.count == 1)

            forwarder.stop()
        }
    }

    @Test
    func aModifiedNewFileIsNotReportedAgainAfterItsCreate() async throws {
        try await withTempDir { dir in
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

            let created = dir.appending(path: "new.swift")
            try "x".write(to: created, atomically: true, encoding: .utf8)
            forwarder.fileManagerModifiedFiles([created])
            await forwarder.settle()
            #expect(recorder.batches.isEmpty)

            try await notify(manager, forwarder)
            #expect(recorder.events == [event(dir, "new.swift", .created)])

            forwarder.fileManagerModifiedFiles([created])
            await forwarder.settle()
            #expect(recorder.batches.count == 1)

            try FileManager.default.removeItem(at: created)
            forwarder.fileManagerModifiedFiles([created])
            await forwarder.settle()
            #expect(recorder.batches.count == 1)

            forwarder.stop()
        }
    }

    @Test
    func operationsQueuedBehindARunningOneAreSkippedOnceTheForwarderStops() async throws {
        try await withTempDir { dir in
            let first = dir.appending(path: "a.swift")
            try "a".write(to: first, atomically: true, encoding: .utf8)
            try "b".write(to: dir.appending(path: "b.swift"), atomically: true, encoding: .utf8)
            let manager = makeFileManager(dir)
            let recorder = LSPWatchedFilesRecorder()
            let gate = LSPServiceGate()
            let stampLog = LSPWatchedFilesStampLog()
            let watchers = [FileSystemWatcher(globPattern: "**/*.swift")]
            let forwarder = LSPWatchedFilesForwarder(
                fileManager: manager,
                workspacePath: dir.path,
                watchers: { watchers },
                send: { params in recorder.record(params) },
                stamps: { paths in
                    await stampLog.record(paths)
                    await gate.wait()
                    return await LSPFileChangeTracker.stamps(of: paths)
                }
            )

            forwarder.start()
            try await eventually(timeout: .seconds(30)) { gate.waiterCount == 1 }
            forwarder.fileManagerModifiedFiles([first])
            let settled = Task { await forwarder.settle() }
            await Task.yield()
            forwarder.stop()
            gate.open()
            await settled.value

            #expect(!stampLog.calls.isEmpty)
            #expect(!stampLog.calls.contains([first.path]))
            #expect(recorder.batches.isEmpty)
        }
    }

    @Test
    func updatesOfSeveralDirectoriesAreForwardedInPathOrder() async throws {
        try await withTempDir { dir in
            let first = dir.appending(path: "a")
            let second = dir.appending(path: "b")
            try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
            let manager = makeFileManager(dir)
            let firstItem = CEWorkspaceFile(url: first)
            let secondItem = CEWorkspaceFile(url: second)
            manager.childrenMap[firstItem.id] = []
            manager.childrenMap[secondItem.id] = []
            let recorder = LSPWatchedFilesRecorder()
            let forwarder = makeForwarder(
                manager,
                directory: dir,
                recorder: recorder,
                watchers: [FileSystemWatcher(globPattern: "**/*.swift")]
            )
            forwarder.start()
            await forwarder.settle()

            let firstFile = first.appending(path: "one.swift")
            let secondFile = second.appending(path: "two.swift")
            try "1".write(to: firstFile, atomically: true, encoding: .utf8)
            try "2".write(to: secondFile, atomically: true, encoding: .utf8)
            manager.childrenMap[firstItem.id] = [firstFile.path]
            manager.childrenMap[secondItem.id] = [secondFile.path]
            forwarder.fileManagerUpdated(updatedItems: [secondItem, firstItem])
            await forwarder.settle()

            #expect(recorder.batches.count == 1)
            #expect(recorder.events == [event(first, "one.swift", .created), event(second, "two.swift", .created)])
            forwarder.stop()
        }
    }
}
