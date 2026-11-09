import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
extension ShelfViewCoverage {
    @Test
    func rowMenuOffersAndRunsEveryShelfAction() async throws {
        try await withTempDir { directory in
            let session = try await makeSession(directory)
            defer { session.close() }
            try session.repo.fixture.write("a.txt", "a2\n")
            let shelf = try await session.shelve(["a.txt"], name: "menu")
            let menu = session.rowMenu(for: shelf)
            defer { menu.close() }

            #expect(menu.titles == ["Unshelve", "Unshelve and Keep", "Rename…", "Delete"])
            #expect(menu.enabledStates == [true, true, true, true])

            try menu.click(titled: "Unshelve and Keep")
            await session.model.settle()
            #expect(session.probe.errors.isEmpty)
            #expect(session.text("a.txt") == "a2\n")
            #expect(session.model.shelves.map(\.hash) == [shelf.hash])
            try await session.repo.fixture.run("checkout", "--", "a.txt")

            session.probe.confirmAnswer = false
            try menu.click(titled: "Delete")
            await session.model.settle()
            #expect(session.probe.confirmMessages.count == 1)
            #expect(session.model.shelves.map(\.hash) == [shelf.hash])

            try menu.click(titled: "Unshelve")
            await session.model.settle()
            #expect(session.model.shelves.isEmpty)
            #expect(try session.repo.fixture.read("a.txt") == "a2\n")
        }
    }

    @Test
    func rowMenuDeleteRemovesTheShelfAfterConfirmation() async throws {
        try await withTempDir { directory in
            let session = try await makeSession(directory)
            defer { session.close() }
            try session.repo.fixture.write("a.txt", "a2\n")
            let shelf = try await session.shelve(["a.txt"], name: "menu")
            let menu = session.rowMenu(for: shelf)
            defer { menu.close() }
            session.probe.confirmAnswer = true

            try menu.click(titled: "Delete")

            await session.model.settle()
            #expect(session.model.shelves.isEmpty)
            #expect(try await session.repo.stashHashes().isEmpty)
        }
    }

    @Test
    func rowMenuRenameAsksForTheNewName() async throws {
        try await withTempDir { directory in
            let session = try await makeSession(directory)
            defer { session.close() }
            try session.repo.fixture.write("a.txt", "a2\n")
            let shelf = try await session.shelve(["a.txt"], name: "menu")
            let menu = session.rowMenu(for: shelf)
            defer { menu.close() }
            session.probe.promptAnswer = "renamed"

            try menu.click(titled: "Rename…")

            await session.model.settle()
            #expect(session.probe.errors.isEmpty)
            #expect(session.model.shelves.first?.name == "renamed")
            #expect(session.probe.promptInitials == ["menu"])
        }
    }

    @Test
    func contextMenuOffersTheShelfActionsForTheClickedRow() async throws {
        try await withTempDir { directory in
            let session = try await makeSession(directory)
            defer { session.close() }
            try session.repo.fixture.write("a.txt", "a2\n")
            let older = try await session.shelve(["a.txt"], name: "older")
            try session.repo.fixture.write("b.txt", "b2\n")
            let newer = try await session.shelve(["b.txt"], name: "newer")
            #expect(session.model.shelves.map(\.hash) == [newer.hash, older.hash])

            let rowItems = try session.input.contextMenu(at: session.rowPoint(1)).items
            let titles = rowItems.map(\.title).filter { !$0.isEmpty }
            #expect(titles == ["Unshelve", "Unshelve and Keep", "Rename…", "Delete"])

            let (keepMenu, keepIndex) = try session.menuIndex("Unshelve and Keep", row: 1)
            keepMenu.performActionForItem(at: keepIndex)
            await session.model.settle()
            #expect(session.probe.errors.isEmpty)
            #expect(session.text("a.txt") == "a2\n")
            #expect(session.model.shelves.count == 2)
            try await session.repo.fixture.run("checkout", "--", "a.txt")

            session.probe.promptAnswer = "newest"
            let (renameMenu, renameIndex) = try session.menuIndex("Rename…", row: 0)
            renameMenu.performActionForItem(at: renameIndex)
            await session.model.settle()
            #expect(session.probe.errors.isEmpty)
            #expect(session.model.shelves.first?.name == "newest")

            let (unshelveMenu, unshelveIndex) = try session.menuIndex("Unshelve", row: 1)
            unshelveMenu.performActionForItem(at: unshelveIndex)
            await session.model.settle()
            #expect(session.model.shelves.map(\.hash) == [newer.hash])
            #expect(try session.repo.fixture.read("a.txt") == "a2\n")

            session.probe.confirmAnswer = true
            let (deleteMenu, deleteIndex) = try session.menuIndex("Delete", row: 0)
            deleteMenu.performActionForItem(at: deleteIndex)
            await session.model.settle()
            #expect(session.model.shelves.isEmpty)
            #expect(try await session.repo.stashHashes().isEmpty)
        }
    }

    @Test
    func stashChangesMadeElsewhereReloadTheList() async throws {
        try await withTempDir { directory in
            let session = try await makeSession(directory)
            defer { session.close() }
            try session.repo.fixture.write("a.txt", "a2\n")
            let shelf = try await session.repo.client.shelve(paths: ["a.txt"], name: "external")
            #expect(session.model.shelves.isEmpty)

            try await session.manager.refreshStashEntries()

            try await eventually { session.model.shelves.map(\.hash) == [shelf.hash] }
            #expect(session.model.selectedHash == shelf.hash)
        }
    }

    @Test
    func toolbarMethodsQueueTheShelfOperationsInOrder() async throws {
        try await withTempDir { directory in
            let session = try await makeSession(directory)
            defer { session.close() }
            let view = ShelfView(model: session.model)
            try await session.repo.makeMixedChanges()
            await session.manager.refreshAllChangedFiles()
            session.probe.promptAnswer = "Queued"

            view.queueShelveAll()
            await session.model.settle()
            #expect(session.model.shelves.map(\.name) == ["Queued"])
            #expect(try session.repo.fixture.read("a.txt") == "a\n")

            view.queueUnshelveKeeping()
            await session.model.settle()
            #expect(session.probe.errors.isEmpty)
            #expect(session.text("a.txt") == "a2\n")
            #expect(session.model.shelves.count == 1)
            try await session.repo.fixture.run("reset", "--hard", "-q")
            try await session.repo.fixture.run("clean", "-fdq")

            session.probe.promptAnswer = "Renamed"
            view.queueRename()
            await session.model.settle()
            #expect(session.model.shelves.map(\.name) == ["Renamed"])

            view.queueUnshelve()
            await session.model.settle()
            #expect(session.model.shelves.isEmpty)
            #expect(try session.repo.fixture.read("a.txt") == "a2\n")

            _ = try await session.shelve(["a.txt"], name: "doomed")
            session.probe.confirmAnswer = true
            view.queueDelete()
            await session.model.settle()
            #expect(session.model.shelves.isEmpty)
            #expect(try await session.repo.stashHashes().isEmpty)
        }
    }

    @Test
    func rowHandlersTrackHoverAndSelectTheirShelf() async throws {
        try await withTempDir { directory in
            let session = try await makeSession(directory)
            defer { session.close() }
            try session.repo.fixture.write("a.txt", "a2\n")
            let first = try await session.shelve(["a.txt"], name: "first")
            try session.repo.fixture.write("b.txt", "b2\n")
            let second = try await session.shelve(["b.txt"], name: "second")
            #expect(session.model.selectedHash == first.hash)
            let row = ShelfRow(shelf: second, model: session.model)

            row.setHovering(true)
            row.setHovering(false)
            row.select()

            #expect(session.model.selectedHash == second.hash)
        }
    }
}
