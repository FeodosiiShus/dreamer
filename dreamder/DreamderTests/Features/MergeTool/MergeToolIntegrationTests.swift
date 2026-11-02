import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite
struct MergeToolIntegrationTests {
    private func answering<T>(_ answer: Bool, _ body: () async -> T) async -> T {
        await MergeToolConfirmation.$override.withValue(answer) {
            await body()
        }
    }

    private func repository(_ root: URL) -> MergeConflictRepository {
        MergeConflictRepository(
            gitClient: GitClient(directoryURL: root, shellClient: .live()),
            rootURL: root
        )
    }

    private func workspace(_ root: URL) -> WorkspaceDocument {
        let document = WorkspaceDocument()
        document.sourceControlManager = SourceControlManager(
            workspaceURL: root,
            editorManager: EditorManager()
        )
        return document
    }

    private func mergeModel(_ root: URL, _ path: String) throws -> MergeRevisionsViewModel {
        let document = workspace(root)
        return try #require(MergeRevisionsViewModel(workspace: document, path: path, autoLoad: false))
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func lines(_ text: String) -> [String] {
        TextDiff.lines(in: text)
    }

    @Test
    func acceptYoursStagesOursVersion() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.offMain { try GitMergeFixture.mergeConflict(in: dir) }
            let repo = repository(dir)
            let context = await repo.context()
            #expect(context.summary == "Merging branch feature into branch main")
            #expect(context.yoursLabel == "main")
            #expect(context.theirsLabel == "feature")
            #expect(context.swapsSides == false)

            let entries = await repo.entries()
            #expect(entries.map(\.path) == ["app/config.txt", "docs/notes.txt"])
            let entry = try #require(entries.first { $0.path == "app/config.txt" })
            try await repo.accept(.yours, entry: entry, context: context)

            #expect(try trimmed(fixture.read("app/config.txt")) == "alpha\nBETA-main\ngamma\ndelta\nepsilon\nzeta-main")
            #expect(try fixture.isFullyStaged("app/config.txt"))
            #expect(try fixture.unmergedPaths() == ["docs/notes.txt"])
            #expect(await repo.entries().map(\.path) == ["docs/notes.txt"])
        }
    }

    @Test
    func acceptTheirsStagesTheirsVersion() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.offMain { try GitMergeFixture.mergeConflict(in: dir) }
            let repo = repository(dir)
            let context = await repo.context()
            let entry = try #require(await repo.entries().first { $0.path == "docs/notes.txt" })
            try await repo.accept(.theirs, entry: entry, context: context)

            #expect(try trimmed(fixture.read("docs/notes.txt")) == "one\nnotes-feature\nthree")
            #expect(try fixture.isFullyStaged("docs/notes.txt"))
            #expect(try fixture.unmergedPaths() == ["app/config.txt"])
        }
    }

    @Test
    func acceptYoursDuringRebaseAcceptsOurCommits() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.offMain { try GitMergeFixture.rebaseConflict(in: dir) }
            let repo = repository(dir)
            let context = await repo.context()

            #expect(context.swapsSides)
            #expect(context.summary == "Rebasing branch feature onto main")
            #expect(context.yoursLabel == "feature")
            #expect(context.theirsLabel == "main")
            #expect(context.yoursHeader == "Yours (feature)")

            let entry = try #require(await repo.entries().first)
            #expect(entry.change(for: .yours, swapsSides: true) == .modified)
            try await repo.accept(.yours, entry: entry, context: context)

            #expect(try trimmed(fixture.read("src/main.swift")) == "line1\nfeature-line\nline3")
            #expect(try fixture.isFullyStaged("src/main.swift"))
            #expect(try fixture.unmergedPaths().isEmpty)
        }
    }

    @Test
    func acceptYoursDeletesFileDeletedOnOurSide() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.offMain { try GitMergeFixture.deleteModifyConflict(in: dir) }
            let repo = repository(dir)
            let context = await repo.context()
            let entry = try #require(await repo.entries().first)
            #expect(entry.ours == .deleted)
            #expect(entry.theirs == .modified)

            try await repo.accept(.yours, entry: entry, context: context)

            #expect(fixture.exists("gone.txt") == false)
            #expect(try fixture.unmergedPaths().isEmpty)
        }
    }

    @Test
    func acceptTheirsRestoresFileDeletedOnOurSide() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.offMain { try GitMergeFixture.deleteModifyConflict(in: dir) }
            let repo = repository(dir)
            let context = await repo.context()
            let entry = try #require(await repo.entries().first)

            try await repo.accept(.theirs, entry: entry, context: context)

            #expect(fixture.exists("gone.txt"))
            #expect(try trimmed(fixture.read("gone.txt")) == "keep me\nmodified by feature")
            #expect(try fixture.unmergedPaths().isEmpty)
        }
    }

    @Test
    func acceptYoursResolvesFileAddedOnBothSides() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.offMain { try GitMergeFixture.bothAddedConflict(in: dir) }
            let repo = repository(dir)
            let context = await repo.context()
            let entry = try #require(await repo.entries().first)
            #expect(entry.ours == .added)
            #expect(entry.theirs == .added)

            try await repo.accept(.yours, entry: entry, context: context)

            #expect(try trimmed(fixture.read("new.txt")) == "main version")
            #expect(try fixture.unmergedPaths().isEmpty)
        }
    }

    @Test
    func mergeWindowLoadsAllThreeRevisions() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.offMain { try GitMergeFixture.mergeConflict(in: dir) }
            let model = try mergeModel(dir, "app/config.txt")
            await model.load()

            #expect(model.isConflictValid)
            #expect(model.errorMessage == nil)
            let merge = try #require(model.merge)
            #expect(model.leftTitle == "Your version, branch main")
            #expect(model.rightTitle == "Theirs, branch feature")
            #expect(lines(model.leftPane.text) == [
                "alpha", "BETA-main", "gamma", "delta", "epsilon", "zeta-main"
            ])
            #expect(lines(model.rightPane.text) == [
                "alpha", "BETA-feature", "gamma", "delta", "epsilon", "zeta", "feature-added"
            ])
            #expect(merge.blocks.count == 3)
            #expect(merge.blocks[0].kind == .conflict)
            #expect(merge.blocks[1].kind == .ours)
            #expect(merge.blocks[2].kind == .theirs)
            #expect(merge.conflictCount == 1)
            #expect(merge.changeCount == 2)
            #expect(model.resultText == "alpha\nbeta\ngamma\ndelta\nepsilon\nzeta-main\nfeature-added\n")
            #expect(model.hasNonConflictingChanges(.left))
            #expect(model.hasNonConflictingChanges(.right))
            #expect(model.hasNonConflictingChanges(.all))
        }
    }

    @Test
    func acceptingBlockLeftWritesThatSideIntoResult() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.offMain { try GitMergeFixture.mergeConflict(in: dir) }
            let model = try mergeModel(dir, "app/config.txt")
            await model.load()
            let merge = try #require(model.merge)
            let conflict = try #require(merge.blocks.first { $0.kind == .conflict })

            model.resolve(conflict.id, with: .left)
            #expect(model.resultText.contains("BETA-main\n"))
            #expect(model.resultText.contains("BETA-feature") == false)
            #expect(model.merge?.conflictCount == 0)
            #expect(model.isResultEdited == false)
        }
    }

    @Test
    func acceptingBlockRightWritesThatSideIntoResult() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.offMain { try GitMergeFixture.mergeConflict(in: dir) }
            let model = try mergeModel(dir, "app/config.txt")
            await model.load()
            let merge = try #require(model.merge)
            let conflict = try #require(merge.blocks.first { $0.kind == .conflict })

            model.resolve(conflict.id, with: .right)
            #expect(model.resultText.contains("BETA-feature\n"))
            #expect(model.merge?.conflictCount == 0)
        }
    }

    @Test
    func ignoringConflictKeepsBaseText() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.offMain { try GitMergeFixture.mergeConflict(in: dir) }
            let model = try mergeModel(dir, "app/config.txt")
            await model.load()
            let merge = try #require(model.merge)
            let conflict = try #require(merge.blocks.first { $0.kind == .conflict })

            model.resolve(conflict.id, with: .ignored)
            #expect(model.resultText.contains("alpha\nbeta\ngamma"))
            #expect(model.merge?.conflictCount == 0)
        }
    }

    @Test
    func applyNonConflictingFromLeftKeepsOnlyLeftChanges() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.offMain { try GitMergeFixture.mergeConflict(in: dir) }
            let model = try mergeModel(dir, "app/config.txt")
            await model.load()

            model.applyNonConflicting(.left)
            #expect(lines(model.resultText) == [
                "alpha", "beta", "gamma", "delta", "epsilon", "zeta-main"
            ])
        }
    }

    @Test
    func applyNonConflictingFromRightKeepsOnlyRightChanges() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.offMain { try GitMergeFixture.mergeConflict(in: dir) }
            let model = try mergeModel(dir, "app/config.txt")
            await model.load()

            model.applyNonConflicting(.right)
            #expect(lines(model.resultText) == [
                "alpha", "beta", "gamma", "delta", "epsilon", "zeta", "feature-added"
            ])
        }
    }

    @Test
    func applyNonConflictingAllKeepsBothSides() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.offMain { try GitMergeFixture.mergeConflict(in: dir) }
            let model = try mergeModel(dir, "app/config.txt")
            await model.load()

            model.applyNonConflicting(.all)
            #expect(lines(model.resultText) == [
                "alpha", "beta", "gamma", "delta", "epsilon", "zeta-main", "feature-added"
            ])
        }
    }

    @Test
    func acceptLeftWritesWholeLeftSideAndStages() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.offMain { try GitMergeFixture.mergeConflict(in: dir) }
            let model = try mergeModel(dir, "app/config.txt")
            await model.load()

            let finished = await model.requestAcceptSide(.yours, window: nil)
            #expect(finished)
            #expect(try trimmed(fixture.read("app/config.txt")) ==
                    "alpha\nBETA-main\ngamma\ndelta\nepsilon\nzeta-main")
            #expect(try fixture.isFullyStaged("app/config.txt"))
            #expect(try fixture.unmergedPaths() == ["docs/notes.txt"])
        }
    }

    @Test
    func acceptRightWritesWholeRightSideAndStages() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.offMain { try GitMergeFixture.mergeConflict(in: dir) }
            let model = try mergeModel(dir, "app/config.txt")
            await model.load()

            let finished = await model.requestAcceptSide(.theirs, window: nil)
            #expect(finished)
            #expect(try trimmed(fixture.read("app/config.txt")) ==
                    "alpha\nBETA-feature\ngamma\ndelta\nepsilon\nzeta\nfeature-added")
            #expect(try fixture.unmergedPaths() == ["docs/notes.txt"])
        }
    }

    @Test
    func applyWritesResultAndStagesAndRefreshesList() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.offMain { try GitMergeFixture.mergeConflict(in: dir) }
            let repo = repository(dir)
            let model = try mergeModel(dir, "app/config.txt")
            await model.load()

            let finished = await answering(true) { await model.requestApply(window: nil) }
            #expect(finished)
            #expect(try trimmed(fixture.read("app/config.txt")) ==
                    "alpha\nbeta\ngamma\ndelta\nepsilon\nzeta-main\nfeature-added")
            #expect(fixture.hasConflictMarkers("app/config.txt") == false)
            #expect(try fixture.unmergedPaths() == ["docs/notes.txt"])
            #expect(await repo.entries().map(\.path) == ["docs/notes.txt"])
        }
    }

    @Test
    func applyWithUnresolvedConflictsRequiresConfirmation() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.offMain { try GitMergeFixture.mergeConflict(in: dir) }
            let model = try mergeModel(dir, "app/config.txt")
            await model.load()
            #expect(model.hasUnresolvedConflicts)

            let declined = await answering(false) { await model.requestApply(window: nil) }
            #expect(declined == false)
            #expect(fixture.hasConflictMarkers("app/config.txt"))

            let accepted = await answering(true) { await model.requestApply(window: nil) }
            #expect(accepted)
            #expect(fixture.hasConflictMarkers("app/config.txt") == false)
            #expect(try fixture.unmergedPaths() == ["docs/notes.txt"])
        }
    }

    @Test
    func applyWritesManuallyEditedResult() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.offMain { try GitMergeFixture.mergeConflict(in: dir) }
            let model = try mergeModel(dir, "app/config.txt")
            await model.load()

            model.userEditedResult("hand written\n")
            #expect(model.isResultEdited)
            let finished = await answering(true) { await model.requestApply(window: nil) }
            #expect(finished)
            #expect(try fixture.read("app/config.txt") == "hand written\n")
        }
    }

    @Test
    func cancelWithoutEditsClosesImmediately() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.offMain { try GitMergeFixture.mergeConflict(in: dir) }
            let model = try mergeModel(dir, "app/config.txt")
            await model.load()
            #expect(model.isResultEdited == false)
            #expect(await model.requestCancel(window: nil))
            #expect(fixture.hasConflictMarkers("app/config.txt"))
            #expect(try fixture.unmergedPaths() == ["app/config.txt", "docs/notes.txt"])
        }
    }

    @Test
    func cancelWithEditsRequiresConfirmation() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.offMain { try GitMergeFixture.mergeConflict(in: dir) }
            let model = try mergeModel(dir, "app/config.txt")
            await model.load()
            model.userEditedResult("draft\n")

            #expect(await answering(false) { await model.requestCancel(window: nil) } == false)

            #expect(await answering(true) { await model.requestCancel(window: nil) })
            #expect(fixture.hasConflictMarkers("app/config.txt"))
            #expect(try fixture.unmergedPaths() == ["app/config.txt", "docs/notes.txt"])
        }
    }

    @Test
    func acceptSideWithEditsRequiresConfirmation() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.offMain { try GitMergeFixture.mergeConflict(in: dir) }
            let model = try mergeModel(dir, "app/config.txt")
            await model.load()
            model.userEditedResult("draft\n")

            #expect(await answering(false) { await model.requestAcceptSide(.yours, window: nil) } == false)
            #expect(try fixture.unmergedPaths() == ["app/config.txt", "docs/notes.txt"])

            #expect(await answering(true) { await model.requestAcceptSide(.yours, window: nil) })
            #expect(try trimmed(fixture.read("app/config.txt")) ==
                    "alpha\nBETA-main\ngamma\ndelta\nepsilon\nzeta-main")
        }
    }

    @Test
    func acceptLeftOfDeleteConflictRemovesTheFile() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.offMain { try GitMergeFixture.deleteModifyConflict(in: dir) }
            let model = try mergeModel(dir, "gone.txt")
            await model.load()

            #expect(await model.requestAcceptSide(.yours, window: nil))
            #expect(fixture.exists("gone.txt") == false)
            #expect(try fixture.unmergedPaths().isEmpty)
        }
    }

    @Test
    func mergeWindowOnDeleteConflictShowsMissingLeftSide() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.offMain { try GitMergeFixture.deleteModifyConflict(in: dir) }
            let model = try mergeModel(dir, "gone.txt")
            await model.load()

            #expect(model.leftPane.lines.isEmpty)
            #expect(lines(model.rightPane.text) == ["keep me", "modified by feature"])
            let merge = try #require(model.merge)
            #expect(merge.blocks.first?.kind == .conflict)
        }
    }

    @Test
    func rebaseMergeWindowUsesSwappedSides() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.offMain { try GitMergeFixture.rebaseConflict(in: dir) }
            let model = try mergeModel(dir, "src/main.swift")
            await model.load()

            #expect(model.leftTitle == "Your commits, branch feature")
            #expect(model.rightTitle == "Changes from branch main")
            #expect(lines(model.leftPane.text) == ["line1", "feature-line", "line3"])
            #expect(lines(model.rightPane.text) == ["line1", "main-line", "line3"])

            #expect(await model.requestAcceptSide(.yours, window: nil))
            #expect(try trimmed(fixture.read("src/main.swift")) == "line1\nfeature-line\nline3")
        }
    }
}
