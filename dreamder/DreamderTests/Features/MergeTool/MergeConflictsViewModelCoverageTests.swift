import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct MergeConflictsViewModelCoverageTests {
    private static let configPath = "app/config.txt"
    private static let notesPath = "docs/notes.txt"

    private func workspace(_ root: URL) -> WorkspaceDocument {
        let document = WorkspaceDocument()
        document.sourceControlManager = SourceControlManager(workspaceURL: root, editorManager: EditorManager())
        return document
    }

    private func loaded(_ root: URL, count: Int) async throws -> MergeConflictsViewModel {
        let model = try #require(MergeConflictsViewModel(workspace: workspace(root)))
        await model.reload()
        try await eventually { model.entries.count == count }
        try await eventually { model.context != nil }
        return model
    }

    @Test
    func freshModelHasNoEntriesAndNeutralHeaders() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.mergeConflict(in: dir)
            let model = try #require(MergeConflictsViewModel(workspace: workspace(dir)))

            #expect(model.isEmpty)
            #expect(model.summary == "All conflicts have been resolved")
            #expect(model.yoursHeader == "Yours")
            #expect(model.theirsHeader == "Theirs")
            #expect(model.canAccept == false)
            #expect(model.canMerge == false)
            #expect(model.primaryEntry == nil)
            model.openMergeWindow()
            #expect(MergeToolPresenter.revisionsWindow(for: model.workspace, path: nil) == nil)

            await model.accept(.yours)
            #expect(model.isBusy == false)
            #expect(model.errorMessage == nil)
        }
    }

    @Test
    func selectionExtendsFromTheLastClickedRow() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.mergeConflict(in: dir)
            let model = try await loaded(dir, count: 2)

            model.select(nil)
            model.select(Self.notesPath, extending: true)
            #expect(model.selectedPaths == [Self.notesPath])
            #expect(model.primaryPath == Self.notesPath)

            model.select(Self.configPath, extending: true)
            #expect(model.selectedPaths == [Self.configPath, Self.notesPath])
            #expect(model.primaryPath == Self.configPath)

            model.select(Self.notesPath, toggling: true)
            #expect(model.selectedPaths == [Self.configPath])
            #expect(model.primaryPath == Self.configPath)
            #expect(model.primaryEntry?.path == Self.configPath)
        }
    }

    @Test
    func failedAcceptReportsTheGitErrorAndLeavesEveryFileUnresolved() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.mergeConflict(in: dir)
            let model = try await loaded(dir, count: 2)
            model.select(Self.configPath)
            model.select(Self.notesPath, extending: true)
            try fixture.write(".git/index.lock", "")

            await model.accept(.yours)

            #expect(model.errorMessage?.isEmpty == false)
            #expect(model.isBusy == false)
            #expect(try await fixture.unmergedPaths() == [Self.configPath, Self.notesPath])
            #expect(model.entries.count == 2)

            try FileManager.default.removeItem(at: dir.appending(path: ".git/index.lock"))
            await model.accept(.yours)

            #expect(model.errorMessage == nil)
            try await eventually { model.entries.isEmpty }
            #expect(try await fixture.unmergedPaths().isEmpty)
        }
    }

    @Test
    func rebaseConflictsUseTheSwappedHeaders() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.rebaseConflict(in: dir)
            let model = try await loaded(dir, count: 1)

            #expect(model.summary == "Rebasing branch feature onto main")
            #expect(model.yoursHeader == "Yours (feature)")
            #expect(model.theirsHeader == "Theirs (main)")
            let entry = try #require(model.entries.first)
            #expect(model.detail(for: entry, choice: .yours) == "Modified")
            #expect(model.detail(for: entry, choice: .theirs) == "Modified")
        }
    }

    @Test
    func detailsUseTheUnswappedSidesUntilTheContextArrives() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.deleteModifyConflict(in: dir)
            let entry = try #require(await loaded(dir, count: 1).entries.first)
            let fresh = try #require(MergeConflictsViewModel(workspace: workspace(dir)))

            #expect(fresh.context == nil)
            #expect(fresh.detail(for: entry, choice: .yours) == "Deleted")
            #expect(fresh.detail(for: entry, choice: .theirs) == "Modified")
        }
    }
}
