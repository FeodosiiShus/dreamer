import Foundation
import Testing
@testable import Dreamder

@Suite
struct CommitToolWindowStagingAtomicityTests {
    private typealias Sample = CommitToolWindowSampleText
    private typealias State = CommitToolWindowRepositoryState

    private func prepareDivergedHead(in fixture: GitMergeFixture) async throws {
        try fixture.write("a.txt", Sample.numbered())
        try fixture.write("b.txt", "b\n")
        try await fixture.commit("initial")
        try await fixture.run("checkout", "-q", "-b", "upstream")
        try fixture.write("a.txt", Sample.numbered(replacing: [2: "upstream"]))
        try await fixture.commit("upstream")
        try await fixture.run("checkout", "-q", "main")
        try fixture.write("a.txt", Sample.numbered(replacing: [5: "L5"]))
        try await fixture.run("add", "a.txt")
        try fixture.write("b.txt", "b staged\n")
        try await fixture.run("add", "b.txt")
        try fixture.write("a.txt", Sample.numbered(replacing: [2: "L2", 5: "L5", 10: "L10"]))
    }

    @Test
    func aPatchThatNoLongerAppliesToHeadLeavesTheIndexAndTheWorktreeExactlyAsTheyWere() async throws {
        try await withTempDir { directory in
            let fixture = try await GitMergeFixture(root: directory)
            try await prepareDivergedHead(in: fixture)
            let client = GitClient(directoryURL: directory, shellClient: .live())
            let source = try await client.commitToolWindowHunkSource(path: "a.txt")
            #expect(source.hunks.map(\.preview) == ["L2", "L5", "L10"])
            let last = try #require(source.hunks.last)
            try await fixture.run("update-ref", "HEAD", "refs/heads/upstream")
            let before = try await State.capture(of: fixture, files: ["a.txt", "b.txt"])
            #expect(before.stagedDiff.isEmpty == false)

            await #expect(throws: GitClient.GitClientError.self) {
                _ = try await client.stageSelectedHunks(from: source, path: "a.txt", excluding: [last.id])
            }

            let after = try await State.capture(of: fixture, files: ["a.txt", "b.txt"])
            #expect(after == before)
        }
    }

    @Test
    func theSameSourceStagesOnceHeadIsWhatTheHunksWereComputedAgainst() async throws {
        try await withTempDir { directory in
            let fixture = try await GitMergeFixture(root: directory)
            try await prepareDivergedHead(in: fixture)
            let client = GitClient(directoryURL: directory, shellClient: .live())
            let source = try await client.commitToolWindowHunkSource(path: "a.txt")
            let last = try #require(source.hunks.last)
            let untouchedB = try await fixture.run("ls-files", "--stage", "--", "b.txt")

            let outcome = try await client.stageSelectedHunks(from: source, path: "a.txt", excluding: [last.id])

            #expect(outcome == .staged)
            #expect(
                try await fixture.run("cat-file", "blob", ":a.txt")
                    == Sample.numbered(replacing: [2: "L2", 5: "L5"])
            )
            #expect(try await fixture.run("ls-files", "--stage", "--", "b.txt") == untouchedB)
        }
    }

    @Test
    func aStaleSourceWithoutAnyMatchingHunkStagesNothingAndReportsTheWholeFile() async throws {
        try await withTempDir { directory in
            let fixture = try await GitMergeFixture(root: directory)
            try await prepareDivergedHead(in: fixture)
            let client = GitClient(directoryURL: directory, shellClient: .live())
            let source = try await client.commitToolWindowHunkSource(path: "a.txt")
            let before = try await State.capture(of: fixture, files: ["a.txt", "b.txt"])

            let outcome = try await client.stageSelectedHunks(from: source, path: "a.txt", excluding: ["0,0"])

            #expect(outcome == .wholeFile)
            #expect(try await State.capture(of: fixture, files: ["a.txt", "b.txt"]) == before)
        }
    }

    @Test
    func selectingNothingDropsOnlyTheStagedEntryOfThatFile() async throws {
        try await withTempDir { directory in
            let fixture = try await GitMergeFixture(root: directory)
            try await prepareDivergedHead(in: fixture)
            let client = GitClient(directoryURL: directory, shellClient: .live())
            let source = try await client.commitToolWindowHunkSource(path: "a.txt")
            let everything = Set(source.hunks.map(\.id))
            let untouchedB = try await fixture.run("ls-files", "--stage", "--", "b.txt")

            let outcome = try await client.stageSelectedHunks(from: source, path: "a.txt", excluding: everything)

            #expect(outcome == .nothingSelected)
            #expect(try await fixture.stagedPaths() == ["b.txt"])
            #expect(try await fixture.run("ls-files", "--stage", "--", "b.txt") == untouchedB)
        }
    }
}
