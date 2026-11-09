import Foundation
import Testing
@testable import Dreamder

extension GitClientFakeRunnerCoverage {
    @Test
    func branchListingParsesTrackInformationAndFiltersByRemote() async throws {
        let output = [
            "main|refs/heads/main|origin/main [ahead 1, behind 2]",
            "feature|refs/heads/feature| ",
            "origin/HEAD|refs/remotes/origin/HEAD| ",
            "origin/main|refs/remotes/origin/main| ",
            "upstream/dev|refs/remotes/upstream/dev| ",
            ""
        ].joined(separator: "\n")
        let (client, fake) = ScmFakeGit.client { _ in ScmFakeGit.ok(output) }

        let all = try await client.getBranches()
        #expect(all.map(\.name) == ["main", "feature", "origin/main", "upstream/dev"])
        #expect(all[0] == GitBranch(
            name: "main",
            longName: "refs/heads/main",
            upstream: "origin/main",
            ahead: 1,
            behind: 2
        ))
        #expect(all[1].upstream == nil)

        let remote = try await client.getBranches(remote: "origin")
        #expect(remote.map(\.name) == ["main"])

        let remoteOnly = ScmFakeGit.client { _ in
            ScmFakeGit.ok([
                "origin/HEAD|refs/remotes/origin/HEAD| \n",
                "origin/dev|refs/remotes/origin/dev| \n",
                "upstream/x|refs/remotes/upstream/x| \n"
            ].joined())
        }.client
        let listed = try await remoteOnly.getBranches(remote: "origin")
        #expect(listed.map(\.name) == ["dev"])
        #expect(listed.first?.longName == "refs/remotes/origin/dev")
        #expect(fake.invocations.map(ScmFakeGit.arguments).map(\.last) == ["-a", "-r"])
    }

    @Test
    func currentBranchCombinesNameUpstreamAndTracking() async throws {
        let (client, _) = ScmFakeGit.client { invocation in
            ScmFakeGit.arguments(invocation).first == "branch"
                ? ScmFakeGit.ok("main\n")
                : ScmFakeGit.ok("refs/heads/main|origin/main [behind 3]\n")
        }
        let branch = try #require(try await client.getCurrentBranch())
        #expect(branch == GitBranch(
            name: "main",
            longName: "refs/heads/main",
            upstream: "origin/main",
            ahead: 0,
            behind: 3
        ))

        let (untracked, _) = ScmFakeGit.client { invocation in
            ScmFakeGit.arguments(invocation).first == "branch"
                ? ScmFakeGit.ok("topic\n")
                : ScmFakeGit.ok("refs/heads/topic| \n")
        }
        let local = try #require(try await untracked.getCurrentBranch())
        #expect(local.upstream == nil)
        #expect(local.ahead == 0)
    }

    @Test
    func currentBranchIsNilOnDetachedHeadAndNeverListsRefsHeads() async throws {
        let (client, fake) = ScmFakeGit.client { invocation in
            ScmFakeGit.arguments(invocation).first == "branch"
                ? ScmFakeGit.ok("\n")
                : ScmFakeGit.ok("refs/heads/main|\nrefs/heads/other|\n")
        }
        #expect(try await client.getCurrentBranch() == nil)
        #expect(fake.invocations.map(ScmFakeGit.arguments) == [["branch", "--show-current"]])
    }

    @Test
    func checkoutOfARemoteBranchFallsBackToTheExistingLocalOne() async throws {
        let (client, fake) = ScmFakeGit.client { invocation in
            let arguments = ScmFakeGit.arguments(invocation)
            if arguments.contains("-b") {
                return ScmFakeGit.failure("fatal: a branch named 'feature' already exists")
            }
            return ScmFakeGit.ok()
        }
        let remote = GitBranch(
            name: "feature",
            longName: "refs/remotes/origin/feature",
            upstream: nil,
            ahead: 0,
            behind: 0
        )
        try await client.checkoutBranch(remote)

        #expect(fake.invocations.map(ScmFakeGit.arguments) == [
            ["checkout", "-b", "feature", "--track", "origin/feature"],
            ["checkout", "feature"]
        ])
    }

    @Test(arguments: [
        ("origin/feature", "refs/remotes/origin/feature", "feature"),
        ("origin/feature/deep", "refs/remotes/origin/feature/deep", "feature/deep"),
        ("feature", "refs/remotes/origin/feature", "feature")
    ])
    func remoteBranchesGetALocalNameWithoutTheRemotePrefix(name: String, longName: String, local: String) async throws {
        let (client, fake) = ScmFakeGit.client { _ in ScmFakeGit.ok() }
        let remote = GitBranch(name: name, longName: longName, upstream: nil, ahead: 0, behind: 0)
        try await client.checkoutBranch(remote)

        #expect(fake.invocations.map(ScmFakeGit.arguments) == [
            ["checkout", "-b", local, "--track", longName.replacingOccurrences(of: "refs/remotes/", with: "")]
        ])
    }

    @Test
    func aRemoteReferenceWithoutARemoteSegmentKeepsItsWholeName() async throws {
        let (client, fake) = ScmFakeGit.client { _ in ScmFakeGit.ok() }
        let odd = GitBranch(name: "x", longName: "refs/remotes/lonely", upstream: nil, ahead: 0, behind: 0)
        try await client.checkoutBranch(odd)
        #expect(fake.invocations.map(ScmFakeGit.arguments) == [["checkout", "-b", "lonely", "--track", "lonely"]])
    }

    @Test
    func checkoutFailuresOtherThanAnExistingBranchPropagate() async throws {
        let (client, fake) = ScmFakeGit.client { _ in ScmFakeGit.failure("error: pathspec 'x' did not match") }
        let remote = GitBranch(name: "x", longName: "refs/remotes/origin/x", upstream: nil, ahead: 0, behind: 0)
        await #expect(throws: GitClient.GitClientError.outputError("pathspec 'x' did not match")) {
            try await client.checkoutBranch(remote)
        }
        let local = GitBranch(name: "x", longName: "refs/heads/x", upstream: nil, ahead: 0, behind: 0)
        await #expect(throws: GitClient.GitClientError.outputError("pathspec 'x' did not match")) {
            try await client.checkoutBranch(local)
        }
        #expect(fake.invocations.count == 2)
    }

    @Test
    func checkoutOfALocalBranchWithANewNameCreatesIt() async throws {
        let (client, fake) = ScmFakeGit.client { _ in ScmFakeGit.ok() }
        let local = GitBranch(name: "main", longName: "refs/heads/main", upstream: nil, ahead: 0, behind: 0)
        try await client.checkoutBranch(local, newName: "copy")
        #expect(fake.invocations.map(ScmFakeGit.arguments) == [["checkout", "-b", "copy", "main"]])
    }

    @Test
    func checkoutOfARemoteBranchUnderANewNameTracksTheRemote() async throws {
        let (client, fake) = ScmFakeGit.client { _ in ScmFakeGit.ok() }
        let remote = GitBranch(
            name: "origin/feature",
            longName: "refs/remotes/origin/feature",
            upstream: nil,
            ahead: 0,
            behind: 0
        )
        try await client.checkoutBranch(remote, newName: "mine")
        #expect(fake.invocations.map(ScmFakeGit.arguments) == [["checkout", "-b", "mine", "--track", "origin/feature"]])
    }

    @Test(arguments: [
        ("HEAD -> main, tag: v1, origin/main", ["main", "origin/main"], "v1"),
        ("tag: v2, tag: v1", [String](), "v2, v1"),
        (
            "HEAD -> main, tag: v1.0, tag: rc-1, origin/main, origin/HEAD, feature",
            ["main", "origin/main", "feature"],
            "v1.0, rc-1"
        ),
        ("HEAD -> main, origin/main, origin/HEAD", ["main", "origin/main"], ""),
        ("tag:v3", [String](), "v3"),
        ("HEAD", ["HEAD"], ""),
        (" , ", [String](), ""),
        ("", [String](), "")
    ])
    func decorationsSplitIntoRefsAndTags(decoration: String, refs: [String], tag: String) {
        let parsed = GitClient.commitHistoryDecoration(decoration)
        #expect(parsed.refs == refs)
        #expect(parsed.tag == tag)
    }
}
