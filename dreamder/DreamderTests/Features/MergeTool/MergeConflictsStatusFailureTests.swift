import Foundation
import Synchronization
import Testing
@testable import Dreamder

nonisolated private enum ScriptedStatus: Sendable {
    case conflicts
    case failing
}

nonisolated private final class StatusSwitch: Sendable {
    private let state = Mutex(ScriptedStatus.conflicts)

    var current: ScriptedStatus { state.withLock { $0 } }

    func set(_ status: ScriptedStatus) {
        state.withLock { $0 = status }
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct MergeConflictsStatusFailureTests {
    private static let unmergedRecord = "u UU N... 100644 100644 100644 100644 h1 h2 h3 a.txt\u{0}"
    private static let failurePrefix = "Could not read the Git status: "

    private func makeManager(_ root: URL) -> SourceControlManager {
        SourceControlManager(workspaceURL: root, editorManager: EditorManager())
    }

    private func workspace(_ root: URL) -> WorkspaceDocument {
        let document = WorkspaceDocument()
        document.sourceControlManager = makeManager(root)
        return document
    }

    private func scriptedCenter(
        root: URL,
        status: StatusSwitch,
        cancelWhileFailing: Bool = false
    ) -> MergeConflictsCenter {
        let unmerged = Self.unmergedRecord
        let (client, _) = ScmFakeGit.client(directory: root) { invocation in
            let arguments = ScmFakeGit.arguments(invocation)
            if arguments.contains("status") {
                if status.current == .failing {
                    if cancelWhileFailing {
                        withUnsafeCurrentTask { (current: UnsafeCurrentTask?) in
                            current?.cancel()
                        }
                    }
                    return ScmFakeGit.failure("fatal: index file corrupt")
                }
                return ScmFakeGit.ok(unmerged)
            }
            if arguments.contains("--abbrev-ref") {
                return ScmFakeGit.ok("main\n")
            }
            return ScmFakeGit.ok("")
        }
        return MergeConflictsCenter(makeRepository: { _ in
            MergeConflictRepository(gitClient: client, rootURL: root)
        })
    }

    private func corruptIndex(in root: URL) throws {
        try Data("not an index".utf8).write(to: root.appending(path: ".git/index"))
    }

    @Test
    func aFailedStatusWithoutEarlierStateIsPublishedAsAFailureNotAsAResolvedTree() async throws {
        try await withTempDir { dir in
            let status = StatusSwitch()
            status.set(.failing)
            let center = scriptedCenter(root: dir, status: status)

            await center.refresh(manager: makeManager(dir))

            let state = try #require(center.state(for: dir))
            #expect(state.entries.isEmpty)
            #expect(state.context == nil)
            #expect(state.failure == Self.failurePrefix + "index file corrupt")
            #expect(center.hasConflicts(rootURL: dir) == false)
        }
    }

    @Test
    func aFailedStatusKeepsTheLastKnownConflictsAndClearsTheFailureOnRecovery() async throws {
        try await withTempDir { dir in
            let status = StatusSwitch()
            let center = scriptedCenter(root: dir, status: status)
            let manager = makeManager(dir)
            await center.refresh(manager: manager)
            let healthy = try #require(center.state(for: dir))
            #expect(healthy.failure == nil)

            status.set(.failing)
            await center.refresh(manager: manager)

            let failed = try #require(center.state(for: dir))
            #expect(failed.entries == healthy.entries)
            #expect(failed.context == healthy.context)
            #expect(failed.failure == Self.failurePrefix + "index file corrupt")
            #expect(center.hasConflicts(rootURL: dir))

            status.set(.conflicts)
            await center.refresh(manager: manager)

            #expect(center.state(for: dir) == healthy)
        }
    }

    @Test
    func aStatusReadCancelledWhileFailingPublishesNothing() async throws {
        try await withTempDir { dir in
            let status = StatusSwitch()
            status.set(.failing)
            let center = scriptedCenter(root: dir, status: status, cancelWhileFailing: true)
            let manager = makeManager(dir)

            let task = Task { @MainActor in
                await center.refresh(manager: manager)
            }
            await task.value

            #expect(center.state(for: dir) == nil)
        }
    }

    @Test
    func theConflictsWindowShowsAFailedStatusInsteadOfTheResolvedMessage() async throws {
        try await withTempDir { dir in
            let model = try #require(MergeConflictsViewModel(workspace: workspace(dir)))

            try await eventually(timeout: .seconds(20)) { model.statusFailure != nil }

            let failure = Self.failurePrefix + "Not a git repository"
            #expect(model.statusFailure == failure)
            #expect(model.isEmpty)
            #expect(model.summary == failure)
            #expect(model.emptyStateMessage == failure)
            #expect(model.emptyStateIcon == "general/warningDialog")
        }
    }

    @Test
    func theConflictsWindowKeepsItsRowsAndReportsTheFailureWhenStatusBreaksLater() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.mergeConflict(in: dir)
            let model = try #require(MergeConflictsViewModel(workspace: workspace(dir)))
            await model.reload()
            try await eventually(timeout: .seconds(20)) { model.entries.count == 2 && model.context != nil }
            #expect(model.statusFailure == nil)
            #expect(model.emptyStateMessage == MergeConflictsViewModel.resolvedMessage)
            #expect(model.emptyStateIcon == "general/greenCheckmark")
            let healthySummary = model.summary

            try corruptIndex(in: dir)
            await model.reload()

            try await eventually(timeout: .seconds(20)) {
                await model.reload()
                return model.statusFailure != nil
            }
            #expect(model.entries.count == 2)
            #expect(model.summary == model.statusFailure)
            #expect(model.summary != healthySummary)
            #expect(model.summary.hasPrefix(Self.failurePrefix))

            try FileManager.default.removeItem(at: dir.appending(path: ".git/index"))

            try await eventually(timeout: .seconds(20)) {
                await model.reload()
                return model.statusFailure == nil
            }
            #expect(model.isEmpty)
            #expect(model.summary == MergeConflictsViewModel.resolvedMessage)
            #expect(try await fixture.unmergedPaths().isEmpty)
        }
    }

    @Test
    func theRevisionsWindowReportsAFailedStatusInsteadOfAnInvalidConflict() async throws {
        try await withTempDir { dir in
            let model = try #require(MergeRevisionsViewModel(workspace: workspace(dir), path: "a.txt", autoLoad: false))

            await model.load()

            #expect(model.errorMessage == Self.failurePrefix + "Not a git repository")
            #expect(model.isLoading == false)
            #expect(model.merge == nil)
            #expect(model.canApply == false)
        }
    }

    @Test
    func describingAStatusFailureUsesTheGitMessageOrTheLocalizedDescription() {
        #expect(
            MergeToolErrorText.describeStatusFailure(GitClient.GitClientError.outputError("bad index"))
                == Self.failurePrefix + "bad index"
        )
        #expect(
            MergeToolErrorText.describeStatusFailure(CocoaError(.fileNoSuchFile))
                == Self.failurePrefix + CocoaError(.fileNoSuchFile).localizedDescription
        )
    }
}
