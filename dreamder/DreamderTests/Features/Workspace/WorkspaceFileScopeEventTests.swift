import Foundation
import Testing
@testable import Dreamder

private func deltaPaths(
    _ change: WorkspaceFileChange?,
    in root: URL
) -> (updated: [String], removed: [String])? {
    guard case .delta(let updated, let removed)? = change else { return nil }
    return (relativePaths(updated, in: root), relativePaths(removed, in: root))
}

private func primedScope(_ root: URL) async -> WorkspaceFileScope {
    let scope = WorkspaceFileScope(rootURL: root)
    _ = await scope.enumerateFiles(limit: nil)
    return scope
}

@Suite("WorkspaceFileScope events")
struct WorkspaceFileScopeEventTests {
    @Test
    func createdFilesAreAddedToTheCacheAndPublished() async throws {
        try await withTempDir { root in
            try touch(root, "a.txt")
            let scope = await primedScope(root)
            var changes = scope.changes().makeAsyncIterator()

            try touch(root, "b.txt")
            scope.handle(events: [fsEvent(root.appending(path: "b.txt"), .itemCreated)])

            let delta = deltaPaths(await changes.next(), in: root)
            #expect(delta?.updated == ["b.txt"])
            #expect(delta?.removed == [])
            #expect(relativePaths(scope.cachedFiles() ?? [], in: root) == ["a.txt", "b.txt"])
        }
    }

    @Test
    func modifiedFilesArePublishedWithoutDuplicatingTheCache() async throws {
        try await withTempDir { root in
            try touch(root, "a.txt")
            let scope = await primedScope(root)
            var changes = scope.changes().makeAsyncIterator()

            scope.handle(events: [fsEvent(root.appending(path: "a.txt"), .itemModified)])

            let delta = deltaPaths(await changes.next(), in: root)
            #expect(delta?.updated == ["a.txt"])
            #expect(scope.cachedFiles()?.count == 1)
        }
    }

    @Test
    func removedFilesLeaveTheCacheAndArePublished() async throws {
        try await withTempDir { root in
            try touch(root, "a.txt")
            try touch(root, "b.txt")
            let scope = await primedScope(root)
            var changes = scope.changes().makeAsyncIterator()

            try FileManager.default.removeItem(at: root.appending(path: "a.txt"))
            scope.handle(events: [fsEvent(root.appending(path: "a.txt"), .itemRemoved)])

            let delta = deltaPaths(await changes.next(), in: root)
            #expect(delta?.removed == ["a.txt"])
            #expect(relativePaths(scope.cachedFiles() ?? [], in: root) == ["b.txt"])
        }
    }

    @Test
    func createdDirectoriesAreWalkedAndRemovedDirectoriesDropEverythingBelow() async throws {
        try await withTempDir { root in
            try touch(root, "keep.txt")
            let scope = await primedScope(root)
            var changes = scope.changes().makeAsyncIterator()

            try touch(root, "d/x.txt")
            try touch(root, "d/deep/y.txt")
            scope.handle(events: [fsEvent(root.appending(path: "d"), .itemCreated)])
            let added = deltaPaths(await changes.next(), in: root)
            #expect(added?.updated == ["d/deep/y.txt", "d/x.txt"])
            #expect(relativePaths(scope.cachedFiles() ?? [], in: root) == ["d/deep/y.txt", "d/x.txt", "keep.txt"])

            try FileManager.default.removeItem(at: root.appending(path: "d"))
            scope.handle(events: [fsEvent(root.appending(path: "d"), .itemRemoved)])
            let removed = deltaPaths(await changes.next(), in: root)
            #expect(removed?.removed == ["d"])
            #expect(relativePaths(scope.cachedFiles() ?? [], in: root) == ["keep.txt"])
        }
    }

    @Test
    func renamedDirectoriesRemoveTheOldPathAndAddTheNewOne() async throws {
        try await withTempDir { root in
            try touch(root, "d/x.txt")
            let scope = await primedScope(root)
            var changes = scope.changes().makeAsyncIterator()

            try FileManager.default.moveItem(at: root.appending(path: "d"), to: root.appending(path: "e"))
            scope.handle(events: [
                fsEvent(root.appending(path: "d"), .itemRenamed),
                fsEvent(root.appending(path: "e"), .itemRenamed)
            ])

            let delta = deltaPaths(await changes.next(), in: root)
            #expect(delta?.updated == ["e/x.txt"])
            #expect(delta?.removed == ["d"])
            #expect(relativePaths(scope.cachedFiles() ?? [], in: root) == ["e/x.txt"])
        }
    }

    @Test
    func modifiedDirectoriesAndSpecialEntriesAreNotWalked() async throws {
        try await withTempDir { root in
            try touch(root, "d/x.txt")
            let scope = await primedScope(root)
            var changes = scope.changes().makeAsyncIterator()
            try FileManager.default.createSymbolicLink(
                at: root.appending(path: "link"),
                withDestinationURL: root.appending(path: "d/x.txt")
            )

            scope.handle(events: [
                fsEvent(root.appending(path: "d"), .itemModified),
                fsEvent(root.appending(path: "link"), .itemCreated)
            ])
            scope.setIgnoreGlobs(["zzz"])

            let first = deltaPaths(await changes.next(), in: root)
            #expect(first?.updated == [])
            #expect(first?.removed == ["link"])
            #expect(await changes.next() == .reset)
        }
    }

    @Test
    func excludedIgnoredAndGitInternalEventsAreFiltered() async throws {
        try await withTempDir { root in
            try touch(root, ".gitignore", "*.log\n")
            try touch(root, "seed.txt")
            let scope = await primedScope(root)
            var changes = scope.changes().makeAsyncIterator()

            try touch(root, "node_modules/x.js")
            try touch(root, ".git/HEAD")
            try touch(root, "ignored.log")
            try touch(root, "real.txt")
            scope.handle(events: [
                fsEvent(root.appending(path: "node_modules/x.js"), .itemCreated),
                fsEvent(root.appending(path: ".git/HEAD"), .itemModified),
                fsEvent(root.appending(path: "ignored.log"), .itemCreated),
                fsEvent(root.appending(path: "real.txt"), .itemCreated)
            ])

            let delta = deltaPaths(await changes.next(), in: root)
            #expect(delta?.updated == ["real.txt"])
            #expect(delta?.removed == ["ignored.log", "node_modules/x.js"])
            #expect(relativePaths(scope.cachedFiles() ?? [], in: root) == [".gitignore", "real.txt", "seed.txt"])
        }
    }

    @Test
    func directoryChangeOwnerAndOutsideEventsAreIgnored() async throws {
        try await withTempDir { root in
            try touch(root, "a.txt")
            let scope = await primedScope(root)
            var changes = scope.changes().makeAsyncIterator()

            try touch(root, "b.txt")
            scope.handle(events: [])
            scope.handle(events: [
                fsEvent(root.appending(path: "a.txt"), .changeInDirectory),
                fsEvent(root.appending(path: "a.txt"), .itemChangedOwner),
                fsEvent(URL(fileURLWithPath: "/somewhere/else/c.txt"), .itemCreated),
                fsEvent(root, .itemModified),
                fsEvent(root.appending(path: "b.txt"), .itemCreated)
            ])

            let delta = deltaPaths(await changes.next(), in: root)
            #expect(delta?.updated == ["b.txt"])
        }
    }

    struct IgnoreFileCase: Sendable {
        let relative: String
        let remaining: [String]
    }

    @Test(arguments: [
        IgnoreFileCase(relative: ".gitignore", remaining: [".gitignore"]),
        IgnoreFileCase(relative: "sub/.gitignore", remaining: ["a.txt", "sub/.gitignore"]),
        IgnoreFileCase(relative: ".git/info/exclude", remaining: [])
    ])
    func ignoreFileChangesResetTheCacheAndTheRules(_ item: IgnoreFileCase) async throws {
        try await withTempDir { root in
            try touch(root, "a.txt")
            try touch(root, "sub/b.txt")
            let scope = await primedScope(root)
            var changes = scope.changes().makeAsyncIterator()

            try touch(root, item.relative, "*.txt\n")
            scope.handle(events: [fsEvent(root.appending(path: item.relative), .itemModified)])

            #expect(await changes.next() == .reset)
            #expect(scope.cachedFiles() == nil)
            let files = await scope.enumerateFiles(limit: nil)
            #expect(relativePaths(files, in: root) == item.remaining)
        }
    }

    @Test
    func rootChangesAndHugeBatchesReset() async throws {
        try await withTempDir { root in
            try touch(root, "a.txt")
            let scope = await primedScope(root)
            var changes = scope.changes().makeAsyncIterator()

            scope.handle(events: [fsEvent(root, .mustRescan)])
            #expect(await changes.next() == .reset)
            #expect(scope.cachedFiles() == nil)

            _ = await scope.enumerateFiles(limit: nil)
            let events = (0..<2001).map { fsEvent(root.appending(path: "f\($0).txt"), .itemCreated) }
            scope.handle(events: events)
            #expect(await changes.next() == .reset)
            #expect(scope.cachedFiles() == nil)
        }
    }

    @Test
    func eventPathsInTheAlternatePrivatePrefixAreRelocated() async throws {
        try await withTempDir { root in
            try touch(root, "a.txt")
            let scope = await primedScope(root)
            var changes = scope.changes().makeAsyncIterator()
            try touch(root, "b.txt")

            let path = root.workspacePathKey
            let alternate = path.hasPrefix("/private/") ? String(path.dropFirst("/private".count)) : "/private" + path
            scope.handle(events: [
                DirectoryEventStream.Event(path: alternate + "/b.txt", eventType: .itemCreated),
                DirectoryEventStream.Event(path: alternate, eventType: .itemModified)
            ])

            let delta = deltaPaths(await changes.next(), in: root)
            #expect(delta?.updated == ["b.txt"])
        }
    }

    @Test
    func eventsBeforeTheFirstScanAreDroppedButTheNextScanSeesTheFiles() async throws {
        try await withTempDir { root in
            let scope = WorkspaceFileScope(rootURL: root)
            var changes = scope.changes().makeAsyncIterator()
            try touch(root, "late.txt")

            scope.handle(events: [fsEvent(root.appending(path: "late.txt"), .itemCreated)])
            scope.setIgnoreGlobs(["zzz"])

            #expect(await changes.next() == .reset)
            let files = await scope.enumerateFiles(limit: nil)
            #expect(relativePaths(files, in: root) == ["late.txt"])
        }
    }
}

@Suite("WorkspaceFileScope directory refresh")
struct WorkspaceFileScopeRefreshTests {
    @Test
    func newAndRemovedFilesInADirectoryArePublished() async throws {
        try await withTempDir { root in
            try touch(root, "a.txt")
            let scope = await primedScope(root)
            var changes = scope.changes().makeAsyncIterator()

            await scope.refreshDirectories([root])
            try touch(root, "b.txt")
            await scope.refreshDirectories([root])
            let added = deltaPaths(await changes.next(), in: root)
            #expect(added?.updated == ["b.txt"])
            #expect(added?.removed == [])

            try FileManager.default.removeItem(at: root.appending(path: "a.txt"))
            await scope.refreshDirectories([root])
            let removed = deltaPaths(await changes.next(), in: root)
            #expect(removed?.removed == ["a.txt"])
            #expect(relativePaths(scope.cachedFiles() ?? [], in: root) == ["b.txt"])
        }
    }

    @Test
    func newSubdirectoriesAreWalkedAndVanishedOnesAreRemovedAsAWhole() async throws {
        try await withTempDir { root in
            try touch(root, "old/x.txt")
            try touch(root, "old/y.txt")
            try touch(root, "kept/z.txt")
            let scope = await primedScope(root)
            var changes = scope.changes().makeAsyncIterator()

            try FileManager.default.removeItem(at: root.appending(path: "old"))
            try touch(root, "fresh/a.txt")
            await scope.refreshDirectories([root])

            let delta = deltaPaths(await changes.next(), in: root)
            #expect(delta?.updated == ["fresh/a.txt"])
            #expect(delta?.removed == ["old"])
            #expect(relativePaths(scope.cachedFiles() ?? [], in: root) == ["fresh/a.txt", "kept/z.txt"])
        }
    }

    @Test
    func filesAndDirectoriesThatSwapKindsAreReconciled() async throws {
        try await withTempDir { root in
            try touch(root, "a")
            try touch(root, "d/x.txt")
            let scope = await primedScope(root)
            var changes = scope.changes().makeAsyncIterator()

            try FileManager.default.removeItem(at: root.appending(path: "a"))
            try touch(root, "a/inner.txt")
            try FileManager.default.removeItem(at: root.appending(path: "d"))
            try touch(root, "d")
            await scope.refreshDirectories([root])

            let delta = deltaPaths(await changes.next(), in: root)
            #expect(delta?.updated == ["a/inner.txt", "d"])
            #expect(delta?.removed == ["a", "d"])
            #expect(relativePaths(scope.cachedFiles() ?? [], in: root) == ["a/inner.txt", "d"])
        }
    }

    @Test
    func nestedDirectoriesOnlyReconcileTheirOwnContent() async throws {
        try await withTempDir { root in
            try touch(root, "sub/a.txt")
            try touch(root, "other/o.txt")
            let scope = await primedScope(root)
            var changes = scope.changes().makeAsyncIterator()

            try touch(root, "sub/b.txt")
            try touch(root, "other/new.txt")
            await scope.refreshDirectories([root.appending(path: "sub", directoryHint: .isDirectory)])

            let delta = deltaPaths(await changes.next(), in: root)
            #expect(delta?.updated == ["sub/b.txt"])
            #expect(relativePaths(scope.cachedFiles() ?? [], in: root) == ["other/o.txt", "sub/a.txt", "sub/b.txt"])
        }
    }

    @Test
    func excludedEntriesDirectoriesAndForeignPathsAreSkipped() async throws {
        try await withTempDir { root in
            try touch(root, ".gitignore", "*.log\nskipdir/\n")
            try touch(root, "a.txt")
            let scope = await primedScope(root)
            var changes = scope.changes().makeAsyncIterator()

            try touch(root, "node_modules/x.js")
            try touch(root, "skipdir/y.txt")
            try touch(root, "noise.log")
            try FileManager.default.createSymbolicLink(
                at: root.appending(path: "link"),
                withDestinationURL: root.appending(path: "a.txt")
            )
            await scope.refreshDirectories([
                root,
                root.appending(path: "node_modules", directoryHint: .isDirectory),
                URL(fileURLWithPath: "/somewhere/else", isDirectory: true)
            ])
            try touch(root, "real.txt")
            await scope.refreshDirectories([root])

            let delta = deltaPaths(await changes.next(), in: root)
            #expect(delta?.updated == ["real.txt"])
        }
    }

    @Test
    func refreshingBeforeTheFirstScanPublishesNothing() async throws {
        try await withTempDir { root in
            try touch(root, "a.txt")
            let scope = WorkspaceFileScope(rootURL: root)
            var changes = scope.changes().makeAsyncIterator()

            await scope.refreshDirectories([root])
            scope.setIgnoreGlobs(["zzz"])

            #expect(await changes.next() == .reset)
        }
    }
}

@MainActor
@Suite("WorkspaceFileScope watching", .uiGate)
struct WorkspaceFileScopeWatchingTests {
    @Test
    func theFileManagerObserverRefreshesChangedFolders() async throws {
        try await withTempDir { root in
            try touch(root, "a.txt")
            let scope = await primedScope(root)
            var changes = scope.changes().makeAsyncIterator()
            let observer = WorkspaceFileScopeObserver(scope: scope)

            observer.fileManagerUpdated(updatedItems: [CEWorkspaceFile(url: root.appending(path: "a.txt"))])
            try touch(root, "b.txt")
            observer.fileManagerUpdated(updatedItems: [
                CEWorkspaceFile(url: root.appending(path: "a.txt")),
                CEWorkspaceFile(url: root)
            ])

            let delta = deltaPaths(await changes.next(), in: root)
            #expect(delta?.updated == ["b.txt"])
        }
    }

    @Test
    func realFileSystemEventsUpdateTheCacheIncrementally() async throws {
        try await withTempDir { root in
            try touch(root, "a.txt")
            let scope = await primedScope(root)
            scope.startWatching()
            scope.startWatching()
            try await Task.sleep(for: .milliseconds(300))

            try touch(root, "created.txt")
            try await eventually {
                (scope.cachedFiles() ?? []).contains { $0.lastPathComponent == "created.txt" }
            }

            try FileManager.default.removeItem(at: root.appending(path: "created.txt"))
            try await eventually {
                !(scope.cachedFiles() ?? []).contains { $0.lastPathComponent == "created.txt" }
            }

            try touch(root, ".gitignore", "*.txt\n")
            try await eventually { scope.cachedFiles() == nil }
            let files = await scope.enumerateFiles(limit: nil)
            #expect(relativePaths(files, in: root) == [".gitignore"])

            scope.stopWatching()
            scope.stopWatching()
        }
    }
}
