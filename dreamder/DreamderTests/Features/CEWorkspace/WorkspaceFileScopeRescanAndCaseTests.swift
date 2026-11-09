import Foundation
import Testing
@testable import Dreamder

private struct CaseInsensitiveFileSystem: WorkspaceFileSystem {
    private let inner = DiskWorkspaceFileSystem()

    func entries(in directory: URL) -> [WorkspaceFileEntry] {
        inner.entries(in: directory)
    }

    func entry(at url: URL) -> WorkspaceFileEntry? {
        let wanted = url.lastPathComponent.lowercased()
        let siblings = inner.entries(in: url.deletingLastPathComponent())
        guard let match = siblings.first(where: { $0.name.lowercased() == wanted }) else { return nil }
        return WorkspaceFileEntry(url: url, name: match.name, kind: match.kind, signature: match.signature)
    }
}

private func primedScope(_ root: URL, fileSystem: any WorkspaceFileSystem = DiskWorkspaceFileSystem()) async
    -> WorkspaceFileScope {
    let scope = WorkspaceFileScope(rootURL: root, fileSystem: fileSystem)
    _ = await scope.enumerateFiles(limit: nil)
    return scope
}

@Suite("WorkspaceFileScope rescans and case-only renames")
struct WorkspaceFileScopeRescanAndCaseTests {
    @Test
    func aRescanRequestForASubdirectoryResetsTheCacheSoSilentChangesAreFound() async throws {
        try await withTempDir { root in
            try touch(root, "a.txt")
            let scope = await primedScope(root)
            var changes = scope.changes().makeAsyncIterator()
            try touch(root, "sub/lost.txt")

            scope.handle(events: [fsEvent(root.appending(path: "sub"), .mustRescan)])

            #expect(await changes.next() == .reset)
            #expect(scope.cachedFiles() == nil)
            let files = await scope.enumerateFiles(limit: nil)
            #expect(relativePaths(files, in: root) == ["a.txt", "sub/lost.txt"])
        }
    }

    @Test
    func aRescanRequestWinsOverItemEventsOfTheSameBatch() async throws {
        try await withTempDir { root in
            try touch(root, "a.txt")
            let scope = await primedScope(root)
            var changes = scope.changes().makeAsyncIterator()
            try touch(root, "b.txt")

            scope.handle(events: [
                fsEvent(root.appending(path: "b.txt"), .itemCreated),
                fsEvent(root, .mustRescan),
                fsEvent(root.appending(path: "c.txt"), .itemCreated)
            ])

            #expect(await changes.next() == .reset)
            #expect(scope.cachedFiles() == nil)
        }
    }

    @Test
    func diskEntriesReportTheNameStoredOnDiskNotTheRequestedSpelling() throws {
        try withTempDir { root in
            try touch(root, "Mixed.txt")
            let disk = DiskWorkspaceFileSystem()

            let exact = disk.entry(at: root.appending(path: "Mixed.txt"))
            let otherSpelling = disk.entry(at: root.appending(path: "mixed.TXT"))
            let missing = disk.entry(at: root.appending(path: "absent.txt"))
            let listed = disk.entries(in: root)

            #expect(exact?.name == "Mixed.txt")
            #expect(exact?.kind == .file)
            #expect(otherSpelling == nil || otherSpelling?.name == "Mixed.txt")
            #expect(missing == nil)
            #expect(listed.map(\.name) == ["Mixed.txt"])
        }
    }

    @Test
    func renamingAFileToADifferentCaseLeavesExactlyOneEntry() async throws {
        try await withTempDir { root in
            try touch(root, "a.txt")
            let scope = await primedScope(root, fileSystem: CaseInsensitiveFileSystem())
            var changes = scope.changes().makeAsyncIterator()
            try FileManager.default.removeItem(at: root.appending(path: "a.txt"))
            try touch(root, "A.txt")

            scope.handle(events: [
                fsEvent(root.appending(path: "a.txt"), .itemRenamed),
                fsEvent(root.appending(path: "A.txt"), .itemRenamed)
            ])

            guard case .delta(let updated, let removed)? = await changes.next() else {
                Issue.record("expected a delta")
                return
            }
            #expect(relativePaths(updated, in: root) == ["A.txt"])
            #expect(relativePaths(removed, in: root) == ["a.txt"])
            #expect(relativePaths(scope.cachedFiles() ?? [], in: root) == ["A.txt"])
        }
    }

    @Test
    func renamingADirectoryToADifferentCaseMovesItsFilesToTheNewSpelling() async throws {
        try await withTempDir { root in
            try touch(root, "Src/x.swift")
            let scope = await primedScope(root, fileSystem: CaseInsensitiveFileSystem())
            try FileManager.default.removeItem(at: root.appending(path: "Src"))
            try touch(root, "src/x.swift")

            scope.handle(events: [
                fsEvent(root.appending(path: "Src"), .itemRenamed),
                fsEvent(root.appending(path: "src"), .itemRenamed)
            ])

            #expect(relativePaths(scope.cachedFiles() ?? [], in: root) == ["src/x.swift"])
        }
    }

    @Test
    func aModifiedEventForTheOldSpellingDoesNotResurrectTheRenamedFile() async throws {
        try await withTempDir { root in
            try touch(root, "A.txt")
            let scope = await primedScope(root, fileSystem: CaseInsensitiveFileSystem())

            scope.handleModified([root.appending(path: "a.txt")])

            #expect(relativePaths(scope.cachedFiles() ?? [], in: root) == ["A.txt"])
        }
    }
}
