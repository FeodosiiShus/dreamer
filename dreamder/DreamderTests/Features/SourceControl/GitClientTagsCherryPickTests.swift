import Foundation
import Testing
@testable import Dreamder

@Suite
struct GitClientTagsCherryPickTests {
    private struct Repo {
        let fixture: GitMergeFixture
        let client: GitClient

        func hash(_ revision: String) async throws -> String {
            try await fixture.run("rev-parse", revision).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func commit(_ revision: String) async throws -> GitLogCommit {
            let line = try await fixture.run("rev-list", "--parents", "-n", "1", revision)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let hashes = line.split(separator: " ").map(String.init)
            let subject = try await fixture.run("log", "-1", "--format=%s", revision)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return GitLogCommit(
                hash: hashes[0],
                parents: Array(hashes.dropFirst()),
                authorName: "Merge",
                authorEmail: "merge@dreamder.test",
                date: Date(),
                refs: [],
                subject: subject
            )
        }

        func message(_ revision: String) async throws -> String {
            try await fixture.run("log", "-1", "--format=%B", revision)
        }

        func objectType(_ name: String) async throws -> String {
            try await fixture.run("cat-file", "-t", name).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func cherryPickHeadExists() async throws -> Bool {
            let output = try await fixture.runIgnoringFailure("rev-parse", "-q", "--verify", "CHERRY_PICK_HEAD")
            return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func makeRepo(_ directory: URL) async throws -> Repo {
        let fixture = try await GitMergeFixture(root: directory)
        try fixture.write("a.txt", "one\n")
        try await fixture.commit("initial")
        return Repo(fixture: fixture, client: GitClient(directoryURL: directory, shellClient: .live()))
    }

    private func makeFeatureRepo(_ directory: URL) async throws -> Repo {
        let repo = try await makeRepo(directory)
        try await repo.fixture.run("checkout", "-q", "-b", "feature")
        try repo.fixture.write("f.txt", "feature\n")
        try await repo.fixture.commit("add f")
        try await repo.fixture.run("checkout", "-q", "main")
        return repo
    }

    @Test
    func plainTagPointsAtTheGivenRevision() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            let first = try await repo.hash("HEAD")
            try repo.fixture.write("a.txt", "two\n")
            try await repo.fixture.commit("second")

            try await repo.client.createTag(name: "v1", at: first)

            #expect(try await repo.objectType("v1") == "commit")
            #expect(try await repo.hash("v1") == first)
        }
    }

    @Test
    func tagWithAMessageIsAnnotated() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            let head = try await repo.hash("HEAD")

            try await repo.client.createTag(name: "v2", at: head, message: "  release notes \n")

            #expect(try await repo.objectType("v2") == "tag")
            #expect(try await repo.fixture.run("tag", "-n1", "v2").contains("release notes"))
            #expect(try await repo.hash("v2^{commit}") == head)
        }
    }

    @Test
    func blankMessageCreatesAPlainTag() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)

            try await repo.client.createTag(name: "v3", at: try await repo.hash("HEAD"), message: "   ")

            #expect(try await repo.objectType("v3") == "commit")
        }
    }

    @Test
    func duplicateTagIsRejectedWithTheIntelliJMessage() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            let head = try await repo.hash("HEAD")
            try await repo.client.createTag(name: "v1", at: head)

            await #expect(throws: GitClient.GitClientError.outputError(GitClient.tagExistsMessage)) {
                try await repo.client.createTag(name: "v1", at: head)
            }
        }
    }

    @Test
    func forcedTagMovesAnExistingTag() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            let first = try await repo.hash("HEAD")
            try await repo.client.createTag(name: "v1", at: first)
            try repo.fixture.write("a.txt", "two\n")
            try await repo.fixture.commit("second")
            let second = try await repo.hash("HEAD")

            try await repo.client.createTag(name: "v1", at: second, force: true)

            #expect(try await repo.hash("v1") == second)
        }
    }

    @Test
    func invalidTagNamesAreRejected() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            let head = try await repo.hash("HEAD")
            for name in ["bad name", "a..b", "caret^", "", "ends."] {
                await #expect(throws: GitClient.GitClientError.outputError("'\(name)' is not a valid tag name.")) {
                    try await repo.client.createTag(name: name, at: head)
                }
            }
            #expect(try await repo.fixture.run("tag").isEmpty)
        }
    }

    @Test
    func tagOutsideARepositoryFails() async throws {
        try await withTempDir { directory in
            let client = GitClient(directoryURL: directory, shellClient: .live())
            await #expect(throws: GitClient.GitClientError.self) {
                try await client.createTag(name: "v1", at: "HEAD")
            }
        }
    }

    @Test
    func tagCreationFailsForAnUnknownRevision() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            await #expect(throws: GitClient.GitClientError.self) {
                try await repo.client.createTag(name: "v1", at: "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef")
            }
        }
    }

    @Test
    func cherryPickAppliesASingleCommit() async throws {
        try await withTempDir { directory in
            let repo = try await makeFeatureRepo(directory)
            let picked = try await repo.commit("feature")

            let outcome = try await repo.client.cherryPick(commit: picked, addSuffix: false)

            #expect(outcome == .success)
            #expect(try repo.fixture.read("f.txt") == "feature\n")
            #expect(try await repo.message("HEAD").hasPrefix("add f"))
            #expect(try await repo.message("HEAD").contains("cherry picked from commit") == false)
            #expect(try await repo.hash("HEAD") != picked.hash)
        }
    }

    @Test
    func cherryPickAddsTheSuffixWhenAsked() async throws {
        try await withTempDir { directory in
            let repo = try await makeFeatureRepo(directory)
            let picked = try await repo.commit("feature")

            let outcome = try await repo.client.cherryPick(commit: picked, addSuffix: true)

            #expect(outcome == .success)
            #expect(try await repo.message("HEAD").contains("(cherry picked from commit \(picked.hash))"))
        }
    }

    @Test
    func cherryPickOfAMergeCommitUsesTheFirstParentAsMainline() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            let base = try await repo.hash("HEAD")
            try await repo.fixture.run("checkout", "-q", "-b", "side")
            try repo.fixture.write("s.txt", "side\n")
            try await repo.fixture.commit("side work")
            try await repo.fixture.run("checkout", "-q", "main")
            try repo.fixture.write("m.txt", "main\n")
            try await repo.fixture.commit("main work")
            try await repo.fixture.run("merge", "-q", "--no-ff", "side", "-m", "Merge side")
            let merge = try await repo.commit("HEAD")
            #expect(merge.isMerge)
            try await repo.fixture.run("checkout", "-q", "-b", "target", base)

            let outcome = try await repo.client.cherryPick(commit: merge, addSuffix: false)

            #expect(outcome == .success)
            #expect(repo.fixture.exists("s.txt"))
            #expect(repo.fixture.exists("m.txt") == false)
        }
    }

    @Test
    func cherryPickOfTheSecondMainlineParentPicksTheOtherSide() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            let base = try await repo.hash("HEAD")
            try await repo.fixture.run("checkout", "-q", "-b", "side")
            try repo.fixture.write("s.txt", "side\n")
            try await repo.fixture.commit("side work")
            try await repo.fixture.run("checkout", "-q", "main")
            try repo.fixture.write("m.txt", "main\n")
            try await repo.fixture.commit("main work")
            try await repo.fixture.run("merge", "-q", "--no-ff", "side", "-m", "Merge side")
            let merge = try await repo.commit("HEAD")
            try await repo.fixture.run("checkout", "-q", "-b", "target", base)

            let outcome = try await repo.client.cherryPick(commit: merge, addSuffix: false, mainlineParent: 2)

            #expect(outcome == .success)
            #expect(repo.fixture.exists("m.txt"))
            #expect(repo.fixture.exists("s.txt") == false)
        }
    }

    @Test
    func cherryPickOfAnAlreadyAppliedChangeIsSkippedAsEmpty() async throws {
        try await withTempDir { directory in
            let repo = try await makeFeatureRepo(directory)
            let picked = try await repo.commit("feature")
            try repo.fixture.write("f.txt", "feature\n")
            try await repo.fixture.commit("same change on main")
            let head = try await repo.hash("HEAD")

            let outcome = try await repo.client.cherryPick(commit: picked, addSuffix: false)

            #expect(outcome == .empty)
            #expect(try await repo.hash("HEAD") == head)
            #expect(try await repo.cherryPickHeadExists() == false)
            #expect(await repo.client.branchOpsOperationState().hasOngoingOperation == false)
        }
    }

    @Test
    func conflictingCherryPickStopsWithConflictsAndKeepsTheState() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            try repo.fixture.write("src/main.swift", "line1\nline2\nline3\n")
            try await repo.fixture.commit("base")
            try await repo.fixture.run("checkout", "-q", "-b", "feature")
            try repo.fixture.write("src/main.swift", "line1\nfeature-line\nline3\n")
            try await repo.fixture.commit("feature edit")
            try await repo.fixture.run("checkout", "-q", "main")
            try repo.fixture.write("src/main.swift", "line1\nmain-line\nline3\n")
            try await repo.fixture.commit("main edit")
            let picked = try await repo.commit("feature")

            let outcome = try await repo.client.cherryPick(commit: picked, addSuffix: false)

            #expect(outcome == .conflicts)
            #expect(try await repo.cherryPickHeadExists())
            #expect(try await repo.fixture.unmergedPaths() == ["src/main.swift"])
            #expect(await repo.client.branchOpsOperationState().isCherryPicking)
        }
    }

    @Test
    func cherryPickIsRefusedWhileACherryPickIsInProgress() async throws {
        try await withTempDir { directory in
            let fixture = try await GitMergeFixture.cherryPickConflict(in: directory)
            let client = GitClient(directoryURL: directory, shellClient: .live())
            let feature = try await fixture.run("rev-parse", "feature").trimmingCharacters(in: .whitespacesAndNewlines)
            let commit = GitLogCommit(
                hash: feature,
                parents: [],
                authorName: "Merge",
                authorEmail: "merge@dreamder.test",
                date: Date(),
                refs: [],
                subject: "feature edit"
            )

            await #expect(throws: GitClient.GitClientError.outputError("Cannot cherry-pick during cherry-pick")) {
                _ = try await client.cherryPick(commit: commit, addSuffix: false)
            }
        }
    }

    @Test
    func cherryPickIsRefusedWhileAMergeIsInProgress() async throws {
        try await withTempDir { directory in
            let fixture = try await GitMergeFixture.mergeConflict(in: directory)
            let client = GitClient(directoryURL: directory, shellClient: .live())
            let head = try await fixture.run("rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
            let commit = GitLogCommit(
                hash: head,
                parents: [],
                authorName: "Merge",
                authorEmail: "merge@dreamder.test",
                date: Date(),
                refs: [],
                subject: "main changes"
            )

            await #expect(throws: GitClient.GitClientError.outputError("Cannot cherry-pick during merge")) {
                _ = try await client.cherryPick(commit: commit, addSuffix: false)
            }
        }
    }

    @Test
    func cherryPickIsRefusedWhileARebaseIsInProgress() async throws {
        try await withTempDir { directory in
            let fixture = try await GitMergeFixture.rebaseConflict(in: directory)
            let client = GitClient(directoryURL: directory, shellClient: .live())
            let main = try await fixture.run("rev-parse", "main").trimmingCharacters(in: .whitespacesAndNewlines)
            let commit = GitLogCommit(
                hash: main,
                parents: [],
                authorName: "Merge",
                authorEmail: "merge@dreamder.test",
                date: Date(),
                refs: [],
                subject: "main edit"
            )

            await #expect(throws: GitClient.GitClientError.outputError("Cannot cherry-pick during rebase")) {
                _ = try await client.cherryPick(commit: commit, addSuffix: false)
            }
        }
    }

    @Test
    func cherryPickOverLocalChangesFailsWithoutLeavingAState() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            try await repo.fixture.run("checkout", "-q", "-b", "feature")
            try repo.fixture.write("a.txt", "feature\n")
            try await repo.fixture.commit("feature edit")
            try await repo.fixture.run("checkout", "-q", "main")
            try repo.fixture.write("a.txt", "dirty\n")
            let picked = try await repo.commit("feature")

            await #expect(throws: GitClient.GitClientError.self) {
                _ = try await repo.client.cherryPick(commit: picked, addSuffix: false)
            }

            #expect(try await repo.cherryPickHeadExists() == false)
            #expect(try repo.fixture.read("a.txt") == "dirty\n")
        }
    }

    @Test
    func ongoingOperationNameDescribesEveryState() {
        #expect(GitBranchOperationState.none.ongoingOperationName == nil)
        #expect(GitBranchOperationState(isMerging: true).ongoingOperationName == "merge")
        #expect(GitBranchOperationState(isRebasing: true).ongoingOperationName == "rebase")
        #expect(GitBranchOperationState(isCherryPicking: true).ongoingOperationName == "cherry-pick")
        #expect(GitBranchOperationState(isReverting: true).ongoingOperationName == "revert")
    }

    @Test
    func commitIsPublishedOnlyWhenAProtectedRemoteBranchContainsIt() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            let published = try await repo.hash("HEAD")
            try await repo.fixture.run("update-ref", "refs/remotes/origin/main", "main")
            try repo.fixture.write("a.txt", "two\n")
            try await repo.fixture.commit("local only")
            let local = try await repo.hash("HEAD")
            try await repo.fixture.run("update-ref", "refs/remotes/origin/topic/work", "main")

            #expect(try await repo.client.isCommitPublished(published))
            #expect(try await repo.client.isCommitPublished(local) == false)
        }
    }

    @Test
    func commitOnAnUnprotectedRemoteBranchIsNotPublished() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            let head = try await repo.hash("HEAD")
            try await repo.fixture.run("update-ref", "refs/remotes/origin/topic", "main")

            #expect(try await repo.client.isCommitPublished(head) == false)
        }
    }

    @Test
    func publishedCheckFailsForAnUnknownCommit() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            await #expect(throws: GitClient.GitClientError.self) {
                _ = try await repo.client.isCommitPublished("deadbeefdeadbeefdeadbeefdeadbeefdeadbeef")
            }
        }
    }

    @Test
    func emptyCherryPickDetectionMatchesTheIntelliJMarkers() {
        func result(out: String = "", err: String = "") -> GitCommandResult {
            GitCommandResult(exitCode: 1, standardOutput: Data(out.utf8), standardError: Data(err.utf8))
        }
        #expect(GitClient.isEmptyCherryPick(result(out: "nothing to commit, working tree clean")))
        #expect(GitClient.isEmptyCherryPick(result(out: "nothing added to commit but untracked files present")))
        #expect(GitClient.isEmptyCherryPick(result(err: "The previous cherry-pick is now empty")))
        #expect(GitClient.isEmptyCherryPick(result(err: "CONFLICT (content)")) == false)
    }
}
