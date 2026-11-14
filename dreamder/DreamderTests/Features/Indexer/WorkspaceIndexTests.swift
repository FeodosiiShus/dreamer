import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct WorkspaceIndexTests {
    private func makeWorkspace(_ dir: URL, files: [String: String]) throws -> WorkspaceDocument {
        for (path, text) in files { try touch(dir, path, text) }
        let workspace = WorkspaceDocument()
        try workspace.read(from: dir, ofType: "")
        return workspace
    }

    private func indexedNames(_ workspace: WorkspaceDocument) -> [String] {
        (workspace.searchState?.indexer?.documents() ?? []).map(\.lastPathComponent).sorted()
    }

    private func searchNames(_ workspace: WorkspaceDocument, _ term: String) -> [String] {
        (workspace.searchState?.indexer?.search(term) ?? []).map(\.url.lastPathComponent).sorted()
    }

    private func isDone(_ workspace: WorkspaceDocument) -> Bool {
        workspace.searchState?.indexStatus == .done
    }

    private func project() -> [String: String] {
        [
            ".gitignore": "secret.txt\nignored/\n",
            ".env": "API_KEY=needle value",
            "README.md": "hello readme world needle",
            "src/a.swift": "let greeting = needle here",
            "secret.txt": "needle secret content",
            "ignored/b.swift": "needle ignored content",
            "node_modules/pkg/c.js": "needle dependency content",
            "build/out.txt": "needle build content",
            ".git/HEAD": "needle ref content"
        ]
    }

    private func addBinaryAndOversizedFiles(_ dir: URL) throws {
        try Data([0x68, 0x69, 0x00, 0x6E, 0x65, 0x65, 0x64, 0x6C, 0x65]).write(to: dir.appending(path: "data.dat"))
        try Data("needle logo".utf8).write(to: dir.appending(path: "logo.png"))
        let oversized = Data(repeating: 0x61, count: WorkspaceFileScope.maxIndexableTextSize + 1)
        try oversized.write(to: dir.appending(path: "huge.txt"))
    }

    @Test
    func candidatesAreExclusionAwareAndSkipBinaryAndOversizedFiles() async throws {
        try await withTempDir { dir in
            for (path, text) in project() { try touch(dir, path, text) }
            try addBinaryAndOversizedFiles(dir)
            let workspace = WorkspaceDocument()
            try workspace.read(from: dir, ofType: "")
            defer { workspace.tearDownFileScope() }

            try await eventually { isDone(workspace) }

            #expect(indexedNames(workspace) == [".env", ".gitignore", "README.md", "a.swift"])
        }
    }

    @Test
    func findInFilesIncludesAFileCreatedAfterOpen() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir, files: project())
            defer { workspace.tearDownFileScope() }
            try await eventually { isDone(workspace) }
            let state = try #require(workspace.searchState)
            let scope = try #require(workspace.fileScope)

            try touch(dir, "src/late.swift", "late needle arrival")
            scope.handle(events: [fsEvent(dir.appending(path: "src/late.swift"), .itemCreated)])

            try await eventually {
                await state.search("needle")
                return state.searchResult.map { $0.file.url.lastPathComponent }.contains("late.swift")
            }
        }
    }

    @Test
    func findInFilesNeverReturnsIgnoredPaths() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir, files: project())
            defer { workspace.tearDownFileScope() }
            try await eventually { isDone(workspace) }
            let state = try #require(workspace.searchState)

            await state.search("needle")

            let names = state.searchResult.map { $0.file.url.lastPathComponent }.sorted()
            #expect(names == [".env", "README.md", "a.swift"])
            #expect(state.findNavigatorStatus == .found)
        }
    }

    @Test
    func theIndexFollowsAddedModifiedAndRemovedFiles() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir, files: project())
            defer { workspace.tearDownFileScope() }
            try await eventually { isDone(workspace) }
            let scope = try #require(workspace.fileScope)
            let fresh = dir.appending(path: "src/fresh.swift")

            try touch(dir, "src/fresh.swift", "original phrase content")
            scope.handle(events: [fsEvent(fresh, .itemCreated)])
            try await eventually { indexedNames(workspace).contains("fresh.swift") }
            try await eventually { searchNames(workspace, "original") == ["fresh.swift"] }

            try touch(dir, "src/fresh.swift", "replacement phrase content")
            scope.handle(events: [fsEvent(fresh, .itemModified)])
            try await eventually { searchNames(workspace, "replacement") == ["fresh.swift"] }
            try await eventually { searchNames(workspace, "original").isEmpty }

            try Data([0x68, 0x00, 0x69]).write(to: fresh)
            scope.handle(events: [fsEvent(fresh, .itemModified)])
            try await eventually { !indexedNames(workspace).contains("fresh.swift") }

            try touch(dir, "pkg/one.swift", "first package file")
            try touch(dir, "pkg/two.swift", "second package file")
            scope.handle(events: [fsEvent(dir.appending(path: "pkg"), .itemCreated)])
            try await eventually { indexedNames(workspace).contains("one.swift") && indexedNames(workspace).contains("two.swift") }

            try FileManager.default.removeItem(at: dir.appending(path: "pkg"))
            scope.handle(events: [fsEvent(dir.appending(path: "pkg"), .itemRemoved)])
            try await eventually { !indexedNames(workspace).contains("one.swift") && !indexedNames(workspace).contains("two.swift") }

            try FileManager.default.removeItem(at: dir.appending(path: "src/a.swift"))
            scope.handle(events: [fsEvent(dir.appending(path: "src/a.swift"), .itemRemoved)])
            try await eventually { !indexedNames(workspace).contains("a.swift") }
        }
    }

    @Test
    func ignoreGlobChangesRebuildTheIndex() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir, files: project())
            defer { workspace.tearDownFileScope() }
            try await eventually { isDone(workspace) }
            let scope = try #require(workspace.fileScope)
            #expect(indexedNames(workspace).contains("README.md"))

            try await eventually {
                scope.setIgnoreGlobs(["README.md"])
                return isDone(workspace) && !indexedNames(workspace).contains("README.md") && indexedNames(workspace).contains("a.swift")
            }
        }
    }

    @Test
    func addingTheProjectAgainRebuildsFromTheScope() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir, files: project())
            defer { workspace.tearDownFileScope() }
            try await eventually { isDone(workspace) }
            let state = try #require(workspace.searchState)

            state.addProjectToIndex()
            state.addProjectToIndex()

            try await eventually { isDone(workspace) && indexedNames(workspace) == [".env", ".gitignore", "README.md", "a.swift"] }
        }
    }

    @Test
    func aWorkspaceWithoutAScopeHasNothingToIndex() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir, files: project())
            try await eventually { isDone(workspace) }
            let state = try #require(workspace.searchState)

            workspace.tearDownFileScope()
            state.addProjectToIndex()

            #expect(state.indexStatus == .done)
            #expect(state.indexer?.documents().isEmpty == true)
        }
    }

    @Test
    func realFileSystemEventsReachTheIndex() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir, files: project())
            defer { workspace.tearDownFileScope() }
            try await eventually { isDone(workspace) }
            try await Task.sleep(for: .milliseconds(300))

            try touch(dir, "src/watched.swift", "watched file content")

            try await eventually { indexedNames(workspace).contains("watched.swift") }
        }
    }

    @Test
    func modifyingAnIndexedFileUpdatesTheIndexContentFromBothSources() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir, files: project())
            defer { workspace.tearDownFileScope() }
            try await eventually { isDone(workspace) }
            let scope = try #require(workspace.fileScope)
            let observer = try #require(workspace.fileScopeObserver)
            let url = dir.appending(path: "src/a.swift")
            try await eventually { searchNames(workspace, "greeting") == ["a.swift"] }

            try touch(dir, "src/a.swift", "let replacement = fresh content here")
            scope.handle(events: [fsEvent(url, .itemModified)])
            observer.fileManagerModifiedFiles([url])

            try await eventually { searchNames(workspace, "replacement") == ["a.swift"] }
            try await eventually { searchNames(workspace, "greeting").isEmpty }
        }
    }

    @Test
    func userExclusionsRebuildTheIndex() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir, files: project())
            defer { workspace.tearDownFileScope() }
            try await eventually { isDone(workspace) && indexedNames(workspace).contains("a.swift") }
            let model = try #require(workspace.excludedDirectories)
            defer { model.cancelExclusion(dir.appending(path: "src")) }

            model.exclude(dir.appending(path: "src"))

            try await eventually { isDone(workspace) && !indexedNames(workspace).contains("a.swift") }
            #expect(indexedNames(workspace).contains("README.md"))
        }
    }

    @Test
    func searchSettingsGlobsReachTheScope() async throws {
        try await withTempDir { settingsDir in
            try await withTempDir { dir in
                let store = Dreamder.Settings(baseURL: settingsDir)
                try touch(dir, "x.zzglob", "glob words")
                try touch(dir, "keep.txt", "keep words")
                let workspace = WorkspaceDocument()
                try SettingsScope.$current.withValue(store) { try workspace.read(from: dir, ofType: "") }
                defer { workspace.tearDownFileScope() }
                let scope = try #require(workspace.fileScope)

                store.preferences.search.ignoreGlobPatterns.append(GlobPattern(value: "*.zzglob"))

                try await eventually {
                    guard scope.isExcluded(dir.appending(path: "x.zzglob")) else { return false }
                    let files = await scope.enumerateFiles(limit: nil)
                    return relativePaths(files, in: dir) == ["keep.txt"]
                }
            }
        }
    }

    @Test
    func deltasCanBeAppliedToAnyIndex() async throws {
        try await withTempDir { dir in
            try touch(dir, "keep.txt", "keep this content")
            try touch(dir, "drop/gone.txt", "drop this content")
            try Data([0x00, 0x01]).write(to: dir.appending(path: "binary.txt"))
            let scope = WorkspaceFileScope(rootURL: dir)
            let indexer = try #require(SearchIndexer.Memory.create())

            await WorkspaceDocument.SearchState.apply(
                updated: [dir.appending(path: "keep.txt"), dir.appending(path: "drop/gone.txt"), dir.appending(path: "binary.txt")],
                removed: [],
                to: indexer,
                scope: scope
            )
            #expect(indexer.documents().map(\.lastPathComponent).sorted() == ["gone.txt", "keep.txt"])

            await WorkspaceDocument.SearchState.apply(
                updated: [],
                removed: [dir.appending(path: "drop")],
                to: indexer,
                scope: scope
            )
            #expect(indexer.documents().map(\.lastPathComponent) == ["keep.txt"])

            await WorkspaceDocument.SearchState.apply(
                updated: [],
                removed: [dir],
                to: indexer,
                scope: scope
            )
            #expect(indexer.documents().isEmpty)
        }
    }
}
