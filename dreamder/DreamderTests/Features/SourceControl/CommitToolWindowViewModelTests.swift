import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite
struct CommitToolWindowViewModelTests {
    private func makeRepo(_ dir: URL) async throws -> (GitMergeFixture, SourceControlManager) {
        let fixture = try await GitMergeFixture.offMain {
            let fixture = try GitMergeFixture(root: dir)
            try fixture.write("a.txt", "a\n")
            try fixture.write("b.txt", "b\n")
            try fixture.commit("initial")
            return fixture
        }
        return (fixture, SourceControlManager(workspaceURL: dir, editorManager: EditorManager()))
    }

    private func file(_ name: String, in manager: SourceControlManager) throws -> GitChangedFile {
        try #require(manager.changedFiles.first { $0.fileURL.lastPathComponent == name })
    }

    private func changedNames(_ manager: SourceControlManager) -> [String] {
        manager.changedFiles.map(\.fileURL.lastPathComponent).sorted()
    }

    private func headFiles(_ fixture: GitMergeFixture) throws -> [String] {
        try fixture.run("show", "--name-only", "--format=", "HEAD")
            .split(separator: "\n")
            .map(String.init)
            .sorted()
    }

    private func changed(_ status: GitStatus, staged: GitStatus = .none, _ path: String) -> GitChangedFile {
        GitChangedFile(
            status: status,
            stagedStatus: staged,
            fileURL: URL(fileURLWithPath: "/tmp/repo/\(path)"),
            originalFilename: nil
        )
    }

    @Test
    func canCommitNeedsMessageAndAnIncludedFile() {
        let model = CommitToolWindowViewModel()
        let files = [changed(.modified, "a.txt"), changed(.untracked, "b.txt")]
        #expect(model.canCommit(in: files) == false)

        model.message = "  \n "
        #expect(model.canCommit(in: files) == false)

        model.message = "Fix"
        #expect(model.canCommit(in: files))

        files.forEach { model.setIncluded(false, for: $0) }
        #expect(model.canCommit(in: files) == false)
        #expect(model.canCommit(in: []) == false)

        model.setIncluded(true, for: files[1])
        #expect(model.isIncluded(files[1]))
        #expect(model.canCommit(in: files))
    }

    @Test
    func unversionedMeansUntrackedAndNotStaged() {
        let model = CommitToolWindowViewModel()
        let untracked = changed(.untracked, "new.txt")
        let addedThenEdited = changed(.modified, staged: .added, "added.txt")
        let modified = changed(.modified, "mod.txt")
        let files = [untracked, addedThenEdited, modified]

        #expect(model.unversionedFiles(in: files) == [untracked])
        #expect(model.versionedFiles(in: files) == [addedThenEdited, modified])
    }

    @Test
    func unversionedFilesStartUncheckedLikeIntelliJ() {
        let model = CommitToolWindowViewModel()
        let untracked = changed(.untracked, "new.txt")
        let stagedNew = changed(.untracked, staged: .added, "staged.txt")
        let modified = changed(.modified, "mod.txt")

        #expect(model.isIncluded(untracked) == false)
        #expect(model.isIncluded(stagedNew))
        #expect(model.isIncluded(modified))

        model.message = "Add"
        #expect(model.canCommit(in: [untracked]) == false)
        model.setIncluded(true, for: untracked)
        #expect(model.canCommit(in: [untracked]))
        model.setIncluded(false, for: untracked)
        #expect(model.isIncluded(untracked) == false)
    }

    @Test
    func commitIncludesOnlyCheckedFilesAndUnstagesExcludedOnes() async throws {
        try await withTempDir { dir in
            let (fixture, manager) = try await makeRepo(dir)
            try fixture.write("a.txt", "a changed\n")
            try fixture.write("b.txt", "b changed\n")
            try fixture.run("add", "b.txt")
            try fixture.write("c.txt", "c\n")
            await manager.refreshAllChangedFiles()
            #expect(changedNames(manager) == ["a.txt", "b.txt", "c.txt"])

            let model = CommitToolWindowViewModel()
            model.setIncluded(false, for: try file("b.txt", in: manager))
            model.setIncluded(true, for: try file("c.txt", in: manager))
            let message = "Ship \"it\" for $HOME `now` \\ done"
            model.message = message
            await model.commit(using: manager, andPush: false)

            let subject = try fixture.run("log", "-1", "--format=%s").trimmingCharacters(in: .newlines)
            #expect(subject == message)
            #expect(try headFiles(fixture) == ["a.txt", "c.txt"])
            #expect(try fixture.stagedPaths().isEmpty)
            #expect(try fixture.read("b.txt") == "b changed\n")
            #expect(changedNames(manager) == ["b.txt"])
            #expect(model.message.isEmpty)
            #expect(model.excludedIDs.isEmpty)
            #expect(model.includedUnversionedIDs.isEmpty)
            #expect(model.isCommitting == false)
            #expect(manager.pushSheetIsPresented == false)
        }
    }

    @Test
    func amendRewritesTheLastCommitAndCommitAndPushOpensPush() async throws {
        try await withTempDir { dir in
            let (fixture, manager) = try await makeRepo(dir)
            try fixture.write("a.txt", "first\n")
            await manager.refreshAllChangedFiles()
            let model = CommitToolWindowViewModel()
            model.message = "First try"
            await model.commit(using: manager, andPush: false)

            try fixture.write("a.txt", "second\n")
            await manager.refreshAllChangedFiles()
            model.message = "Final"
            model.amend = true
            await model.commit(using: manager, andPush: true)

            let subjects = try fixture.run("log", "--format=%s").split(separator: "\n").map(String.init)
            #expect(subjects == ["Final", "initial"])
            #expect(try fixture.run("show", "HEAD:a.txt") == "second\n")
            #expect(model.amend == false)
            #expect(manager.pushSheetIsPresented)
        }
    }

    @Test
    func commitWithoutMessageDoesNothing() async throws {
        try await withTempDir { dir in
            let (fixture, manager) = try await makeRepo(dir)
            try fixture.write("a.txt", "changed\n")
            await manager.refreshAllChangedFiles()
            let model = CommitToolWindowViewModel()
            await model.commit(using: manager, andPush: true)

            #expect(try fixture.run("rev-list", "--count", "HEAD").trimmingCharacters(in: .newlines) == "1")
            #expect(manager.pushSheetIsPresented == false)
        }
    }

    @Test
    func rollbackRestoresModifiedAndRemovesNewFiles() async throws {
        try await withTempDir { dir in
            let (fixture, manager) = try await makeRepo(dir)
            try fixture.write("a.txt", "changed\n")
            try fixture.write("untracked.txt", "u\n")
            try fixture.write("staged.txt", "s\n")
            try fixture.run("add", "staged.txt")
            try fixture.run("rm", "-q", "b.txt")
            await manager.refreshAllChangedFiles()
            #expect(changedNames(manager) == ["a.txt", "b.txt", "staged.txt", "untracked.txt"])

            let model = CommitToolWindowViewModel()
            await model.rollback(manager.changedFiles, using: manager)

            #expect(try fixture.read("a.txt") == "a\n")
            #expect(try fixture.read("b.txt") == "b\n")
            #expect(fixture.exists("untracked.txt") == false)
            #expect(fixture.exists("staged.txt") == false)
            #expect(try fixture.stagedPaths().isEmpty)
            #expect(manager.changedFiles.isEmpty)
        }
    }
}
