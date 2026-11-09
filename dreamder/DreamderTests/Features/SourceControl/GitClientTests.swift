//
//  GitClientTests.swift
//  DreamderTests
//
//  Created by Khan Winter on 9/11/25.
//

import Foundation
import Testing
@testable import Dreamder

@Suite
struct GitClientTests {
    private struct Repo {
        let fixture: GitMergeFixture
        let client: GitClient
    }

    private func makeRepo(_ directory: URL) async throws -> Repo {
        let fixture = try await GitMergeFixture(root: directory)
        try fixture.write("a.txt", "one\n")
        try await fixture.commit("initial")
        return Repo(fixture: fixture, client: GitClient(directoryURL: directory, shellClient: .live()))
    }

    private func relativePaths(_ files: [GitChangedFile]) -> [String] {
        files.map(\.fileURL.relativePath).sorted()
    }

    private static let sampleStatus = [
        "# branch.head main",
        "1 .M N... 100644 100644 100644 aaaa bbbb dir/with space.txt",
        "2 R. N... 100644 100644 100644 aaaa bbbb R100 new name.txt",
        "old name.txt",
        "u UU N... 100644 100644 100644 100644 aaaa bbbb cccc conflict.txt",
        "? untracked é.txt",
        "! ignored.log"
    ].joined(separator: "\0") + "\0"

    @Test
    func statusParseNullAtEnd() throws {
        try withTempDir { dirURL in
            // swiftlint:disable:next line_length
            let string = "1 .M N... 100644 100644 100644 eaef31cfa2a22418c00d7477da0b7151d122681e eaef31cfa2a22418c00d7477da0b7151d122681e Dreamder/Features/SourceControl/Client/GitClient+Status.swift\01 AM N... 000000 100644 100644 0000000000000000000000000000000000000000 e0f5ce250b32cf6610a284b7a33ac114079f5159 DreamderTests/Features/SourceControl/GitClientTests.swift\0"
            let client = GitClient(directoryURL: dirURL, shellClient: .live())
            let status = try client.parseStatusString(string)

            try #require(status.changedFiles.count == 2)
            // No null string at the end
            #expect(status.changedFiles[0].fileURL.lastPathComponent == "GitClient+Status.swift")
            #expect(status.changedFiles[1].fileURL.lastPathComponent == "GitClientTests.swift")
        }
    }

    @Test
    func statusParseHandlesEveryEntryKind() throws {
        try withTempDir { dirURL in
            let client = GitClient(directoryURL: dirURL, shellClient: .live())
            let status = try client.parseStatusString(Self.sampleStatus)

            #expect(status.changedFiles.map(\.fileURL.relativePath) == ["dir/with space.txt", "new name.txt"])
            #expect(status.changedFiles[0].status == .modified)
            #expect(status.changedFiles[0].stagedStatus == GitStatus.none)
            #expect(status.changedFiles[0].originalFilename == nil)
            #expect(status.changedFiles[1].stagedStatus == .renamed)
            #expect(status.changedFiles[1].originalFilename == "old name.txt")
            #expect(status.unmergedChanges.map(\.fileURL.relativePath) == ["conflict.txt"])
            #expect(status.unmergedChanges[0].status == .unmerged)
            #expect(status.untrackedFiles.map(\.fileURL.relativePath) == ["untracked é.txt"])
            #expect(status.untrackedFiles[0].status == .untracked)
        }
    }

    @Test
    func statusParseOfEmptyOutputIsEmpty() throws {
        try withTempDir { dirURL in
            let client = GitClient(directoryURL: dirURL, shellClient: .live())
            let status = try client.parseStatusString("")
            #expect(status.changedFiles.isEmpty && status.unmergedChanges.isEmpty && status.untrackedFiles.isEmpty)
        }
    }

    @Test
    func statusParseNeverTrapsOnTruncatedOutput() throws {
        try withTempDir { dirURL in
            let client = GitClient(directoryURL: dirURL, shellClient: .live())
            let bytes = Array(Self.sampleStatus.utf8)
            var parsed = 0
            var rejected = 0
            for length in 0...bytes.count {
                let prefix = String(decoding: bytes[0..<length], as: UTF8.self)
                do {
                    _ = try client.parseStatusString(prefix)
                    parsed += 1
                } catch is GitClient.GitClientError {
                    rejected += 1
                }
            }
            #expect(parsed > 0)
            #expect(rejected > 0)
            #expect(parsed + rejected == bytes.count + 1)
        }
    }

    @Test(arguments: ["\0", "1", "1 ", "1 .M", "1 .M ", "1 .M N...", "2 R. a b c d e f g", "u", "u UU", "?", "? ", "? x", "!", "#", "x"])
    func statusParseRejectsMalformedOutputWithoutCrashing(output: String) throws {
        try withTempDir { dirURL in
            let client = GitClient(directoryURL: dirURL, shellClient: .live())
            #expect(throws: GitClient.GitClientError.self) {
                try client.parseStatusString(output)
            }
        }
    }

    @Test
    func statusParseReportsUnknownEntryTypesAndStatusCharacters() throws {
        try withTempDir { dirURL in
            let client = GitClient(directoryURL: dirURL, shellClient: .live())
            #expect(throws: GitClient.GitClientError.statusInvalidChangeType("x")) {
                try client.parseStatusString("x file\0")
            }
            #expect(throws: GitClient.GitClientError.invalidStatus("Z")) {
                try client.parseStatusString("1 ZM N... 100644 100644 100644 a b path\0")
            }
        }
    }

    @Test
    func realStatusListsStagedModifiedRenamedAndUntrackedFiles() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            try repo.fixture.write("keep me.txt", "keep\n")
            try await repo.fixture.commit("second")
            try repo.fixture.write("a.txt", "changed\n")
            try repo.fixture.write("dir/ünï file.txt", "new\n")
            try await repo.fixture.run("mv", "keep me.txt", "moved é.txt")

            let status = try await repo.client.getStatus()

            #expect(relativePaths(status.changedFiles) == ["a.txt", "moved é.txt"])
            let modified = try #require(status.changedFiles.first { $0.fileURL.relativePath == "a.txt" })
            #expect(modified.status == .modified)
            #expect(modified.stagedStatus == GitStatus.none)
            let renamed = try #require(status.changedFiles.first { $0.fileURL.relativePath == "moved é.txt" })
            #expect(renamed.stagedStatus == .renamed)
            #expect(renamed.originalFilename == "keep me.txt")
            #expect(status.untrackedFiles.map(\.fileURL.lastPathComponent) == ["dir"])
            #expect(status.unmergedChanges.isEmpty)
        }
    }

    @Test
    func scopedStatusOnlyListsChangesBelowTheScope() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            try repo.fixture.write("sub/inside.txt", "x\n")
            try repo.fixture.write("other/outside.txt", "y\n")
            let scoped = GitClient(directoryURL: directory, shellClient: .live(), scopePath: "sub")

            let status = try await scoped.getStatus()

            #expect(status.untrackedFiles.map(\.fileURL.lastPathComponent) == ["sub"])
            #expect(scoped.scopePathspecArguments == ["--", "sub"])
            #expect(scoped.scopePathspec == " -- 'sub'")
        }
    }

    @Test
    func outsideARepositoryEveryCommandReportsNotAGitRepository() async throws {
        try await withTempDir { directory in
            let client = GitClient(directoryURL: directory, shellClient: .live())
            await #expect(throws: GitClient.GitClientError.notGitRepository) { try await client.run("status") }
            await #expect(throws: GitClient.GitClientError.notGitRepository) { try await client.getStatus() }
            #expect(await client.validate() == false)
        }
    }

    @Test
    func validateRecognizesWorkTrees() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            #expect(await repo.client.validate())
        }
    }

    @Test
    func aMissingWorkingDirectoryIsAnErrorNotACrash() async {
        let client = GitClient(
            directoryURL: URL(fileURLWithPath: "/nonexistent/dreamder-project-directory"),
            shellClient: .live()
        )
        await #expect(throws: GitClient.GitClientError.self) { try await client.run("status") }
        #expect(await client.validate() == false)
    }

    @Test
    func aFailingCommandSurfacesGitsMessage() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            do {
                _ = try await repo.client.run("checkout missing-branch")
                Issue.record("expected the command to fail")
            } catch GitClient.GitClientError.outputError(let message) {
                #expect(message.contains("missing-branch"))
                #expect(!message.hasPrefix("fatal:") && !message.hasPrefix("error:"))
            }
        }
    }

    @Test
    func standardOutputIsReturnedVerbatim() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            let output = try await repo.client.run("rev-parse HEAD")
            #expect(output.trimmingCharacters(in: .whitespacesAndNewlines).count == 40)
        }
    }

    @Test
    func runResultReportsExitCodesInsteadOfThrowing() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            let result = try await repo.client.runResult("rev-parse -q --verify refs/heads/nope")
            #expect(result.exitCode == 1)
            #expect(!result.success)
            #expect(result.success(ignoring: [1]))
            #expect(result.output.isEmpty)

            #expect(try await repo.client.run("rev-parse -q --verify refs/heads/nope", accepting: [1]).isEmpty)
            await #expect(throws: GitClient.GitClientError.self) {
                try await repo.client.run("rev-parse -q --verify refs/heads/nope")
            }
        }
    }

    @Test
    func runDataReturnsBinaryBlobsUnchanged() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            let bytes = Data([0x00, 0xFF, 0xFE, 0x0A, 0x61, 0x00])
            try bytes.write(to: directory.appending(path: "blob.bin"))
            try await repo.fixture.commit("binary")

            #expect(try await repo.client.runData("show HEAD:blob.bin") == bytes)
            let lossy = try await repo.client.run("show HEAD:blob.bin")
            #expect(lossy.contains("\0"))
            await #expect(throws: GitClient.GitClientError.self) { try await repo.client.runData("show HEAD:missing.bin") }
        }
    }

    @Test
    func commitMessagesNeverReachAShell() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            try repo.fixture.write("b.txt", "b\n")
            try await repo.client.add([directory.appending(path: "b.txt")])
            let message = "fix \"quotes\" & 'single' $(touch pwned-subshell) `touch pwned-backtick` back\\slash"
            let details = "second paragraph\nline 3 ${HOME}; touch pwned-semicolon\n\nfourth"

            try await repo.client.commit(message: message, details: details)

            let stored = try await repo.fixture.run("log", "-1", "--format=%B").trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(stored == message + "\n\n" + details)
            for marker in ["pwned-subshell", "pwned-backtick", "pwned-semicolon"] {
                #expect(!repo.fixture.exists(marker))
                #expect(!FileManager.default.fileExists(atPath: FileManager.default.currentDirectoryPath + "/" + marker))
            }
        }
    }

    @Test
    func commitWithoutDetailsStoresOnlyTheMessage() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            try repo.fixture.write("b.txt", "b\n")
            try await repo.client.add([directory.appending(path: "b.txt")])
            try await repo.client.commit(message: "just a subject", details: "")
            #expect(try await repo.fixture.run("log", "-1", "--format=%B").trimmingCharacters(in: .whitespacesAndNewlines) == "just a subject")
        }
    }

    @Test
    func theCommitToolWindowQuotingIsParsedWithoutExpansion() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            let message = "amend \"x\" $(touch pwned-amend) `touch pwned-amend2` \\ end\nsecond line"

            try await repo.client.commitToolWindow(message: message, amend: true)

            let stored = try await repo.fixture.run("log", "-1", "--format=%B").trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(stored == message)
            #expect(!repo.fixture.exists("pwned-amend"))
            #expect(!repo.fixture.exists("pwned-amend2"))
        }
    }

    @Test
    func committingNothingIsReportedAsAnError() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            do {
                try await repo.client.commit(message: "empty", details: nil)
                Issue.record("expected the commit to fail")
            } catch GitClient.GitClientError.outputError(let message) {
                #expect(message.contains("nothing to commit"))
            }
        }
    }

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
            #expect(try await repo.fixture.run("config", "--get", "dreamder.probe").trimmingCharacters(in: .newlines) == value)
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
            #expect(try await repo.fixture.run("rev-parse", "--abbrev-ref", "HEAD").trimmingCharacters(in: .newlines) == "main")

            try await repo.fixture.run("checkout", "--", "a.txt")
            try await repo.client.checkoutBranch(other)
            #expect(try await repo.fixture.run("rev-parse", "--abbrev-ref", "HEAD").trimmingCharacters(in: .newlines) == "other")
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
            #expect(added.fileURL.path(percentEncoded: false) == directory.appending(path: "dir/with space & ünï.txt").path(percentEncoded: false))
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
            #expect(try await repo.client.getCommitHistory(branchName: "main", fileLocalPath: "no \"such\" file.txt").isEmpty)
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
            #expect(try await repo.client.logGraph(filters: GitLogFilterCollection(branch: .fromBranch("main")), limit: 1).count == 1)

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

            let filters = GitLogFilterCollection(text: GitLogTextFilter.fromPattern("^(sec|thi)", isRegexpAllowed: true))
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

    @Test
    func unsyncedCommitCountsComeFromTheUpstream() async throws {
        try await withTempDir { directory in
            let origin = try await makeRepo(directory.appending(path: "origin", directoryHint: .isDirectory).createDirectoryReturningSelf())
            let cloneDirectory = directory.appending(path: "clone", directoryHint: .isDirectory)
            try await origin.fixture.run("clone", "-q", origin.fixture.root.path(percentEncoded: false), cloneDirectory.path(percentEncoded: false))
            let clone = GitMergeFixture(existing: cloneDirectory)
            try await clone.run("config", "user.email", "clone@dreamder.test")
            try await clone.run("config", "user.name", "Clone")
            try await clone.run("config", "commit.gpgsign", "false")
            try clone.write("local.txt", "l\n")
            try await clone.commit("local one")
            try clone.write("local2.txt", "l\n")
            try await clone.commit("local two")
            try origin.fixture.write("remote.txt", "r\n")
            try await origin.fixture.commit("remote one")
            try await clone.run("fetch", "-q")

            let client = GitClient(directoryURL: cloneDirectory, shellClient: .live())
            let counts = try await client.numberOfUnsyncedCommits()

            #expect(counts.ahead == 2)
            #expect(counts.behind == 1)
            let current = try #require(try await client.getCurrentBranch())
            #expect(current.upstream == "origin/main")
            #expect(current.ahead == 2)
            #expect(current.behind == 1)
        }
    }

    @Test
    func concurrentWritesAreSerializedPerRepository() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            let names = (0..<12).map { "file-\($0).txt" }
            for name in names {
                try repo.fixture.write(name, "x\n")
            }

            try await withThrowingTaskGroup(of: Void.self) { group in
                for name in names {
                    let url = directory.appending(path: name)
                    group.addTask { try await repo.client.add([url]) }
                }
                try await group.waitForAll()
            }

            #expect(try await repo.fixture.stagedPaths() == names.sorted())
        }
    }

    @Test
    func readsDuringWritesKeepWorking() async throws {
        try await withTempDir { directory in
            let repo = try await makeRepo(directory)
            for index in 0..<6 {
                try repo.fixture.write("f\(index).txt", "x\n")
            }
            try await withThrowingTaskGroup(of: Void.self) { group in
                for index in 0..<6 {
                    let url = directory.appending(path: "f\(index).txt")
                    group.addTask { try await repo.client.add([url]) }
                    group.addTask { _ = try await repo.client.getStatus() }
                }
                try await group.waitForAll()
            }
            #expect(try await repo.client.getStatus().changedFiles.count == 6)
        }
    }

    @Test
    func cloningStreamsProgressAndProducesAWorkingCopy() async throws {
        try await withTempDir { directory in
            let origin = try await makeRepo(directory.appending(path: "origin", directoryHint: .isDirectory).createDirectoryReturningSelf())
            let destination = directory.appending(path: "cloned repo", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let client = GitClient(directoryURL: destination, shellClient: .live())

            var steps = 0
            for try await _ in client.cloneRepository(
                remoteUrl: URL(fileURLWithPath: origin.fixture.root.path(percentEncoded: false)),
                localPath: destination
            ) {
                steps += 1
            }

            #expect(steps > 0)
            #expect(FileManager.default.fileExists(atPath: destination.appending(path: ".git").path(percentEncoded: false)))
            #expect(try String(contentsOf: destination.appending(path: "a.txt"), encoding: .utf8) == "one\n")
        }
    }

    @Test
    func cloningAnUnknownRepositoryFailsWithGitsMessage() async throws {
        try await withTempDir { directory in
            let destination = directory.appending(path: "target", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let client = GitClient(directoryURL: destination, shellClient: .live())
            do {
                for try await _ in client.cloneRepository(
                    remoteUrl: URL(fileURLWithPath: directory.appending(path: "does-not-exist").path(percentEncoded: false)),
                    localPath: destination
                ) {}
                Issue.record("expected the clone to fail")
            } catch GitClient.GitClientError.outputError(let message) {
                #expect(message.contains("does-not-exist"))
            }
        }
    }
}

private extension URL {
    func createDirectoryReturningSelf() throws -> URL {
        try FileManager.default.createDirectory(at: self, withIntermediateDirectories: true)
        return self
    }
}
