import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct CommitToolWindowRenameRollbackTests {
    private typealias State = CommitToolWindowRepositoryState

    private let trackedFiles = ["old.txt", "new.txt", "sub/moved.txt", "copy.txt", "other.txt"]

    private func makeRepo(_ directory: URL) async throws -> (GitMergeFixture, SourceControlManager) {
        let fixture = try await GitMergeFixture(root: directory)
        try fixture.write("old.txt", "old content\nsecond line\n")
        try fixture.write("other.txt", "other\n")
        try fixture.write("sub/keep.txt", "keep\n")
        try await fixture.commit("initial")
        return (fixture, SourceControlManager(workspaceURL: directory, editorManager: EditorManager()))
    }

    private func changed(_ name: String, in manager: SourceControlManager) throws -> GitChangedFile {
        try #require(manager.changedFiles.first { $0.fileURL.lastPathComponent == name })
    }

    @Test
    func rollingBackAStagedRenameRestoresTheOldPathAndRemovesTheNewOneInIndexAndWorktree() async throws {
        try await withTempDir { directory in
            let (fixture, manager) = try await makeRepo(directory)
            let clean = try await State.capture(of: fixture, files: trackedFiles)
            try await fixture.run("mv", "old.txt", "new.txt")
            await manager.refreshAllChangedFiles()
            let renamed = try changed("new.txt", in: manager)
            #expect(renamed.originalFilename == "old.txt")
            #expect(renamed.stagedStatus == .renamed)
            #expect(try await State.capture(of: fixture, files: trackedFiles) != clean)

            await CommitToolWindowViewModel().rollback([renamed], using: manager)

            #expect(manager.lastAlert == nil)
            #expect(try await State.capture(of: fixture, files: trackedFiles) == clean)
            #expect(fixture.exists("new.txt") == false)
            #expect(try await fixture.run("status", "--porcelain").isEmpty)
            #expect(manager.changedFiles.isEmpty)
        }
    }

    @Test
    func rollingBackARenameWithEditsIntoASubfolderDiscardsTheEditsAndLeavesOtherChangesAlone() async throws {
        try await withTempDir { directory in
            let (fixture, manager) = try await makeRepo(directory)
            let original = try Data(contentsOf: directory.appending(path: "old.txt"))
            try await fixture.run("mv", "old.txt", "sub/moved.txt")
            try fixture.write("sub/moved.txt", "old content\nsecond line\nedited after the move\n")
            try fixture.write("other.txt", "other changed\n")
            await manager.refreshAllChangedFiles()
            let moved = try changed("moved.txt", in: manager)
            #expect(moved.originalFilename == "old.txt")

            await CommitToolWindowViewModel().rollback([moved], using: manager)

            #expect(manager.lastAlert == nil)
            #expect(try Data(contentsOf: directory.appending(path: "old.txt")) == original)
            #expect(fixture.exists("sub/moved.txt") == false)
            #expect(fixture.exists("sub/keep.txt"))
            #expect(try fixture.read("other.txt") == "other changed\n")
            #expect(try await fixture.run("diff", "--cached").isEmpty)
            #expect(try await fixture.run("status", "--porcelain") == " M other.txt\n")
            #expect(try changed("other.txt", in: manager).status == .modified)
            #expect(manager.changedFiles.count == 1)
        }
    }

    @Test
    func rollingBackACopyRemovesTheCopyAndKeepsTheLocalEditsOfItsSource() async throws {
        try await withTempDir { directory in
            let (fixture, manager) = try await makeRepo(directory)
            try FileManager.default.copyItem(
                at: directory.appending(path: "old.txt"),
                to: directory.appending(path: "copy.txt")
            )
            try await fixture.run("add", "copy.txt")
            try fixture.write("old.txt", "old content edited locally\n")
            let copy = GitChangedFile(
                status: GitStatus.none,
                stagedStatus: .copied,
                fileURL: URL(filePath: "copy.txt", relativeTo: manager.gitClient.directoryURL),
                originalFilename: "old.txt"
            )

            await CommitToolWindowViewModel().rollback([copy], using: manager)

            #expect(manager.lastAlert == nil)
            #expect(fixture.exists("copy.txt") == false)
            #expect(try fixture.read("old.txt") == "old content edited locally\n")
            #expect(try await fixture.run("diff", "--cached").isEmpty)
            #expect(try await fixture.run("status", "--porcelain") == " M old.txt\n")
        }
    }

    @Test
    func rollingBackARenameWhoseOldPathIsUnknownToGitReportsTheFailureAndChangesNothing() async throws {
        try await withTempDir { directory in
            let (fixture, manager) = try await makeRepo(directory)
            try await fixture.run("mv", "old.txt", "new.txt")
            let before = try await State.capture(of: fixture, files: trackedFiles)
            let bogus = GitChangedFile(
                status: GitStatus.none,
                stagedStatus: .renamed,
                fileURL: URL(filePath: "new.txt", relativeTo: manager.gitClient.directoryURL),
                originalFilename: "never-existed.txt"
            )

            await CommitToolWindowViewModel().rollback([bogus], using: manager)

            #expect(manager.lastAlert?.title == "Failed to rollback")
            #expect(try await State.capture(of: fixture, files: trackedFiles) == before)
            #expect(fixture.exists("new.txt"))
        }
    }
}
