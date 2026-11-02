import Foundation
import Testing
@testable import Dreamder

@Suite
struct GitLogParsingTests {
    private let field = "\u{1f}"

    private func record(
        hash: String,
        parents: String,
        author: String = "Ada Lovelace",
        email: String = "ada@example.com",
        seconds: String = "1700000000",
        decoration: String = "",
        subject: String
    ) -> String {
        [hash, parents, author, email, seconds, decoration, subject].joined(separator: field)
    }

    @Test
    func parsesMergeCommitWithTwoParents() throws {
        let output = record(
            hash: "aaaa0000bbbb1111",
            parents: "bbbb2222 cccc3333",
            decoration: "HEAD -> main, origin/main",
            subject: "Merge branch 'feature'"
        )

        let commits = GitClient.logGraphParse(output)
        #expect(commits.count == 1)
        let commit = try #require(commits.first)
        #expect(commit.hash == "aaaa0000bbbb1111")
        #expect(commit.parents == ["bbbb2222", "cccc3333"])
        #expect(commit.isMerge)
        #expect(commit.shortHash == "aaaa0000")
        #expect(commit.authorName == "Ada Lovelace")
        #expect(commit.authorEmail == "ada@example.com")
        #expect(commit.date == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(commit.subject == "Merge branch 'feature'")
    }

    @Test
    func parsesRootCommitWithoutParents() throws {
        let output = record(hash: "aaaa", parents: "", subject: "Initial commit")
        let commits = GitClient.logGraphParse(output)
        #expect(commits.count == 1)
        let commit = try #require(commits.first)
        #expect(commit.parents.isEmpty)
        #expect(!commit.isMerge)
    }

    @Test
    func parsesEmptyDecorationAsNoRefs() throws {
        let output = record(hash: "aaaa", parents: "bbbb", decoration: "", subject: "No refs here")
        let commits = GitClient.logGraphParse(output)
        let commit = try #require(commits.first)
        #expect(commit.refs.isEmpty)
    }

    @Test
    func parsesRefKinds() {
        let refs = GitClient.logGraphRefs(
            from: "grafted, HEAD -> main, origin/main, origin/HEAD, tag: v1.0"
        )
        #expect(refs.count == 3)
        #expect(refs.contains(GitLogRef(name: "main", kind: .head)))
        #expect(refs.contains(GitLogRef(name: "origin/main", kind: .remote)))
        #expect(refs.contains(GitLogRef(name: "v1.0", kind: .tag)))
    }

    @Test
    func keepsSeparatorsInsideSubject() throws {
        let subject = "Fix \u{1f} parsing, keep it"
        let output = record(hash: "aaaa", parents: "bbbb", subject: subject)
        let commits = GitClient.logGraphParse(output)
        #expect(commits.count == 1)
        let commit = try #require(commits.first)
        #expect(commit.subject == subject)
    }

    @Test
    func separatesRecordsWithNull() {
        let output = [
            record(hash: "aaaa", parents: "bbbb", subject: "First"),
            record(hash: "bbbb", parents: "", subject: "Second")
        ].joined(separator: "\0")

        let commits = GitClient.logGraphParse(output)
        #expect(commits.count == 2)
        #expect(commits.map(\.hash) == ["aaaa", "bbbb"])
    }

    @Test
    func skipsMalformedRecords() {
        let output = [
            record(hash: "aaaa", parents: "bbbb", subject: "Good"),
            "only\u{1f}two",
            record(hash: "cccc", parents: "", seconds: "not-a-number", subject: "Bad timestamp")
        ].joined(separator: "\0")

        let commits = GitClient.logGraphParse(output)
        #expect(commits.count == 1)
        #expect(commits.first?.hash == "aaaa")
    }
}
