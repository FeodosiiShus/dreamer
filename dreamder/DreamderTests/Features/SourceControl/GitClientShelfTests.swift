import Foundation
import Testing
@testable import Dreamder

@Suite
struct GitClientShelfTests {
    @Test
    func shelvesOnlyTheSelectedMixedChangesAndRevertsThem() async throws {
        try await withTempDir { dir in
            let repo = try await ShelfRepo.make(in: dir)
            try await repo.makeMixedChanges()

            let shelf = try await repo.client.shelve(paths: ShelfRepo.selectedPaths, name: "Subset")

            #expect(shelf.name == "Subset")
            #expect(shelf.index == 0)
            #expect(shelf.files == [
                GitShelfFile(status: .modified, path: "a.txt"),
                GitShelfFile(status: .modified, path: "b.txt"),
                GitShelfFile(status: .deleted, path: "c.txt"),
                GitShelfFile(status: .added, path: "new.txt")
            ])
            #expect(try repo.fixture.read("a.txt") == "a\n")
            #expect(try repo.fixture.read("b.txt") == "b\n")
            #expect(try repo.fixture.read("c.txt") == "c\n")
            #expect(!repo.fixture.exists("new.txt"))
            #expect(try repo.fixture.read("old.txt") == "old2\n")
            #expect(repo.fixture.exists("other.txt"))
            #expect(try await repo.fixture.stagedPaths().isEmpty)
            let subjects = try await repo.stashSubjects()
            #expect(subjects.count == 1)
            #expect(subjects[0].hasSuffix(GitShelf.marker + "Subset"))
        }
    }

    @Test
    func shelvesStagedNewFilesAndRenames() async throws {
        try await withTempDir { dir in
            let repo = try await ShelfRepo.make(in: dir)
            try repo.fixture.write("added.txt", "added\n")
            try await repo.fixture.run("add", "added.txt")
            try await repo.fixture.run("mv", "old.txt", "moved.txt")

            let shelf = try await repo.client.shelve(paths: ["added.txt", "moved.txt", "old.txt"], name: "Renamed")

            #expect(shelf.files == [
                GitShelfFile(status: .added, path: "added.txt"),
                GitShelfFile(status: .added, path: "moved.txt"),
                GitShelfFile(status: .deleted, path: "old.txt")
            ])
            #expect(try repo.fixture.read("old.txt") == "old\n")
            #expect(!repo.fixture.exists("moved.txt"))
            #expect(!repo.fixture.exists("added.txt"))
            #expect(try await repo.fixture.run("status", "--porcelain").isEmpty)
        }
    }

    @Test
    func pathspecsAreLiteral() async throws {
        try await withTempDir { dir in
            let repo = try await ShelfRepo.make(in: dir)
            try repo.fixture.write("a*.txt", "star\n")
            try await repo.fixture.commit("star")
            try repo.fixture.write("a*.txt", "star2\n")
            try repo.fixture.write("a.txt", "a2\n")

            let shelf = try await repo.client.shelve(paths: ["a*.txt"], name: "Star")

            #expect(shelf.files == [GitShelfFile(status: .modified, path: "a*.txt")])
            #expect(try repo.fixture.read("a*.txt") == "star\n")
            #expect(try repo.fixture.read("a.txt") == "a2\n")
        }
    }

    @Test
    func emptySelectionAndUnchangedFilesAreRejected() async throws {
        try await withTempDir { dir in
            let repo = try await ShelfRepo.make(in: dir)

            let empty = await shelfThrownError { try await repo.client.shelve(paths: [], name: "x") }
            let unchanged = await shelfThrownError { try await repo.client.shelve(paths: ["a.txt"], name: "x") }

            #expect((empty as? GitShelfError) == .emptySelection)
            #expect((unchanged as? GitShelfError) == .nothingToShelve)
            #expect(try await repo.stashSubjects().isEmpty)
        }
    }

    @Test
    func namesAreNormalized() async throws {
        try await withTempDir { dir in
            let repo = try await ShelfRepo.make(in: dir)
            try repo.fixture.write("a.txt", "a2\n")
            let blank = try await repo.client.shelve(paths: ["a.txt"], name: "  \n ")
            try repo.fixture.write("b.txt", "b2\n")
            let multiline = try await repo.client.shelve(paths: ["b.txt"], name: "first line\nsecond line")

            #expect(blank.name == GitShelf.unnamed)
            #expect(multiline.name == "first line second line")
            #expect(GitShelf.normalizedName("  padded  ") == "padded")
        }
    }

    @Test
    func listIsMostRecentFirstAndSkipsPlainStashes() async throws {
        try await withTempDir { dir in
            let repo = try await ShelfRepo.make(in: dir)
            try repo.fixture.write("a.txt", "a2\n")
            let first = try await repo.client.shelve(paths: ["a.txt"], name: "first")
            _ = try await repo.plainStash("docs/guide.md", "guide2\n", message: "plain stash")
            try repo.fixture.write("b.txt", "b2\n")
            let second = try await repo.client.shelve(paths: ["b.txt"], name: "second")

            let shelves = try await repo.client.shelfList()

            #expect(shelves.map(\.name) == ["second", "first"])
            #expect(shelves.map(\.index) == [0, 2])
            #expect(shelves.map(\.hash) == [second.hash, first.hash])
            #expect(shelves[0].files == [GitShelfFile(status: .modified, path: "b.txt")])
            #expect(shelves[1].files == [GitShelfFile(status: .modified, path: "a.txt")])
            #expect(shelves[0].date >= shelves[1].date)
            let stashes = try await repo.client.stashList()
            #expect(stashes.count == 3)
            #expect(stashes.filter { $0.message.hasPrefix(GitShelf.marker) }.count == 2)
            #expect(try await repo.client.shelf(hash: first.hash).name == "first")
        }
    }

    @Test
    func unshelveAppliesAndRemovesTheShelf() async throws {
        try await withTempDir { dir in
            let repo = try await ShelfRepo.make(in: dir)
            try await repo.makeMixedChanges()
            let shelf = try await repo.client.shelve(paths: ShelfRepo.selectedPaths, name: "Subset")

            let outcome = try await repo.client.unshelve(hash: shelf.hash, keep: false)

            #expect(outcome == .applied)
            #expect(try repo.fixture.read("a.txt") == "a2\n")
            #expect(try repo.fixture.read("b.txt") == "b2\n")
            #expect(!repo.fixture.exists("c.txt"))
            #expect(try repo.fixture.read("new.txt") == "new\n")
            #expect(try repo.fixture.read("old.txt") == "old2\n")
            #expect(try await repo.client.shelfList().isEmpty)
            #expect(try await repo.stashSubjects().isEmpty)
        }
    }

    @Test
    func unshelveKeepAppliesAndLeavesTheShelf() async throws {
        try await withTempDir { dir in
            let repo = try await ShelfRepo.make(in: dir)
            try await repo.makeMixedChanges()
            let shelf = try await repo.client.shelve(paths: ShelfRepo.selectedPaths, name: "Subset")

            let outcome = try await repo.client.unshelve(hash: shelf.hash, keep: true)

            #expect(outcome == .applied)
            #expect(try repo.fixture.read("a.txt") == "a2\n")
            #expect(try repo.fixture.read("new.txt") == "new\n")
            #expect(try await repo.client.shelfList().map(\.hash) == [shelf.hash])
        }
    }

    @Test
    func unshelveResolvesTheStashByHashAfterIndicesShift() async throws {
        try await withTempDir { dir in
            let repo = try await ShelfRepo.make(in: dir)
            try repo.fixture.write("a.txt", "a2\n")
            let shelf = try await repo.client.shelve(paths: ["a.txt"], name: "older")
            let plain = try await repo.plainStash("docs/guide.md", "guide2\n", message: "newer plain stash")
            #expect(try await repo.client.shelfReference(of: shelf.hash) == "stash@{1}")

            let outcome = try await repo.client.unshelve(hash: shelf.hash, keep: false)

            #expect(outcome == .applied)
            #expect(try repo.fixture.read("a.txt") == "a2\n")
            #expect(try await repo.client.shelfList().isEmpty)
            #expect(try await repo.stashHashes() == [plain])
            #expect(try repo.fixture.read("docs/guide.md") == "guide\n")
        }
    }

    @Test
    func unshelveWithConflictsKeepsTheShelfAndLeavesUnmergedPaths() async throws {
        try await withTempDir { dir in
            let repo = try await ShelfRepo.make(in: dir)
            try repo.fixture.write("a.txt", "shelved\n")
            let shelf = try await repo.client.shelve(paths: ["a.txt"], name: "Conflicting")
            try repo.fixture.write("a.txt", "committed\n")
            try await repo.fixture.commit("diverge")

            let outcome = try await repo.client.unshelve(hash: shelf.hash, keep: false)

            #expect(outcome == .conflicts)
            #expect(try await repo.fixture.unmergedPaths() == ["a.txt"])
            #expect(repo.fixture.hasConflictMarkers("a.txt"))
            #expect(try await repo.client.shelfList().map(\.hash) == [shelf.hash])
        }
    }

    @Test
    func unshelveRefusesToOverwriteAnExistingUntrackedFile() async throws {
        try await withTempDir { dir in
            let repo = try await ShelfRepo.make(in: dir)
            try repo.fixture.write("new.txt", "shelved\n")
            let shelf = try await repo.client.shelve(paths: ["new.txt"], name: "Untracked")
            try repo.fixture.write("new.txt", "in the way\n")

            let error = await shelfThrownError { try await repo.client.unshelve(hash: shelf.hash, keep: false) }

            guard case .untrackedFileExists(let detail)? = error as? GitShelfError else {
                Issue.record("expected an untracked collision, got \(String(describing: error))")
                return
            }
            #expect(detail.contains("new.txt"))
            #expect(try repo.fixture.read("new.txt") == "in the way\n")
            #expect(try await repo.client.shelfList().map(\.hash) == [shelf.hash])
        }
    }

    @Test
    func unshelveRefusesWhenLocalChangesWouldBeOverwritten() async throws {
        try await withTempDir { dir in
            let repo = try await ShelfRepo.make(in: dir)
            try repo.fixture.write("a.txt", "shelved\n")
            let shelf = try await repo.client.shelve(paths: ["a.txt"], name: "Overlapping")
            try repo.fixture.write("a.txt", "local edit\n")

            let error = await shelfThrownError { try await repo.client.unshelve(hash: shelf.hash, keep: false) }

            guard case .wouldOverwriteLocalChanges(let detail)? = error as? GitShelfError else {
                Issue.record("expected an overwrite refusal, got \(String(describing: error))")
                return
            }
            #expect(detail.contains("a.txt"))
            #expect(try repo.fixture.read("a.txt") == "local edit\n")
            #expect(try await repo.client.shelfList().map(\.hash) == [shelf.hash])
        }
    }

    @Test
    func renamePreservesTheStashCommitAndMovesTheEntryToTheTop() async throws {
        try await withTempDir { dir in
            let repo = try await ShelfRepo.make(in: dir)
            try repo.fixture.write("a.txt", "a2\n")
            let older = try await repo.client.shelve(paths: ["a.txt"], name: "older")
            try repo.fixture.write("b.txt", "b2\n")
            let newer = try await repo.client.shelve(paths: ["b.txt"], name: "newer")

            try await repo.client.renameShelf(hash: older.hash, to: "  renamed older ")

            let shelves = try await repo.client.shelfList()
            #expect(shelves.map(\.name) == ["renamed older", "newer"])
            #expect(shelves.map(\.hash) == [older.hash, newer.hash])
            #expect(shelves[0].files == older.files)
            #expect(shelves[0].date == older.date)
            #expect(try await repo.stashHashes() == [older.hash, newer.hash])
            let subjects = try await repo.stashSubjects()
            #expect(subjects[0] == "On main: " + GitShelf.marker + "renamed older")
        }
    }

    @Test
    func renameToTheSameNameIsANoOpAndBlankBecomesUnnamed() async throws {
        try await withTempDir { dir in
            let repo = try await ShelfRepo.make(in: dir)
            try repo.fixture.write("a.txt", "a2\n")
            let shelf = try await repo.client.shelve(paths: ["a.txt"], name: "same")
            let subjectsBefore = try await repo.stashSubjects()

            try await repo.client.renameShelf(hash: shelf.hash, to: "same")
            #expect(try await repo.stashSubjects() == subjectsBefore)

            try await repo.client.renameShelf(hash: shelf.hash, to: "   ")
            #expect(try await repo.client.shelfList().map(\.name) == [GitShelf.unnamed])
            #expect(try await repo.stashHashes() == [shelf.hash])
        }
    }

    @Test
    func deleteDropsOnlyTheResolvedShelf() async throws {
        try await withTempDir { dir in
            let repo = try await ShelfRepo.make(in: dir)
            try repo.fixture.write("a.txt", "a2\n")
            let shelf = try await repo.client.shelve(paths: ["a.txt"], name: "doomed")
            let plain = try await repo.plainStash("docs/guide.md", "guide2\n", message: "keep me")

            try await repo.client.deleteShelf(hash: shelf.hash)

            #expect(try await repo.client.shelfList().isEmpty)
            #expect(try await repo.stashHashes() == [plain])
            #expect(try repo.fixture.read("a.txt") == "a\n")
        }
    }

    @Test
    func unknownAndPlainStashesAreNotFound() async throws {
        try await withTempDir { dir in
            let repo = try await ShelfRepo.make(in: dir)
            let plain = try await repo.plainStash("docs/guide.md", "guide2\n", message: "plain")
            let missing = String(repeating: "0", count: 40)

            let unshelve = await shelfThrownError { try await repo.client.unshelve(hash: missing, keep: false) }
            let delete = await shelfThrownError { try await repo.client.deleteShelf(hash: missing) }
            let rename = await shelfThrownError { try await repo.client.renameShelf(hash: missing, to: "x") }
            let renamePlain = await shelfThrownError { try await repo.client.renameShelf(hash: plain, to: "x") }
            let lookup = await shelfThrownError { try await repo.client.shelf(hash: missing) }

            #expect((unshelve as? GitShelfError) == .notFound)
            #expect((delete as? GitShelfError) == .notFound)
            #expect((rename as? GitShelfError) == .notFound)
            #expect((renamePlain as? GitShelfError) == .notFound)
            #expect((lookup as? GitShelfError) == .notFound)
            #expect(try await repo.stashHashes() == [plain])
        }
    }

    @Test
    func applyingInTheMiddleOfAMergeSurfacesTheGitError() async throws {
        try await withTempDir { dir in
            let repo = try await ShelfRepo.make(in: dir)
            try repo.fixture.write("b.txt", "b2\n")
            let shelf = try await repo.client.shelve(paths: ["b.txt"], name: "Blocked")
            try await repo.fixture.run("checkout", "-q", "-b", "topic")
            try repo.fixture.write("a.txt", "topic\n")
            try await repo.fixture.commit("topic change")
            try await repo.fixture.run("checkout", "-q", "main")
            try repo.fixture.write("a.txt", "main\n")
            try await repo.fixture.commit("main change")
            _ = try await repo.fixture.runIgnoringFailure("merge", "topic")
            #expect(try await repo.fixture.unmergedPaths() == ["a.txt"])

            let error = await shelfThrownError { try await repo.client.unshelve(hash: shelf.hash, keep: false) }

            guard case .outputError(let text)? = error as? GitClient.GitClientError else {
                Issue.record("expected a git error, got \(String(describing: error))")
                return
            }
            #expect(!text.isEmpty)
            #expect(try repo.fixture.read("b.txt") == "b\n")
            #expect(try await repo.client.shelfList().map(\.hash) == [shelf.hash])
        }
    }

    @Test
    func errorClassificationReadsGitMessages() {
        let collision = GitShelfError.classify(
            applyFailure: "new.txt already exists, no checkout\nerror: could not restore untracked files from stash"
        )
        let restoreOnly = GitShelfError.classify(applyFailure: "error: could not restore untracked files from stash")
        let overwrite = GitShelfError.classify(
            applyFailure: "error: Your local changes to the following files would be overwritten by merge:\n\ta.txt\n\tdir/b.txt\nPlease commit"
        )
        let unknown = GitShelfError.classify(applyFailure: "fatal: something else")

        #expect(collision == .untrackedFileExists("new.txt already exists, no checkout\nerror: could not restore untracked files from stash"))
        #expect(restoreOnly == .untrackedFileExists("error: could not restore untracked files from stash"))
        #expect(overwrite == .wouldOverwriteLocalChanges("a.txt\ndir/b.txt"))
        #expect(unknown == nil)
    }

    @Test
    func errorMessagesDescribeEachCase() {
        #expect(GitShelfError.emptySelection.message == "No changes selected to shelve")
        #expect(GitShelfError.nothingToShelve.message == "The selected files have no local changes to shelve")
        #expect(GitShelfError.notFound.message == "The shelf no longer exists")
        #expect(GitShelfError.untrackedFileExists("x.txt").message.contains("x.txt"))
        #expect(GitShelfError.untrackedFileExists("x.txt").message.hasSuffix("The shelf was kept."))
        #expect(GitShelfError.wouldOverwriteLocalChanges("y.txt").message.contains("y.txt"))
        #expect(GitShelfError.wouldOverwriteLocalChanges("y.txt").message.hasSuffix("The shelf was kept."))
    }

    @Test
    func stashEntriesParseShelfSubjects() {
        let output = [
            "aaa\u{1f}100\u{1f}On main: \(GitShelf.marker)first: with colon",
            "bbb\u{1f}200\u{1f}WIP on main: abc subject",
            "ccc\u{1f}300\u{1f}no separator here",
            "broken line",
            "ddd\u{1f}notanumber\u{1f}On main: \(GitShelf.marker)bad date",
            "eee\u{1f}400\u{1f}On (no branch): \(GitShelf.marker)detached",
            ""
        ].joined(separator: "\n")

        let entries = GitShelfStashEntry.parse(output)

        #expect(entries.map(\.hash) == ["aaa", "bbb", "ccc", "eee"])
        #expect(entries.map(\.index) == [0, 1, 2, 5])
        #expect(entries[0].date == Date(timeIntervalSince1970: 100))
        #expect(entries[0].shelfParts?.name == "first: with colon")
        #expect(entries[0].shelfParts?.prefix == "On main: ")
        #expect(entries[1].shelfParts == nil)
        #expect(entries[2].shelfParts == nil)
        #expect(entries[3].shelfParts?.prefix == "On (no branch): ")
        #expect(entries[3].shelfParts?.name == "detached")
    }
}
