import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct CommitToolWindowAmendTests {
    private func makeRepo(_ directory: URL) async throws -> (GitMergeFixture, SourceControlManager) {
        let fixture = try await GitMergeFixture(root: directory)
        try fixture.write("a.txt", "a\n")
        try await fixture.commit("initial")
        try fixture.write("a.txt", "a2\n")
        try await fixture.run("commit", "-qam", "Second commit", "-m", "Body line")
        return (fixture, SourceControlManager(workspaceURL: directory, editorManager: EditorManager()))
    }

    @Test
    func checkingAmendPrefillsTheLastCommitMessageAndUncheckingRestoresTheEmptyOne() async throws {
        try await withTempDir { directory in
            let (_, manager) = try await makeRepo(directory)
            let model = CommitToolWindowViewModel()

            await model.setAmend(true, using: manager)

            #expect(model.amend)
            #expect(model.message == "Second commit\n\nBody line")
            #expect(
                model.amendPrefill
                    == CommitToolWindowViewModel.AmendPrefill(beforeAmend: "", amendMessage: "Second commit\n\nBody line")
            )

            await model.setAmend(false, using: manager)

            #expect(model.amend == false)
            #expect(model.message.isEmpty)
            #expect(model.amendPrefill == nil)
        }
    }

    @Test
    func aBlankMessageIsReplacedAndComesBackOnUncheck() async throws {
        try await withTempDir { directory in
            let (_, manager) = try await makeRepo(directory)
            let model = CommitToolWindowViewModel()
            model.message = "  \n"

            await model.setAmend(true, using: manager)
            #expect(model.message == "Second commit\n\nBody line")

            await model.setAmend(false, using: manager)
            #expect(model.message == "  \n")
        }
    }

    @Test
    func aMessageTheUserTypedIsNeverOverwrittenOrRestored() async throws {
        try await withTempDir { directory in
            let (_, manager) = try await makeRepo(directory)
            let model = CommitToolWindowViewModel()
            model.message = "work in progress"

            await model.setAmend(true, using: manager)
            #expect(model.message == "work in progress")
            #expect(model.amendPrefill == nil)

            await model.setAmend(false, using: manager)
            #expect(model.message == "work in progress")
        }
    }

    @Test
    func aPrefilledMessageThatWasEditedStaysWhenAmendIsUnchecked() async throws {
        try await withTempDir { directory in
            let (_, manager) = try await makeRepo(directory)
            let model = CommitToolWindowViewModel()

            await model.setAmend(true, using: manager)
            model.message = "Second commit, reworded"
            await model.setAmend(false, using: manager)

            #expect(model.message == "Second commit, reworded")
            #expect(model.amendPrefill == nil)
        }
    }

    @Test
    func settingTheCurrentAmendStateAgainDoesNothing() async throws {
        try await withTempDir { directory in
            let (_, manager) = try await makeRepo(directory)
            let model = CommitToolWindowViewModel()

            await model.setAmend(false, using: manager)
            #expect(model.amend == false)
            #expect(model.message.isEmpty)

            await model.setAmend(true, using: manager)
            model.message = "edited"
            await model.setAmend(true, using: manager)
            #expect(model.message == "edited")
            #expect(model.amend)
        }
    }

    @Test
    func anEmptyLastCommitMessageLeavesTheEditorAlone() async throws {
        try await withTempDir { directory in
            let (fixture, manager) = try await makeRepo(directory)
            try await fixture.run("commit", "-q", "--allow-empty", "--allow-empty-message", "-m", "")
            let model = CommitToolWindowViewModel()

            await model.setAmend(true, using: manager)

            #expect(model.amend)
            #expect(model.message.isEmpty)
            #expect(model.amendPrefill == nil)
            #expect(manager.lastAlert == nil)
        }
    }

    @Test
    func aRepositoryWithoutCommitsReportsTheMissingMessage() async throws {
        try await withTempDir { directory in
            _ = try await GitMergeFixture(root: directory)
            let manager = SourceControlManager(workspaceURL: directory, editorManager: EditorManager())
            let model = CommitToolWindowViewModel()

            await model.setAmend(true, using: manager)

            #expect(manager.lastAlert?.title == "Commit Message Not Loaded")
            #expect(model.amend)
            #expect(model.message.isEmpty)
            #expect(model.amendPrefill == nil)
        }
    }

    @Test
    func amendNeedsNoIncludedFilesButStillNeedsAMessage() {
        let model = CommitToolWindowViewModel()
        #expect(model.canCommit(in: []) == false)

        model.amend = true
        #expect(model.canCommit(in: []) == false)

        model.message = "Reworded"
        #expect(model.canCommit(in: []))

        model.amend = false
        #expect(model.canCommit(in: []) == false)
    }

    @Test
    func aMessageOnlyAmendRewritesTheLastCommitWithoutTouchingItsTree() async throws {
        try await withTempDir { directory in
            let (fixture, manager) = try await makeRepo(directory)
            let treeBefore = try await fixture.run("rev-parse", "HEAD^{tree}")
            let model = CommitToolWindowViewModel()
            await model.setAmend(true, using: manager)
            model.message = "Reworded"

            await model.commit(using: manager, andPush: false)

            #expect(try await fixture.run("log", "--format=%s") == "Reworded\ninitial\n")
            #expect(try await fixture.run("rev-parse", "HEAD^{tree}") == treeBefore)
            #expect(model.amend == false)
            #expect(model.amendPrefill == nil)
            #expect(model.message.isEmpty)
            #expect(model.isCommitting == false)
            #expect(manager.lastAlert == nil)
        }
    }

    @Test
    func aMessageOnlyAmendStillUnstagesExcludedStagedFiles() async throws {
        try await withTempDir { directory in
            let (fixture, manager) = try await makeRepo(directory)
            try fixture.write("a.txt", "staged change\n")
            try await fixture.run("add", "a.txt")
            await manager.refreshAllChangedFiles()
            let changed = try #require(manager.changedFiles.first)
            let model = CommitToolWindowViewModel()
            model.setIncluded(false, for: changed)
            model.amend = true
            model.message = "Reworded"

            await model.commit(using: manager, andPush: false)

            #expect(try await fixture.run("log", "-1", "--format=%s") == "Reworded\n")
            #expect(try await fixture.run("show", "HEAD:a.txt") == "a2\n")
            #expect(try await fixture.stagedPaths().isEmpty)
            #expect(try fixture.read("a.txt") == "staged change\n")
        }
    }
}
