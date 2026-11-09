import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct GitToolWindowShelfCoverage {
    private static let windowSize = NSSize(width: 900, height: 600)

    @MainActor
    private struct Session {
        let workspace: WorkspaceDocument
        let manager: SourceControlManager
        let model: GitToolWindowModel
        let probe: ShelfDialogProbe
        let hosted: HostedView

        var shelfModel: ShelfModel {
            model.shelfModel
        }

        func showShelfAndWaitForShelves(_ count: Int) async throws {
            model.showShelf()
            try await eventually { shelfModel.isLoaded && shelfModel.shelves.count == count }
            try await hosted.settle(.milliseconds(300))
        }

        func close() {
            hosted.close()
            workspace.close()
        }
    }

    private func makeSession(_ directory: URL) throws -> Session {
        let workspace = try HostedViewFixture.makeWorkspace(in: directory)
        let manager = try #require(workspace.sourceControlManager)
        let probe = ShelfDialogProbe()
        let model = GitToolWindowModel(shelfModel: ShelfModel(dialogs: probe.dialogs))
        let hosted = try HostedViewFixture.hostInWorkspace(workspace, size: Self.windowSize) {
            GitToolWindow(model: model)
        }
        return Session(workspace: workspace, manager: manager, model: model, probe: probe, hosted: hosted)
    }

    @Test
    func shelfTabListsShelvesAndUnshelvesTheSelectedOne() async throws {
        try await withTempDir { directory in
            let repo = try await ShelfRepo.make(in: directory)
            try repo.fixture.write("a.txt", "a2\n")
            try repo.fixture.write("new.txt", "new\n")
            let shelf = try await repo.client.shelve(paths: ["a.txt", "new.txt"], name: "UI shelf")
            let session = try makeSession(directory)
            defer { session.close() }
            try await eventually { session.manager.currentBranch != nil }
            try await session.hosted.settle(.milliseconds(500))
            #expect(!session.shelfModel.isLoaded)
            let log = session.hosted.snapshot()

            try await session.showShelfAndWaitForShelves(1)

            #expect(HostedView.pixelsDiffer(log, session.hosted.snapshot()))
            #expect(session.shelfModel.shelves.map(\.hash) == [shelf.hash])
            #expect(session.shelfModel.selectedHash == shelf.hash)

            await session.shelfModel.unshelveSelected(keep: false)

            #expect(session.shelfModel.shelves.isEmpty)
            #expect(try repo.fixture.read("a.txt") == "a2\n")
            #expect(try repo.fixture.read("new.txt") == "new\n")
            #expect(try await repo.stashHashes().isEmpty)
        }
    }

    @Test
    func tabsSwitchBetweenLogConsoleAndShelfContent() async throws {
        try await withTempDir { directory in
            let repo = try await ShelfRepo.make(in: directory)
            try repo.fixture.write("a.txt", "a2\n")
            _ = try await repo.client.shelve(paths: ["a.txt"], name: "Tabbed")
            let session = try makeSession(directory)
            defer { session.close() }
            let log = GitConsoleLog.log(for: session.manager.repositoryURL)
            log.record(command: "stash push", directory: session.manager.repositoryURL, output: "error: nothing")
            try await eventually { session.manager.currentBranch != nil }
            try await session.hosted.settle(.milliseconds(500))
            #expect(!log.entries.isEmpty)
            let logContent = session.hosted.snapshot()

            session.model.setConsoleSelected(true)
            try await session.hosted.settle(.milliseconds(300))
            let consoleContent = session.hosted.snapshot()
            #expect(!session.shelfModel.isLoaded)
            #expect(HostedView.pixelsDiffer(logContent, consoleContent))

            try await session.showShelfAndWaitForShelves(1)
            let shelfContent = session.hosted.snapshot()
            #expect(HostedView.pixelsDiffer(consoleContent, shelfContent))
            #expect(HostedView.pixelsDiffer(logContent, shelfContent))

            let tab = GitConsoleTab(log: log, isSelected: session.model.consoleSelection)
            tab.select()
            tab.dismiss()
            session.model.showLog()
            try await session.hosted.settle(.milliseconds(300))

            #expect(log.isDismissed)
            #expect(session.model.pane == .log)
            #expect(session.hosted.renders())
        }
    }

    @Test
    func shelfTabInADirectoryWithoutARepositoryKeepsThePlaceholder() async throws {
        try await withTempDir { directory in
            let session = try makeSession(directory)
            defer { session.close() }
            try await session.hosted.settle(.milliseconds(400))
            #expect(session.manager.isGitRepository == false)

            session.model.showShelf()
            try await session.hosted.settle(.milliseconds(300))

            #expect(!session.shelfModel.isLoaded)
            #expect(session.model.pane == .shelf)
            #expect(session.hosted.renders())
        }
    }

    @Test
    func conflictingUnshelveOpensTheMergeToolWithTheLivePresenter() async throws {
        try await withTempDir { directory in
            let repo = try await ShelfRepo.make(in: directory)
            try repo.fixture.write("a.txt", "shelved\n")
            let shelf = try await repo.client.shelve(paths: ["a.txt"], name: "Conflicting")
            try repo.fixture.write("a.txt", "committed\n")
            try await repo.fixture.commit("diverge")
            let session = try makeSession(directory)
            defer {
                if let own = MergeToolPresenter.conflictsModel(for: session.workspace), MergeToolPresenter.conflictsModel === own {
                    MergeToolPresenter.conflictsWindow?.close()
                }
                session.close()
            }
            try await eventually { session.manager.currentBranch != nil }
            try await session.hosted.settle(.milliseconds(500))
            try await session.showShelfAndWaitForShelves(1)

            await session.shelfModel.unshelveSelected(keep: false)

            #expect(MergeToolPresenter.conflictsModel(for: session.workspace) != nil)
            #expect(session.shelfModel.shelves.map(\.hash) == [shelf.hash])
            #expect(session.probe.notifications.count == 1)
            #expect(try await repo.fixture.unmergedPaths() == ["a.txt"])
        }
    }
}
