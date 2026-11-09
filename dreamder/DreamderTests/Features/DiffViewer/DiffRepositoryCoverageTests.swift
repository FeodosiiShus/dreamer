import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct DiffRepositoryCoverageTests {
    private func repository(_ root: URL) throws -> DiffRepository {
        let document = WorkspaceDocument()
        document.sourceControlManager = SourceControlManager(workspaceURL: root, editorManager: EditorManager())
        return try #require(DiffRepository(workspace: document))
    }

    private func makeFixture(_ dir: URL) async throws -> GitMergeFixture {
        let fixture = try await GitMergeFixture(root: dir)
        try fixture.write("keep.txt", "keep\n")
        try await fixture.commit("base")
        return fixture
    }

    @Test
    func nameStatusParserKeepsKnownStatusesAndRenamePairs() {
        let parsed = DiffRepository.parseNameStatus(
            "M\tedit.txt\nR100\told.txt\tnew.txt\nC75\tsource.txt\tcopy.txt\nD\tgone.txt\nT\ttype.txt\n"
        )

        #expect(parsed.map { $0.status } == [.modified, .renamed, .copied, .deleted, .fileTypeChange])
        #expect(parsed.map { $0.path } == ["edit.txt", "new.txt", "copy.txt", "gone.txt", "type.txt"])
        #expect(parsed.map { $0.originalPath } == [nil, "old.txt", "source.txt", nil, nil])
    }

    @Test
    func nameStatusParserSkipsMalformedLines() {
        #expect(DiffRepository.parseNameStatus("M").isEmpty)
        #expect(DiffRepository.parseNameStatus("X\tunknown.txt").isEmpty)
        #expect(DiffRepository.parseNameStatus(".\tnone.txt").isEmpty)
        #expect(DiffRepository.parseNameStatus("M\t").isEmpty)
        #expect(DiffRepository.parseNameStatus("").isEmpty)
    }

    @Test
    func workingTreeTextThatIsNotUTF8IsTreatedAsBinary() async throws {
        try await withTempDir { dir in
            _ = try await makeFixture(dir)
            try Data([0x41, 0xFF, 0xFE, 0x42]).write(to: dir.appending(path: "latin.txt"))
            let repo = try repository(dir)

            let content = await repo.load(
                repo.workingTreeRequest(status: .untracked, path: "latin.txt", originalPath: nil, ref: "HEAD")
            )

            #expect(content.left == .empty)
            #expect(content.right == .binary)
        }
    }

    @Test
    func historyPathThatDoesNotExistLoadsAsEmpty() async throws {
        try await withTempDir { dir in
            _ = try await makeFixture(dir)
            let repo = try repository(dir)

            let content = await repo.load(
                repo.workingTreeRequest(status: .modified, path: "never-existed.txt", originalPath: nil, ref: "HEAD")
            )

            #expect(content.left == .empty)
            #expect(content.right == .empty)
        }
    }

    @Test
    func historyEntryThatCannotBeShownLoadsAsBinary() async throws {
        try await withTempDir { dir in
            let fixture = try await makeFixture(dir)
            try await fixture.run(
                "update-index", "--add", "--cacheinfo", "160000,1111111111111111111111111111111111111111,vendored"
            )
            try await fixture.run("commit", "-qm", "gitlink")
            let repo = try repository(dir)

            let content = await repo.load(
                repo.workingTreeRequest(status: .modified, path: "vendored", originalPath: nil, ref: "HEAD")
            )

            #expect(content.left == .binary)
        }
    }

    @Test
    func workingTreeRequestsAgainstUnknownRefThrows() async throws {
        try await withTempDir { dir in
            _ = try await makeFixture(dir)
            let repo = try repository(dir)

            await #expect(throws: GitClient.GitClientError.self) {
                _ = try await repo.workingTreeRequests(against: "no-such-ref")
            }
        }
    }

    @Test
    func diffSideTextAccessors() {
        #expect(DiffSideText.text("a").stringValue == "a")
        #expect(DiffSideText.empty.stringValue == nil)
        #expect(DiffSideText.binary.stringValue == nil)
        #expect(DiffSideText.binary.isBinary)
        #expect(DiffSideText.empty.isBinary == false)
    }
}
