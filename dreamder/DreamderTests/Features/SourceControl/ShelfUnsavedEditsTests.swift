import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct ShelfUnsavedEditsTests {
    @MainActor
    private struct World {
        let repo: ShelfRepo
        let manager: SourceControlManager

        var root: URL { repo.fixture.root }

        func changedFiles(named paths: [String]) -> [GitChangedFile] {
            manager.changedFiles.filter {
                paths.contains(DiffPath.relativePath(of: $0.fileURL, from: manager.repositoryURL))
            }
        }

        func open(_ relativePath: String) throws -> CodeFileDocument {
            let url = root.appending(path: relativePath)
            let document = try CodeFileDocument(for: url, withContentsOf: url, ofType: "public.plain-text")
            NSDocumentController.shared.addDocument(document)
            return document
        }

        func edit(_ document: CodeFileDocument, to text: String) {
            document.content?.mutableString.setString(text)
            document.updateChangeCount(.changeDone)
        }
    }

    private func makeWorld(_ directory: URL) async throws -> World {
        let repo = try await ShelfRepo.make(in: directory)
        return World(repo: repo, manager: SourceControlManager(workspaceURL: directory, editorManager: EditorManager()))
    }

    private func closeDocuments(_ documents: CodeFileDocument...) {
        for document in documents {
            NSDocumentController.shared.removeDocument(document)
        }
    }

    @Test
    func shelvingRefusesWhenAFileInTheSelectionHasUnsavedEdits() async throws {
        try await withTempDir { directory in
            let world = try await makeWorld(directory)
            try world.repo.fixture.write("a.txt", "a2\n")
            await world.manager.refreshAllChangedFiles()
            let document = try world.open("a.txt")
            defer { closeDocuments(document) }
            world.edit(document, to: "typed in the editor\n")

            let error = await shelfThrownError {
                try await world.manager.shelveChanges(files: world.changedFiles(named: ["a.txt"]), name: "Typing")
            }

            #expect((error as? GitShelfError) == .unsavedChanges("a.txt"))
            #expect(try await world.repo.stashSubjects().isEmpty)
            #expect(try world.repo.fixture.read("a.txt") == "a2\n")
            #expect(document.content?.string == "typed in the editor\n")
            #expect(document.isDocumentEdited)
        }
    }

    @Test
    func shelvingIgnoresUnsavedEditsOutsideTheSelectionAndReloadsCleanDocuments() async throws {
        try await withTempDir { directory in
            let world = try await makeWorld(directory)
            try world.repo.fixture.write("a.txt", "a2\n")
            try world.repo.fixture.write("b.txt", "b2\n")
            await world.manager.refreshAllChangedFiles()
            let shelved = try world.open("a.txt")
            let untouched = try world.open("b.txt")
            defer { closeDocuments(shelved, untouched) }
            world.edit(untouched, to: "b typed\n")

            try await world.manager.shelveChanges(files: world.changedFiles(named: ["a.txt"]), name: "Only a")

            #expect(shelved.content?.string == "a\n")
            #expect(!shelved.isDocumentEdited)
            #expect(untouched.content?.string == "b typed\n")
            #expect(untouched.isDocumentEdited)
            #expect(try world.repo.fixture.read("b.txt") == "b2\n")
        }
    }

    @Test
    func unshelveRefusesWhenAShelvedFileHasUnsavedEditsAndAppliesNothing() async throws {
        try await withTempDir { directory in
            let world = try await makeWorld(directory)
            try world.repo.fixture.write("a.txt", "a2\n")
            await world.manager.refreshAllChangedFiles()
            let files = world.changedFiles(named: ["a.txt"])
            let shelf = try await world.manager.shelveChanges(files: files, name: "Shelf")
            let document = try world.open("a.txt")
            defer { closeDocuments(document) }
            world.edit(document, to: "typed after shelving\n")

            let error = await shelfThrownError { try await world.manager.unshelve(shelf, keep: false) }

            #expect((error as? GitShelfError) == .unsavedChanges("a.txt"))
            #expect(try await world.manager.shelfList().map(\.hash) == [shelf.hash])
            #expect(try world.repo.fixture.read("a.txt") == "a\n")
            #expect(document.content?.string == "typed after shelving\n")
            #expect(document.isDocumentEdited)
        }
    }

    @Test
    func aFailedUnshelveReloadsNoDocumentButStillRefreshesTheStatus() async throws {
        try await withTempDir { directory in
            let world = try await makeWorld(directory)
            try world.repo.fixture.write("new.txt", "shelved\n")
            await world.manager.refreshAllChangedFiles()
            let files = world.changedFiles(named: ["new.txt"])
            let shelf = try await world.manager.shelveChanges(files: files, name: "Untracked")
            try world.repo.fixture.write("new.txt", "in the way\n")
            let document = try world.open("new.txt")
            defer { closeDocuments(document) }
            document.content?.mutableString.setString("memory only\n")

            let error = await shelfThrownError { try await world.manager.unshelve(shelf, keep: false) }

            guard case .untrackedFileExists? = error as? GitShelfError else {
                Issue.record("expected an untracked collision, got \(String(describing: error))")
                return
            }
            #expect(document.content?.string == "memory only\n")
            #expect(!document.isDocumentEdited)
            try await eventually(timeout: .seconds(20)) {
                world.manager.changedFiles.map(\.fileURL.lastPathComponent) == ["new.txt"]
            }
            #expect(try await world.manager.shelfList().map(\.hash) == [shelf.hash])
        }
    }

    @Test
    func unsavedPathsAreMatchedByFileOrDirectoryPrefixAndSorted() async throws {
        try await withTempDir { directory in
            let world = try await makeWorld(directory)
            let guide = try world.open("docs/guide.md")
            let first = try world.open("a.txt")
            let clean = try world.open("b.txt")
            let untitled = CodeFileDocument()
            NSDocumentController.shared.addDocument(untitled)
            defer {
                closeDocuments(guide, first, clean, untitled)
            }
            world.edit(guide, to: "guide typed\n")
            world.edit(first, to: "a typed\n")
            world.edit(untitled, to: "scratch\n")
            let docs = world.root.appending(path: "docs")
            let aFile = world.root.appending(path: "a.txt")
            let sibling = world.root.appending(path: "doc")

            #expect(world.manager.unsavedOpenDocumentPaths(touchedBy: [docs]) == ["docs/guide.md"])
            #expect(world.manager.unsavedOpenDocumentPaths(touchedBy: [docs, aFile]) == ["a.txt", "docs/guide.md"])
            #expect(world.manager.unsavedOpenDocumentPaths(touchedBy: [aFile, aFile]) == ["a.txt"])
            #expect(world.manager.unsavedOpenDocumentPaths(touchedBy: [world.root.appending(path: "b.txt")]).isEmpty)
            #expect(world.manager.unsavedOpenDocumentPaths(touchedBy: [sibling]).isEmpty)
            #expect(world.manager.unsavedOpenDocumentPaths(touchedBy: []).isEmpty)
        }
    }

    @Test
    func reloadingUneditedDocumentsNeverClearsTheChangeCountOfAnEditedOne() async throws {
        try await withTempDir { directory in
            let world = try await makeWorld(directory)
            let edited = try world.open("a.txt")
            let clean = try world.open("b.txt")
            defer { closeDocuments(edited, clean) }
            world.edit(edited, to: "a typed\n")
            clean.content?.mutableString.setString("stale memory\n")

            world.manager.reloadUneditedOpenDocuments(touchedBy: [world.root])

            #expect(edited.content?.string == "a typed\n")
            #expect(edited.isDocumentEdited)
            #expect(clean.content?.string == "b\n")
            #expect(!clean.isDocumentEdited)
        }
    }

    @Test
    func theUnsavedChangesMessageListsTheFilesAndPromisesNothingChanged() {
        let error = GitShelfError.unsavedChanges("a.txt\ndocs/guide.md")

        #expect(error.message == """
        These files have unsaved changes in the editor:
        a.txt
        docs/guide.md

        Save or revert them first. Nothing was changed.
        """)
        #expect(ShelfModel.message(for: error) == error.message)
    }
}
