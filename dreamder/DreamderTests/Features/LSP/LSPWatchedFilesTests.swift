import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@Suite("LSP glob matching")
struct LSPGlobTests {
    private struct Case: CustomStringConvertible {
        let glob: String
        let path: String
        let matches: Bool

        var description: String {
            "\(glob) ~ \(path) == \(matches)"
        }
    }

    private static let table: [Case] = [
        Case(glob: "**/*.ts", path: "a.ts", matches: true),
        Case(glob: "**/*.ts", path: "src/a.ts", matches: true),
        Case(glob: "**/*.ts", path: "src/deep/er/a.ts", matches: true),
        Case(glob: "**/*.ts", path: "/abs/src/a.ts", matches: true),
        Case(glob: "**/*.ts", path: "a.tsx", matches: false),
        Case(glob: "**/*.ts", path: "src/a.ts/b", matches: false),
        Case(glob: "*.json", path: "package.json", matches: true),
        Case(glob: "*.json", path: "dir/package.json", matches: false),
        Case(glob: "src/**", path: "src/a", matches: true),
        Case(glob: "src/**", path: "src/a/b/c.ts", matches: true),
        Case(glob: "src/**", path: "src/", matches: true),
        Case(glob: "src/**", path: "srcx/a", matches: false),
        Case(glob: "src/**", path: "src", matches: false),
        Case(glob: "a/**/b", path: "a/b", matches: true),
        Case(glob: "a/**/b", path: "a/x/y/b", matches: true),
        Case(glob: "a/**/b", path: "a/xb", matches: false),
        Case(glob: "a**b", path: "a/x/b", matches: true),
        Case(glob: "{a,b}", path: "a", matches: true),
        Case(glob: "{a,b}", path: "b", matches: true),
        Case(glob: "{a,b}", path: "ab", matches: false),
        Case(glob: "{a,b}", path: "c", matches: false),
        Case(glob: "*.{ts,tsx}", path: "x.tsx", matches: true),
        Case(glob: "*.{ts,tsx}", path: "x.js", matches: false),
        Case(glob: "a?c", path: "abc", matches: true),
        Case(glob: "a?c", path: "ac", matches: false),
        Case(glob: "a?c", path: "a/c", matches: false),
        Case(glob: "x[abc]", path: "xa", matches: true),
        Case(glob: "x[abc]", path: "xd", matches: false),
        Case(glob: "x[a-c]", path: "xb", matches: true),
        Case(glob: "x[!a]", path: "xb", matches: true),
        Case(glob: "x[!a]", path: "xa", matches: false),
        Case(glob: "[\\d]", path: "d", matches: true),
        Case(glob: "[\\d]", path: "\\", matches: true),
        Case(glob: "[\\d]", path: "5", matches: false),
        Case(glob: "a}", path: "a}", matches: true),
        Case(glob: "a}", path: "a", matches: false),
        Case(glob: "a,b", path: "a,b", matches: true),
        Case(glob: "a,b", path: "a", matches: false),
        Case(glob: "a[b", path: "a[b", matches: true),
        Case(glob: "a[b", path: "ab", matches: false),
        Case(glob: "[]", path: "[]", matches: true),
        Case(glob: "a.b", path: "a.b", matches: true),
        Case(glob: "a.b", path: "axb", matches: false),
        Case(glob: "a+b(c)", path: "a+b(c)", matches: true),
        Case(glob: "a+b(c)", path: "aab(c)", matches: false),
        Case(glob: "[z-a]", path: "m", matches: false),
        Case(glob: "{a", path: "a", matches: false),
        Case(glob: "{a,b", path: "b", matches: false),
        Case(glob: "", path: "", matches: true),
        Case(glob: "", path: "a", matches: false)
    ]

    @Test
    func tableOfPatterns() {
        for entry in Self.table {
            #expect(LSPGlob.matches(entry.glob, path: entry.path) == entry.matches, "\(entry)")
        }
    }

    @Test
    func regexPatternShapes() {
        #expect(LSPGlob.regexPattern(for: "*.ts") == "^[^/]*\\.ts$")
        #expect(LSPGlob.regexPattern(for: "**/x") == "^(?:.*/)?x$")
        #expect(LSPGlob.regexPattern(for: "x/**") == "^x/.*$")
        #expect(LSPGlob.regexPattern(for: "{a,b}") == "^(?:a|b)$")
        #expect(LSPGlob.regexPattern(for: "a}") == "^a\\}$")
        #expect(LSPGlob.regexPattern(for: "a[") == "^a\\[$")
        #expect(LSPGlob.regexPattern(for: "[!a]") == "^[^a]$")
        #expect(LSPGlob.regexPattern(for: "a?") == "^a[^/]$")
    }
}

@Suite("LSP file change tracker")
struct LSPFileChangeTrackerTests {
    private func file(_ modified: TimeInterval) -> LSPFileStamp {
        LSPFileStamp(modified: modified, isDirectory: false)
    }

    private func directory(_ modified: TimeInterval = 1) -> LSPFileStamp {
        LSPFileStamp(modified: modified, isDirectory: true)
    }

    @Test
    func theFirstUpdateOfAnUnseededDirectoryIsSilent() {
        var tracker = LSPFileChangeTracker()
        #expect(tracker.update("/r", children: ["/r/a": file(1)]).isEmpty)
        #expect(tracker.trackedDirectories == ["/r"])
        #expect(tracker.update("/r", children: ["/r/a": file(2)]) == [LSPFileChange(path: "/r/a", type: .changed)])
    }

    @Test
    func seededListingsReportCreatedChangedAndDeleted() {
        var tracker = LSPFileChangeTracker()
        tracker.seed("/r", children: ["/r/keep": file(1), "/r/edit": file(1), "/r/gone": file(1), "/r/dir": directory()])

        let unchanged = tracker.update("/r", children: ["/r/keep": file(1), "/r/edit": file(1), "/r/gone": file(1), "/r/dir": directory()])
        #expect(unchanged.isEmpty)

        let changes = tracker.update(
            "/r",
            children: ["/r/keep": file(1), "/r/edit": file(2), "/r/new-b": file(1), "/r/new-a": directory(), "/r/dir": directory()]
        )
        #expect(changes == [
            LSPFileChange(path: "/r/edit", type: .changed),
            LSPFileChange(path: "/r/new-a", type: .created),
            LSPFileChange(path: "/r/new-b", type: .created),
            LSPFileChange(path: "/r/gone", type: .deleted)
        ])
    }

    @Test
    func directoriesAreNeverReportedAsChanged() {
        var tracker = LSPFileChangeTracker()
        tracker.seed("/r", children: ["/r/d": directory(1), "/r/f": file(1)])
        #expect(tracker.update("/r", children: ["/r/d": directory(9), "/r/f": file(1)]).isEmpty)
        #expect(tracker.update("/r", children: ["/r/d": directory(9), "/r/f": directory(2)]).isEmpty)
        #expect(tracker.update("/r", children: ["/r/d": file(3), "/r/f": directory(2)]) == [
            LSPFileChange(path: "/r/d", type: .changed)
        ])
    }

    @Test
    func aDeletedDirectoryForgetsItsDescendants() {
        var tracker = LSPFileChangeTracker()
        tracker.seed("/r", children: ["/r/d": directory(), "/r/dd": directory()])
        tracker.seed("/r/d", children: ["/r/d/f": file(1), "/r/d/e": directory()])
        tracker.seed("/r/d/e", children: ["/r/d/e/g": file(1)])
        tracker.seed("/r/dd", children: ["/r/dd/h": file(1)])
        #expect(tracker.trackedDirectories == ["/r", "/r/d", "/r/d/e", "/r/dd"])

        let changes = tracker.update("/r", children: ["/r/dd": directory()])

        #expect(changes == [LSPFileChange(path: "/r/d", type: .deleted)])
        #expect(tracker.trackedDirectories == ["/r", "/r/dd"])
        #expect(tracker.update("/r", children: ["/r/dd": directory(), "/r/d": directory()]) == [
            LSPFileChange(path: "/r/d", type: .created)
        ])
        #expect(tracker.update("/r/d", children: ["/r/d/f": file(1)]).isEmpty)
    }

    @Test
    func modifyReportsOnlyKnownChangedNonDirectoryFiles() {
        var tracker = LSPFileChangeTracker()
        let old = LSPFileStamp(modified: 5, isDirectory: false)
        let newer = LSPFileStamp(modified: 9, isDirectory: false)
        tracker.seed("/ws", children: ["/ws/a.swift": old, "/ws/dir": LSPFileStamp(modified: 5, isDirectory: true)])

        #expect(tracker.modify("/ws/unknown.swift", stamp: newer) == nil)
        #expect(tracker.modify("/other/a.swift", stamp: newer) == nil)
        #expect(tracker.modify("/ws/a.swift", stamp: old) == nil)
        #expect(tracker.modify("/ws/a.swift", stamp: LSPFileStamp(modified: 0, isDirectory: false)) == nil)
        #expect(tracker.modify("/ws/dir", stamp: LSPFileStamp(modified: 9, isDirectory: true)) == nil)
        #expect(tracker.modify("/ws/a.swift", stamp: newer) == LSPFileChange(path: "/ws/a.swift", type: .changed))
        #expect(tracker.modify("/ws/a.swift", stamp: newer) == nil)
        #expect(tracker.update("/ws", children: ["/ws/a.swift": newer, "/ws/dir": LSPFileStamp(modified: 5, isDirectory: true)]).isEmpty)
    }

    @Test
    func stampsReadModificationDatesAndDirectoryFlags() async throws {
        try await withTempDir { dir in
            let file = dir.appending(path: "f.txt")
            try "x".write(to: file, atomically: true, encoding: .utf8)
            let date = Date(timeIntervalSinceReferenceDate: 700_000_000)
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path)
            let folder = dir.appending(path: "sub", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let missing = dir.appending(path: "missing").path

            let stamps = await LSPFileChangeTracker.stamps(of: [file.path, folder.path, missing])

            #expect(stamps.count == 3)
            let fileStamp = try #require(stamps[file.path])
            #expect(abs(fileStamp.modified - 700_000_000) < 0.001)
            #expect(!fileStamp.isDirectory)
            #expect(stamps[folder.path]?.isDirectory == true)
            #expect(stamps[missing] == LSPFileStamp(modified: 0, isDirectory: false))
        }
    }
}

@Suite("LSP watched files filter")
struct LSPWatchedFilesFilterTests {
    private func events(
        _ changes: [LSPFileChange],
        _ watchers: [FileSystemWatcher],
        workspace: String = "/ws"
    ) -> [FileEvent] {
        LSPWatchedFilesFilter.events(for: changes, watchers: watchers, workspacePath: workspace)
    }

    @Test
    func noWatchersProduceNoEvents() {
        #expect(events([LSPFileChange(path: "/ws/a.ts", type: .created)], []).isEmpty)
    }

    @Test
    func watchKindsMapFromChangeTypes() {
        #expect(LSPWatchedFilesFilter.watchKind(for: .created) == .create)
        #expect(LSPWatchedFilesFilter.watchKind(for: .changed) == .change)
        #expect(LSPWatchedFilesFilter.watchKind(for: .deleted) == .delete)
    }

    @Test
    func kindMasksRestrictChangeTypes() {
        let changes = [
            LSPFileChange(path: "/ws/a.ts", type: .created),
            LSPFileChange(path: "/ws/b.ts", type: .changed),
            LSPFileChange(path: "/ws/c.ts", type: .deleted)
        ]
        #expect(events(changes, [FileSystemWatcher(globPattern: "**/*.ts", kind: .create)]).map(\.type) == [.created])
        #expect(events(changes, [FileSystemWatcher(globPattern: "**/*.ts", kind: [.change, .delete])]).map(\.type) == [.changed, .deleted])
        #expect(events(changes, [FileSystemWatcher(globPattern: "**/*.ts")]).map(\.type) == [.created, .changed, .deleted])
        #expect(events(changes, [FileSystemWatcher(globPattern: "**/*.ts", kind: .all)]).count == 3)
    }

    @Test
    func globsMatchAbsoluteAndWorkspaceRelativePaths() {
        let change = [LSPFileChange(path: "/ws/src/a.ts", type: .changed)]
        #expect(events(change, [FileSystemWatcher(globPattern: "src/*.ts")]).count == 1)
        #expect(events(change, [FileSystemWatcher(globPattern: "/ws/src/*.ts")]).count == 1)
        #expect(events(change, [FileSystemWatcher(globPattern: "**/*.ts")]).count == 1)
        #expect(events(change, [FileSystemWatcher(globPattern: "lib/*.ts")]).isEmpty)
        #expect(events(change, [FileSystemWatcher(globPattern: "*.ts")]).isEmpty)
        #expect(events(change, [FileSystemWatcher(globPattern: "src/*.ts")], workspace: "/ws/").count == 1)
    }

    @Test
    func pathsOutsideTheWorkspaceOnlyMatchAbsoluteGlobs() {
        let change = [LSPFileChange(path: "/other/src/a.ts", type: .created)]
        #expect(events(change, [FileSystemWatcher(globPattern: "src/*.ts")]).isEmpty)
        #expect(events(change, [FileSystemWatcher(globPattern: "/other/src/*.ts")]).count == 1)
    }

    @Test
    func urisArePercentEncoded() throws {
        let change = [LSPFileChange(path: "/ws/my dir/a b.ts", type: .created)]
        let result = events(change, [FileSystemWatcher(globPattern: "**/*.ts")])
        #expect(result == [FileEvent(uri: "file:///ws/my%20dir/a%20b.ts", type: .created)])
    }
}
