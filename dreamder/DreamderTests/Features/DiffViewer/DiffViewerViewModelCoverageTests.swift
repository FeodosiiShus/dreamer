import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct DiffViewerViewModelCoverageTests {
    private func repository(_ root: URL) throws -> DiffRepository {
        let document = WorkspaceDocument()
        document.sourceControlManager = SourceControlManager(workspaceURL: root, editorManager: EditorManager())
        return try #require(DiffRepository(workspace: document))
    }

    private func makeFixture(_ dir: URL) async throws -> GitMergeFixture {
        let fixture = try await GitMergeFixture(root: dir)
        let lines = (1...30).map { "line \($0)" }.joined(separator: "\n") + "\n"
        try fixture.write("two-hunks.txt", lines)
        try fixture.write("single.txt", "one\ntwo\n")
        try fixture.write("same.txt", "same\n")
        try await fixture.commit("base")
        try fixture.write(
            "two-hunks.txt",
            lines
                .replacingOccurrences(of: "line 2\n", with: "line two\n")
                .replacingOccurrences(of: "line 25\n", with: "line twenty-five\n")
        )
        try fixture.write("single.txt", "one\nTWO\n")
        return fixture
    }

    @Test
    func identicalSidesReportNoDifferences() async throws {
        try await withTempDir { dir in
            _ = try await makeFixture(dir)
            let repo = try repository(dir)
            let model = DiffViewerViewModel(
                repository: repo,
                mode: .workingTree(ref: "HEAD"),
                files: [repo.workingTreeRequest(status: .modified, path: "same.txt", originalPath: nil, ref: "HEAD")]
            )

            await model.loadInitial()

            #expect(model.diff != nil)
            #expect(model.differenceCount == 0)
            #expect(model.differenceSummary == "No differences")
            #expect(model.canNavigateNext == false)
            #expect(model.canNavigatePrevious == false)
            model.nextDifference()
            model.previousDifference()
            #expect(model.currentHunkIndex == nil)
            #expect(model.scrollRequest == nil)
        }
    }

    @Test
    func aSupersededLoadNeverOverwritesTheNewerSelection() async throws {
        try await withTempDir { dir in
            _ = try await makeFixture(dir)
            let repo = try repository(dir)
            let files = try await repo.workingTreeRequests(against: "HEAD")
            let model = DiffViewerViewModel(repository: repo, mode: .workingTree(ref: "HEAD"), files: files)

            let first = Task { await model.select("two-hunks.txt") }
            await model.select("single.txt")
            await first.value

            #expect(model.isLoading == false)
            let expectedDifferences = model.selectedID == "single.txt" ? 1 : 2
            #expect(model.differenceCount == expectedDifferences)
            #expect(model.title == "\(model.selectedID ?? "") (HEAD vs Local)")
        }
    }

    @Test
    func selectingResetsHunkNavigationAndScrollRequest() async throws {
        try await withTempDir { dir in
            _ = try await makeFixture(dir)
            let repo = try repository(dir)
            let files = try await repo.workingTreeRequests(against: "HEAD")
            let model = DiffViewerViewModel(repository: repo, mode: .workingTree(ref: "HEAD"), files: files)
            await model.loadInitial()
            model.nextDifference()
            #expect(model.currentHunkIndex == 0)
            #expect(model.scrollRequest != nil)

            await model.select("single.txt")

            #expect(model.currentHunkIndex == nil)
            #expect(model.scrollRequest == nil)
            #expect(model.selectedFile?.path == "single.txt")
        }
    }

    @Test
    func aDiffWithMoreRowsThanTheLimitIsNotDisplayed() async throws {
        try await withTempDir { dir in
            let fixture = try await makeFixture(dir)
            let huge = (0...3).map { "row \($0)" }.joined(separator: "\n") + "\n"
            try fixture.write("huge.txt", huge)
            let repo = try repository(dir)
            let model = DiffViewerViewModel(
                repository: repo,
                mode: .workingTree(ref: "HEAD"),
                files: [repo.workingTreeRequest(status: .untracked, path: "huge.txt", originalPath: nil, ref: "HEAD")],
                maximumRows: 3
            )

            await model.loadInitial()

            #expect(model.diff == nil)
            #expect(model.message == "Diff is too large to display (1 differences)")
            #expect(model.isLoading == false)
            #expect(model.metrics == .empty)
            #expect(model.differenceSummary.isEmpty)
        }
    }

    @Test
    func selectedFileIsNilWhenNothingIsSelected() async throws {
        try await withTempDir { dir in
            _ = try await makeFixture(dir)
            let model = DiffViewerViewModel(repository: try repository(dir), mode: .workingTree(ref: "HEAD"), files: [])

            #expect(model.selectedFile == nil)
            #expect(model.selectedID == nil)
            #expect(model.showsFileList == false)
            #expect(model.differenceSummary.isEmpty)
            #expect(model.canNavigateNext == false)
            #expect(model.canNavigatePrevious == false)
        }
    }

    @Test
    func updatingFilesWithTheSameSelectionReloadsItsDiff() async throws {
        try await withTempDir { dir in
            let fixture = try await makeFixture(dir)
            let repo = try repository(dir)
            let files = try await repo.workingTreeRequests(against: "HEAD")
            let model = DiffViewerViewModel(repository: repo, mode: .workingTree(ref: "HEAD"), files: files)
            await model.select("single.txt")
            #expect(model.diff?.rightLines == ["one", "TWO"])

            try fixture.write("single.txt", "one\nthree\n")
            await model.updateFiles(try await repo.workingTreeRequests(against: "HEAD"))

            #expect(model.selectedID == "single.txt")
            #expect(model.diff?.rightLines == ["one", "three"])
        }
    }
}
