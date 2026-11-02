import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite
struct DiffViewerViewModelTests {
    private func repository(_ root: URL) throws -> DiffRepository {
        let document = WorkspaceDocument()
        document.sourceControlManager = SourceControlManager(workspaceURL: root, editorManager: EditorManager())
        return try #require(DiffRepository(workspace: document))
    }

    private func makeFixture(_ dir: URL) throws -> GitMergeFixture {
        let fixture = try GitMergeFixture(root: dir)
        let lines = (1...30).map { "line \($0)" }.joined(separator: "\n") + "\n"
        try fixture.write("two-hunks.txt", lines)
        try fixture.write("same.txt", "same\n")
        try fixture.commit("base")
        let edited = lines
            .replacingOccurrences(of: "line 2\n", with: "line two\n")
            .replacingOccurrences(of: "line 25\n", with: "line twenty-five\n")
        try fixture.write("two-hunks.txt", edited)
        return fixture
    }

    private func model(_ dir: URL) async throws -> DiffViewerViewModel {
        let repo = try repository(dir)
        let files = try await repo.workingTreeRequests(against: "HEAD")
        let model = DiffViewerViewModel(repository: repo, mode: .workingTree(ref: "HEAD"), files: files)
        await model.loadInitial()
        return model
    }

    @Test
    func loadsFirstFileAndNavigatesBetweenHunks() async throws {
        try await withTempDir { dir in
            _ = try makeFixture(dir)
            let model = try await model(dir)

            #expect(model.title == "two-hunks.txt (HEAD vs Local)")
            #expect(model.showsFileList == false)
            #expect(model.isLoading == false)
            #expect(model.differenceCount == 2)
            #expect(model.differenceSummary == "2 differences")
            #expect(model.canNavigatePrevious)
            #expect(model.canNavigateNext)

            model.nextDifference()
            #expect(model.currentHunkIndex == 0)
            #expect(model.canNavigatePrevious == false)
            let firstRequest = try #require(model.scrollRequest)

            model.nextDifference()
            #expect(model.currentHunkIndex == 1)
            #expect(model.canNavigateNext == false)
            let secondRequest = try #require(model.scrollRequest)
            #expect(secondRequest.row > firstRequest.row)
            #expect(secondRequest.token > firstRequest.token)

            model.nextDifference()
            #expect(model.currentHunkIndex == 1)
            model.previousDifference()
            model.previousDifference()
            #expect(model.currentHunkIndex == 0)
        }
    }

    @Test
    func previousFromNothingJumpsToTheLastHunk() async throws {
        try await withTempDir { dir in
            _ = try makeFixture(dir)
            let model = try await model(dir)
            model.previousDifference()
            #expect(model.currentHunkIndex == 1)
        }
    }

    @Test
    func switchingFilesKeepsSelectionWhenStillPresent() async throws {
        try await withTempDir { dir in
            let fixture = try makeFixture(dir)
            try fixture.write("same.txt", "changed\n")
            let model = try await model(dir)
            #expect(model.showsFileList)

            await model.select("same.txt")
            #expect(model.title == "same.txt (HEAD vs Local)")
            #expect(model.differenceSummary == "1 difference")

            let repo = try repository(dir)
            await model.updateFiles(try await repo.workingTreeRequests(against: "HEAD"))
            #expect(model.selectedID == "same.txt")

            try fixture.run("checkout", "--", "same.txt")
            await model.updateFiles(try await repo.workingTreeRequests(against: "HEAD"))
            #expect(model.selectedID == "two-hunks.txt")

            await model.updateFiles([])
            #expect(model.files.count == 1)
            await model.select("missing.txt")
            #expect(model.selectedID == "two-hunks.txt")
        }
    }

    @Test
    func binaryAndEmptySidesShowAMessageInsteadOfADiff() async throws {
        try await withTempDir { dir in
            let fixture = try makeFixture(dir)
            try Data([0x50, 0x00, 0x01]).write(to: dir.appending(path: "blob.bin"))
            try fixture.write("empty.txt", "")
            let repo = try repository(dir)
            let model = DiffViewerViewModel(
                repository: repo,
                mode: .workingTree(ref: "HEAD"),
                files: [
                    repo.workingTreeRequest(status: .untracked, path: "blob.bin", originalPath: nil, ref: "HEAD"),
                    repo.workingTreeRequest(status: .untracked, path: "empty.txt", originalPath: nil, ref: "HEAD")
                ]
            )

            await model.loadInitial()
            #expect(model.message == "Binary file")
            #expect(model.diff == nil)
            #expect(model.differenceSummary.isEmpty)
            #expect(model.canNavigateNext == false)

            await model.select("empty.txt")
            #expect(model.message == "Nothing to compare")
        }
    }

    @Test
    func commitModeTitlesUseShortHashes() async throws {
        try await withTempDir { dir in
            _ = try makeFixture(dir)
            let repo = try repository(dir)
            let request = repo.commitRequest(path: "same.txt", status: .added, commit: "abcdef0123456789", parent: nil)
            let rootCommit = DiffViewerViewModel(
                repository: repo,
                mode: .commit(hash: "abcdef0123456789", parentHash: nil),
                files: [request]
            )
            #expect(rootCommit.title == "same.txt (Empty vs abcdef01)")

            let child = DiffViewerViewModel(
                repository: repo,
                mode: .commit(hash: "abcdef0123456789", parentHash: "0011223344556677"),
                files: [request]
            )
            #expect(child.title == "same.txt (00112233 vs abcdef01)")

            let empty = DiffViewerViewModel(repository: repo, mode: .workingTree(ref: "HEAD"), files: [])
            #expect(empty.title == "Diff")
            await empty.loadInitial()
            #expect(empty.diff == nil)
        }
    }
}
