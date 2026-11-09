import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct MergeRevisionsViewModelCoverageTests {
    private static let configPath = "app/config.txt"

    private func workspace(_ root: URL) -> WorkspaceDocument {
        let document = WorkspaceDocument()
        document.sourceControlManager = SourceControlManager(workspaceURL: root, editorManager: EditorManager())
        return document
    }

    private func makeModel(_ root: URL, _ path: String) throws -> MergeRevisionsViewModel {
        try #require(MergeRevisionsViewModel(workspace: workspace(root), path: path, autoLoad: false))
    }

    private func answering<T>(_ answer: Bool, _ body: () async -> T) async -> T {
        await MergeToolConfirmation.$override.withValue(answer) {
            await body()
        }
    }

    private func binaryConflict(in root: URL) async throws -> GitMergeFixture {
        let fixture = try await GitMergeFixture(root: root)
        try fixture.write("blob.bin", "base\u{0}data\n")
        try await fixture.commit("base")
        try await fixture.run("checkout", "-q", "-b", "feature")
        try fixture.write("blob.bin", "feature\u{0}data\n")
        try await fixture.commit("feature")
        try await fixture.run("checkout", "-q", "main")
        try fixture.write("blob.bin", "main\u{0}data\n")
        try await fixture.commit("main")
        _ = try await fixture.runIgnoringFailure("merge", "feature")
        return fixture
    }

    private func stashConflict(in root: URL) async throws -> GitMergeFixture {
        let fixture = try await GitMergeFixture(root: root)
        try fixture.write("f.txt", "line1\nline2\nline3\n")
        try await fixture.commit("base")
        try fixture.write("f.txt", "line1\nstash\nline3\n")
        try await fixture.run("stash", "-q")
        try fixture.write("f.txt", "line1\nmain\nline3\n")
        try await fixture.commit("main edit")
        _ = try await fixture.runIgnoringFailure("stash", "pop")
        return fixture
    }

    @Test
    func rejectsWorkspacesWithoutSourceControlAndEmptyPaths() {
        let root = URL(filePath: "/Users/dreamder-test/none")

        #expect(MergeRevisionsViewModel(workspace: WorkspaceDocument(), path: "a.txt", autoLoad: false) == nil)
        #expect(MergeRevisionsViewModel(workspace: workspace(root), path: "", autoLoad: false) == nil)
    }

    @Test
    func modelBeforeTheFirstLoadIsInert() async throws {
        let model = try makeModel(URL(filePath: "/Users/dreamder-test/none"), "a.txt")

        #expect(model.title == "Merge Revisions for a.txt")
        #expect(model.leftTitle == "Yours")
        #expect(model.rightTitle == "Theirs")
        #expect(model.summary == "Computing differences…")
        #expect(model.isLoading)
        #expect(model.canApply == false)
        #expect(model.canAcceptSide == false)
        #expect(model.hasUnresolvedConflicts == false)
        #expect(model.hasNonConflictingChanges(.all) == false)
        #expect(model.canApplyNonConflicting(.all) == false)

        await model.requestResolve(0, with: .left, window: nil)
        await model.requestApplyNonConflicting(.all, window: nil)
        #expect(model.contentRevision == 0)
        #expect(await model.requestApply(window: nil) == false)
        #expect(await model.requestAcceptSide(.yours, window: nil) == false)
        #expect(await model.apply() == false)
        #expect(await model.acceptSide(.theirs) == false)
    }

    @Test
    func conflictThatIsNoLongerValidHasNoSummary() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.mergeConflict(in: dir)
            let model = try makeModel(dir, "not-in-conflict.txt")

            await model.load()

            #expect(model.isLoading == false)
            #expect(model.isConflictValid == false)
            #expect(model.summary.isEmpty)
            #expect(model.canApply == false)
            #expect(model.canApplyNonConflicting(.all) == false)
        }
    }

    @Test
    func binaryConflictCannotBeMergedManually() async throws {
        try await withTempDir { dir in
            _ = try await binaryConflict(in: dir)
            let model = try makeModel(dir, "blob.bin")

            await model.load()

            #expect(model.errorMessage == "Binary files cannot be merged manually")
            #expect(model.isLoading == false)
            #expect(model.isConflictValid)
            #expect(model.merge == nil)
            #expect(model.summary.isEmpty)
            #expect(model.canAcceptSide == false)
        }
    }

    @Test
    func cherryPickConflictNamesTheCommit() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.cherryPickConflict(in: dir)
            let short = try await fixture.run("rev-parse", "--short", "CHERRY_PICK_HEAD")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let model = try makeModel(dir, "src/main.swift")

            await model.load()

            #expect(model.leftTitle == "Local changes")
            #expect(model.rightTitle == "Changes from \(short)")
        }
    }

    @Test
    func stashConflictNamesTheStash() async throws {
        try await withTempDir { dir in
            _ = try await stashConflict(in: dir)
            let model = try makeModel(dir, "f.txt")

            await model.load()

            #expect(model.context?.operation == .stash(branch: "main"))
            #expect(model.leftTitle == "Local changes")
            #expect(model.rightTitle == "Changes from stash")
        }
    }

    @Test
    func conflictWithoutAnOperationUsesTheNeutralTitles() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.mergeConflict(in: dir)
            try FileManager.default.removeItem(at: dir.appending(path: ".git/MERGE_HEAD"))
            try #require(fixture.exists(".git/MERGE_HEAD") == false)
            let model = try makeModel(dir, Self.configPath)

            await model.load()

            #expect(model.context?.operation == .unknown)
            #expect(model.leftTitle == "Yours")
            #expect(model.rightTitle == "Theirs")
            #expect(model.isConflictValid)
        }
    }

    @Test
    func summaryTracksTheResolutionOfEveryConflict() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.mergeConflict(in: dir)
            let model = try makeModel(dir, Self.configPath)

            await model.load()

            #expect(model.summary == "2 changes, 1 conflict")
            #expect(model.canApply)
            #expect(model.canAcceptSide)
            #expect(model.hasUnresolvedConflicts)
            #expect(model.canApplyNonConflicting(.left))
            let conflict = try #require(model.merge?.blocks.first { $0.kind == .conflict })

            await model.requestResolve(conflict.id, with: .right, window: nil)

            #expect(model.summary == "All conflicts resolved")
            #expect(model.hasUnresolvedConflicts == false)
        }
    }

    @Test
    func editingBackToTheComputedResultIsNotAnEdit() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.mergeConflict(in: dir)
            let model = try makeModel(dir, Self.configPath)
            await model.load()
            let computed = try #require(model.merge).resultText

            model.userEditedResult(computed)
            #expect(model.isResultEdited == false)

            model.userEditedResult("changed\n")
            #expect(model.isResultEdited)
        }
    }

    @Test
    func applyFailsWhileTheIndexIsLocked() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.mergeConflict(in: dir)
            let model = try makeModel(dir, Self.configPath)
            await model.load()
            model.userEditedResult("hand written\n")
            try fixture.write(".git/index.lock", "")

            let finished = await answering(true) { await model.requestApply(window: nil) }

            #expect(finished == false)
            #expect(model.errorMessage?.isEmpty == false)
            #expect(model.isSaving == false)
            #expect(model.isResultEdited)
            #expect(try await fixture.unmergedPaths() == [Self.configPath, "docs/notes.txt"])
        }
    }

    @Test
    func acceptingASideFailsWhileTheIndexIsLocked() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.mergeConflict(in: dir)
            let model = try makeModel(dir, Self.configPath)
            await model.load()
            try fixture.write(".git/index.lock", "")

            let finished = await model.acceptSide(.yours)

            #expect(finished == false)
            #expect(model.errorMessage?.isEmpty == false)
            #expect(model.isSaving == false)
        }
    }

    @Test
    func acceptingAMissingSideFailsWhileTheIndexIsLocked() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.deleteModifyConflict(in: dir)
            let model = try makeModel(dir, "gone.txt")
            await model.load()
            try fixture.write(".git/index.lock", "")

            let finished = await model.acceptSide(.yours)

            #expect(finished == false)
            #expect(model.errorMessage?.isEmpty == false)
            #expect(model.isSaving == false)
            #expect(try await fixture.unmergedPaths() == ["gone.txt"])
        }
    }

    @Test
    func decliningToDiscardEditsKeepsTheMergeOpenForTheRightSideToo() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.mergeConflict(in: dir)
            let model = try makeModel(dir, Self.configPath)
            await model.load()
            model.userEditedResult("draft\n")

            let finished = await answering(false) { await model.requestAcceptSide(.theirs, window: nil) }

            #expect(finished == false)
            #expect(model.isResultEdited)
            #expect(try await fixture.unmergedPaths() == [Self.configPath, "docs/notes.txt"])
        }
    }

    @Test
    func reloadingAfterEditsRecomputesTheResult() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.mergeConflict(in: dir)
            let model = try makeModel(dir, Self.configPath)
            await model.load()
            let revision = model.contentRevision
            model.userEditedResult("draft\n")

            await model.load()

            #expect(model.contentRevision == revision + 1)
            #expect(model.isResultEdited == false)
            #expect(model.resultText != "draft\n")
        }
    }

    @Test
    func acceptingTheRightSideDuringARebaseKeepsTheRebasedOntoBranch() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.rebaseConflict(in: dir)
            let model = try makeModel(dir, "src/main.swift")
            await model.load()
            #expect(model.context?.swapsSides == true)

            let finished = await model.acceptSide(.theirs)

            #expect(finished)
            #expect(try fixture.read("src/main.swift").trimmingCharacters(in: .whitespacesAndNewlines)
                    == "line1\nmain-line\nline3")
            #expect(try await fixture.unmergedPaths().isEmpty)
        }
    }
}
