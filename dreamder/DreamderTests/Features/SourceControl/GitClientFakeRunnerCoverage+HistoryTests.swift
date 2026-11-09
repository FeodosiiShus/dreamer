import Foundation
import Testing
@testable import Dreamder

extension GitClientFakeRunnerCoverage {
    @Test
    func commitHistoryParsesRefsTagsAndMissingFields() async throws {
        let full = "abc1234¦abc1234full¦Subject one¦Ann¦ann@x.io¦Ann C¦ann@c.io¦1700000000¦Body text¦"
        let output = [
            full + "HEAD -> main, origin/main, origin/HEAD¦",
            full + "tag: v1.0¦",
            full + "¦",
            "h¦H",
            "solo"
        ].joined(separator: "\0") + "\0"
        let (client, fake) = ScmFakeGit.client { invocation in
            switch ScmFakeGit.arguments(invocation).first {
            case "log": ScmFakeGit.ok(output)
            default: ScmFakeGit.ok("https://github.com/acme/widgets.git\n")
            }
        }
        let commits = try await client.getCommitHistory()

        #expect(commits.count == 5)
        let first = commits[0]
        #expect(first.hash == "abc1234")
        #expect(first.commitHash == "abc1234full")
        #expect(first.message == "Subject one")
        #expect(first.author == "Ann")
        #expect(first.authorEmail == "ann@x.io")
        #expect(first.committer == "Ann C")
        #expect(first.committerEmail == "ann@c.io")
        #expect(first.body == "Body text")
        #expect(first.refs == ["main", "origin/main"])
        #expect(first.tag.isEmpty)
        #expect(first.remoteURL == URL(string: "https://github.com/acme/widgets.git"))
        #expect(first.date == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(commits[1].tag == "v1.0")
        #expect(commits[1].refs.isEmpty)
        #expect(commits[2].refs.isEmpty)
        let sparse = commits[3]
        #expect(sparse.hash == "h")
        #expect(sparse.commitHash == "H")
        #expect(sparse.message.isEmpty)
        #expect(sparse.author.isEmpty)
        #expect(sparse.body.isEmpty)
        #expect(abs(sparse.date.timeIntervalSinceNow) < 60)
        let bare = commits[4]
        #expect(bare.hash == "solo")
        #expect(bare.commitHash.isEmpty)
        #expect(bare.refs.isEmpty)

        let logArguments = ScmFakeGit.arguments(try #require(fake.invocations.first))
        #expect(logArguments.starts(with: ["log", "--no-merges", "-z"]))
        #expect(logArguments.last == "--")
    }

    @Test
    func commitHistoryHonoursBranchLimitPathAndMergeFlag() async throws {
        let (client, fake) = ScmFakeGit.client { invocation in
            ScmFakeGit.arguments(invocation).first == "log"
                ? ScmFakeGit.ok("")
                : ScmFakeGit.failure("fatal: No remote configured to list refs from.")
        }
        let commits = try await client.getCommitHistory(
            branchName: "release",
            maxCount: 5,
            fileLocalPath: "src/a.txt",
            showMergeCommits: true
        )

        #expect(commits.isEmpty)
        let logArguments = ScmFakeGit.arguments(try #require(fake.invocations.first))
        #expect(!logArguments.contains("--no-merges"))
        #expect(Array(logArguments.suffix(5)) == ["-n", "5", "release", "--", "src/a.txt"])
    }

    @Test
    func commitHistoryRecordsMissingRemoteAsNil() async throws {
        let record = "abc¦ABC¦S¦A¦a@x¦C¦c@x¦1700000000¦¦¦"
        let (client, _) = ScmFakeGit.client { invocation in
            ScmFakeGit.arguments(invocation).first == "log"
                ? ScmFakeGit.ok(record + "\0")
                : ScmFakeGit.failure("fatal: No remote configured to list refs from.")
        }
        let commits = try await client.getCommitHistory()
        #expect(commits.count == 1)
        #expect(commits[0].remoteURL == nil)
    }

    @Test
    func logGraphChangedFilesDiffAgainstTheFirstParentOrTheRootTree() async throws {
        let directory = URL(fileURLWithPath: "/tmp/dreamder-fake-log", isDirectory: true)
        let (client, fake) = ScmFakeGit.client(directory: directory) { _ in
            ScmFakeGit.ok("M\ta.txt\nR100\told.txt\tnew.txt\n")
        }
        let withParent = GitLogCommit(
            hash: "h1",
            parents: ["p1", "p2"],
            authorName: "A",
            authorEmail: "a@x",
            date: Date(timeIntervalSince1970: 0),
            refs: [],
            subject: "s"
        )
        let root = GitLogCommit(
            hash: "h0",
            parents: [],
            authorName: "A",
            authorEmail: "a@x",
            date: Date(timeIntervalSince1970: 0),
            refs: [],
            subject: "s"
        )

        let merged = try await client.logGraphChangedFiles(commit: withParent)
        let initial = try await client.logGraphChangedFiles(commit: root)

        #expect(merged.count == 2)
        #expect(initial.count == 2)
        let invocations = fake.invocations.map(ScmFakeGit.arguments)
        #expect(invocations[0] == ["diff", "--name-status", "p1", "h1"])
        #expect(invocations[1] == ["diff-tree", "--root", "--no-commit-id", "--name-status", "-r", "h0"])
    }

    @Test
    func logGraphMessageIsTrimmed() async throws {
        let (client, fake) = ScmFakeGit.client { _ in ScmFakeGit.ok("\nSubject\n\nBody\n\n") }
        #expect(try await client.logGraphMessage(hash: "abc") == "Subject\n\nBody")
        #expect(ScmFakeGit.arguments(try #require(fake.invocations.first)) == ["log", "-1", "--format=%B", "abc"])
    }

    @Test
    func logGraphBranchNamesComeFromBothRefNamespaces() async throws {
        let (client, _) = ScmFakeGit.client { _ in
            ScmFakeGit.ok("refs/heads/main\nrefs/remotes/origin/main\nrefs/remotes/origin/HEAD\n")
        }
        #expect(try await client.logGraphBranchNames() == ["main", "origin/main"])
    }

    @Test
    func logGraphBranchNameParsingSkipsOtherNamespacesAndHeads() {
        let output = [
            "  refs/heads/main  ",
            "refs/heads/feature/x",
            "refs/heads/",
            "refs/remotes/origin/HEAD",
            "refs/remotes/origin/dev",
            "refs/remotes/",
            "refs/tags/v1",
            "refs/heads/HEAD",
            ""
        ].joined(separator: "\n")
        #expect(GitClient.logGraphBranchNames(fromRefNames: output) == ["main", "feature/x", "origin/dev"])
    }

    @Test
    func logGraphCurrentUserNeedsAtLeastOneOfNameOrEmail() async throws {
        let both = ScmFakeGit.client { invocation in
            ScmFakeGit.arguments(invocation).last == "user.name" ? ScmFakeGit.ok("Ann\n") : ScmFakeGit.ok("ann@x.io\n")
        }.client
        #expect(await both.logGraphCurrentUser() == GitLogUser(name: "Ann", email: "ann@x.io"))

        let nameOnly = ScmFakeGit.client { invocation in
            ScmFakeGit.arguments(invocation).last == "user.name"
                ? ScmFakeGit.ok("Ann\n")
                : ScmFakeGit.failure("", code: 1)
        }.client
        #expect(await nameOnly.logGraphCurrentUser() == GitLogUser(name: "Ann", email: ""))

        let emailOnly = ScmFakeGit.client { invocation in
            ScmFakeGit.arguments(invocation).last == "user.email"
                ? ScmFakeGit.ok("ann@x.io\n")
                : ScmFakeGit.failure("", code: 1)
        }.client
        #expect(await emailOnly.logGraphCurrentUser() == GitLogUser(name: "", email: "ann@x.io"))

        let neither = ScmFakeGit.client { _ in ScmFakeGit.failure("", code: 1) }.client
        #expect(await neither.logGraphCurrentUser() == nil)
    }

    @Test
    func logGraphChangedFileParsingHandlesRenamesAndRejectsBrokenLines() {
        let root = URL(fileURLWithPath: "/repo", isDirectory: true)
        let output = "M\ta.txt\nR100\told.txt\tnew.txt\nZ\tx\nM\n\nD\tgone.txt"
        let files = GitClient.logGraphParseChangedFiles(output, root: root)

        #expect(files.map(\.status) == [.modified, .renamed, .deleted])
        #expect(files.map(\.fileURL.lastPathComponent) == ["a.txt", "new.txt", "gone.txt"])
        #expect(files.map(\.originalFilename) == [nil, "old.txt", nil])
    }
}
