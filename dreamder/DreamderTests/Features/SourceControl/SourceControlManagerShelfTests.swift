import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct SourceControlManagerShelfTests {
    @MainActor
    private struct World {
        let repo: ShelfRepo
        let manager: SourceControlManager

        func relativePaths() -> Set<String> {
            Set(manager.changedFiles.map { DiffPath.relativePath(of: $0.fileURL, from: manager.repositoryURL) })
        }

        func changedFiles(named paths: [String]) -> [GitChangedFile] {
            manager.changedFiles.filter {
                paths.contains(DiffPath.relativePath(of: $0.fileURL, from: manager.repositoryURL))
            }
        }
    }

    private func makeWorld(_ directory: URL) async throws -> World {
        let repo = try await ShelfRepo.make(in: directory)
        return World(repo: repo, manager: SourceControlManager(workspaceURL: directory, editorManager: EditorManager()))
    }

    @Test
    func shelvingTheSelectedFilesRefreshesStatusAndStashes() async throws {
        try await withTempDir { directory in
            let world = try await makeWorld(directory)
            try await world.repo.makeMixedChanges()
            await world.manager.refreshAllChangedFiles()
            let files = world.changedFiles(named: ShelfRepo.selectedPaths)
            #expect(files.count == 4)

            let shelf = try await world.manager.shelveChanges(files: files, name: "Subset")

            #expect(shelf.name == "Subset")
            #expect(shelf.files.map(\.path) == ShelfRepo.selectedPaths)
            try await eventually(timeout: .seconds(30)) { world.relativePaths() == ["old.txt", "other.txt"] }
            #expect(world.manager.stashEntries.count == 1)
            #expect(try await world.manager.shelfList().map(\.hash) == [shelf.hash])
        }
    }

    @Test
    func renamedFilesAreShelvedWithTheirOriginalPathOnce() async throws {
        try await withTempDir { directory in
            let world = try await makeWorld(directory)
            try await world.repo.fixture.run("mv", "old.txt", "moved.txt")
            await world.manager.refreshAllChangedFiles()
            let renamed = try #require(world.changedFiles(named: ["moved.txt"]).first)
            #expect(renamed.originalFilename == "old.txt")

            let shelf = try await world.manager.shelveChanges(files: [renamed, renamed], name: "Renamed")

            #expect(shelf.files.map(\.path) == ["moved.txt", "old.txt"])
            #expect(world.repo.fixture.exists("old.txt"))
            #expect(!world.repo.fixture.exists("moved.txt"))
        }
    }

    @Test
    func emptyAndOutsideSelectionsAreRejected() async throws {
        try await withTempDir { directory in
            let world = try await makeWorld(directory)
            let outside = GitChangedFile(
                status: .modified,
                stagedStatus: .none,
                fileURL: URL(filePath: "/definitely/elsewhere/file.txt"),
                originalFilename: nil
            )

            let none = await shelfThrownError { try await world.manager.shelveChanges(files: [], name: "x") }
            let elsewhere = await shelfThrownError { try await world.manager.shelveChanges(files: [outside], name: "x") }

            #expect((none as? GitShelfError) == .emptySelection)
            #expect((elsewhere as? GitShelfError) == .emptySelection)
            #expect(try await world.repo.stashSubjects().isEmpty)
        }
    }

    @Test
    func unshelveRestoresChangesRefreshesStatusAndKeepsBranchesUntouched() async throws {
        try await withTempDir { directory in
            let world = try await makeWorld(directory)
            try await world.repo.makeMixedChanges()
            await world.manager.refreshAllChangedFiles()
            let shelf = try await world.manager.shelveChanges(
                files: world.changedFiles(named: ShelfRepo.selectedPaths),
                name: "Subset"
            )

            let outcome = try await world.manager.unshelve(shelf, keep: false)

            #expect(outcome == .applied)
            #expect(world.manager.currentBranch == nil)
            try await eventually(timeout: .seconds(30)) { world.relativePaths() == ["a.txt", "b.txt", "c.txt", "new.txt", "old.txt", "other.txt"] }
            #expect(world.manager.stashEntries.isEmpty)
            #expect(try await world.manager.shelfList().isEmpty)
        }
    }

    @Test
    func unshelveWithConflictsRefreshesBranchesAndFeedsTheMergeCenter() async throws {
        try await withTempDir { directory in
            let world = try await makeWorld(directory)
            try world.repo.fixture.write("a.txt", "shelved\n")
            await world.manager.refreshAllChangedFiles()
            let shelf = try await world.manager.shelveChanges(files: world.changedFiles(named: ["a.txt"]), name: "Conflicting")
            try world.repo.fixture.write("a.txt", "committed\n")
            try await world.repo.fixture.commit("diverge")

            let outcome = try await world.manager.unshelve(shelf, keep: false)

            #expect(outcome == .conflicts)
            #expect(world.manager.currentBranch?.name == "main")
            #expect(try await world.repo.fixture.unmergedPaths() == ["a.txt"])
            #expect(try await world.manager.shelfList().map(\.hash) == [shelf.hash])
            try await eventually(timeout: .seconds(30)) { world.manager.changedFiles.contains { $0.anyStatus() == .unmerged } }
            await MergeConflictsCenter.shared.refresh(manager: world.manager)
            #expect(MergeConflictsCenter.shared.entries(for: world.manager.workspaceURL).count == 1)
        }
    }

    @Test
    func failedUnshelveRethrowsAfterRefreshingAndKeepsTheShelf() async throws {
        try await withTempDir { directory in
            let world = try await makeWorld(directory)
            try world.repo.fixture.write("new.txt", "shelved\n")
            await world.manager.refreshAllChangedFiles()
            let shelf = try await world.manager.shelveChanges(files: world.changedFiles(named: ["new.txt"]), name: "Untracked")
            try world.repo.fixture.write("new.txt", "in the way\n")

            let error = await shelfThrownError { try await world.manager.unshelve(shelf, keep: false) }

            guard case .untrackedFileExists? = error as? GitShelfError else {
                Issue.record("expected an untracked collision, got \(String(describing: error))")
                return
            }
            try await eventually(timeout: .seconds(30)) { world.relativePaths() == ["new.txt"] }
            #expect(try await world.manager.shelfList().map(\.hash) == [shelf.hash])
            #expect(try world.repo.fixture.read("new.txt") == "in the way\n")
        }
    }

    @Test
    func renameAndDeleteUpdateStashEntries() async throws {
        try await withTempDir { directory in
            let world = try await makeWorld(directory)
            try world.repo.fixture.write("a.txt", "a2\n")
            await world.manager.refreshAllChangedFiles()
            let shelf = try await world.manager.shelveChanges(files: world.changedFiles(named: ["a.txt"]), name: "before")

            try await world.manager.renameShelf(shelf, to: "after")

            #expect(world.manager.stashEntries.map(\.message) == [GitShelf.marker + "after"])
            #expect(try await world.manager.shelfList().map(\.hash) == [shelf.hash])

            try await world.manager.deleteShelf(shelf)

            #expect(world.manager.stashEntries.isEmpty)
            #expect(try await world.manager.shelfList().isEmpty)
        }
    }
}
