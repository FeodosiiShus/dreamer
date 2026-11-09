import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct GitGutterCoordinatorCoverageTests {
    private static let headSource = "alpha\nbravo\ncharlie\ndelta\necho\nfoxtrot\ngolf\nhotel\n"
    private static let timeout: Duration = .seconds(60)

    @MainActor
    private struct Session {
        let workspace: WorkspaceDocument
        let hosted: HostedSourceEditor
        let textView: TextView
        let coordinator: GitGutterCoordinator
        let marker: GitGutterMarkerView
        let manager: SourceControlManager
        let git: GitMergeFixture
        let fileName: String

        var text: String { textView.string }

        func close() {
            hosted.close()
            workspace.close()
        }

        func replace(_ target: String, with replacement: String) throws {
            let range = (textView.string as NSString).range(of: target)
            try #require(range.location != NSNotFound, "missing \(target)")
            textView.replaceCharacters(in: range, with: replacement)
        }

        func replaceEverything(with text: String) {
            textView.replaceCharacters(in: NSRange(location: 0, length: textView.textStorage.length), with: text)
        }

        func rollbackCallback() throws -> (GitLineChange) -> Void {
            try #require(marker.rollback)
        }
    }

    private func openSession(in directory: URL, trackedURLOverride: URL? = nil) async throws -> Session {
        let fileName = "\(UUID().uuidString).swift"
        let git = try await GitMergeFixture(root: directory)
        try git.write(fileName, Self.headSource)
        try await git.commit("initial")
        let workspace = try HostedSourceEditorFixture.registerWorkspace(at: directory)
        let fixture = try HostedSourceEditorFixture.make(in: directory, fileName: fileName, contents: Self.headSource)
        if let trackedURLOverride {
            fixture.document.fileURL = trackedURLOverride
        }
        let coordinator = GitGutterCoordinator(codeFile: fixture.document, debounceInterval: .milliseconds(50))
        let hosted = fixture.host(
            coordinators: [fixture.document.contentCoordinator, coordinator],
            size: NSSize(width: 900, height: 600)
        )
        try await eventually(timeout: Self.timeout) {
            hosted.controller?.textView?.window === hosted.window
                && !hosted.views(ofType: GitGutterMarkerView.self).isEmpty
        }
        let textView = try #require(hosted.controller?.textView)
        let marker = try #require(hosted.views(ofType: GitGutterMarkerView.self).first)
        let manager = try #require(workspace.sourceControlManager)
        return Session(
            workspace: workspace,
            hosted: hosted,
            textView: textView,
            coordinator: coordinator,
            marker: marker,
            manager: manager,
            git: git,
            fileName: fileName
        )
    }

    private func openTrackedSession(in directory: URL) async throws -> Session {
        let session = try await openSession(in: directory)
        try await eventually(timeout: Self.timeout) { session.coordinator.loadedHeadText == Self.headSource }
        return session
    }

    private func settleOnSingleChange(of session: Session) async throws -> GitLineChange {
        try await eventually(timeout: Self.timeout) { session.marker.changes.count == 1 }
        return try #require(session.marker.changes.first)
    }

    @Test
    func previousContentReturnsTheCommittedLinesOfAnOldRange() async throws {
        try await withTempDir { directory in
            let session = try await openTrackedSession(in: directory)
            defer { session.close() }
            let previousContent = try #require(session.marker.previousContent)

            func previous(_ old: ClosedRange<Int>?) -> String? {
                previousContent(GitLineChange(kind: .modified, oldLines: old, newLines: 1...1, anchorLine: 1))
            }

            #expect(previous(2...3) == "bravo\ncharlie")
            #expect(previous(4...4) == "delta")
            #expect(previous(0...1) == "alpha")
            #expect(previous(7...50) == "golf\nhotel")
            #expect(previous(50...51) == nil)
            #expect(previous(nil) == nil)
        }
    }

    @Test
    func previousContentIsUnavailableOnceTrackingStopsOrTheEditorIsDestroyed() async throws {
        try await withTempDir { directory in
            let session = try await openTrackedSession(in: directory)
            defer { session.close() }
            let previousContent = try #require(session.marker.previousContent)
            let change = GitLineChange(kind: .modified, oldLines: 2...2, newLines: 2...2, anchorLine: 2)
            #expect(previousContent(change) == "bravo")

            try FileManager.default.removeItem(at: directory.appending(path: ".git"))
            await session.manager.validate()
            try await eventually(timeout: Self.timeout) { session.coordinator.loadedHeadText == nil }

            #expect(previousContent(change) == nil)
        }
    }

    @Test
    func rollbackOfAModifiedLineRestoresTheCommittedText() async throws {
        try await withTempDir { directory in
            let session = try await openTrackedSession(in: directory)
            defer { session.close() }

            try session.replace("bravo", with: "BRAVO!")
            let change = try await settleOnSingleChange(of: session)
            #expect(change.kind == .modified)
            try session.rollbackCallback()(change)

            #expect(session.text == Self.headSource)
            try await eventually(timeout: Self.timeout) { session.marker.changes.isEmpty }
        }
    }

    @Test
    func rollbackOfAModifiedRangeRestoresEveryCommittedLine() async throws {
        try await withTempDir { directory in
            let session = try await openTrackedSession(in: directory)
            defer { session.close() }

            try session.replace("charlie\ndelta", with: "CHARLIE\nDELTA")
            let change = try await settleOnSingleChange(of: session)
            #expect(change.kind == .modified)
            try session.rollbackCallback()(change)

            #expect(session.text == Self.headSource)
        }
    }

    @Test
    func rollbackOfAnAddedLineRemovesIt() async throws {
        try await withTempDir { directory in
            let session = try await openTrackedSession(in: directory)
            defer { session.close() }

            try session.replace("delta\n", with: "delta\ndelta2\n")
            let change = try await settleOnSingleChange(of: session)
            #expect(change.kind == .added)
            try session.rollbackCallback()(change)

            #expect(session.text == Self.headSource)
            try await eventually(timeout: Self.timeout) { session.marker.changes.isEmpty }
        }
    }

    @Test
    func rollbackOfADeletedLineReinsertsItBelowTheAnchor() async throws {
        try await withTempDir { directory in
            let session = try await openTrackedSession(in: directory)
            defer { session.close() }

            try session.replace("golf\n", with: "")
            let change = try await settleOnSingleChange(of: session)
            #expect(change.kind == .deleted)
            try session.rollbackCallback()(change)

            #expect(session.text == Self.headSource)
        }
    }

    @Test
    func rollbackOfADeletionAtTheTopReinsertsItAtTheStart() async throws {
        try await withTempDir { directory in
            let session = try await openTrackedSession(in: directory)
            defer { session.close() }

            try session.replace("alpha\n", with: "")
            let change = try await settleOnSingleChange(of: session)
            #expect(change.anchorLine == 0)
            try session.rollbackCallback()(change)

            #expect(session.text == Self.headSource)
        }
    }

    @Test
    func rollbackOfADeletionAfterTheLastLineWithoutATrailingNewlineAddsTheLineBreak() async throws {
        try await withTempDir { directory in
            let session = try await openTrackedSession(in: directory)
            defer { session.close() }
            session.replaceEverything(with: "alpha\nbravo")

            try session.rollbackCallback()(
                GitLineChange(kind: .deleted, oldLines: 3...3, newLines: nil, anchorLine: 2)
            )

            #expect(session.text == "alpha\nbravo\ncharlie")
        }
    }

    @Test
    func rollbackOfAModifiedLastLineWithoutATrailingNewlineKeepsItWithoutOne() async throws {
        try await withTempDir { directory in
            let session = try await openTrackedSession(in: directory)
            defer { session.close() }
            session.replaceEverything(with: "alpha\nBRAVO")

            try session.rollbackCallback()(
                GitLineChange(kind: .modified, oldLines: 2...2, newLines: 2...2, anchorLine: 2)
            )

            #expect(session.text == "alpha\nbravo")
        }
    }

    @Test
    func rollbackIgnoresChangesThatCannotBeLocatedOrHaveNothingToRestore() async throws {
        try await withTempDir { directory in
            let session = try await openTrackedSession(in: directory)
            defer { session.close() }
            let rollback = try session.rollbackCallback()

            rollback(GitLineChange(kind: .modified, oldLines: 1...1, newLines: 50...51, anchorLine: 50))
            rollback(GitLineChange(kind: .modified, oldLines: 1...1, newLines: 2...50, anchorLine: 2))
            rollback(GitLineChange(kind: .deleted, oldLines: 1...1, newLines: nil, anchorLine: 99))
            rollback(GitLineChange(kind: .deleted, oldLines: 99...99, newLines: nil, anchorLine: 2))
            rollback(GitLineChange(kind: .deleted, oldLines: nil, newLines: nil, anchorLine: 2))

            #expect(session.text == Self.headSource)
        }
    }

    @Test
    func callbacksOfADestroyedCoordinatorDoNothing() async throws {
        try await withTempDir { directory in
            let session = try await openTrackedSession(in: directory)
            defer { session.close() }
            let rollback = try session.rollbackCallback()
            let showDiff = try #require(session.marker.showDiff)
            let previousContent = try #require(session.marker.previousContent)
            let change = GitLineChange(kind: .modified, oldLines: 2...2, newLines: 2...2, anchorLine: 2)
            try session.replace("bravo", with: "BRAVO!")
            let edited = session.text

            session.coordinator.destroy()
            rollback(change)
            showDiff(change)

            #expect(session.text == edited)
            #expect(previousContent(change) == nil)
            #expect(DiffViewerPresenter.windows["worktree:HEAD:\(session.fileName)"] == nil)
        }
    }

    @Test
    func showDiffOpensTheWorkingTreeDiffOfTheFileAgainstHead() async throws {
        try await withTempDir { directory in
            let session = try await openTrackedSession(in: directory)
            defer { session.close() }
            let showDiff = try #require(session.marker.showDiff)
            let key = "worktree:HEAD:\(session.fileName)"

            showDiff(GitLineChange(kind: .modified, oldLines: 2...2, newLines: 2...2, anchorLine: 2))

            let controller = try #require(DiffViewerPresenter.windows[key])
            controller.window?.close()
            #expect(DiffViewerPresenter.windows[key] == nil)
        }
    }

    @Test
    func consecutiveEditsSettleOnTheMarkersOfTheLatestText() async throws {
        try await withTempDir { directory in
            let session = try await openTrackedSession(in: directory)
            defer { session.close() }

            try session.replace("bravo", with: "BRAVO!")
            try session.replace("echo", with: "ECHO!")
            try session.replace("BRAVO!", with: "bravo")

            let expected = [GitLineChange(kind: .modified, oldLines: 5...5, newLines: 5...5, anchorLine: 5)]
            try await eventually(timeout: Self.timeout) { session.marker.changes == expected }
            #expect(session.coordinator.currentChanges == expected)
        }
    }

    @Test
    func fileThatIsNotInsideTheRepositoryRootIsNotTracked() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory, trackedURLOverride: directory)
            defer { session.close() }
            await session.manager.refreshAllChangedFiles()

            try session.replace("bravo", with: "BRAVO!")
            await session.manager.refreshAllChangedFiles()

            #expect(session.manager.isGitRepository)
            #expect(session.coordinator.loadedHeadText == nil)
            #expect(session.coordinator.currentChanges.isEmpty)
            #expect(session.marker.changes.isEmpty)
        }
    }

    @Test
    func trackingStopsWhenTheWorkspaceLosesItsSourceControlManager() async throws {
        try await withTempDir { directory in
            let session = try await openTrackedSession(in: directory)
            defer { session.close() }
            try session.replace("bravo", with: "BRAVO!")
            _ = try await settleOnSingleChange(of: session)
            let observedManager = session.manager

            session.workspace.sourceControlManager = nil
            try session.git.write(session.fileName, "changed on disk\n")
            await observedManager.refreshAllChangedFiles()

            try await eventually(timeout: Self.timeout) {
                session.coordinator.loadedHeadText == nil && session.marker.changes.isEmpty
            }
            #expect(session.coordinator.currentChanges.isEmpty)
        }
    }
}
