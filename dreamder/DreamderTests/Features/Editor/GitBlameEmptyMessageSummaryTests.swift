import Foundation
import Testing
@testable import Dreamder

@Suite
struct GitBlameEmptyMessageSummaryTests {
    private let emptyMessageHash = "d3d7927040675c52d26b9f63e91b2eedd805d639"
    private let parenthesizedHash = "d1095f70730f48499f37d1793a3c5769da93328f"
    private let plainHash = "e491e2afd233dd0d9d30b1e8a9bd042e8ff068b4"

    private func entry(hash: String, line: Int, summary: String) -> String {
        [
            "\(hash) \(line) \(line) 1",
            "author Merge",
            "author-time 1677672000",
            "summary \(summary)",
            "filename Blamed.txt",
            "\tline \(line)"
        ].joined(separator: "\n")
    }

    @Test
    func theHashPlaceholderGitPrintsForAnEmptyCommitMessageIsNoSummary() {
        let output = entry(hash: emptyMessageHash, line: 1, summary: "(\(emptyMessageHash))") + "\n"

        let lines = GitBlameParser.parse(output)

        #expect(lines.map(\.summary) == [""])
        #expect(lines.map(\.commitHash) == [emptyMessageHash])
    }

    @Test
    func summariesThatMerelyLookParenthesizedAreKept() {
        let output = [
            entry(hash: parenthesizedHash, line: 1, summary: "(wip)"),
            entry(hash: plainHash, line: 2, summary: "(\(emptyMessageHash))"),
            entry(hash: emptyMessageHash, line: 3, summary: "initial")
        ].joined(separator: "\n") + "\n"

        let lines = GitBlameParser.parse(output)

        #expect(lines.map(\.summary) == ["(wip)", "(\(emptyMessageHash))", "initial"])
    }
}
