import Foundation
import Testing
@testable import Dreamder

extension GitClientTests {
    @Test
    func checkingOutALocalBranchSwitchesAndAFailedCheckoutThrows() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            try await repo.fixture.run("checkout", "-q", "-b", "other")
            try repo.fixture.write("a.txt", "other side\n")
            try await repo.fixture.commit("other edits a")
            try await repo.fixture.run("checkout", "-q", "main")
            let other = GitBranch(name: "other", longName: "refs/heads/other", upstream: nil, ahead: 0, behind: 0)

            try repo.fixture.write("a.txt", "local edit\n")
            await #expect(throws: GitClient.GitClientError.self) { try await repo.client.checkoutBranch(other) }
            #expect(
                try await repo.fixture.run("rev-parse", "--abbrev-ref", "HEAD")
                    .trimmingCharacters(in: .newlines) == "main"
            )

            try await repo.fixture.run("checkout", "--", "a.txt")
            try await repo.client.checkoutBranch(other)
            #expect(
                try await repo.fixture.run("rev-parse", "--abbrev-ref", "HEAD")
                    .trimmingCharacters(in: .newlines) == "other"
            )
        }
    }

    @Test(arguments: [
        ("[ahead 2, behind 3]", 2, 3),
        ("[ahead 4]", 4, 0),
        ("[behind 5]", 0, 5),
        ("[gone]", 0, 0),
        ("", 0, 0),
        ("[ahead x]", 0, 0),
        ("[ahead 1, behind ]", 1, 0),
        ("ahead 2", 0, 0),
        ("[behind 1", 0, 0),
        ("]ahead 1[", 0, 0),
        ("[ahead 12, behind 345]", 12, 345),
        ("[other 3]", 0, 0)
    ])
    func trackInfoParsing(input: String, ahead: Int, behind: Int) {
        let parsed = GitClient.parseBranchTrackInfo(from: input)
        #expect(parsed.ahead == ahead)
        #expect(parsed.behind == behind)
    }

    @Test
    func commitChangedFilesHandlePathsThatAreNotValidURLs() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            try repo.fixture.write("dir/with space & ünï.txt", "x\n")
            try repo.fixture.write("a.txt", "two\n")
            try await repo.fixture.commit("second")
            let sha = try await repo.fixture.run("rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)

            let files = try await repo.client.getCommitChangedFiles(commitSHA: sha)

            #expect(files.map { $0.fileURL.lastPathComponent }.sorted() == ["a.txt", "with space & ünï.txt"])
            let added = try #require(files.first { $0.fileURL.lastPathComponent.hasPrefix("with") })
            #expect(added.status == .added)
            let addedPath = added.fileURL.path(percentEncoded: false)
            let expectedPath = directory.appending(path: "dir/with space & ünï.txt").path(percentEncoded: false)
            #expect(addedPath == expectedPath)
        }
    }

    @Test
    func commitChangedFilesFailLoudlyForUnknownCommits() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            await #expect(throws: GitClient.GitClientError.self) {
                try await repo.client.getCommitChangedFiles(commitSHA: "0123456789abcdef0123456789abcdef01234567")
            }
        }
    }

    @Test
    func commitHistoryUsesAuthorTimestampsAndFilters() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            try repo.fixture.write("a.txt", "two\n")
            try await repo.fixture.commit("second | pipes")
            try repo.fixture.write("other.txt", "x\n")
            try await repo.fixture.commit("third")

            let all = try await repo.client.getCommitHistory()
            #expect(all.map(\.message) == ["third", "second | pipes", "initial"])
            #expect(all.allSatisfy { abs($0.date.timeIntervalSinceNow) < 300 })
            #expect(all.allSatisfy { $0.hash.count >= 7 && $0.commitHash.count == 40 })
            #expect(all.first?.author == "Merge")
            #expect(all.first?.authorEmail == "merge@dreamder.test")

            #expect(try await repo.client.getCommitHistory(maxCount: 1).count == 1)
            #expect(try await repo.client.getCommitHistory(fileLocalPath: "a.txt").count == 2)
            #expect(
                try await repo.client.getCommitHistory(
                    branchName: "main",
                    fileLocalPath: "no \"such\" file.txt"
                ).isEmpty
            )
        }
    }

    @Test
    func logGraphParsesRealCommitsAndLimitsThem() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            try repo.fixture.write("a.txt", "two\n")
            try await repo.fixture.commit("second")

            let commits = try await repo.client.logGraph()
            try #require(commits.count == 2)
            #expect(commits.map(\.subject) == ["second", "initial"])
            #expect(commits[0].parents == [commits[1].hash])
            #expect(commits[1].parents.isEmpty)
            #expect(commits[0].message == "second")
            #expect(commits[0].authorName == "Merge")
            #expect(commits[0].authorEmail == "merge@dreamder.test")
            #expect(abs(commits[0].commitDate.timeIntervalSinceNow) < 300)
            #expect(
                try await repo.client.logGraph(
                    filters: GitLogFilterCollection(branch: .fromBranch("main")),
                    limit: 1
                ).count == 1
            )

            #expect(try await repo.client.logGraphMessage(hash: commits[0].hash) == "second")
            let changed = try await repo.client.logGraphChangedFiles(commit: commits[0])
            #expect(changed.map { $0.fileURL.lastPathComponent } == ["a.txt"])
            let root = try await repo.client.logGraphChangedFiles(commit: commits[1])
            #expect(root.map { $0.fileURL.lastPathComponent } == ["a.txt"])
        }
    }

    @Test
    func logGraphKeepsTheFullMessageBody() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            try repo.fixture.write("a.txt", "two\n")
            try await repo.fixture.commit("second\n\nbody line")

            let commit = try #require(try await repo.client.logGraph(limit: 1).first)
            #expect(commit.subject == "second")
            #expect(commit.message == "second\n\nbody line")
        }
    }

    @Test
    func logGraphClassifiesSlashedLocalBranchesAndRemotesFromFullRefNames() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            try await repo.fixture.run("branch", "feature/login")
            try await repo.fixture.run("update-ref", "refs/remotes/origin/main", "HEAD")
            try await repo.fixture.run("tag", "v1")

            let refs = try #require(try await repo.client.logGraph().first).refs

            #expect(Set(refs) == [
                GitLogRef(name: "main", kind: .head),
                GitLogRef(name: "feature/login", kind: .branch),
                GitLogRef(name: "origin/main", kind: .remote),
                GitLogRef(name: "v1", kind: .tag)
            ])
        }
    }

    @Test
    func currentBranchOfADetachedHeadIsNil() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            try await repo.fixture.run("checkout", "-q", "--detach")

            #expect(try await repo.client.getCurrentBranch() == nil)
        }
    }

    @Test
    func logGraphOfAnUnbornRepositoryIsEmpty() async throws {
        try await withTempDir { directory in
            _ = try await GitMergeFixture(root: directory)
            let client = GitClient(directoryURL: directory, shellClient: .live())
            #expect(try await client.logGraph().isEmpty)
            #expect(await client.logGraphHeadIsResolvable() == false)
        }
    }

    @Test
    func logGraphBranchFilterOfAnUnknownBranchMatchesNothing() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            let filters = GitLogFilterCollection(branch: .fromBranch("no-such-branch"))
            #expect(try await repo.client.logGraph(filters: filters).isEmpty)
        }
    }

    @Test
    func logGraphBranchFilterOfAnUnbornRepositoryMatchesNothing() async throws {
        try await withTempDir { directory in
            _ = try await GitMergeFixture(root: directory)
            let client = GitClient(directoryURL: directory, shellClient: .live())
            #expect(try await client.logGraph(filters: GitLogFilterCollection(branch: .fromBranch("main"))).isEmpty)
        }
    }
}
