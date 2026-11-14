import AppKit
import Foundation
import Testing
@testable import Dreamder

extension MergeAutomationTests {
    private static let commandsAimedAtOpenWindows = [
        "select:docs/notes.txt", "selectAdd:docs/notes.txt", "selectRange:docs/notes.txt",
        "acceptYours", "acceptTheirs", "mergeSelected", "resolve:0:left", "applyNonConflicting:all",
        "editResult:foreign", "acceptLeft", "acceptRight", "apply", "cancel", "closeRevisions", "closeConflicts"
    ]

    @Test(arguments: ["target:/Users/dreamder-test/no-such-workspace", "target:"])
    func commandsWhoseTargetHasNoWindowLeaveOtherWorkspacesAlone(retarget: String) async throws {
        try await withSession { session in
            let conflicts = try await openConflicts(session)
            let revisions = try await openRevisions(session)
            let conflictsSelection = conflicts.selectedPaths
            let resultText = revisions.resultText

            await MergeAutomation.perform(retarget)
            for command in Self.commandsAimedAtOpenWindows {
                await MergeAutomation.perform(command)
            }

            #expect(MergeToolPresenter.conflictsWindow(for: session.workspace) != nil)
            #expect(revisionsWindow(session) != nil)
            #expect(conflicts.selectedPaths == conflictsSelection)
            #expect(conflicts.entries.count == 2)
            #expect(revisions.resultText == resultText)
            #expect(revisions.isResultEdited == false)
            #expect(try await session.fixture.unmergedPaths() == [Self.configPath, Self.notesPath])
        }
    }

    @Test
    func theConflictsCommandAdoptsItsWorkspaceWhenNoTargetIsSet() async throws {
        try await withSession { session in
            await MergeAutomation.perform("target:")
            #expect(MergeAutomation.targetPath.isEmpty)

            await MergeAutomation.perform("conflicts:\(session.path)")
            let model = try #require(MergeToolPresenter.conflictsModel(for: session.workspace))
            try await eventually(timeout: .seconds(20)) { model.entries.count == 2 }

            #expect(MergeAutomation.targetPath == session.path)
            await MergeAutomation.perform("select:\(Self.notesPath)")
            #expect(model.selectedPaths == [Self.notesPath])
        }
    }

    @Test
    func anExplicitTargetIsNeverReplacedByTheConflictsCommand() async throws {
        try await withSession { session in
            await MergeAutomation.perform("target:/Users/dreamder-test/explicit-target")

            await MergeAutomation.perform("conflicts:\(session.path)")

            #expect(MergeAutomation.targetPath == "/Users/dreamder-test/explicit-target")
            #expect(MergeToolPresenter.conflictsModel(for: session.workspace) != nil)
        }
    }

    @Test
    func workspaceResolutionFallsBackToTheActiveWorkspaceOnlyWithoutATarget() async throws {
        try await withSession { session in
            await MergeAutomation.perform("target:")

            #expect(MergeAutomation.targetWorkspace() == nil)
            #expect(MergeAutomation.openingWorkspace() === MergeAutomation.workspace(for: ""))
            #expect(MergeAutomation.commandWorkspace(path: "") === MergeAutomation.workspace(for: ""))

            await MergeAutomation.perform("target:\(session.path)")

            #expect(MergeAutomation.targetWorkspace() === session.workspace)
            #expect(MergeAutomation.openingWorkspace() === session.workspace)
            #expect(MergeAutomation.commandWorkspace(path: "") === session.workspace)
            #expect(MergeAutomation.commandWorkspace(path: session.path) === session.workspace)

            await MergeAutomation.perform("target:/Users/dreamder-test/no-such-workspace")

            #expect(MergeAutomation.targetWorkspace() == nil)
            #expect(MergeAutomation.openingWorkspace() == nil)
        }
    }

    @Test
    func mergeFileAddressesLaterRevisionCommandsToThatFileOnly() async throws {
        try await withSession { session in
            let config = try await openRevisions(session)
            let notes = try await openRevisions(session, path: Self.notesPath)
            #expect(MergeAutomation.revisionsPath == Self.notesPath)

            await MergeAutomation.perform("editResult:only notes")

            #expect(notes.resultText == "only notes")
            #expect(notes.isResultEdited)
            #expect(config.isResultEdited == false)
            #expect(revisionsWindow(session) != nil)
            #expect(revisionsWindow(session, path: Self.notesPath) != nil)

            await MergeAutomation.perform("target:\(session.path)")
            #expect(MergeAutomation.revisionsPath == nil)
        }
    }

    @Test
    func aRevisionsWindowOpenedFromTheUserInterfaceIsAddressedWithoutAFilePath() async throws {
        try await withSession { session in
            MergeToolPresenter.showMergeRevisions(workspace: session.workspace, path: Self.configPath)
            let model = try #require(
                MergeToolPresenter.revisionsModel(for: session.workspace, path: Self.configPath)
            )
            try await eventually(timeout: .seconds(20)) { model.isLoading == false }

            await MergeAutomation.perform("target:\(session.path)")
            #expect(MergeAutomation.revisionsPath == nil)
            await MergeAutomation.perform("editResult:typed")

            #expect(model.resultText == "typed")

            MergeToolPresenter.showMergeRevisions(workspace: session.workspace, path: Self.notesPath)
            await MergeAutomation.perform("editResult:ambiguous")

            #expect(model.resultText == "typed")
        }
    }
}
