import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
final class ShelfDialogProbe {
    var promptAnswer: String? = "Probe shelf"
    var confirmAnswer = true
    private(set) var promptTitles: [String] = []
    private(set) var promptInitials: [String] = []
    private(set) var confirmMessages: [String] = []
    private(set) var errors: [(title: String, message: String)] = []
    private(set) var notifications: [BranchesPopupNotificationRequest] = []
    private(set) var conflictPresentations = 0

    var dialogs: ShelfDialogs {
        ShelfDialogs(
            promptName: { [self] title, _, initial in
                promptTitles.append(title)
                promptInitials.append(initial)
                return promptAnswer
            },
            confirm: { [self] _, message, _ in
                confirmMessages.append(message)
                return confirmAnswer
            },
            error: { [self] title, message in
                errors.append((title, message))
            },
            notify: { [self] request in
                notifications.append(request)
            }
        )
    }

    func presentConflicts() {
        conflictPresentations += 1
    }
}

@MainActor
struct ShelfModelWorld {
    let repo: ShelfRepo
    let manager: SourceControlManager
    let probe: ShelfDialogProbe
    let model: ShelfModel

    static func make(in directory: URL) async throws -> ShelfModelWorld {
        let repo = try await ShelfRepo.make(in: directory)
        let manager = SourceControlManager(workspaceURL: directory, editorManager: EditorManager())
        let probe = ShelfDialogProbe()
        let model = ShelfModel(dialogs: probe.dialogs)
        model.attach(manager: manager, showConflicts: { [probe] in probe.presentConflicts() })
        return ShelfModelWorld(repo: repo, manager: manager, probe: probe, model: model)
    }

    func shelveFile(_ path: String, text: String, name: String) async throws -> GitShelf {
        try repo.fixture.write(path, text)
        let shelf = try await repo.client.shelve(paths: [path], name: name)
        await model.reload()
        return shelf
    }

    func makeConflictingShelf(name: String) async throws -> GitShelf {
        let shelf = try await shelveFile("a.txt", text: "shelved\n", name: name)
        try repo.fixture.write("a.txt", "committed\n")
        try await repo.fixture.commit("diverge")
        return shelf
    }
}

@MainActor
@Suite(.uiGate)
struct ShelfModelTests {
    private static let ghost = GitShelf(index: 0, hash: "feedface", name: "ghost", date: Date(), files: [])

    @Test
    func detachedModelIgnoresEveryOperation() async {
        let probe = ShelfDialogProbe()
        let model = ShelfModel(dialogs: probe.dialogs)

        await model.reload()
        await model.shelveAllChanges()
        let shelved = await model.shelve(files: [], name: "x")
        await model.unshelve(Self.ghost, keep: false)
        await model.rename(Self.ghost)
        await model.delete(Self.ghost)

        #expect(shelved == nil)
        #expect(model.shelves.isEmpty)
        #expect(!model.isLoaded)
        #expect(probe.promptTitles.isEmpty)
        #expect(probe.confirmMessages.isEmpty)
        #expect(probe.errors.isEmpty)
        #expect(probe.notifications.isEmpty)
    }

    @Test
    func selectionDependentOperationsAreNoOpsWithoutASelection() async throws {
        try await withTempDir { directory in
            let world = try await ShelfModelWorld.make(in: directory)

            await world.model.reload()
            await world.model.unshelveSelected(keep: false)
            await world.model.unshelveSelected(keep: true)
            await world.model.renameSelected()
            await world.model.deleteSelected()

            #expect(world.model.isLoaded)
            #expect(world.model.shelves.isEmpty)
            #expect(world.model.selectedShelf == nil)
            #expect(world.probe.promptTitles.isEmpty)
            #expect(world.probe.confirmMessages.isEmpty)
            #expect(world.probe.errors.isEmpty)
        }
    }

    @Test
    func shelvingAllChangesPromptsForANameAndSelectsTheNewShelf() async throws {
        try await withTempDir { directory in
            let world = try await ShelfModelWorld.make(in: directory)
            try await world.repo.makeMixedChanges()
            await world.manager.refreshAllChangedFiles()
            world.probe.promptAnswer = "My shelf"

            await world.model.shelveAllChanges()

            #expect(world.probe.promptTitles == ["Shelve Changes"])
            #expect(world.probe.promptInitials == [ShelfModel.defaultName])
            let shelf = try #require(world.model.shelves.first)
            #expect(world.model.shelves.count == 1)
            #expect(shelf.name == "My shelf")
            #expect(world.model.selectedHash == shelf.hash)
            #expect(shelf.files.map(\.path) == ["a.txt", "b.txt", "c.txt", "new.txt", "old.txt", "other.txt"])
            #expect(try world.repo.fixture.read("a.txt") == "a\n")
            #expect(try world.repo.fixture.read("old.txt") == "old\n")
            #expect(!world.repo.fixture.exists("other.txt"))
            #expect(world.probe.errors.isEmpty)
        }
    }

    @Test
    func cancellingTheNamePromptShelvesNothing() async throws {
        try await withTempDir { directory in
            let world = try await ShelfModelWorld.make(in: directory)
            try await world.repo.makeMixedChanges()
            await world.manager.refreshAllChangedFiles()
            world.probe.promptAnswer = nil

            await world.model.shelveAllChanges()

            #expect(world.model.shelves.isEmpty)
            #expect(try world.repo.fixture.read("a.txt") == "a2\n")
            #expect(try await world.repo.stashSubjects().isEmpty)
            #expect(world.probe.errors.isEmpty)
        }
    }

    @Test
    func shelvingWithoutChangesReportsAnError() async throws {
        try await withTempDir { directory in
            let world = try await ShelfModelWorld.make(in: directory)
            await world.manager.refreshAllChangedFiles()

            await world.model.shelveAllChanges()

            #expect(world.model.shelves.isEmpty)
            #expect(world.probe.errors.count == 1)
            #expect(world.probe.errors.first?.title == "Shelving failed")
            #expect(world.probe.errors.first?.message == GitShelfError.emptySelection.message)
        }
    }

    @Test
    func shelvingUnchangedFilesReportsNothingToShelve() async throws {
        try await withTempDir { directory in
            let world = try await ShelfModelWorld.make(in: directory)
            let unchanged = GitChangedFile(
                status: .modified,
                stagedStatus: .none,
                fileURL: world.manager.repositoryURL.appending(path: "a.txt"),
                originalFilename: nil
            )

            let shelf = await world.model.shelve(files: [unchanged], name: "x")

            #expect(shelf == nil)
            #expect(world.probe.errors.map(\.message) == [GitShelfError.nothingToShelve.message])
        }
    }

    @Test
    func unshelveSelectedRemovesTheShelfAndKeepVariantKeepsIt() async throws {
        try await withTempDir { directory in
            let world = try await ShelfModelWorld.make(in: directory)
            let first = try await world.shelveFile("a.txt", text: "a2\n", name: "first")
            #expect(world.model.selectedHash == first.hash)

            await world.model.unshelveSelected(keep: true)

            #expect(try world.repo.fixture.read("a.txt") == "a2\n")
            #expect(world.model.shelves.map(\.hash) == [first.hash])

            try await world.repo.fixture.run("checkout", "--", "a.txt")
            await world.model.unshelveSelected(keep: false)

            #expect(try world.repo.fixture.read("a.txt") == "a2\n")
            #expect(world.model.shelves.isEmpty)
            #expect(world.model.selectedShelf == nil)
            #expect(world.probe.conflictPresentations == 0)
            #expect(world.probe.errors.isEmpty)
            #expect(world.probe.notifications.isEmpty)
        }
    }

    @Test
    func unshelveWithConflictsPresentsTheMergeToolAndNotifies() async throws {
        try await withTempDir { directory in
            let world = try await ShelfModelWorld.make(in: directory)
            let shelf = try await world.makeConflictingShelf(name: "Conflicting")

            await world.model.unshelve(shelf, keep: false)

            #expect(world.probe.conflictPresentations == 1)
            #expect(world.probe.errors.isEmpty)
            #expect(world.model.shelves.map(\.hash) == [shelf.hash])
            #expect(world.manager.currentBranch?.name == "main")
            #expect(try await world.repo.fixture.unmergedPaths() == ["a.txt"])
            let notification = try #require(world.probe.notifications.first)
            #expect(world.probe.notifications.count == 1)
            #expect(notification.title == "Shelf 'Conflicting' unshelved with conflicts")
            #expect(notification.actionTitle == "Resolve Conflicts…")
            notification.action()
            #expect(world.probe.conflictPresentations == 2)
        }
    }

    @Test
    func unshelveFailuresShowAnErrorAndKeepTheShelf() async throws {
        try await withTempDir { directory in
            let world = try await ShelfModelWorld.make(in: directory)
            let shelf = try await world.shelveFile("new.txt", text: "shelved\n", name: "Untracked")
            try world.repo.fixture.write("new.txt", "in the way\n")

            await world.model.unshelve(shelf, keep: false)

            #expect(world.probe.errors.count == 1)
            #expect(world.probe.errors.first?.title == "Unshelve failed")
            #expect(world.probe.errors.first?.message.contains("new.txt") == true)
            #expect(world.model.shelves.map(\.hash) == [shelf.hash])
            #expect(world.probe.conflictPresentations == 0)
            #expect(try world.repo.fixture.read("new.txt") == "in the way\n")
        }
    }

    @Test
    func renamePromptsWithTheCurrentNameAndKeepsTheCommit() async throws {
        try await withTempDir { directory in
            let world = try await ShelfModelWorld.make(in: directory)
            let shelf = try await world.shelveFile("a.txt", text: "a2\n", name: "before")
            world.probe.promptAnswer = "after"

            await world.model.renameSelected()

            #expect(world.probe.promptTitles == ["Rename Shelf"])
            #expect(world.probe.promptInitials == ["before"])
            #expect(world.model.shelves.map(\.name) == ["after"])
            #expect(world.model.selectedHash == shelf.hash)
            #expect(try await world.repo.stashHashes() == [shelf.hash])

            world.probe.promptAnswer = nil
            let current = try #require(world.model.selectedShelf)
            await world.model.rename(current)

            #expect(world.model.shelves.map(\.name) == ["after"])
            #expect(world.probe.errors.isEmpty)
        }
    }

    @Test
    func renameFailureShowsAnErrorAndRefreshesTheList() async throws {
        try await withTempDir { directory in
            let world = try await ShelfModelWorld.make(in: directory)
            let shelf = try await world.shelveFile("a.txt", text: "a2\n", name: "before")
            try await world.repo.fixture.run("stash", "drop")

            await world.model.rename(shelf)

            #expect(world.probe.errors.map(\.title) == ["Rename failed"])
            #expect(world.probe.errors.map(\.message) == [GitShelfError.notFound.message])
            #expect(world.model.shelves.isEmpty)
        }
    }

    @Test
    func deleteAsksForConfirmationFirst() async throws {
        try await withTempDir { directory in
            let world = try await ShelfModelWorld.make(in: directory)
            let shelf = try await world.shelveFile("a.txt", text: "a2\n", name: "doomed")
            world.probe.confirmAnswer = false

            await world.model.deleteSelected()

            #expect(world.probe.confirmMessages.count == 1)
            #expect(world.probe.confirmMessages[0].contains("doomed"))
            #expect(world.model.shelves.map(\.hash) == [shelf.hash])
            #expect(try await world.repo.stashHashes() == [shelf.hash])

            world.probe.confirmAnswer = true
            await world.model.deleteSelected()

            #expect(world.probe.confirmMessages.count == 2)
            #expect(world.model.shelves.isEmpty)
            #expect(world.model.selectedHash == nil)
            #expect(try await world.repo.stashHashes().isEmpty)
            #expect(world.probe.errors.isEmpty)
        }
    }

    @Test
    func deleteFailureShowsAnError() async throws {
        try await withTempDir { directory in
            let world = try await ShelfModelWorld.make(in: directory)
            let shelf = try await world.shelveFile("a.txt", text: "a2\n", name: "gone")
            try await world.repo.fixture.run("stash", "drop")

            await world.model.delete(shelf)

            #expect(world.probe.errors.map(\.title) == ["Delete failed"])
            #expect(world.probe.errors.map(\.message) == [GitShelfError.notFound.message])
            #expect(world.model.shelves.isEmpty)
        }
    }

    @Test
    func reloadKeepsAValidSelectionAndFallsBackToTheFirstShelf() async throws {
        try await withTempDir { directory in
            let world = try await ShelfModelWorld.make(in: directory)
            let older = try await world.shelveFile("a.txt", text: "a2\n", name: "older")
            let newer = try await world.shelveFile("b.txt", text: "b2\n", name: "newer")
            #expect(world.model.shelves.map(\.hash) == [newer.hash, older.hash])

            world.model.selectedHash = older.hash
            await world.model.reload()
            #expect(world.model.selectedShelf?.hash == older.hash)

            world.model.selectedHash = "bogus"
            await world.model.reload()
            #expect(world.model.selectedHash == newer.hash)
        }
    }

    @Test
    func errorMessagesComeFromTheMostSpecificSource() {
        struct Plain: LocalizedError {
            var errorDescription: String? { "plain failure" }
        }

        #expect(ShelfModel.message(for: GitShelfError.notFound) == GitShelfError.notFound.message)
        #expect(ShelfModel.message(for: GitClient.GitClientError.outputError("boom")) == "boom")
        #expect(ShelfModel.message(for: Plain()) == "plain failure")
    }

    @Test
    func liveDialogsAreRoutedThroughTheSuppressedModalsAndNotifications() async throws {
        let live = ShelfDialogs.live
        let token = UUID().uuidString

        #expect(live.promptName("Prompt \(token)", "m", "initial") == nil)
        #expect(!live.confirm("Confirm \(token)", "m", "Go"))
        live.error("Error \(token)", "m")

        let modals = DreamderHeadless.suppressedModals
        #expect(modals.contains("Prompt \(token)"))
        #expect(modals.contains("Confirm \(token)"))
        #expect(modals.contains("Error \(token)"))

        live.notify(
            BranchesPopupNotificationRequest(
                title: "Shelf \(token)",
                description: "d",
                actionTitle: "Go",
                action: {}
            )
        )
        try await eventually { NotificationManager.shared.notifications.contains { $0.title == "Shelf \(token)" } }
    }

    @Test
    func reloadEmptiesTheListWhenTheRepositoryCannotBeListed() async throws {
        try await withTempDir { directory in
            let world = try await ShelfModelWorld.make(in: directory)
            _ = try await world.shelveFile("a.txt", text: "a2\n", name: "kept")
            #expect(world.model.shelves.count == 1)
            try FileManager.default.removeItem(at: directory.appending(path: ".git"))

            await world.model.reload()

            #expect(world.model.shelves.isEmpty)
            #expect(world.model.selectedHash == nil)
            #expect(world.model.isLoaded)
            #expect(world.probe.errors.isEmpty)
        }
    }

    @Test
    func selectingAShelfMakesItTheSelectedShelf() async throws {
        try await withTempDir { directory in
            let world = try await ShelfModelWorld.make(in: directory)
            let older = try await world.shelveFile("a.txt", text: "a2\n", name: "older")
            let newer = try await world.shelveFile("b.txt", text: "b2\n", name: "newer")
            #expect(world.model.selectedHash == older.hash)

            world.model.select(newer)

            #expect(world.model.selectedHash == newer.hash)
            #expect(world.model.selectedShelf?.name == "newer")

            world.model.select(older)

            #expect(world.model.selectedHash == older.hash)
            #expect(world.model.selectedShelf?.name == "older")
        }
    }

    @MainActor
    private final class OrderRecorder {
        var events: [String] = []
    }

    @Test
    func enqueuedOperationsRunOneAfterAnotherAndSettleWaitsForAllOfThem() async {
        let model = ShelfModel(dialogs: ShelfDialogProbe().dialogs)
        let recorder = OrderRecorder()

        model.enqueue { _ in
            recorder.events.append("first start")
            await Task.yield()
            await Task.yield()
            recorder.events.append("first end")
        }
        model.enqueue { _ in
            recorder.events.append("second start")
            recorder.events.append("second end")
        }
        await model.settle()

        #expect(recorder.events == ["first start", "first end", "second start", "second end"])
    }
}
