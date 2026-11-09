import Foundation
import Testing
@testable import Dreamder

extension GitClientFakeRunnerCoverage {
    @Test
    func logGraphRecordParsingRequiresNineFieldsAHashAndADate() {
        let unit = "\u{1f}"
        func record(_ fields: [String]) -> String { fields.joined(separator: unit) }

        let valid = record([
            "h1", "p1 p2", "Ann", "a@x", "100", "200", "HEAD -> refs/heads/main", "Subject", "Subject\n\nBody\n"
        ])
        let parsed = GitClient.logGraphParse(record: valid)
        #expect(parsed?.hash == "h1")
        #expect(parsed?.parents == ["p1", "p2"])
        #expect(parsed?.date == Date(timeIntervalSince1970: 100))
        #expect(parsed?.commitDate == Date(timeIntervalSince1970: 200))
        #expect(parsed?.message == "Subject\n\nBody")
        #expect(parsed?.refs == [GitLogRef(name: "main", kind: .head)])

        let fallbackCommitDate = GitClient.logGraphParse(
            record: record(["h2", "", "Ann", "a@x", "100", "later", "", "Subject", "  \n"])
        )
        #expect(fallbackCommitDate?.commitDate == Date(timeIntervalSince1970: 100))
        #expect(fallbackCommitDate?.message == "Subject")
        #expect(fallbackCommitDate?.parents.isEmpty == true)

        #expect(GitClient.logGraphParse(record: record(["h", "p"])) == nil)
        #expect(GitClient.logGraphParse(record: record(["h", "", "A", "a", "abc", "1", "", "s", "m"])) == nil)
        #expect(GitClient.logGraphParse(record: record(["", "", "A", "a", "1", "1", "", "s", "m"])) == nil)

        let joined = valid + "\0" + "broken" + "\0" + record(["h3", "", "B", "b@x", "5", "5", "", "S3", "S3"])
        #expect(GitClient.logGraphParse(joined).map(\.hash) == ["h1", "h3"])
    }

    @Test
    func logGraphDecorationParsingClassifiesAndDeduplicatesRefs() {
        #expect(GitClient.logGraphRefs(from: "  ").isEmpty)

        let refs = GitClient.logGraphRefs(
            from: "HEAD -> refs/heads/main, tag: refs/tags/v1, refs/remotes/origin/main, refs/remotes/origin/HEAD, "
                + "grafted, refs/heads/feature, refs/heads/feature, tag: refs/tags/v1, "
                + "other -> refs/heads/x, HEAD ->, "
        )
        #expect(refs == [
            GitLogRef(name: "main", kind: .head),
            GitLogRef(name: "v1", kind: .tag),
            GitLogRef(name: "origin/main", kind: .remote),
            GitLogRef(name: "feature", kind: .branch)
        ])
    }

    @Test
    func logGraphDecorationParsingDecidesLocalOrRemoteFromTheFullRefNotFromSlashes() {
        let refs = GitClient.logGraphRefs(
            from: "HEAD -> refs/heads/feature/login, refs/heads/origin/main, refs/remotes/origin/main, "
                + "refs/remotes/origin/feature/login, refs/heads/HEAD, refs/remotes/upstream/HEAD, "
                + "refs/stash, refs/heads/, tag: refs/tags/release/1.0, tag: v2, tag: refs/tags/, HEAD -> main"
        )
        #expect(refs == [
            GitLogRef(name: "feature/login", kind: .head),
            GitLogRef(name: "origin/main", kind: .branch),
            GitLogRef(name: "origin/main", kind: .remote),
            GitLogRef(name: "origin/feature/login", kind: .remote),
            GitLogRef(name: "HEAD", kind: .branch),
            GitLogRef(name: "release/1.0", kind: .tag)
        ])
    }

    @Test
    func logGraphDecorationOfADetachedHeadIsABranchNamedHead() {
        #expect(GitClient.logGraphRefs(from: "HEAD, refs/heads/main") == [
            GitLogRef(name: "HEAD", kind: .branch),
            GitLogRef(name: "main", kind: .branch)
        ])
    }

    @Test
    func logGraphQuotingEscapesSingleQuotes() {
        #expect(GitClient.logGraphQuote("a b") == "'a b'")
        #expect(GitClient.logGraphQuote("it's") == "'it'\\''s'")
    }

    @Test
    func cloneProgressMapsEveryPhaseOntoOneBar() async throws {
        let (client, fake) = ScmFakeGit.client { _ in
            FakeProcessRunner.output(
                "",
                stderr: [
                    "Cloning into 'x'...",
                    "remote: Counting objects:  50% (1/2)",
                    "Counting objects: 100% (2/2), done.",
                    "Compressing objects:  50% (1/2)",
                    "Receiving objects:  50% (1/2)",
                    "Resolving deltas:  50% (1/2)"
                ].joined(separator: "\n") + "\n"
            )
        }
        var steps: [GitClient.CloneProgress] = []
        for try await step in client.cloneRepository(
            remoteUrl: URL(fileURLWithPath: "/tmp/origin repo"),
            localPath: URL(fileURLWithPath: "/tmp/target")
        ) {
            steps.append(step)
        }

        let expected: [Double] = [0, 5, 10, 15, 40, 80]
        #expect(steps.count == expected.count)
        for (step, value) in zip(steps, expected) {
            #expect(abs(step.progress - value) < 1e-9)
        }
        #expect(
            steps.map(\.state.label)
                == ["Cloning", "Counting", "Counting", "Compressing", "Receiving", "Resolving"]
        )
        #expect(
            ScmFakeGit.arguments(try #require(fake.invocations.first))
                == ["clone", "--progress", "--", "file:///tmp/origin%20repo", "/tmp/target"]
        )
    }

    @Test
    func cloneProgressLabelsNameEveryState() {
        let states: [(GitClient.GitCloneProgressState, String)] = [
            (.initialState, "Cloning"),
            (.counting, "Counting"),
            (.compressing, "Compressing"),
            (.receiving, "Receiving"),
            (.resolving, "Resolving")
        ]
        for (state, label) in states {
            #expect(state.label == label)
        }
    }

    @Test
    func remoteListingPairsFetchAndPushLocationsOnly() {
        let output = [
            "origin\thttps://example.com/a.git (fetch)",
            "origin\thttps://example.com/a.git (push)",
            "pushfirst\tgit@example.com:b.git (push)",
            "pushfirst\tgit@example.com:b.git (fetch)",
            "fetchfirst\thttps://example.com/c.git (fetch)",
            "fetchfirst\thttps://example.com/c.git (push)",
            "fetchonly\thttps://example.com/d.git (fetch)",
            "pushonly\thttps://example.com/e.git (push)",
            "no tab here",
            "odd\thttps://example.com/f.git (weird)"
        ].joined(separator: "\n")

        let remotes = Set(parseGitRemotes(from: output))
        #expect(remotes == [
            GitRemote(
                name: "origin",
                pushLocation: "https://example.com/a.git",
                fetchLocation: "https://example.com/a.git"
            ),
            GitRemote(
                name: "pushfirst",
                pushLocation: "git@example.com:b.git",
                fetchLocation: "git@example.com:b.git"
            ),
            GitRemote(
                name: "fetchfirst",
                pushLocation: "https://example.com/c.git",
                fetchLocation: "https://example.com/c.git"
            )
        ])
    }

    @Test
    func stashParsingSkipsMalformedEntries() {
        let input = [
            "stash@{0}\u{1f}1700000000\u{1f}On main: first",
            "stash@{1}\u{1f}notatime\u{1f}On main: skipped",
            "stash@{2}\u{1f}1700000000",
            "stash@{3}\u{1f}1700000000\u{1f}no separator",
            "stash@{4}\u{1f}1699999999\u{1f}WIP on main: abc subject"
        ].joined(separator: "\n")
        let entries = parseGitStashEntries(input)

        #expect(entries.map(\.index) == [0, 4])
        #expect(entries.map(\.message) == ["first", "abc subject"])
        #expect(entries[0].date == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(parseGitStashEntries("").isEmpty)
    }
}
