import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct GitLogViewModelRaceCoverageTests {
    private func makeManager(_ dir: URL) async throws -> SourceControlManager {
        let fixture = try await GitMergeFixture(root: dir)
        try fixture.write("a.txt", "a\n")
        try await fixture.commit("initial")
        try fixture.write("b.txt", "b\n")
        try await fixture.commit("Feature subject")
        try fixture.write("c.txt", "c\n")
        try await fixture.commit("Third change")
        return SourceControlManager(workspaceURL: dir, editorManager: EditorManager())
    }

    @Test
    func firstParentOptionWithoutManagerOnlyStoresTheOption() async {
        let model = GitLogViewModel()
        await model.setFirstParent(true)

        #expect(model.options.firstParent)
        #expect(model.commits.isEmpty)
        #expect(model.isLoading == false)
    }

    @Test
    func selectionKeepsTheSubjectWhenGitCannotProvideDetails() async throws {
        try await withTempDir { dir in
            let manager = try await makeManager(dir)
            let model = GitLogViewModel()
            await model.load(manager: manager)
            let target = try #require(model.commits.first { $0.subject == "Feature subject" })

            try FileManager.default.removeItem(at: dir.appending(path: ".git"))
            await model.select(hash: target.hash)

            #expect(model.selectedHash == target.hash)
            #expect(model.selectedFiles.isEmpty)
            #expect(model.selectedMessage == "Feature subject")
        }
    }

    @Test
    func cancelledLoadReportsTheErrorText() async throws {
        try await withTempDir { dir in
            let manager = try await makeManager(dir)
            let model = GitLogViewModel()

            let task = Task { await model.load(manager: manager) }
            task.cancel()
            await task.value

            #expect(model.commits.isEmpty)
            #expect(model.errorMessage?.isEmpty == false)
            #expect(model.isLoading == false)
        }
    }

    @Test
    func supersededLoadDropsItsResult() async throws {
        try await withTempDir { dir in
            let manager = try await makeManager(dir)
            let model = GitLogViewModel()

            let first = Task { await model.load(manager: manager) }
            await Task.yield()
            await model.setFirstParent(true)
            await first.value

            #expect(model.options.firstParent)
            #expect(model.errorMessage == nil)
            #expect(model.commits.count == 3)
            #expect(model.selectedHash == model.commits.first?.hash)
        }
    }

    @Test
    func supersededFailureDoesNotReplaceTheNewerResult() async throws {
        try await withTempDir { dir in
            let manager = try await makeManager(dir)
            let model = GitLogViewModel()

            let first = Task { await model.load(manager: manager) }
            first.cancel()
            await Task.yield()
            await model.setFirstParent(true)
            await first.value

            #expect(model.errorMessage == nil)
            #expect(model.commits.count == 3)
        }
    }

    @Test
    func supersededRebuildKeepsTheLatestFilter() async throws {
        try await withTempDir { dir in
            let manager = try await makeManager(dir)
            let model = GitLogViewModel()
            await model.load(manager: manager)

            let first = Task {
                await model.setFilters(GitLogFilterCollection(text: GitLogTextFilter.fromPattern("initial")))
            }
            await Task.yield()
            await model.setFilters(GitLogFilterCollection(text: GitLogTextFilter.fromPattern("Feature")))
            await first.value

            #expect(model.visibleCommits.map(\.subject) == ["Feature subject"])
            #expect(model.selectedHash == model.visibleCommits.first?.hash)
        }
    }

    @Test
    func supersededSelectionDoesNotApplyItsDetails() async throws {
        try await withTempDir { dir in
            let manager = try await makeManager(dir)
            let model = GitLogViewModel()
            await model.load(manager: manager)
            let target = try #require(model.commits.first { $0.subject == "Feature subject" })

            let first = Task { await model.select(hash: target.hash) }
            await Task.yield()
            await model.select(hash: nil)
            await first.value

            #expect(model.selectedHash == nil)
            #expect(model.selectedFiles.isEmpty)
            #expect(model.selectedMessage.isEmpty)
        }
    }
}
