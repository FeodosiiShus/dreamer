import Foundation
import Testing
@testable import Dreamder

@Suite
struct CommitToolWindowStagingContentTests {
    private typealias Sample = CommitToolWindowSampleText
    private typealias State = CommitToolWindowRepositoryState

    private let editedLines: [Int: String] = [2: "L2", 10: "L10", 19: "L19"]
    private let stagedLines: [Int: String] = [2: "L2", 19: "L19"]

    private func client(_ directory: URL) -> GitClient {
        GitClient(directoryURL: directory, shellClient: .live())
    }

    @Test(arguments: CommitToolWindowLineEndingSetup.allCases)
    func partialStagingStoresTheLineEndingsGitWouldStageNotTheRawWorktreeBytes(
        setup: CommitToolWindowLineEndingSetup
    ) async throws {
        try await withTempDir { directory in
            let fixture = try await GitMergeFixture(root: directory)
            try await setup.apply(to: fixture)
            try fixture.write("a.txt", Sample.numbered())
            try fixture.write("b.txt", "b\n")
            try await fixture.commit("initial")
            let edited = Sample.numbered(replacing: editedLines, lineEnding: "\r\n")
            try fixture.write("a.txt", edited)
            let client = client(directory)
            let hunks = try await client.commitToolWindowHunks(path: "a.txt")
            #expect(hunks.map(\.preview) == ["L2", "L10", "L19"])
            let middle = try #require(hunks.dropFirst().first)
            let before = try await State.capture(of: fixture, files: ["a.txt", "b.txt"])
            #expect(before.stagedDiff.isEmpty)

            let outcome = try await client.stageSelectedHunks(path: "a.txt", excluding: [middle.id])

            #expect(outcome == .staged)
            let staged = try await fixture.run("cat-file", "blob", ":a.txt")
            #expect(staged == Sample.numbered(replacing: stagedLines))
            #expect(staged.utf8.contains(UInt8(ascii: "\r")) == false)
            let after = try await State.capture(of: fixture, files: ["a.txt", "b.txt"])
            #expect(after.worktree == before.worktree)
            #expect(after.worktree["a.txt"] == Data(edited.utf8))
            #expect(try await Sample.hunkCount(fixture, "diff", "--cached", "-U0", "--", "a.txt") == 2)
            #expect(try await Sample.hunkCount(fixture, "diff", "-U0", "--", "a.txt") == 1)
            #expect(try await fixture.stagedPaths() == ["a.txt"])
        }
    }

    @Test
    func withoutAnyLineEndingConversionPartialStagingKeepsTheCrlfOfTheBlob() async throws {
        try await withTempDir { directory in
            let fixture = try await GitMergeFixture(root: directory)
            try await fixture.run("config", "core.autocrlf", "false")
            try fixture.write("a.txt", Sample.numbered(lineEnding: "\r\n"))
            try await fixture.commit("initial")
            try fixture.write("a.txt", Sample.numbered(replacing: editedLines, lineEnding: "\r\n"))
            let client = client(directory)
            let hunks = try await client.commitToolWindowHunks(path: "a.txt")
            let middle = try #require(hunks.dropFirst().first)

            let outcome = try await client.stageSelectedHunks(path: "a.txt", excluding: [middle.id])

            #expect(outcome == .staged)
            let staged = try await fixture.run("cat-file", "blob", ":a.txt")
            #expect(staged == Sample.numbered(replacing: stagedLines, lineEnding: "\r\n"))
        }
    }

    @Test
    func aCleanFilterRewritesTheStagedLinesTheWayGitAddWould() async throws {
        try await withTempDir { directory in
            let fixture = try await GitMergeFixture(root: directory)
            try await fixture.run(
                "config", "filter.redact.clean",
                #"/bin/bash -c 'while IFS= read -r line; do printf "%s\n" "${line//SECRET/xxx}"; done'"#
            )
            try fixture.write(".gitattributes", "a.txt filter=redact\n")
            try fixture.write("a.txt", Sample.numbered())
            try await fixture.commit("initial")
            let secrets: [Int: String] = [2: "token=SECRET-2", 10: "token=SECRET-10", 19: "token=SECRET-19"]
            let edited = Sample.numbered(replacing: secrets)
            try fixture.write("a.txt", edited)
            let client = client(directory)
            let hunks = try await client.commitToolWindowHunks(path: "a.txt")
            #expect(hunks.map(\.preview) == ["token=xxx-2", "token=xxx-10", "token=xxx-19"])
            let middle = try #require(hunks.dropFirst().first)

            let outcome = try await client.stageSelectedHunks(path: "a.txt", excluding: [middle.id])

            #expect(outcome == .staged)
            let staged = try await fixture.run("cat-file", "blob", ":a.txt")
            #expect(staged == Sample.numbered(replacing: [2: "token=xxx-2", 19: "token=xxx-19"]))
            #expect(staged.contains("SECRET") == false)
            #expect(try Data(contentsOf: directory.appending(path: "a.txt")) == Data(edited.utf8))
        }
    }

    @Test
    func stagingTheSelectionReplacesOnlyTheEntryOfThatFile() async throws {
        try await withTempDir { directory in
            let fixture = try await GitMergeFixture(root: directory)
            try fixture.write("a.txt", Sample.numbered())
            try fixture.write("b.txt", "b\n")
            try await fixture.commit("initial")
            try fixture.write("a.txt", Sample.numbered(replacing: [5: "L5"]))
            try await fixture.run("add", "a.txt")
            try fixture.write("b.txt", "b staged\n")
            try await fixture.run("add", "b.txt")
            let stagedB = try await fixture.run("ls-files", "--stage", "--", "b.txt")
            try fixture.write("a.txt", Sample.numbered(replacing: editedLines))
            let client = client(directory)
            let hunks = try await client.commitToolWindowHunks(path: "a.txt")
            let middle = try #require(hunks.dropFirst().first)

            let outcome = try await client.stageSelectedHunks(path: "a.txt", excluding: [middle.id])

            #expect(outcome == .staged)
            #expect(try await fixture.run("cat-file", "blob", ":a.txt") == Sample.numbered(replacing: stagedLines))
            #expect(try await fixture.run("ls-files", "--stage", "--", "b.txt") == stagedB)
        }
    }
}
