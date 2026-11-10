import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct GitGutterStalenessTests {
    private static let fileName = "Tracked.swift"
    private static let initialSource = "alpha\nbravo\ncharlie\ndelta\necho\nfoxtrot\ngolf\nhotel\n"
    private static let editedSource = "alpha\nBRAVO!\ncharlie\ndelta\necho\nfoxtrot\ngolf\nhotel\n"
    private static let otherSource = "one\ntwo\nthree\nfour\n"

    @MainActor
    private struct Session {
        let workspace: WorkspaceDocument
        let hosted: HostedSourceEditor
        let textView: TextView
        let coordinator: GitGutterCoordinator
        let manager: SourceControlManager
        let git: GitMergeFixture

        func close() {
            hosted.close()
            workspace.close()
        }

        func replaceEverything(with text: String) {
            textView.replaceCharacters(in: NSRange(location: 0, length: textView.textStorage.length), with: text)
        }

        func commitOnDisk(_ text: String, message: String) async throws {
            try git.write(GitGutterStalenessTests.fileName, text)
            try await git.commit(message)
        }

        func commitObservedByTheManager(_ text: String, message: String) async throws {
            try git.write(GitGutterStalenessTests.fileName, text)
            await refreshManager()
            try await eventually(timeout: GitGutterStalenessTests.timeout) { !manager.changedFiles.isEmpty }
            try await git.commit(message)
            await refreshManager()
            try await eventually(timeout: GitGutterStalenessTests.timeout) { manager.changedFiles.isEmpty }
        }

        func refreshManager() async {
            await manager.refreshAllChangedFiles()
            await manager.refreshCurrentBranch()
        }
    }

    private static let timeout: Duration = .seconds(40)

    private func awaitCondition(
        sourceLocation: SourceLocation = #_sourceLocation,
        _ condition: () -> Bool
    ) async throws {
        try await eventually(timeout: Self.timeout, sourceLocation: sourceLocation, condition)
    }

    private func openSession(
        in directory: URL,
        beforeOpening prepare: (GitMergeFixture) async throws -> Void = { _ in }
    ) async throws -> Session {
        let git = try await GitMergeFixture(root: directory)
        try git.write(Self.fileName, Self.initialSource)
        try await git.commit("initial")
        try await prepare(git)
        let workspace = try HostedSourceEditorFixture.registerWorkspace(at: directory)
        let fixture = try HostedSourceEditorFixture.make(
            in: directory,
            fileName: Self.fileName,
            contents: Self.initialSource
        )
        let coordinator = GitGutterCoordinator(codeFile: fixture.document)
        let hosted = fixture.host(
            coordinators: [fixture.document.contentCoordinator, coordinator],
            size: NSSize(width: 900, height: 600)
        )
        try await awaitCondition {
            hosted.controller?.textView?.window === hosted.window && !hosted.views(ofType: GutterView.self).isEmpty
        }
        let textView = try #require(hosted.controller?.textView)
        let manager = try #require(workspace.sourceControlManager)
        let session = Session(
            workspace: workspace,
            hosted: hosted,
            textView: textView,
            coordinator: coordinator,
            manager: manager,
            git: git
        )
        try await awaitCondition { coordinator.loadedHeadText == Self.initialSource }
        await session.refreshManager()
        return session
    }

    @Test
    func commitThatMakesTheFileCleanReloadsHeadAndClearsTheMarkers() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory)
            defer { session.close() }

            session.replaceEverything(with: Self.editedSource)
            try await awaitCondition { !session.coordinator.currentChanges.isEmpty }
            try session.git.write(Self.fileName, Self.editedSource)
            await session.refreshManager()
            try await awaitCondition { !session.manager.changedFiles.isEmpty }

            try await session.git.commit("second")
            await session.refreshManager()

            try await awaitCondition {
                session.coordinator.loadedHeadText == Self.editedSource && session.coordinator.currentChanges.isEmpty
            }
            #expect(session.coordinator.loadedHeadText == Self.editedSource)
            #expect(session.coordinator.currentChanges.isEmpty)
        }
    }

    @Test
    func commitThroughTheManagerReloadsHead() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory)
            defer { session.close() }

            session.replaceEverything(with: Self.editedSource)
            try await awaitCondition { !session.coordinator.currentChanges.isEmpty }
            try session.git.write(Self.fileName, Self.editedSource)
            try await session.git.run("add", "-A")
            await session.refreshManager()
            try await awaitCondition { !session.manager.changedFiles.isEmpty }

            try await session.manager.commit(message: "through manager")

            try await awaitCondition {
                session.coordinator.loadedHeadText == Self.editedSource && session.coordinator.currentChanges.isEmpty
            }
            #expect(session.manager.changedFiles.isEmpty)
        }
    }

    @Test
    func fastForwardOnTheSameBranchWithCleanTreeReloadsHead() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory) { git in
                try await git.run("checkout", "-q", "-b", "other")
                try git.write(Self.fileName, Self.otherSource)
                try await git.commit("other")
                try await git.run("checkout", "-q", "-")
            }
            defer { session.close() }
            let branchBefore = session.manager.currentBranch?.longName
            let headBefore = session.manager.currentHeadCommit

            try await session.git.run("merge", "-q", "--ff-only", "other")
            await session.manager.refreshCurrentBranch()

            #expect(session.manager.currentBranch?.longName == branchBefore)
            #expect(session.manager.currentHeadCommit != headBefore)
            try await awaitCondition { session.coordinator.loadedHeadText == Self.otherSource }
        }
    }

    @Test
    func branchSwitchesMakeHeadAndMarkersFollowTheCheckedOutBranch() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory)
            defer { session.close() }
            await session.manager.refreshCurrentBranch()
            let mainBranch = try #require(session.manager.currentBranch)

            try await session.git.run("checkout", "-q", "-b", "other")
            try await session.commitOnDisk(Self.otherSource, message: "other")
            await session.refreshManager()

            try await awaitCondition { session.coordinator.loadedHeadText == Self.otherSource }
            session.replaceEverything(with: Self.initialSource)
            try await awaitCondition { !session.coordinator.currentChanges.isEmpty }

            try await session.manager.checkoutBranch(branch: mainBranch)

            try await awaitCondition { session.coordinator.loadedHeadText == Self.initialSource }
            try await awaitCondition { session.coordinator.currentChanges.isEmpty }
            #expect(session.manager.currentBranch?.name == mainBranch.name)
        }
    }

    @Test
    func rapidConsecutiveCommitsSettleOnTheLatestHead() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory)
            defer { session.close() }
            let finalSource = "final\nsource\n"

            try await session.commitObservedByTheManager(Self.editedSource, message: "second")
            try await session.commitObservedByTheManager(Self.otherSource, message: "third")
            try await session.commitObservedByTheManager(finalSource, message: "fourth")
            session.replaceEverything(with: finalSource)

            try await awaitCondition { session.coordinator.loadedHeadText == finalSource }
            try await awaitCondition { session.coordinator.currentChanges.isEmpty }
            #expect(session.coordinator.loadedHeadText == finalSource)
            #expect(session.coordinator.currentChanges.isEmpty)
        }
    }

    @Test
    func leavingRepositoryStateStopsTrackingAndClearsMarkers() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory)
            defer { session.close() }

            session.replaceEverything(with: Self.editedSource)
            try await awaitCondition { !session.coordinator.currentChanges.isEmpty }

            try FileManager.default.removeItem(at: directory.appending(path: ".git"))
            await session.manager.validate()

            try await awaitCondition { session.coordinator.currentChanges.isEmpty }
            #expect(!session.manager.isGitRepository)
            #expect(session.coordinator.loadedHeadText == nil)
        }
    }
}
