import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite
struct DiffRepositoryTests {
    private func repository(_ root: URL) throws -> DiffRepository {
        let document = WorkspaceDocument()
        document.sourceControlManager = SourceControlManager(workspaceURL: root, editorManager: EditorManager())
        return try #require(DiffRepository(workspace: document))
    }

    private func makeFixture(_ dir: URL) throws -> GitMergeFixture {
        let fixture = try GitMergeFixture(root: dir)
        try fixture.write("keep.txt", "keep\n")
        try fixture.write("edit.txt", "before\n")
        try fixture.write("remove.txt", "remove\n")
        try fixture.write("old-name.txt", "renamed content\nline two\nline three\n")
        try fixture.commit("base")
        return fixture
    }

    @Test
    func workspaceWithoutSourceControlHasNoRepository() {
        #expect(DiffRepository(workspace: WorkspaceDocument()) == nil)
    }

    @Test
    func workingTreeRequestsCoverEveryChangeKindSortedByPath() async throws {
        try await withTempDir { dir in
            let fixture = try makeFixture(dir)
            try fixture.write("edit.txt", "after\n")
            try fixture.run("rm", "-q", "remove.txt")
            try fixture.write("staged-new.txt", "new\n")
            try fixture.run("add", "staged-new.txt")
            try fixture.run("mv", "old-name.txt", "new-name.txt")
            try fixture.write("Untracked 10.txt", "u\n")
            try fixture.write("Untracked 9.txt", "u\n")

            let requests = try await repository(dir).workingTreeRequests(against: "HEAD")

            #expect(requests.map(\.path) == [
                "edit.txt", "new-name.txt", "remove.txt", "staged-new.txt", "Untracked 9.txt", "Untracked 10.txt"
            ])
            let byPath = Dictionary(uniqueKeysWithValues: requests.map { ($0.path, $0) })
            #expect(byPath["edit.txt"]?.status == .modified)
            #expect(byPath["edit.txt"]?.left == .history(ref: "HEAD", path: "edit.txt"))
            #expect(byPath["edit.txt"]?.right == .workingTree)
            #expect(byPath["remove.txt"]?.status == .deleted)
            #expect(byPath["remove.txt"]?.right == .missing)
            #expect(byPath["staged-new.txt"]?.status == .added)
            #expect(byPath["staged-new.txt"]?.left == .missing)
            #expect(byPath["Untracked 9.txt"]?.status == .untracked)
            #expect(byPath["new-name.txt"]?.status == .renamed)
            #expect(byPath["new-name.txt"]?.originalPath == "old-name.txt")
            #expect(byPath["new-name.txt"]?.left == .history(ref: "HEAD", path: "old-name.txt"))
        }
    }

    @Test
    func cleanTreeHasNoRequests() async throws {
        try await withTempDir { dir in
            _ = try makeFixture(dir)
            #expect(try await repository(dir).workingTreeRequests(against: "HEAD").isEmpty)
        }
    }

    @Test
    func loadReadsHistoryAndWorkingTreeSides() async throws {
        try await withTempDir { dir in
            let fixture = try makeFixture(dir)
            try fixture.write("edit.txt", "after\n")
            let repo = try repository(dir)
            let request = repo.workingTreeRequest(status: .modified, path: "edit.txt", originalPath: nil, ref: "HEAD")

            let content = await repo.load(request)

            #expect(content.left == .text("before\n"))
            #expect(content.right == .text("after\n"))
        }
    }

    @Test
    func loadMarksBinaryAndMissingSides() async throws {
        try await withTempDir { dir in
            let fixture = try makeFixture(dir)
            try Data([0x50, 0x4E, 0x47, 0x00, 0x01]).write(to: dir.appending(path: "image.bin"))
            try fixture.commit("binary")
            try Data([0x50, 0x4E, 0x47, 0x00, 0x02]).write(to: dir.appending(path: "image.bin"))
            let repo = try repository(dir)

            let binary = await repo.load(
                repo.workingTreeRequest(status: .modified, path: "image.bin", originalPath: nil, ref: "HEAD")
            )
            #expect(binary.left.isBinary)
            #expect(binary.right.isBinary)
            #expect(binary.left.stringValue == nil)

            let added = await repo.load(
                repo.workingTreeRequest(status: .untracked, path: "fresh.txt", originalPath: nil, ref: "HEAD")
            )
            #expect(added.left == .empty)
            #expect(added.right == .empty)
        }
    }

    @Test
    func commitRequestComparesAgainstParentOrNothingForRootCommit() async throws {
        try await withTempDir { dir in
            let fixture = try makeFixture(dir)
            let root = try fixture.run("rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
            try fixture.write("edit.txt", "after\n")
            try fixture.commit("second")
            let head = try fixture.run("rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
            let repo = try repository(dir)

            let change = repo.commitRequest(path: "edit.txt", status: .modified, commit: head, parent: root)
            let changeContent = await repo.load(change)
            #expect(changeContent.left == .text("before\n"))
            #expect(changeContent.right == .text("after\n"))

            let initial = repo.commitRequest(path: "keep.txt", status: .added, commit: root, parent: nil)
            #expect(initial.left == .missing)
            let initialContent = await repo.load(initial)
            #expect(initialContent.left == .empty)
            #expect(initialContent.right == .text("keep\n"))
        }
    }

    @Test
    func requestExposesFileNameAndDirectory() {
        let request = DiffFileRequest(path: "src/app/main.swift", status: .modified, left: .missing, right: .workingTree)
        #expect(request.fileName == "main.swift")
        #expect(request.directory == "src/app")
        #expect(request.id == "src/app/main.swift")
    }
}
