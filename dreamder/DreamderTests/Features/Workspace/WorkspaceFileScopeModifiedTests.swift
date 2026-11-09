import Foundation
import Testing
@testable import Dreamder

private func updatedPaths(_ change: WorkspaceFileChange?, in root: URL) -> [String]? {
    guard case .delta(let updated, _)? = change else { return nil }
    return relativePaths(updated, in: root)
}

private func primed(_ root: URL) async -> WorkspaceFileScope {
    let scope = WorkspaceFileScope(rootURL: root)
    _ = await scope.enumerateFiles(limit: nil)
    return scope
}

@MainActor
@Suite("WorkspaceFileScope modified files", .uiGate)
struct WorkspaceFileScopeModifiedTests {
    @Test
    func theSameModificationFromBothSourcesIsReindexedExactlyOnce() async throws {
        try await withTempDir { root in
            try touch(root, "a.txt", "one")
            let scope = await primed(root)
            let observer = WorkspaceFileScopeObserver(scope: scope)
            var changes = scope.changes().makeAsyncIterator()
            let url = root.appending(path: "a.txt")

            try touch(root, "a.txt", "two words")
            scope.handle(events: [fsEvent(url, .itemModified)])
            observer.fileManagerModifiedFiles([url])
            await scope.applyModifiedFiles([url])
            scope.handle(events: [fsEvent(url, .itemModified)])
            scope.setIgnoreGlobs(["zzz"])

            #expect(updatedPaths(await changes.next(), in: root) == ["a.txt"])
            #expect(await changes.next() == .reset)
        }
    }

    @Test
    func theFileManagerSourceAloneReportsAndAnotherChangeIsReportedAgain() async throws {
        try await withTempDir { root in
            try touch(root, "a.txt", "one")
            let scope = await primed(root)
            var changes = scope.changes().makeAsyncIterator()
            let url = root.appending(path: "a.txt")

            try touch(root, "a.txt", "second version")
            await scope.applyModifiedFiles([url])
            #expect(updatedPaths(await changes.next(), in: root) == ["a.txt"])

            try touch(root, "a.txt", "third and longer version")
            scope.handle(events: [fsEvent(url, .itemModified)])
            #expect(updatedPaths(await changes.next(), in: root) == ["a.txt"])
            #expect(scope.cachedFiles()?.count == 1)
        }
    }

    @Test
    func removalForgetsTheSignatureSoARecreatedFileIsReportedAgain() async throws {
        try await withTempDir { root in
            try touch(root, "a.txt", "same")
            let scope = await primed(root)
            var changes = scope.changes().makeAsyncIterator()
            let url = root.appending(path: "a.txt")

            scope.handle(events: [fsEvent(url, .itemModified)])
            #expect(updatedPaths(await changes.next(), in: root) == ["a.txt"])

            try FileManager.default.removeItem(at: url)
            scope.handle(events: [fsEvent(url, .itemRemoved)])
            #expect(updatedPaths(await changes.next(), in: root) == [])

            try touch(root, "a.txt", "same")
            scope.handle(events: [fsEvent(url, .itemCreated)])
            #expect(updatedPaths(await changes.next(), in: root) == ["a.txt"])
        }
    }

    @Test
    func onlyExistingIncludedRegularFilesAreReportedFromTheFileManager() async throws {
        try await withTempDir { root in
            try touch(root, ".gitignore", "*.log\n")
            try touch(root, "kept.txt")
            try touch(root, "noise.log")
            try touch(root, "node_modules/x.js")
            try touch(root, ".git/HEAD")
            try touch(root, "dir/inner.txt")
            let scope = await primed(root)
            var changes = scope.changes().makeAsyncIterator()

            await scope.applyModifiedFiles([
                root.appending(path: "noise.log"),
                root.appending(path: "node_modules/x.js"),
                root.appending(path: ".git/HEAD"),
                root.appending(path: "dir"),
                root.appending(path: "missing.txt"),
                root,
                URL(fileURLWithPath: "/somewhere/else/a.txt"),
                root.appending(path: "kept.txt")
            ])
            await scope.applyModifiedFiles([])

            #expect(updatedPaths(await changes.next(), in: root) == ["kept.txt"])
        }
    }

    @Test
    func theObserverIgnoresEmptyBatchesAndForwardsFiles() async throws {
        try await withTempDir { root in
            try touch(root, "a.txt", "one")
            let scope = await primed(root)
            let observer = WorkspaceFileScopeObserver(scope: scope)
            var changes = scope.changes().makeAsyncIterator()

            observer.fileManagerModifiedFiles([])
            try touch(root, "a.txt", "changed content")
            observer.fileManagerModifiedFiles([root.appending(path: "a.txt")])

            #expect(updatedPaths(await changes.next(), in: root) == ["a.txt"])
        }
    }

    @Test
    func entriesCarryModificationSignatures() throws {
        try withTempDir { root in
            try touch(root, "a.txt", "12345")
            let fileSystem = DiskWorkspaceFileSystem()
            let first = try #require(fileSystem.entry(at: root.appending(path: "a.txt")))
            #expect(first.signature.size == 5)
            #expect(first.signature.modified != nil)

            try touch(root, "a.txt", "123456789")
            let second = try #require(fileSystem.entry(at: root.appending(path: "a.txt")))
            #expect(second.signature != first.signature)
        }
    }
}
