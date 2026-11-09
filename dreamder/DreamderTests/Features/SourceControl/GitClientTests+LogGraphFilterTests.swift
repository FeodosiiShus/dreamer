import Foundation
import Testing
@testable import Dreamder

extension GitClientTests {
    @Test
    func logGraphTextFilterMatchesTheMessage() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            try repo.fixture.write("a.txt", "two\n")
            try await repo.fixture.commit("second")
            try repo.fixture.write("a.txt", "three\n")
            try await repo.fixture.commit("third")

            let filters = GitLogFilterCollection(text: GitLogTextFilter.fromPattern("SECOND"))
            #expect(try await repo.client.logGraph(filters: filters).map(\.subject) == ["second"])

            let matchCase = GitLogFilterCollection(text: GitLogTextFilter.fromPattern("SECOND", isMatchCase: true))
            #expect(try await repo.client.logGraph(filters: matchCase).isEmpty)
        }
    }

    @Test
    func logGraphRegexTextFilterMatchesTheMessage() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            try repo.fixture.write("a.txt", "two\n")
            try await repo.fixture.commit("second")
            try repo.fixture.write("a.txt", "three\n")
            try await repo.fixture.commit("third")

            let filters = GitLogFilterCollection(
                text: GitLogTextFilter.fromPattern("^(sec|thi)", isRegexpAllowed: true)
            )
            #expect(try await repo.client.logGraph(filters: filters).map(\.subject) == ["third", "second"])
        }
    }

    @Test
    func logGraphNoMergesFilterDropsMergeCommits() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            try await repo.fixture.run("checkout", "-q", "-b", "feature")
            try repo.fixture.write("feature.txt", "f\n")
            try await repo.fixture.commit("feature work")
            try await repo.fixture.run("checkout", "-q", "main")
            try repo.fixture.write("main.txt", "m\n")
            try await repo.fixture.commit("main work")
            try await repo.fixture.run("merge", "-q", "--no-ff", "-m", "merge feature", "feature")

            let all = try await repo.client.logGraph()
            #expect(all.filter(\.isMerge).map(\.subject) == ["merge feature"])

            let noMerges = try await repo.client.logGraph(filters: GitLogFilterCollection(parent: .noMerges))
            #expect(noMerges.count == all.count - 1)
            #expect(noMerges.allSatisfy { !$0.isMerge })

            let onlyMerges = try await repo.client.logGraph(filters: GitLogFilterCollection(parent: .onlyMerges))
            #expect(onlyMerges.map(\.subject) == ["merge feature"])
        }
    }

    @Test
    func logGraphStructureFilterKeepsCommitsTouchingThePaths() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            try repo.fixture.write("other.txt", "x\n")
            try await repo.fixture.commit("add other")
            try repo.fixture.write("a.txt", "two\n")
            try await repo.fixture.commit("touch a")

            let filters = GitLogFilterCollection().settingPaths(from: "other.txt")
            #expect(try await repo.client.logGraph(filters: filters).map(\.subject) == ["add other"])

            let both = GitLogFilterCollection().settingPaths(from: "a.txt, other.txt")
            #expect(try await repo.client.logGraph(filters: both).map(\.subject) == ["touch a", "add other", "initial"])
        }
    }

    @Test
    func logGraphUserFilterResolvesNamesAgainstKnownAuthors() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            try repo.fixture.write("a.txt", "two\n")
            try await repo.fixture.run("add", "-A")
            try await repo.fixture.run(
                "-c", "user.name=Other Person", "-c", "user.email=other@dreamder.test",
                "commit", "-qm", "by other"
            )

            let everyone = try await repo.client.logGraph()
            let resolver = GitLogUserResolver(allUsers: GitLogUserResolver.users(of: everyone))

            let other = GitLogFilterCollection(user: GitLogUserFilter(userNames: ["Other Person"]))
            let byOther = try await repo.client.logGraph(filters: other, userResolver: resolver)
            #expect(byOther.map(\.subject) == ["by other"])

            let merge = GitLogFilterCollection(user: GitLogUserFilter(userNames: ["merge"]))
            let byMerge = try await repo.client.logGraph(filters: merge, userResolver: resolver)
            #expect(byMerge.map(\.subject) == ["initial"])
        }
    }

    @Test
    func logGraphUserFilterMatchesNothingWhenTheNameIsUnresolved() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            let filters = GitLogFilterCollection(user: GitLogUserFilter(userNames: ["nobody"]))
            #expect(try await repo.client.logGraph(filters: filters).isEmpty)
        }
    }

    @Test
    func logGraphFirstParentOptionSkipsMergedBranchCommits() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            try await repo.fixture.run("checkout", "-q", "-b", "feature")
            try repo.fixture.write("feature.txt", "f\n")
            try await repo.fixture.commit("feature work")
            try await repo.fixture.run("checkout", "-q", "main")
            try repo.fixture.write("main.txt", "m\n")
            try await repo.fixture.commit("main work")
            try await repo.fixture.run("merge", "-q", "--no-ff", "-m", "merge feature", "feature")

            var options = GitLogOptions()
            options.firstParent = true
            let filters = GitLogFilterCollection(branch: .fromBranch("main"))
            let commits = try await repo.client.logGraph(filters: filters, options: options)
            #expect(commits.map(\.subject) == ["merge feature", "main work", "initial"])
        }
    }

    @Test
    func logGraphCurrentUserReadsTheRepositoryConfig() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            let user = await repo.client.logGraphCurrentUser()
            #expect(user == GitLogUser(name: "Merge", email: "merge@dreamder.test"))
            #expect(user?.exactString == "Merge <merge@dreamder.test>")
        }
    }

    @Test
    func logGraphCurrentUserIsNilExactlyWhenNeitherNameNorEmailIsConfigured() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            try await repo.fixture.run("config", "--unset", "user.name")
            try await repo.fixture.run("config", "--unset", "user.email")
            let name: String? = try await repo.client.getConfig(key: "user.name")
            let email: String? = try await repo.client.getConfig(key: "user.email")

            let user = await repo.client.logGraphCurrentUser()

            #expect((user == nil) == (name == nil && email == nil))
        }
    }

    @Test
    func logGraphHeadIsResolvableOnlyOnceTheRepositoryHasACommit() async throws {
        try await withTempDir { directory in
            let fixture = try await GitMergeFixture(root: directory)
            let client = GitClient(directoryURL: directory, shellClient: .live())
            #expect(await client.logGraphHeadIsResolvable() == false)

            try fixture.write("a.txt", "one\n")
            try await fixture.commit("initial")
            #expect(await client.logGraphHeadIsResolvable())
        }
    }

    @Test
    func logGraphHeadIsNotResolvableOutsideARepository() async throws {
        try await withTempDir { directory in
            let client = GitClient(directoryURL: directory, shellClient: .live())
            #expect(await client.logGraphHeadIsResolvable() == false)
        }
    }

    @Test
    func logGraphHeadIsNotResolvableInAMissingDirectory() async throws {
        try await withTempDir { directory in
            let missing = directory.appending(path: "missing", directoryHint: .isDirectory)
            let client = GitClient(directoryURL: missing, shellClient: .live())
            #expect(await client.logGraphHeadIsResolvable() == false)
        }
    }

    @Test
    func unsyncedCommitCountsAreZeroWithoutAnUpstream() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            let counts = try await repo.client.numberOfUnsyncedCommits()
            #expect(counts.ahead == 0)
            #expect(counts.behind == 0)
        }
    }
}
