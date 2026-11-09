import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct CEWorkspaceFileManagerExclusionTests {
    private func makeDirectories(_ names: [String], in root: URL) throws {
        for name in names {
            try FileManager.default.createDirectory(
                at: root.appending(path: name, directoryHint: .isDirectory),
                withIntermediateDirectories: true
            )
        }
    }

    @Test
    func refreshingTheStreamAppliesNewExclusionsInBothDirections() async throws {
        try withTempDir { dir in
            try makeDirectories(["node_modules", "gen", "src"], in: dir)
            let isolated = try makeIsolatedDefaults()
            defer { removeIsolatedDefaults(isolated.defaults, suiteName: isolated.suiteName) }
            let model = ExcludedDirectories(rootURL: dir, defaults: isolated.defaults)
            let manager = CEWorkspaceFileManager(folderUrl: dir, ignoredFilesAndFolders: [], sourceControlManager: nil)
            defer { manager.cleanUp() }
            let base = manager.exclusionPolicy().streamRootPath
            let initial = try #require(manager.fsEventStream)

            #expect(initial.isRunning)
            #expect(initial.exclusionPaths.contains("\(base)/node_modules"))
            #expect(!initial.exclusionPaths.contains("\(base)/gen"))

            manager.refreshEventStream()
            #expect(manager.fsEventStream === initial)

            model.exclude(dir.appending(path: "gen"))
            manager.refreshEventStream()

            let afterExclude = try #require(manager.fsEventStream)
            #expect(afterExclude !== initial)
            #expect(!initial.isRunning)
            #expect(afterExclude.isRunning)
            #expect(afterExclude.exclusionPaths.first == "\(base)/gen")
            #expect(afterExclude.exclusionPaths.contains("\(base)/node_modules"))

            model.cancelExclusion(dir.appending(path: "node_modules"))
            manager.refreshEventStream()

            let afterCancel = try #require(manager.fsEventStream)
            #expect(afterCancel !== afterExclude)
            #expect(!afterExclude.isRunning)
            #expect(afterCancel.exclusionPaths.contains("\(base)/gen"))
            #expect(!afterCancel.exclusionPaths.contains("\(base)/node_modules"))
        }
    }

    @Test
    func aDirectoryWhoseExclusionWasCancelledStartsReportingFileChanges() async throws {
        try await withTempDir { dir in
            try makeDirectories(["node_modules"], in: dir)
            let isolated = try makeIsolatedDefaults()
            defer { removeIsolatedDefaults(isolated.defaults, suiteName: isolated.suiteName) }
            let model = ExcludedDirectories(rootURL: dir, defaults: isolated.defaults)
            let manager = CEWorkspaceFileManager(folderUrl: dir, ignoredFilesAndFolders: [], sourceControlManager: nil)
            defer { manager.cleanUp() }
            let observer = RecordingObserver()
            manager.addObserver(observer)
            let dependency = dir.appending(path: "node_modules/dep.js")
            var revision = 0

            model.cancelExclusion(dir.appending(path: "node_modules"))
            manager.refreshEventStream()

            try await eventually {
                revision += 1
                try? "revision \(revision)".write(to: dependency, atomically: false, encoding: .utf8)
                return observer.modified.contains { $0.contains { $0.lastPathComponent == "dep.js" } }
            }
        }
    }

    @Test
    func refreshingDoesNothingWhenWatchingWasStopped() async throws {
        try withTempDir { dir in
            try makeDirectories(["gen"], in: dir)
            let isolated = try makeIsolatedDefaults()
            defer { removeIsolatedDefaults(isolated.defaults, suiteName: isolated.suiteName) }
            let model = ExcludedDirectories(rootURL: dir, defaults: isolated.defaults)
            let manager = CEWorkspaceFileManager(folderUrl: dir, ignoredFilesAndFolders: [], sourceControlManager: nil)
            let stream = try #require(manager.fsEventStream)
            model.exclude(dir.appending(path: "gen"))

            manager.cleanUp()
            manager.refreshEventStream()
            #expect(manager.fsEventStream === stream)
            #expect(!stream.isRunning)

            manager.fsEventStream = nil
            manager.refreshEventStream()
            #expect(manager.fsEventStream == nil)
        }
    }
}
