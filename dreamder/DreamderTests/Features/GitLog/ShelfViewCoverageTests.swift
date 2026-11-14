import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct ShelfViewCoverage {
    @MainActor
    struct Session {
        let workspace: WorkspaceDocument
        let manager: SourceControlManager
        let model: ShelfModel
        let probe: ShelfDialogProbe
        let repo: ShelfRepo
        let hosted: HostedView
        let input: GitToolWindowCovInput

        func text(_ path: String) -> String? {
            try? repo.fixture.read(path)
        }

        func close() {
            hosted.close()
            workspace.close()
        }

        func toolbarSnapshot() -> NSBitmapImageRep? {
            guard let full = hosted.snapshot(), let image = full.cgImage else { return nil }
            let scale = CGFloat(full.pixelsWide) / hosted.hosting.bounds.width
            let width = ShelfView.toolbarInset * 2 + 5 * ShelfView.buttonSize + 4 * ShelfView.buttonSpacing
            let region = CGRect(x: 0, y: 0, width: width * scale, height: ShelfView.toolbarHeight * scale)
            return image.cropping(to: region).map(NSBitmapImageRep.init(cgImage:))
        }

        func rowPoint(_ index: Int) -> CGPoint {
            let height = Islands.listRowHeight
            return CGPoint(x: 100, y: ShelfView.toolbarHeight + 1 + CGFloat(index) * height + height / 2)
        }

        func menuIndex(_ title: String, row: Int) throws -> (NSMenu, Int) {
            let menu = try input.contextMenu(at: rowPoint(row))
            return (menu, try #require(menu.items.firstIndex { $0.title == title }))
        }

        func shelve(_ paths: [String], name: String) async throws -> GitShelf {
            let shelf = try await repo.client.shelve(paths: paths, name: name)
            await model.reload()
            try await hosted.settle(.milliseconds(150))
            return shelf
        }

        func rowMenu(for shelf: GitShelf) -> CommandsACoverageMenu {
            CommandsACoverageSupport.host { ShelfRowMenu(shelf: shelf, model: model) }
        }
    }

    func makeSession(_ directory: URL, livePresenter: Bool = false) async throws -> Session {
        let repo = try await ShelfRepo.make(in: directory)
        let workspace = try HostedViewFixture.makeWorkspace(in: directory)
        let manager = try #require(workspace.sourceControlManager)
        let probe = ShelfDialogProbe()
        let model = ShelfModel(dialogs: probe.dialogs)
        let hosted = try HostedViewFixture.hostInWorkspace(workspace) {
            if livePresenter {
                ShelfView(model: model)
            } else {
                ShelfView(model: model, showConflicts: { _ in probe.presentConflicts() })
            }
        }
        let input = GitToolWindowCovInput(hosted: hosted)
        try await eventually { model.isLoaded }
        try await hosted.settle(.milliseconds(150))
        return Session(
            workspace: workspace,
            manager: manager,
            model: model,
            probe: probe,
            repo: repo,
            hosted: hosted,
            input: input
        )
    }

    @Test
    func emptyStateGivesWayToTheShelfListAndItsFiles() async throws {
        try await withTempDir { directory in
            let session = try await makeSession(directory)
            defer { session.close() }
            #expect(session.model.shelves.isEmpty)
            #expect(session.hosted.renders())
            let empty = session.hosted.snapshot()

            try session.repo.fixture.write("a.txt", "a2\n")
            let single = try await session.shelve(["a.txt"], name: "Single")
            #expect(session.model.selectedHash == single.hash)
            let one = session.hosted.snapshot()
            #expect(HostedView.pixelsDiffer(empty, one))

            try session.repo.fixture.write("a.txt", "a3\n")
            try session.repo.fixture.write("b.txt", "b2\n")
            let double = try await session.shelve(["a.txt", "b.txt"], name: "Double")
            #expect(session.model.shelves.map(\.hash) == [double.hash, single.hash])
            let two = session.hosted.snapshot()
            #expect(HostedView.pixelsDiffer(one, two))

            session.model.select(double)
            try await session.hosted.settle(.milliseconds(150))
            #expect(session.model.selectedHash == double.hash)
            #expect(HostedView.pixelsDiffer(two, session.hosted.snapshot()))
        }
    }

    @Test
    func rowBackgroundPrefersSelectionOverHoverOverNothing() {
        #expect(ShelfRow.background(isSelected: true, isHovering: false) == Islands.selection)
        #expect(ShelfRow.background(isSelected: true, isHovering: true) == Islands.selection)
        #expect(ShelfRow.background(isSelected: false, isHovering: true) == Islands.hover)
        #expect(ShelfRow.background(isSelected: false, isHovering: false) == Color.clear)
        #expect(Islands.hover != Color.clear)
        #expect(Islands.selection != Islands.hover)
    }

    @Test
    func selectingARowMovesTheSelectionBackgroundToIt() async throws {
        try await withTempDir { directory in
            let session = try await makeSession(directory)
            defer { session.close() }
            try session.repo.fixture.write("a.txt", "a2\n")
            let first = try await session.shelve(["a.txt"], name: "first")
            try session.repo.fixture.write("b.txt", "b2\n")
            let second = try await session.shelve(["b.txt"], name: "second")
            #expect(session.model.selectedHash == first.hash)
            let beforeSelecting = session.hosted.snapshot()

            session.model.select(second)
            try await session.hosted.settle(.milliseconds(150))

            #expect(session.model.selectedHash == second.hash)
            #expect(HostedView.pixelsDiffer(beforeSelecting, session.hosted.snapshot()))
        }
    }

    @Test
    func toolbarActionsShelveKeepAndUnshelve() async throws {
        try await withTempDir { directory in
            let session = try await makeSession(directory)
            defer { session.close() }
            try await session.repo.makeMixedChanges()
            await session.manager.refreshAllChangedFiles()
            session.probe.promptAnswer = "Shelved"

            await session.model.shelveAllChanges()
            #expect(session.model.shelves.map(\.name) == ["Shelved"])
            #expect(try session.repo.fixture.read("a.txt") == "a\n")

            await session.model.unshelveSelected(keep: true)
            #expect(session.probe.errors.isEmpty)
            #expect(session.text("a.txt") == "a2\n")
            #expect(session.text("b.txt") == "b2\n")
            #expect(session.repo.fixture.exists("new.txt"))
            #expect(session.repo.fixture.exists("other.txt"))
            #expect(!session.repo.fixture.exists("c.txt"))
            #expect(session.model.shelves.count == 1)

            try await session.repo.fixture.run("reset", "--hard", "-q")
            try await session.repo.fixture.run("clean", "-fdq")
            #expect(try session.repo.fixture.read("a.txt") == "a\n")

            await session.model.unshelveSelected(keep: false)
            #expect(session.model.shelves.isEmpty)
            #expect(try session.repo.fixture.read("a.txt") == "a2\n")
            #expect(try session.repo.fixture.read("new.txt") == "new\n")
            try await session.hosted.settle(.milliseconds(200))
            #expect(session.hosted.renders())
        }
    }

    @Test
    func toolbarRenameActionRenamesTheSelectedShelf() async throws {
        try await withTempDir { directory in
            let session = try await makeSession(directory)
            defer { session.close() }
            try session.repo.fixture.write("a.txt", "a2\n")
            let shelf = try await session.shelve(["a.txt"], name: "before")
            session.probe.promptAnswer = "Renamed"

            await session.model.renameSelected()

            #expect(session.model.shelves.map(\.name) == ["Renamed"])
            #expect(session.model.selectedHash == shelf.hash)
            #expect(session.probe.errors.isEmpty)
        }
    }

    @Test
    func toolbarButtonsAreDisabledWithoutASelection() async throws {
        try await withTempDir { directory in
            let session = try await makeSession(directory)
            defer { session.close() }
            let withoutSelection = session.toolbarSnapshot()
            #expect(withoutSelection != nil)

            await session.model.unshelveSelected(keep: false)
            await session.model.unshelveSelected(keep: true)
            await session.model.renameSelected()
            await session.model.deleteSelected()

            #expect(session.probe.promptTitles.isEmpty)
            #expect(session.probe.confirmMessages.isEmpty)
            #expect(session.probe.errors.isEmpty)

            try session.repo.fixture.write("a.txt", "a2\n")
            _ = try await session.shelve(["a.txt"], name: "selectable")
            #expect(session.model.selectedShelf != nil)
            #expect(HostedView.pixelsDiffer(withoutSelection, session.toolbarSnapshot()))
        }
    }

    @Test
    func deleteActionConfirmsBeforeRemoving() async throws {
        try await withTempDir { directory in
            let session = try await makeSession(directory)
            defer { session.close() }
            try session.repo.fixture.write("a.txt", "a2\n")
            _ = try await session.shelve(["a.txt"], name: "doomed")
            session.probe.confirmAnswer = false

            await session.model.deleteSelected()
            #expect(session.probe.confirmMessages.count == 1)
            #expect(session.model.shelves.count == 1)

            session.probe.confirmAnswer = true
            await session.model.deleteSelected()
            #expect(session.model.shelves.isEmpty)
            #expect(try await session.repo.stashHashes().isEmpty)
        }
    }

    @Test
    func conflictingUnshelvePresentsTheMergeToolAndNotifies() async throws {
        try await withTempDir { directory in
            let session = try await makeSession(directory)
            defer { session.close() }
            try session.repo.fixture.write("a.txt", "shelved\n")
            let shelf = try await session.shelve(["a.txt"], name: "Conflicting")
            try session.repo.fixture.write("a.txt", "committed\n")
            try await session.repo.fixture.commit("diverge")

            await session.model.unshelveSelected(keep: false)

            #expect(session.probe.conflictPresentations == 1)
            #expect(session.model.shelves.map(\.hash) == [shelf.hash])
            #expect(session.probe.notifications.count == 1)
        }
    }

    @Test
    func defaultConflictPresenterOpensTheMergeToolForTheWorkspace() async throws {
        try await withTempDir { directory in
            let session = try await makeSession(directory, livePresenter: true)
            defer {
                MergeToolPresenter.conflictsWindow(for: session.workspace)?.close()
                session.close()
            }
            try session.repo.fixture.write("a.txt", "shelved\n")
            let shelf = try await session.shelve(["a.txt"], name: "Conflicting")
            try session.repo.fixture.write("a.txt", "committed\n")
            try await session.repo.fixture.commit("diverge")
            #expect(MergeToolPresenter.conflictsModel(for: session.workspace) == nil)

            await session.model.unshelveSelected(keep: false)

            #expect(MergeToolPresenter.conflictsModel(for: session.workspace) != nil)
            #expect(session.model.shelves.map(\.hash) == [shelf.hash])
            #expect(session.probe.notifications.count == 1)
            #expect(try await session.repo.fixture.unmergedPaths() == ["a.txt"])
        }
    }
}
