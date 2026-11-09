import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct MergeConflictRepositoryCoverageTests {
    private func repository(_ root: URL) -> MergeConflictRepository {
        MergeConflictRepository(
            gitClient: GitClient(directoryURL: root, shellClient: .live()),
            rootURL: root
        )
    }

    private func capturedError(_ body: () async throws -> Void) async -> Error? {
        do {
            try await body()
            return nil
        } catch {
            return error
        }
    }

    private func binaryConflict(in root: URL) async throws -> GitMergeFixture {
        let fixture = try await GitMergeFixture(root: root)
        try fixture.write("blob.bin", "base\u{0}data\n")
        try await fixture.commit("base")
        try await fixture.run("checkout", "-q", "-b", "feature")
        try fixture.write("blob.bin", "feature\u{0}data\n")
        try await fixture.commit("feature")
        try await fixture.run("checkout", "-q", "main")
        try fixture.write("blob.bin", "main\u{0}data\n")
        try await fixture.commit("main")
        _ = try await fixture.runIgnoringFailure("merge", "feature")
        return fixture
    }

    private func applyBackendRebaseConflict(in root: URL) async throws -> GitMergeFixture {
        let fixture = try await GitMergeFixture(root: root)
        try fixture.write("src/main.swift", "line1\nline2\nline3\n")
        try await fixture.commit("base")
        try await fixture.run("checkout", "-q", "-b", "feature")
        try fixture.write("src/main.swift", "line1\nfeature-line\nline3\n")
        try await fixture.commit("feature edit")
        try await fixture.run("checkout", "-q", "main")
        try fixture.write("src/main.swift", "line1\nmain-line\nline3\n")
        try await fixture.commit("main edit")
        try await fixture.run("checkout", "-q", "feature")
        _ = try await fixture.runIgnoringFailure("rebase", "--apply", "main")
        return fixture
    }

    private func rebaseOntoTaggedCommitConflict(in root: URL) async throws -> GitMergeFixture {
        let fixture = try await GitMergeFixture(root: root)
        try fixture.write("src/main.swift", "line1\nline2\nline3\n")
        try await fixture.commit("base")
        try await fixture.run("checkout", "-q", "-b", "feature")
        try fixture.write("src/main.swift", "line1\nfeature-line\nline3\n")
        try await fixture.commit("feature edit")
        try await fixture.run("checkout", "-q", "main")
        try fixture.write("src/main.swift", "line1\nmain-line\nline3\n")
        try await fixture.commit("main edit")
        let onto = try await fixture.run("rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
        try await fixture.run("tag", "v1", onto)
        try fixture.write("src/other.swift", "other\n")
        try await fixture.commit("main tip")
        try await fixture.run("checkout", "-q", "feature")
        _ = try await fixture.runIgnoringFailure("rebase", onto)
        return fixture
    }

    private func stashConflict(in root: URL) async throws -> GitMergeFixture {
        let fixture = try await GitMergeFixture(root: root)
        try fixture.write("f.txt", "line1\nline2\nline3\n")
        try await fixture.commit("base")
        try fixture.write("f.txt", "line1\nstash\nline3\n")
        try await fixture.run("stash", "-q")
        try fixture.write("f.txt", "line1\nmain\nline3\n")
        try await fixture.commit("main edit")
        _ = try await fixture.runIgnoringFailure("stash", "pop")
        return fixture
    }

    @Test
    func stageContentExposesItsTextAndBinaryFlag() {
        typealias Content = MergeConflictRepository.StageContent

        #expect(Content.text("abc").text == "abc")
        #expect(Content.missing.text.isEmpty)
        #expect(Content.binary.text.isEmpty)
        #expect(Content.binary.isBinary)
        #expect(Content.missing.isBinary == false)
        #expect(Content.text("x").isBinary == false)
    }

    @Test
    func revisionSetIsBinaryWhenAnyStageIsBinary() {
        typealias Content = MergeConflictRepository.StageContent
        typealias Revisions = MergeConflictRepository.RevisionSet
        let text = Content.text("a")

        #expect(Revisions(base: text, ours: text, theirs: text).isBinary == false)
        #expect(Revisions(base: .binary, ours: text, theirs: text).isBinary)
        #expect(Revisions(base: text, ours: .binary, theirs: text).isBinary)
        #expect(Revisions(base: text, ours: text, theirs: .binary).isBinary)
    }

    @Test
    func outsideARepositoryEverythingIsEmpty() async throws {
        try await withTempDir { dir in
            let repo = repository(dir)

            await #expect(throws: GitClient.GitClientError.notGitRepository) {
                try await repo.entries()
            }
            let context = await repo.context()
            #expect(context.operation == .unknown)
            #expect(context.yoursLabel == "HEAD")
            #expect(context.summary == "The following files have conflicts:")
            let revisions = await repo.revisions(for: "missing.txt")
            #expect(revisions == MergeConflictRepository.RevisionSet(base: .missing, ours: .missing, theirs: .missing))
        }
    }

    @Test
    func revisionsCarryTheTextOfEveryStage() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.mergeConflict(in: dir)

            let revisions = await repository(dir).revisions(for: "docs/notes.txt")

            #expect(revisions.base == .text("one\ntwo\nthree\n"))
            #expect(revisions.ours == .text("one\nnotes-main\nthree\n"))
            #expect(revisions.theirs == .text("one\nnotes-feature\nthree\n"))
            #expect(revisions.isBinary == false)
        }
    }

    @Test
    func aDeletedSideHasNoStage() async throws {
        try await withTempDir { dir in
            _ = try await GitMergeFixture.deleteModifyConflict(in: dir)

            let revisions = await repository(dir).revisions(for: "gone.txt")

            #expect(revisions.ours == .missing)
            #expect(revisions.base == .text("keep me\nsecond line\n"))
            #expect(revisions.theirs == .text("keep me\nmodified by feature\n"))
        }
    }

    @Test
    func binaryStagesAreRecognizedByTheirNulBytes() async throws {
        try await withTempDir { dir in
            _ = try await binaryConflict(in: dir)

            let revisions = await repository(dir).revisions(for: "blob.bin")

            #expect(revisions.base == .binary)
            #expect(revisions.ours == .binary)
            #expect(revisions.theirs == .binary)
            #expect(revisions.isBinary)
        }
    }

    @Test
    func applyBackendRebaseIsDetectedFromRebaseApplyFiles() async throws {
        try await withTempDir { dir in
            let fixture = try await applyBackendRebaseConflict(in: dir)
            try #require(fixture.exists(".git/rebase-apply"))

            let context = await repository(dir).context()

            #expect(context.operation == .rebase(branch: "feature", onto: "main"))
            #expect(context.swapsSides)
            #expect(context.summary == "Rebasing branch feature onto main")
        }
    }

    @Test
    func rebaseOntoATaggedCommitUsesTheTagName() async throws {
        try await withTempDir { dir in
            _ = try await rebaseOntoTaggedCommitConflict(in: dir)

            let context = await repository(dir).context()

            #expect(context.yoursLabel == "feature")
            #expect(context.theirsLabel.hasSuffix("v1"))
            #expect(context.theirsLabel.contains("~") == false)
            #expect(context.swapsSides)
        }
    }

    @Test
    func unresolvableMergeHeadYieldsAnUnknownOperation() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture(root: dir)
            try fixture.write("a.txt", "a\n")
            try await fixture.commit("base")
            let repo = repository(dir)

            try fixture.write(".git/MERGE_HEAD", "\n")
            #expect(await repo.context().operation == .unknown)

            try fixture.write(".git/MERGE_HEAD", "garbage\n")
            let context = await repo.context()
            #expect(context.operation == .unknown)
            #expect(context.yoursLabel == "main")
        }
    }

    @Test
    func stashPopConflictIsReportedAsUnstashing() async throws {
        try await withTempDir { dir in
            let fixture = try await stashConflict(in: dir)
            try #require(fixture.exists(".git/refs/stash"))
            let repo = repository(dir)

            let context = await repo.context()

            #expect(context.operation == .stash(branch: "main"))
            #expect(context.summary == "Conflicts during unstashing")
            #expect(context.swapsSides == false)
            #expect(try await repo.entries().map(\.path) == ["f.txt"])
        }
    }

    @Test
    func checkoutBasedAcceptFailsWhileTheIndexIsLocked() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.mergeConflict(in: dir)
            let repo = repository(dir)
            let context = await repo.context()
            let entry = try #require(try await repo.entries().first)
            try fixture.write(".git/index.lock", "")

            let failure = await capturedError {
                try await repo.accept(.theirs, entry: entry, context: context)
            }

            let error = try #require(failure)
            #expect(MergeToolErrorText.describe(error).isEmpty == false)
            #expect(try await fixture.unmergedPaths() == ["app/config.txt", "docs/notes.txt"])
        }
    }

    @Test
    func removalBasedAcceptFailsWhileTheIndexIsLocked() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.deleteModifyConflict(in: dir)
            let repo = repository(dir)
            let context = await repo.context()
            let entry = try #require(try await repo.entries().first)
            try fixture.write(".git/index.lock", "")

            let failure = await capturedError {
                try await repo.accept(.yours, entry: entry, context: context)
            }

            #expect(failure != nil)
            #expect(try await fixture.unmergedPaths() == ["gone.txt"])
        }
    }

    @Test
    func stagingAResultFailsWhenTheFileCannotBeWrittenOrAdded() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.mergeConflict(in: dir)
            let repo = repository(dir)

            let unwritable = await capturedError {
                try await repo.stageResult("text\n", path: "missing-directory/file.txt")
            }
            #expect(unwritable != nil)

            try fixture.write(".git/index.lock", "")
            let locked = await capturedError {
                try await repo.stageResult("text\n", path: "app/config.txt")
            }
            #expect(locked != nil)
            #expect(try fixture.read("app/config.txt") == "text\n")
        }
    }
}
