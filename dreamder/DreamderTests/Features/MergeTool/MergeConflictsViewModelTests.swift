import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite
struct MergeConflictsViewModelTests {
    private func workspace(_ root: URL) -> WorkspaceDocument {
        let document = WorkspaceDocument()
        document.sourceControlManager = SourceControlManager(workspaceURL: root, editorManager: EditorManager())
        return document
    }

    private func loadedModel(_ root: URL) async throws -> MergeConflictsViewModel {
        let model = try #require(MergeConflictsViewModel(workspace: workspace(root)))
        await model.reload()
        try await eventually { model.entries.count == 2 }
        return model
    }

    @Test
    func workspaceWithoutSourceControlHasNoDialogModel() {
        #expect(MergeConflictsViewModel(workspace: WorkspaceDocument()) == nil)
    }

    @Test
    func loadsConflictsWithMergeHeadersAndSelectsTheFirstFile() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.offMain { try GitMergeFixture.mergeConflict(in: dir) }
            let model = try await loadedModel(dir)

            #expect(model.entries.map(\.path) == ["app/config.txt", "docs/notes.txt"])
            #expect(model.summary == "Merging branch feature into branch main")
            #expect(model.yoursHeader.contains("main"))
            #expect(model.theirsHeader.contains("feature"))
            #expect(model.primaryEntry?.path == "app/config.txt")
            #expect(model.isSelected("app/config.txt"))
            #expect(model.canAccept)
            #expect(model.canMerge)
            #expect(model.isEmpty == false)
            let entry = try #require(model.entries.first)
            #expect(model.detail(for: entry, choice: .yours) == "Modified")
            #expect(model.detail(for: entry, choice: .theirs) == "Modified")
        }
    }

    @Test
    func clickShiftClickAndCommandClickSelectLikeATable() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.offMain { try GitMergeFixture.mergeConflict(in: dir) }
            let model = try await loadedModel(dir)
            let first = "app/config.txt"
            let second = "docs/notes.txt"

            model.select(second)
            #expect(model.selectedPaths == [second])
            #expect(model.primaryEntry?.path == second)

            model.select(first, extending: true)
            #expect(model.selectedPaths == [first, second])
            #expect(model.primaryEntry?.path == first)

            model.select(first, toggling: true)
            #expect(model.selectedPaths == [second])
            #expect(model.primaryEntry?.path == second)

            model.select(second, toggling: true)
            #expect(model.selectedPaths.isEmpty)
            #expect(model.primaryEntry == nil)
            #expect(model.canAccept == false)
            #expect(model.canMerge == false)

            model.select(first, toggling: true)
            #expect(model.selectedPaths == [first])
            #expect(model.primaryEntry?.path == first)

            model.select(nil)
            #expect(model.selectedPaths.isEmpty)
            #expect(model.canAccept == false)
        }
    }

    @Test
    func acceptTheirsResolvesEverySelectedFile() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.offMain { try GitMergeFixture.mergeConflict(in: dir) }
            let model = try await loadedModel(dir)
            model.select("app/config.txt")
            model.select("docs/notes.txt", extending: true)

            await model.accept(.theirs)
            try await eventually { model.entries.isEmpty }

            #expect(try fixture.unmergedPaths().isEmpty)
            #expect(try fixture.read("docs/notes.txt") == "one\nnotes-feature\nthree\n")
            #expect(try fixture.isFullyStaged("app/config.txt"))
            #expect(model.summary == "All conflicts have been resolved")
            #expect(model.isBusy == false)
            #expect(model.errorMessage == nil)
            #expect(model.selectedPaths.isEmpty)
            #expect(model.canMerge == false)
        }
    }

    @Test
    func acceptYoursOnOneFileKeepsTheOtherSelectedAfterReload() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.offMain { try GitMergeFixture.mergeConflict(in: dir) }
            let model = try await loadedModel(dir)
            model.select("app/config.txt")

            await model.accept(.yours)
            try await eventually { model.entries.count == 1 }

            #expect(try fixture.unmergedPaths() == ["docs/notes.txt"])
            #expect(model.primaryEntry?.path == "docs/notes.txt")
            #expect(model.selectedPaths == ["docs/notes.txt"])
        }
    }
}
