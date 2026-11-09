import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct MergeRevisionsManualEditProtectionTests {
    private static let configPath = "app/config.txt"
    private static let draft = "draft\n"

    private func loadedModel(_ root: URL) async throws -> MergeRevisionsViewModel {
        let document = WorkspaceDocument()
        document.sourceControlManager = SourceControlManager(workspaceURL: root, editorManager: EditorManager())
        let model = try #require(MergeRevisionsViewModel(workspace: document, path: Self.configPath, autoLoad: false))
        await model.load()
        return model
    }

    private func conflictID(_ model: MergeRevisionsViewModel) throws -> Int {
        try #require(model.merge?.blocks.first { $0.kind == .conflict }).id
    }

    private func answering(_ answer: Bool, _ body: () async -> Void) async {
        await MergeToolConfirmation.$override.withValue(answer) {
            await body()
        }
    }

    @Test
    func resolvingABlockAfterAManualEditNeedsConfirmationAndKeepsTheEditWhenDeclined() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.mergeConflict(in: dir)
            let model = try await loadedModel(dir)
            let conflict = try conflictID(model)
            let revision = model.contentRevision
            model.userEditedResult(Self.draft)

            await answering(false) { await model.requestResolve(conflict, with: .left, window: nil) }

            #expect(model.resultText == Self.draft)
            #expect(model.isResultEdited)
            #expect(model.contentRevision == revision)
            #expect(model.merge?.conflictCount == 1)
        }
    }

    @Test
    func resolvingABlockAfterAManualEditReplacesTheEditOnlyWhenConfirmed() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.mergeConflict(in: dir)
            let model = try await loadedModel(dir)
            let conflict = try conflictID(model)
            let revision = model.contentRevision
            model.userEditedResult(Self.draft)

            await answering(true) { await model.requestResolve(conflict, with: .left, window: nil) }

            #expect(model.resultText.contains("zeta-main\n"))
            #expect(model.resultText != Self.draft)
            #expect(model.isResultEdited == false)
            #expect(model.contentRevision == revision + 1)
            #expect(model.merge?.conflictCount == 0)
        }
    }

    @Test
    func applyingNonConflictingChangesAfterAManualEditKeepsTheEditWhenDeclined() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.mergeConflict(in: dir)
            let model = try await loadedModel(dir)
            let revision = model.contentRevision
            model.userEditedResult(Self.draft)

            await answering(false) { await model.requestApplyNonConflicting(.all, window: nil) }

            #expect(model.resultText == Self.draft)
            #expect(model.isResultEdited)
            #expect(model.contentRevision == revision)
        }
    }

    @Test
    func applyingNonConflictingChangesAfterAManualEditReplacesTheEditOnlyWhenConfirmed() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.mergeConflict(in: dir)
            let model = try await loadedModel(dir)
            let revision = model.contentRevision
            model.userEditedResult(Self.draft)

            await answering(true) { await model.requestApplyNonConflicting(.all, window: nil) }

            #expect(model.resultText.contains("feature-added"))
            #expect(model.isResultEdited == false)
            #expect(model.contentRevision == revision + 1)
        }
    }

    @Test
    func theEditedFlagSurvivesADeclinedChipSoClosingStillAsks() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.mergeConflict(in: dir)
            let model = try await loadedModel(dir)
            let conflict = try conflictID(model)
            model.userEditedResult(Self.draft)

            await answering(false) { await model.requestResolve(conflict, with: .right, window: nil) }

            let cancelled = await MergeToolConfirmation.$override.withValue(false) {
                await model.requestCancel(window: nil)
            }

            #expect(cancelled == false)
        }
    }

    @Test
    func chipsNeverAskWhileTheResultIsUntouched() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.mergeConflict(in: dir)
            let model = try await loadedModel(dir)
            let conflict = try conflictID(model)

            await answering(false) { await model.requestResolve(conflict, with: .left, window: nil) }
            #expect(model.merge?.conflictCount == 0)

            await answering(false) { await model.requestApplyNonConflicting(.right, window: nil) }
            #expect(model.resultText.contains("feature-added"))
        }
    }

    @Test
    func typingTheComputedResultBackIsNotAnEditAndNeverAsks() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.mergeConflict(in: dir)
            let model = try await loadedModel(dir)
            let conflict = try conflictID(model)
            let computed = try #require(model.merge).resultText

            model.userEditedResult(computed)
            await answering(false) { await model.requestResolve(conflict, with: .left, window: nil) }

            #expect(model.isResultEdited == false)
            #expect(model.merge?.conflictCount == 0)
        }
    }

    @Test
    func editingBeforeAnythingIsLoadedKeepsTheTextAsTyped() throws {
        let document = WorkspaceDocument()
        document.sourceControlManager = SourceControlManager(
            workspaceURL: URL(filePath: "/Users/dreamder-test/none"),
            editorManager: EditorManager()
        )
        let model = try #require(MergeRevisionsViewModel(workspace: document, path: "a.txt", autoLoad: false))

        model.userEditedResult("typed\r\ntext")

        #expect(model.resultText == "typed\ntext")
        #expect(model.isResultEdited)
    }
}
