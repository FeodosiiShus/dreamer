import Foundation
import Testing
@testable import Dreamder

nonisolated struct ScmRemoteWorld: Sendable {
    let bare: GitMergeFixture
    let work: GitMergeFixture
    let client: GitClient

    var barePath: String {
        bare.root.path(percentEncoded: false)
    }

    static func make(in directory: URL, origin: Bool = true) async throws -> ScmRemoteWorld {
        let bareRoot = directory.appending(path: "remote.git", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: bareRoot, withIntermediateDirectories: true)
        let bare = GitMergeFixture(existing: bareRoot)
        try await bare.run("init", "-q", "--bare", "-b", "main")

        let workRoot = directory.appending(path: "work", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: workRoot, withIntermediateDirectories: true)
        let work = try await GitMergeFixture(root: workRoot)
        try work.write("a.txt", "one\n")
        try await work.commit("initial")

        let client = GitClient(directoryURL: workRoot, shellClient: .live())
        if origin {
            try await client.addRemote(name: "origin", location: bareRoot.path(percentEncoded: false))
        }
        return ScmRemoteWorld(bare: bare, work: work, client: client)
    }

    func clone(named name: String, in directory: URL) async throws -> (fixture: GitMergeFixture, client: GitClient) {
        let root = directory.appending(path: name, directoryHint: .isDirectory)
        try await GitMergeFixture(existing: directory).run("clone", "-q", barePath, root.path(percentEncoded: false))
        let fixture = GitMergeFixture(existing: root)
        try await fixture.run("config", "user.email", "\(name)@dreamder.test")
        try await fixture.run("config", "user.name", name)
        try await fixture.run("config", "commit.gpgsign", "false")
        return (fixture, GitClient(directoryURL: root, shellClient: .live()))
    }

    func head(of fixture: GitMergeFixture, _ revision: String = "HEAD") async throws -> String {
        try await fixture.run("rev-parse", revision).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@Suite
struct GitClientRemoteCoverage {
    @Test
    func remotesAreRegisteredListedAndResolved() async throws {
        try await withTempDir { directory in
            let world = try await ScmRemoteWorld.make(in: directory)

            let remotes = try await world.client.getRemotes()
            #expect(remotes == [GitRemote(name: "origin", pushLocation: world.barePath, fetchLocation: world.barePath)])
            #expect(try await world.client.getRemoteURL() == URL(string: world.barePath))
        }
    }

    @Test
    func pushSetsUpstreamThenPlainPushFollowsIt() async throws {
        try await withTempDir { directory in
            let world = try await ScmRemoteWorld.make(in: directory)

            try await world.client.pushToRemote(remote: "origin", branch: "main", setUpstream: true)
            #expect(try await world.head(of: world.bare, "main") == world.head(of: world.work))
            let upstream = try await world.work.run("rev-parse", "--abbrev-ref", "main@{upstream}")
            #expect(upstream.trimmingCharacters(in: .whitespacesAndNewlines) == "origin/main")

            try world.work.write("b.txt", "two\n")
            try await world.work.commit("second")
            try await world.client.pushToRemote()
            #expect(try await world.head(of: world.bare, "main") == world.head(of: world.work))

            try world.work.write("c.txt", "three\n")
            try await world.work.commit("third")
            try await world.client.pushToRemote(remote: "origin", branch: "main", setUpstream: nil, force: nil, tags: nil)
            #expect(try await world.head(of: world.bare, "main") == world.head(of: world.work))
        }
    }

    @Test
    func rewrittenHistoryIsRejectedUnlessForced() async throws {
        try await withTempDir { directory in
            let world = try await ScmRemoteWorld.make(in: directory)
            try await world.client.pushToRemote(remote: "origin", branch: "main", setUpstream: true)

            try await world.work.run("commit", "-q", "--amend", "-m", "rewritten")
            await #expect(throws: GitClient.GitClientError.self) {
                try await world.client.pushToRemote(remote: "origin", branch: "main")
            }

            try await world.client.pushToRemote(remote: "origin", branch: "main", force: true)
            #expect(try await world.head(of: world.bare, "main") == world.head(of: world.work))
        }
    }

    @Test
    func pushingWithTagsPublishesThem() async throws {
        try await withTempDir { directory in
            let world = try await ScmRemoteWorld.make(in: directory)
            try await world.work.run("tag", "v1")

            try await world.client.pushToRemote(remote: "origin", branch: "main", tags: true)

            let tags = try await world.bare.run("tag", "--list")
            #expect(tags.trimmingCharacters(in: .whitespacesAndNewlines) == "v1")
        }
    }

    @Test
    func pushingWithoutAnyRemoteFails() async throws {
        try await withTempDir { directory in
            let world = try await ScmRemoteWorld.make(in: directory, origin: false)
            await #expect(throws: GitClient.GitClientError.self) { try await world.client.pushToRemote() }
        }
    }

    @Test
    func fetchBringsRemoteCommitsIntoTheUnsyncedCounters() async throws {
        try await withTempDir { directory in
            let world = try await ScmRemoteWorld.make(in: directory)
            try await world.client.pushToRemote(remote: "origin", branch: "main", setUpstream: true)
            let other = try await world.clone(named: "other", in: directory)
            try other.fixture.write("remote.txt", "r\n")
            try await other.fixture.commit("remote change")
            try await other.fixture.run("push", "-q", "origin", "main")

            let before = try await world.client.numberOfUnsyncedCommits()
            #expect(before.behind == 0)
            try await world.client.fetchFromRemote()
            let after = try await world.client.numberOfUnsyncedCommits()
            #expect(after.behind == 1)
            #expect(after.ahead == 0)
        }
    }

    @Test
    func pullMergesTheUpstreamAndRebaseReplaysLocalWork() async throws {
        try await withTempDir { directory in
            let world = try await ScmRemoteWorld.make(in: directory)
            try await world.client.pushToRemote(remote: "origin", branch: "main", setUpstream: true)
            let other = try await world.clone(named: "other", in: directory)

            try other.fixture.write("first.txt", "1\n")
            try await other.fixture.commit("remote first")
            try await other.fixture.run("push", "-q", "origin", "main")
            try await world.client.pullFromRemote()
            #expect(world.work.exists("first.txt"))

            try world.work.write("local.txt", "l\n")
            try await world.work.commit("local")
            try other.fixture.write("second.txt", "2\n")
            try await other.fixture.commit("remote second")
            try await other.fixture.run("push", "-q", "origin", "main")
            try await world.client.pullFromRemote(remote: "origin", branch: "main", rebase: true)

            #expect(world.work.exists("second.txt"))
            #expect(world.work.exists("local.txt"))
            let merges = try await world.work.run("rev-list", "--merges", "--count", "HEAD")
            #expect(merges.trimmingCharacters(in: .whitespacesAndNewlines) == "0")

            try await world.client.pushToRemote()
            try await other.fixture.run("pull", "-q", "--ff-only")
            try other.fixture.write("third.txt", "3\n")
            try await other.fixture.commit("remote third")
            try await other.fixture.run("push", "-q", "origin", "main")
            try await world.client.pullFromRemote(remote: nil, branch: "main")
            #expect(world.work.exists("third.txt"))
        }
    }

    @Test
    func pullingAnUnknownBranchFails() async throws {
        try await withTempDir { directory in
            let world = try await ScmRemoteWorld.make(in: directory)
            await #expect(throws: GitClient.GitClientError.self) {
                try await world.client.pullFromRemote(remote: "origin", branch: "nope")
            }
        }
    }

    @Test
    func remoteBranchesAreListedFilteredAndCheckedOut() async throws {
        try await withTempDir { directory in
            let world = try await ScmRemoteWorld.make(in: directory)
            try await world.client.pushToRemote(remote: "origin", branch: "main", setUpstream: true)
            let other = try await world.clone(named: "other", in: directory)
            try await other.fixture.run("checkout", "-q", "-b", "feature")
            try other.fixture.write("feature.txt", "f\n")
            try await other.fixture.commit("feature work")
            try await other.fixture.run("push", "-q", "-u", "origin", "feature")

            let listedByClone = try await other.client.getBranches(remote: "origin")
            #expect(listedByClone.map(\.name).sorted() == ["feature", "main"])
            let allByClone = try await other.client.getBranches()
            #expect(allByClone.map(\.name).contains("origin/feature"))
            #expect(!allByClone.map(\.name).contains { $0.contains("HEAD") })

            try await world.client.fetchFromRemote()
            let remoteBranches = try await world.client.getBranches(remote: "origin")
            let feature = try #require(remoteBranches.first { $0.name == "feature" })
            #expect(feature.isRemote)

            try await world.client.checkoutBranch(feature)
            #expect(try await world.client.getCurrentBranch()?.name == "feature")
            #expect(world.work.exists("feature.txt"))

            let main = try #require(try await world.client.getBranches().first { $0.name == "main" })
            try await world.client.checkoutBranch(main)
            try await world.client.checkoutBranch(feature)
            #expect(try await world.client.getCurrentBranch()?.name == "feature")
        }
    }

    @Test
    func checkingOutARemoteBranchFromTheCombinedListCreatesATrackingBranchWithoutThePrefix() async throws {
        try await withTempDir { directory in
            let world = try await ScmRemoteWorld.make(in: directory)
            try await world.client.pushToRemote(remote: "origin", branch: "main", setUpstream: true)
            let other = try await world.clone(named: "other", in: directory)
            try await other.fixture.run("checkout", "-q", "-b", "feature")
            try other.fixture.write("feature.txt", "f\n")
            try await other.fixture.commit("feature work")
            try await other.fixture.run("push", "-q", "-u", "origin", "feature")
            try await world.client.fetchFromRemote()

            let combined = try await world.client.getBranches()
            let remoteFeature = try #require(combined.first { $0.name == "origin/feature" })
            try await world.client.checkoutBranch(remoteFeature)

            let current = try #require(try await world.client.getCurrentBranch())
            #expect(current.name == "feature")
            #expect(current.upstream == "origin/feature")
            let locals = try await world.work.run("branch", "--format=%(refname:short)")
            #expect(locals.split(separator: "\n").map(String.init).sorted() == ["feature", "main"])
            #expect(world.work.exists("feature.txt"))
        }
    }

    @Test
    func checkingOutARemoteBranchWhoseLocalBranchExistsJustSwitchesToIt() async throws {
        try await withTempDir { directory in
            let world = try await ScmRemoteWorld.make(in: directory)
            try await world.client.pushToRemote(remote: "origin", branch: "main", setUpstream: true)
            let other = try await world.clone(named: "other", in: directory)
            try await other.fixture.run("checkout", "-q", "-b", "feature")
            try other.fixture.write("feature.txt", "f\n")
            try await other.fixture.commit("feature work")
            try await other.fixture.run("push", "-q", "-u", "origin", "feature")
            try await world.client.fetchFromRemote()
            try await world.work.run("branch", "feature", "main")

            let combined = try await world.client.getBranches()
            let remoteFeature = try #require(combined.first { $0.name == "origin/feature" })
            try await world.client.checkoutBranch(remoteFeature)

            #expect(try await world.client.getCurrentBranch()?.name == "feature")
            #expect(world.work.exists("feature.txt") == false)
            let locals = try await world.work.run("branch", "--format=%(refname:short)")
            #expect(locals.split(separator: "\n").map(String.init).sorted() == ["feature", "main"])
        }
    }

    @Test
    func branchesCanBeCopied() async throws {
        try await withTempDir { directory in
            let world = try await ScmRemoteWorld.make(in: directory)
            let main = try #require(try await world.client.getBranches().first { $0.name == "main" })

            try await world.client.checkoutBranch(main, newName: "copy")
            #expect(try await world.client.getCurrentBranch()?.name == "copy")
            try await world.client.checkoutBranch(main)
            #expect(try await world.client.getBranches().map(\.name).sorted() == ["copy", "main"])
        }
    }

    @Test
    func stashRoundTripsThroughPushListAndApply() async throws {
        try await withTempDir { directory in
            let world = try await ScmRemoteWorld.make(in: directory, origin: false)

            try world.work.write("a.txt", "wip\n")
            try await world.client.stash(message: "named")
            #expect(try world.work.read("a.txt") == "one\n")
            let listed = try await world.client.stashList()
            #expect(listed.map(\.message) == ["named"])

            try await world.client.applyStashEntry(nil)
            #expect(try world.work.read("a.txt") == "wip\n")
            try await world.work.run("checkout", "--", ".")
            try await world.client.applyStashEntry(0)
            #expect(try world.work.read("a.txt") == "wip\n")
        }
    }

    @Test
    func commitsAreCreatedWithMessageAndDetails() async throws {
        try await withTempDir { directory in
            let world = try await ScmRemoteWorld.make(in: directory, origin: false)
            try world.work.write("b.txt", "b\n")
            try await world.client.add([world.work.root.appending(path: "b.txt")])
            try await world.client.commit(message: "Subject", details: "Details line")

            let body = try await world.work.run("log", "-1", "--format=%B")
            #expect(body.trimmingCharacters(in: .whitespacesAndNewlines) == "Subject\n\nDetails line")

            try world.work.write("c.txt", "c\n")
            try await world.client.add([world.work.root.appending(path: "c.txt")])
            try await world.client.reset([world.work.root.appending(path: "c.txt")])
            #expect(try await world.work.stagedPaths().isEmpty)
            try await world.client.add([world.work.root.appending(path: "c.txt")])
            try await world.client.commit(message: "Plain", details: "")
            let subject = try await world.work.run("log", "-1", "--format=%B")
            #expect(subject.trimmingCharacters(in: .whitespacesAndNewlines) == "Plain")
        }
    }

    @Test
    func commitHistoryOfAClonedRepositoryCarriesTheRemoteAndRefs() async throws {
        try await withTempDir { directory in
            let world = try await ScmRemoteWorld.make(in: directory)
            try await world.client.pushToRemote(remote: "origin", branch: "main", setUpstream: true)
            let other = try await world.clone(named: "other", in: directory)
            try other.fixture.write("x.txt", "x\n")
            try await other.fixture.commit("on clone")

            let commits = try await other.client.getCommitHistory(branchName: "main", maxCount: 5)
            #expect(commits.count == 2)
            #expect(commits.first?.refs == ["main"])
            #expect(commits.last?.refs == ["origin/main"])
            #expect(commits.first?.remoteURL == URL(string: world.barePath))
        }
    }

    @Test
    func commitHistoryKeepsBranchRefsAndTagsApartOnTaggedCommits() async throws {
        try await withTempDir { directory in
            let world = try await ScmRemoteWorld.make(in: directory)
            try await world.work.run("tag", "v1")
            try await world.client.pushToRemote(remote: "origin", branch: "main", setUpstream: true)
            try await world.client.pushToRemote(remote: "origin", branch: "main", tags: true)
            let other = try await world.clone(named: "other", in: directory)
            try other.fixture.write("x.txt", "x\n")
            try await other.fixture.commit("on clone")
            try await other.fixture.run("tag", "v2")
            try await other.fixture.run("tag", "-a", "v2-annotated", "-m", "annotated")

            let commits = try await other.client.getCommitHistory(branchName: "main", maxCount: 5)

            #expect(commits.count == 2)
            #expect(commits[0].refs == ["main"])
            #expect(Set(commits[0].tag.components(separatedBy: ", ")) == ["v2", "v2-annotated"])
            #expect(commits[1].refs == ["origin/main"])
            #expect(commits[1].tag == "v1")
        }
    }
}
