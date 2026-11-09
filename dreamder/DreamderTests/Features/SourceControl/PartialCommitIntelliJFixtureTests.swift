import Foundation
import Testing
@testable import Dreamder

nonisolated struct PartialCommitFixtureCase: Sendable, CustomStringConvertible {
    let name: String
    let before: Data
    let after: Data

    var description: String { name }
}

nonisolated enum PartialCommitFixtureCases {
    static let directory = "platform/platform-tests/testData/diff/patch"

    static let all: [PartialCommitFixtureCase] = {
        guard let names = try? IntelliJTestData.files(in: directory, suffix: "") else { return [] }
        return names.compactMap { name in
            guard let before = try? Data(contentsOf: IntelliJTestData.url("\(directory)/\(name)/before/1.txt")),
                  let after = try? Data(contentsOf: IntelliJTestData.url("\(directory)/\(name)/after/1.txt")) else {
                return nil
            }
            return PartialCommitFixtureCase(name: name, before: before, after: after)
        }
    }()
}

@Suite
struct PartialCommitIntelliJFixtureTests {
    private func hunkCount(_ fixture: GitMergeFixture, _ arguments: String...) async throws -> Int {
        let output = try await fixture.runAllowingFailure(arguments)
        return PartialCommitDiffParser.hunks(inDiff: output).count
    }

    private func stage(
        _ selected: Set<String>,
        hunks: [PartialCommitHunk],
        testCase: PartialCommitFixtureCase,
        fixture: GitMergeFixture
    ) async throws -> Bool {
        try await fixture.run("reset", "-q", "--", "f.txt")
        guard let patch = PartialCommitPatchBuilder.patch(
            path: "f.txt",
            head: testCase.before,
            worktree: testCase.after,
            hunks: hunks,
            selected: selected
        ) else {
            return false
        }
        let patchURL = fixture.root.appending(path: "selection.patch")
        try patch.write(to: patchURL)
        try await fixture.run("apply", "--cached", "--recount", "--whitespace=nowarn", patchURL.path(percentEncoded: false))
        return true
    }

    @Test
    func theIntelliJPatchFixturesAreDiscovered() {
        #expect(PartialCommitFixtureCases.all.count > 15)
    }

    @Test(arguments: PartialCommitFixtureCases.all)
    func everySelectionStagesExactlyTheSelectedHunksLikeGitApply(testCase: PartialCommitFixtureCase) async throws {
        try await withTempDir { directory in
            let fixture = try await GitMergeFixture(root: directory)
            let file = directory.appending(path: "f.txt")
            try testCase.before.write(to: file)
            try await fixture.commit("before")
            try testCase.after.write(to: file)

            let diff = try await fixture.run("diff", "HEAD", "-U0", "--no-color", "--", "f.txt")
            let headers = PartialCommitDiffParser.hunks(inDiff: diff)
            let hunks = PartialCommitPatchBuilder.hunks(from: headers, head: testCase.before, worktree: testCase.after)
            #expect(hunks.count == headers.count)
            let ids = Set(hunks.map(\.id))
            #expect(ids.count == hunks.count)

            let none = try await stage([], hunks: hunks, testCase: testCase, fixture: fixture)
            #expect(none == false)
            #expect(try await hunkCount(fixture, "diff", "--cached", "-U0", "--", "f.txt") == 0)

            guard !hunks.isEmpty else { return }

            let all = try await stage(ids, hunks: hunks, testCase: testCase, fixture: fixture)
            #expect(all)
            try await fixture.run("diff", "--exit-code", "--", "f.txt")
            #expect(try await hunkCount(fixture, "diff", "--cached", "-U0", "--", "f.txt") == hunks.count)

            guard hunks.count > 1 else { return }
            for hunk in hunks {
                _ = try await stage([hunk.id], hunks: hunks, testCase: testCase, fixture: fixture)
                #expect(try await hunkCount(fixture, "diff", "--cached", "-U0", "--", "f.txt") == 1, "only \(hunk.id)")
                #expect(
                    try await hunkCount(fixture, "diff", "-U0", "--", "f.txt") == hunks.count - 1,
                    "only \(hunk.id)"
                )

                _ = try await stage(ids.subtracting([hunk.id]), hunks: hunks, testCase: testCase, fixture: fixture)
                #expect(
                    try await hunkCount(fixture, "diff", "--cached", "-U0", "--", "f.txt") == hunks.count - 1,
                    "all but \(hunk.id)"
                )
                #expect(try await hunkCount(fixture, "diff", "-U0", "--", "f.txt") == 1, "all but \(hunk.id)")
            }
        }
    }
}
