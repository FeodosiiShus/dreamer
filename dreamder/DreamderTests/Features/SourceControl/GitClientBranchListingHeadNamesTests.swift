import Foundation
import Testing
@testable import Dreamder

@Suite
struct GitClientBranchListingHeadNamesTests {
    private static let listing = [
        "main|refs/heads/main|origin/main [ahead 1]",
        "feature/HEAD-fix|refs/heads/feature/HEAD-fix| ",
        "HEADER|refs/heads/HEADER| ",
        "feature/HEAD|refs/heads/feature/HEAD| ",
        "(x)|refs/heads/(x)| ",
        "(HEAD detached at abc1234)|(HEAD detached at abc1234)| ",
        "(no branch, rebasing topic)|(no branch, rebasing topic)| ",
        "origin|refs/remotes/origin/HEAD| ",
        "origin/HEAD|refs/remotes/origin/HEAD| ",
        "origin/feature/HEAD-fix|refs/remotes/origin/feature/HEAD-fix| ",
        "origin/feature/HEAD|refs/remotes/origin/feature/HEAD| ",
        "upstream/dev|refs/remotes/upstream/dev| ",
        ""
    ].joined(separator: "\n")

    @Test
    func branchesThatMerelyContainHeadInTheirNameAreListed() async throws {
        let (client, _) = ScmFakeGit.client { _ in ScmFakeGit.ok(Self.listing) }

        let names = try await client.getBranches().map(\.name)

        #expect(names == [
            "main",
            "feature/HEAD-fix",
            "HEADER",
            "feature/HEAD",
            "(x)",
            "origin/feature/HEAD-fix",
            "origin/feature/HEAD",
            "upstream/dev"
        ])
    }

    @Test
    func remoteListingKeepsHeadNamedBranchesAndDropsOnlyTheSymbolicHead() async throws {
        let (client, _) = ScmFakeGit.client { _ in ScmFakeGit.ok(Self.listing) }

        let names = try await client.getBranches(remote: "origin").map(\.name)

        #expect(names == ["feature/HEAD-fix", "feature/HEAD"])
    }

    @Test(arguments: [
        ("refs/heads/main", true),
        ("refs/heads/feature/x", true),
        ("refs/heads/feature/HEAD", true),
        ("refs/remotes/origin/main", true),
        ("refs/remotes/origin/HEADER", true),
        ("refs/remotes/origin/feature/HEAD", true),
        ("refs/remotes/origin/HEAD", false),
        ("(HEAD", false),
        ("(HEAD detached at abc1234)", false),
        ("origin", false)
    ])
    func onlySymbolicRemoteHeadsAndPseudoEntriesAreFilteredOut(longName: String, isListed: Bool) {
        #expect(GitClient.isListedBranch(longName: longName) == isListed)
    }

    @Test
    func aRealRepositoryListsHeadNamedBranchesNextToTheirRemoteCounterparts() async throws {
        try await withTempDir { directory in
            let originRoot = directory.appending(path: "origin")
            try FileManager.default.createDirectory(at: originRoot, withIntermediateDirectories: true)
            let origin = try await GitMergeFixture(root: originRoot)
            try origin.write("a.txt", "one\n")
            try await origin.commit("initial")
            try await origin.run("branch", "feature/HEAD-fix")
            try await origin.run("branch", "HEADER")
            let cloneRoot = directory.appending(path: "clone")
            let originPath = originRoot.path(percentEncoded: false)
            try await origin.run("clone", "-q", originPath, cloneRoot.path(percentEncoded: false))
            let clone = GitMergeFixture(existing: cloneRoot)
            try await clone.run("branch", "feature/HEAD-fix")
            try await clone.run("branch", "HEADER")
            try await clone.run("checkout", "-q", "--detach")
            let client = GitClient(directoryURL: cloneRoot, shellClient: .live())

            let all = try await client.getBranches().map(\.name).sorted()
            let remote = try await client.getBranches(remote: "origin").map(\.name).sorted()

            #expect(all == [
                "HEADER",
                "feature/HEAD-fix",
                "main",
                "origin/HEADER",
                "origin/feature/HEAD-fix",
                "origin/main"
            ])
            #expect(remote == ["HEADER", "feature/HEAD-fix", "main"])
        }
    }
}
