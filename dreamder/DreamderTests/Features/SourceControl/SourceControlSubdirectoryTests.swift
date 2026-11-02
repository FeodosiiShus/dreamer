import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite
struct SourceControlSubdirectoryTests {
    private func makeNestedWorkspace(_ dir: URL) throws -> (GitMergeFixture, URL) {
        let fixture = try GitMergeFixture(root: dir)
        try fixture.write("app/main.swift", "print(1)\n")
        try fixture.write("app/sub/helper.swift", "let x = 1\n")
        try fixture.write("other/readme.txt", "outside\n")
        try fixture.commit("initial")
        return (fixture, dir.appending(path: "app", directoryHint: .isDirectory))
    }

    @Test
    func workspaceInsideARepositoryUsesTheRepositoryRoot() throws {
        try withTempDir { dir in
            let (_, workspace) = try makeNestedWorkspace(dir)
            let manager = SourceControlManager(workspaceURL: workspace, editorManager: EditorManager())

            #expect(manager.repositoryURL.standardizedFileURL.path(percentEncoded: false).hasSuffix(dir.lastPathComponent + "/"))
            #expect(manager.gitClient.scopePath == "app")
            #expect(manager.isGitRepository)
            #expect(SourceControlManager.repositoryLocation(of: workspace) == .init(prefix: "app"))
            #expect(SourceControlManager.repositoryLocation(of: dir) == .init(prefix: nil))
            #expect(SourceControlManager.repositoryLocation(of: dir.deletingLastPathComponent()) == nil)
        }
    }

    @Test
    func statusOnlyListsWorkspaceFilesWithCorrectPaths() async throws {
        try await withTempDir { dir in
            let (fixture, workspace) = try makeNestedWorkspace(dir)
            try fixture.write("app/sub/helper.swift", "let x = 2\n")
            try fixture.write("app/new.swift", "new\n")
            try fixture.write("other/readme.txt", "changed outside\n")
            let manager = SourceControlManager(workspaceURL: workspace, editorManager: EditorManager())

            #expect(await manager.gitClient.validate())
            await manager.refreshAllChangedFiles()

            let paths = manager.changedFiles.map { $0.fileURL.standardizedFileURL.path(percentEncoded: false) }.sorted()
            let expected = [
                workspace.appending(path: "new.swift").standardizedFileURL.path(percentEncoded: false),
                workspace.appending(path: "sub/helper.swift").standardizedFileURL.path(percentEncoded: false)
            ]
            #expect(paths == expected)
            #expect(paths.allSatisfy { FileManager.default.fileExists(atPath: $0) })
        }
    }

    @Test
    func diffAndMergeRepositoriesResolveFilesFromTheRepositoryRoot() async throws {
        try await withTempDir { dir in
            let (fixture, workspace) = try makeNestedWorkspace(dir)
            try fixture.write("app/sub/helper.swift", "let x = 3\n")
            try fixture.write("other/readme.txt", "changed outside\n")
            let document = WorkspaceDocument()
            document.sourceControlManager = SourceControlManager(workspaceURL: workspace, editorManager: EditorManager())
            let repository = try #require(DiffRepository(workspace: document))

            let requests = try await repository.workingTreeRequests(against: "HEAD")
            #expect(requests.map(\.path) == ["app/sub/helper.swift"])

            let content = await repository.load(try #require(requests.first))
            #expect(content.left == .text("let x = 1\n"))
            #expect(content.right == .text("let x = 3\n"))

            let merge = try #require(MergeConflictRepository(workspace: document))
            #expect(merge.rootURL.standardizedFileURL == repository.rootURL.standardizedFileURL)
        }
    }
}
