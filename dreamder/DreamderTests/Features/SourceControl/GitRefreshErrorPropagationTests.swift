import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct GitRefreshErrorPropagationTests {
    private func makeWorkspaceOutsideAnyRepository(_ directory: URL) throws -> (WorkspaceDocument, SourceControlManager) {
        let workspace = try HostedViewFixture.makeWorkspace(in: directory)
        let editorManager = try #require(workspace.editorManager)
        let (client, _) = ScmFakeGit.client(directory: directory) { _ in
            ScmFakeGit.failure("fatal: not a git repository (or any of the parent directories): .git")
        }
        let manager = SourceControlManager(workspaceURL: directory, editorManager: editorManager, gitClient: client)
        workspace.sourceControlManager = manager
        return (workspace, manager)
    }

    @Test
    func refreshRemotesRethrowsGitFailures() async throws {
        try await withTempDir { directory in
            let (workspace, manager) = try makeWorkspaceOutsideAnyRepository(directory)
            defer { workspace.close() }

            await #expect(throws: GitClient.GitClientError.notGitRepository) {
                try await manager.refreshRemotes()
            }
            #expect(manager.remotes.isEmpty)
        }
    }

    @Test
    func refreshStashEntriesRethrowsGitFailures() async throws {
        try await withTempDir { directory in
            let (workspace, manager) = try makeWorkspaceOutsideAnyRepository(directory)
            defer { workspace.close() }

            await #expect(throws: GitClient.GitClientError.notGitRepository) {
                try await manager.refreshStashEntries()
            }
            #expect(manager.stashEntries.isEmpty)
        }
    }

    @Test
    func theWorkspaceRefreshSurfacesTheGitFailureAsAnAlert() async throws {
        try await withTempDir { directory in
            let (workspace, manager) = try makeWorkspaceOutsideAnyRepository(directory)
            defer { workspace.close() }

            await IslandsWorkspaceView.refreshGitData(enabled: true, in: workspace)

            #expect(
                manager.lastAlert
                    == SourceControlAlert(title: "Error refreshing Git data", message: "Not a git repository")
            )
        }
    }
}
