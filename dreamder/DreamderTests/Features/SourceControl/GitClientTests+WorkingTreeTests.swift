import Foundation
import Testing
@testable import Dreamder

extension GitClientTests {
    @Test
    func addAndResetHandleHostilePathNames() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            let names = ["with space.txt", "-dash.txt", "it's.txt", "$(touch pwned-add).txt"]
            for name in names {
                try repo.fixture.write(name, "x\n")
            }
            let urls = names.map { directory.appending(path: $0) }

            try await repo.client.add(urls)
            #expect(try await repo.fixture.stagedPaths() == names.sorted())

            try await repo.client.reset(urls)
            #expect(try await repo.fixture.stagedPaths().isEmpty)
            #expect(!repo.fixture.exists("pwned-add"))
        }
    }

    @Test
    func discardChangesRestoresTheFile() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            try repo.fixture.write("a.txt", "dirty\n")
            try await repo.client.discardChanges(for: directory.appending(path: "a.txt"))
            #expect(try repo.fixture.read("a.txt") == "one\n")

            try repo.fixture.write("a.txt", "dirty again\n")
            try await repo.client.discardAllChanges()
            #expect(try repo.fixture.read("a.txt") == "one\n")
        }
    }

    @Test
    func discardingAnUnknownFileFails() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            await #expect(throws: GitClient.GitClientError.self) {
                try await repo.client.discardChanges(for: directory.appending(path: "never-existed.txt"))
            }
        }
    }

    @Test
    func stashMessagesNeverReachAShell() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            try repo.fixture.write("a.txt", "wip\n")
            let message = "wip \"x\" 'y' $(touch pwned-stash) `touch pwned-stash2`: with colon"

            try await repo.client.stash(message: message)

            #expect(try repo.fixture.read("a.txt") == "one\n")
            let entries = try await repo.client.stashList()
            let entry = try #require(entries.first)
            #expect(entries.count == 1)
            #expect(entry.index == 0)
            #expect(entry.message == message)
            #expect(abs(entry.date.timeIntervalSinceNow) < 300)
            #expect(!repo.fixture.exists("pwned-stash"))
            #expect(!repo.fixture.exists("pwned-stash2"))
        }
    }

    @Test
    func stashApplyTargetsTheRequestedEntry() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            try repo.fixture.write("a.txt", "first\n")
            try await repo.client.stash(message: "first")
            try repo.fixture.write("a.txt", "second\n")
            try await repo.client.stash(message: nil)

            let entries = try await repo.client.stashList()
            try #require(entries.count == 2)
            #expect(entries[1].message == "first")

            try await repo.client.applyStashEntry(1)
            #expect(try repo.fixture.read("a.txt") == "first\n")
        }
    }

    @Test
    func stashEntriesParseSubjectsDatesAndIndexes() {
        let input = [
            "stash@{0}\u{1f}1700000000\u{1f}On main: first: with colon",
            "stash@{1}\u{1f}1699999000\u{1f}WIP on main: abc1234 subject line",
            "garbage line",
            "stash@{3}\u{1f}notanumber\u{1f}On main: skipped"
        ].joined(separator: "\n")

        let entries = parseGitStashEntries(input + "\n")

        #expect(entries.map(\.index) == [0, 1])
        #expect(entries.map(\.message) == ["first: with colon", "abc1234 subject line"])
        #expect(entries[0].date == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(parseGitStashEntries("").isEmpty)
    }

    @Test
    func configValuesRoundTripWithoutShellInterpretation() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            let value = "va\"lue 'q' $(touch pwned-config) `touch pwned-config2` ; back\\slash"

            await repo.client.setConfig(key: "dreamder.probe", value: value)

            let stored: String? = try await repo.client.getConfig(key: "dreamder.probe")
            #expect(stored == value)
            #expect(
                try await repo.fixture.run("config", "--get", "dreamder.probe")
                    .trimmingCharacters(in: .newlines) == value
            )
            #expect(!repo.fixture.exists("pwned-config"))
            #expect(!repo.fixture.exists("pwned-config2"))
        }
    }

    @Test
    func missingConfigKeysAreNilAndEmptyValuesUnsetTheKey() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            let missing: String? = try await repo.client.getConfig(key: "dreamder.missing")
            #expect(missing == nil)
            let missingBool: Bool? = try await repo.client.getConfig(key: "dreamder.missing")
            #expect(missingBool == nil)

            await repo.client.setConfig(key: "dreamder.flag", value: true)
            let flag: Bool? = try await repo.client.getConfig(key: "dreamder.flag")
            #expect(flag == true)

            await repo.client.setConfig(key: "dreamder.flag", value: false)
            let unset: Bool? = try await repo.client.getConfig(key: "dreamder.flag")
            #expect(unset == nil)

            await repo.client.setConfig(key: "dreamder.never-set", value: "")
            let stillMissing: String? = try await repo.client.getConfig(key: "dreamder.never-set")
            #expect(stillMissing == nil)
        }
    }

    @Test
    func readingConfigOutsideARepositoryUsesGlobalScopeOnly() async throws {
        try await withTempDir { directory in
            let config = GitConfigClient(projectURL: directory, shellClient: .live())
            let value: String? = try await config.get(key: "dreamder.definitely.not.set.anywhere", global: true)
            #expect(value == nil)
        }
    }

    @Test
    func remotesAreAddedAndListedWithoutShellInterpretation() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            let location = "/tmp/remote$(touch pwned-remote);x`y`"

            try await repo.client.addRemote(name: "upstream", location: location)
            let remotes = try await repo.client.getRemotes()
            #expect(remotes.map(\.name) == ["upstream"])
            #expect(remotes.first?.fetchLocation == location)
            #expect(remotes.first?.pushLocation == location)
            #expect(!repo.fixture.exists("pwned-remote"))

            await #expect(throws: GitClient.GitClientError.self) {
                try await repo.client.addRemote(name: "upstream", location: location)
            }
        }
    }

    @Test
    func branchesAreListedThroughArguments() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            try await repo.fixture.run("branch", "feature/one")
            try await repo.fixture.run("branch", "old")

            let branches = try await repo.client.getBranches()
            #expect(branches.map(\.name).sorted() == ["feature/one", "main", "old"])
            #expect(branches.allSatisfy { $0.longName.hasPrefix("refs/heads/") && $0.upstream == nil })

            let current = try #require(try await repo.client.getCurrentBranch())
            #expect(current.name == "main")
            #expect(current.longName == "refs/heads/main")
        }
    }
}
