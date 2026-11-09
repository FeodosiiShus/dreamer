import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct SourceControlManagerStatusFailureTests {
    private static let alertTitle = "Error reading Git status"

    private func dirtyRepository(_ dir: URL) async throws -> (GitMergeFixture, SourceControlManager) {
        let fixture = try await GitMergeFixture(root: dir)
        try fixture.write("a.txt", "one\n")
        try await fixture.commit("initial")
        try fixture.write("a.txt", "two\n")
        let manager = SourceControlManager(workspaceURL: dir, editorManager: EditorManager())
        return (fixture, manager)
    }

    private func changedNames(_ manager: SourceControlManager) -> [String] {
        manager.changedFiles.map(\.fileURL.lastPathComponent)
    }

    @Test
    func aFailedStatusKeepsTheChangedFilesAndIsSurfacedOnce() async throws {
        try await withTempDir { dir in
            let (_, manager) = try await dirtyRepository(dir)
            await manager.refreshAllChangedFiles()
            #expect(changedNames(manager) == ["a.txt"])
            #expect(manager.changedFilesFailure == nil)

            try Data("not an index".utf8).write(to: dir.appending(path: ".git/index"))
            await manager.refreshAllChangedFiles()

            let failure = try #require(manager.changedFilesFailure)
            #expect(failure.isEmpty == false)
            #expect(changedNames(manager) == ["a.txt"])
            #expect(manager.lastAlert == SourceControlAlert(title: Self.alertTitle, message: failure))

            manager.lastAlert = nil
            await manager.refreshAllChangedFiles()

            #expect(manager.changedFilesFailure == failure)
            #expect(manager.lastAlert == nil)
            #expect(changedNames(manager) == ["a.txt"])
        }
    }

    @Test
    func aDifferentFailureIsSurfacedAgain() async throws {
        try await withTempDir { dir in
            let (_, manager) = try await dirtyRepository(dir)
            manager.changedFilesFailure = "an earlier, different failure"
            try Data("not an index".utf8).write(to: dir.appending(path: ".git/index"))

            await manager.refreshAllChangedFiles()

            let failure = try #require(manager.changedFilesFailure)
            #expect(failure != "an earlier, different failure")
            #expect(manager.lastAlert?.title == Self.alertTitle)
            #expect(manager.lastAlert?.message == failure)
        }
    }

    @Test
    func aSuccessfulStatusClearsTheFailure() async throws {
        try await withTempDir { dir in
            let (_, manager) = try await dirtyRepository(dir)
            try Data("not an index".utf8).write(to: dir.appending(path: ".git/index"))
            await manager.refreshAllChangedFiles()
            #expect(manager.changedFilesFailure != nil)

            try FileManager.default.removeItem(at: dir.appending(path: ".git/index"))
            await manager.refreshAllChangedFiles()

            #expect(manager.changedFilesFailure == nil)
        }
    }

    @Test
    func aFailedStatusOnAnEmptyListStaysEmptyAndReportsTheFailure() async throws {
        try await withTempDir { dir in
            let (_, manager) = try await dirtyRepository(dir)
            try Data("not an index".utf8).write(to: dir.appending(path: ".git/index"))

            await manager.refreshAllChangedFiles()

            #expect(manager.changedFiles.isEmpty)
            #expect(manager.changedFilesFailure != nil)
        }
    }

    @Test
    func leavingTheRepositoryClearsTheListAndTheFailure() async throws {
        try await withTempDir { dir in
            let manager = SourceControlManager(workspaceURL: dir, editorManager: EditorManager())
            manager.changedFilesFailure = "stale"
            manager.changedFiles = [
                GitChangedFile(
                    status: .modified,
                    stagedStatus: .none,
                    fileURL: dir.appending(path: "a.txt"),
                    originalFilename: nil
                )
            ]

            await manager.refreshAllChangedFiles()

            #expect(manager.changedFiles.isEmpty)
            #expect(manager.changedFilesFailure == nil)
            #expect(manager.lastAlert == nil)
        }
    }
}
