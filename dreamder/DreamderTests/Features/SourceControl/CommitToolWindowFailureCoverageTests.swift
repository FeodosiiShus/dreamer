import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct CommitToolWindowFailureCoverage {
    private func makeRepo(_ directory: URL) async throws -> (GitMergeFixture, SourceControlManager) {
        let fixture = try await GitMergeFixture(root: directory)
        try fixture.write("a.txt", "a\n")
        try fixture.write("b.txt", "b\n")
        try await fixture.commit("initial")
        return (fixture, SourceControlManager(workspaceURL: directory, editorManager: EditorManager()))
    }

    private func installRejectingHook(in fixture: GitMergeFixture) async throws {
        let hooks = fixture.root.appending(path: ".git/hooks", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: hooks, withIntermediateDirectories: true)
        let hook = hooks.appending(path: "pre-commit")
        try "#!/bin/sh\necho rejected-by-hook >&2\nexit 1\n".write(to: hook, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path(percentEncoded: false))
        try await fixture.run("config", "core.hooksPath", hooks.path(percentEncoded: false))
    }

    @Test
    func aRejectedCommitKeepsTheMessageAndReportsTheFailure() async throws {
        try await withTempDir { directory in
            let (fixture, manager) = try await makeRepo(directory)
            try await installRejectingHook(in: fixture)
            try fixture.write("a.txt", "changed\n")
            await manager.refreshAllChangedFiles()

            let model = CommitToolWindowViewModel()
            model.message = "Try"
            await model.commit(using: manager, andPush: true)

            #expect(model.isCommitting == false)
            #expect(model.message == "Try")
            #expect(manager.lastAlert?.title == "Failed to commit")
            #expect(manager.lastAlert?.message.contains("rejected-by-hook") == true)
            #expect(manager.pushSheetIsPresented == false)
            #expect(try await fixture.run("rev-list", "--count", "HEAD").trimmingCharacters(in: .newlines) == "1")
        }
    }

    @Test
    func aRejectedAmendNamesTheAmendInTheAlert() async throws {
        try await withTempDir { directory in
            let (fixture, manager) = try await makeRepo(directory)
            try await installRejectingHook(in: fixture)
            try fixture.write("a.txt", "changed\n")
            await manager.refreshAllChangedFiles()

            let model = CommitToolWindowViewModel()
            model.message = "Amend"
            model.amend = true
            await model.commit(using: manager, andPush: false)

            #expect(manager.lastAlert?.title == "Failed to amend commit")
            #expect(model.amend)
            #expect(model.isCommitting == false)
        }
    }

    @Test
    func stagingAFileThatDisappearedFailsTheCommit() async throws {
        try await withTempDir { directory in
            let (fixture, manager) = try await makeRepo(directory)
            try fixture.write("new.txt", "n\n")
            await manager.refreshAllChangedFiles()
            let untracked = try #require(manager.changedFiles.first { $0.fileURL.lastPathComponent == "new.txt" })

            let model = CommitToolWindowViewModel()
            model.setIncluded(true, for: untracked)
            model.message = "Add new"
            try FileManager.default.removeItem(at: fixture.root.appending(path: "new.txt"))
            await model.commit(using: manager, andPush: false)

            #expect(manager.lastAlert?.title == "Failed to commit")
            #expect(model.isCommitting == false)
            #expect(model.includedUnversionedIDs.contains(untracked.id))
            #expect(try await fixture.run("rev-list", "--count", "HEAD").trimmingCharacters(in: .newlines) == "1")
        }
    }

    @Test
    func rollbackStopsAtTheFirstFailureAndReportsIt() async throws {
        try await withTempDir { directory in
            let (fixture, manager) = try await makeRepo(directory)
            try fixture.write("a.txt", "changed\n")
            await manager.refreshAllChangedFiles()
            let real = try #require(manager.changedFiles.first { $0.fileURL.lastPathComponent == "a.txt" })
            let ghost = GitChangedFile(
                status: .modified,
                stagedStatus: GitStatus.none,
                fileURL: fixture.root.appending(path: "ghost.txt"),
                originalFilename: nil
            )

            let model = CommitToolWindowViewModel()
            await model.rollback([ghost, real], using: manager)

            #expect(manager.lastAlert?.title == "Failed to rollback")
            #expect(try fixture.read("a.txt") == "changed\n")
            #expect(manager.changedFiles.map(\.fileURL.lastPathComponent) == ["a.txt"])
        }
    }
}
