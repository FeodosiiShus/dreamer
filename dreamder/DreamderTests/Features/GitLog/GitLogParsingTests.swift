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
        commitSeconds: String = "1700000500",
        decoration: String = "",
        subject: String,
        message: String = ""
    ) -> String {
        [hash, parents, author, email, seconds, commitSeconds, decoration, subject, message].joined(separator: field)
    }

    @Test
    func parsesMergeCommitWithTwoParents() throws {
        let output = record(
            hash: "aaaa0000bbbb1111",
            parents: "bbbb2222 cccc3333",
            decoration: "HEAD -> refs/heads/main, refs/remotes/origin/main",
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
    func parsesCommitDateFromTheCommitterTimestamp() throws {
        let output = record(hash: "aaaa", parents: "", subject: "Dated")
        let commit = try #require(GitClient.logGraphParse(output).first)
        #expect(commit.date == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(commit.commitDate == Date(timeIntervalSince1970: 1_700_000_500))
    }

    @Test
    func commitDateFallsBackToAuthorDateWhenNotNumeric() throws {
        let output = record(hash: "aaaa", parents: "", commitSeconds: "oops", subject: "Dated")
        let commit = try #require(GitClient.logGraphParse(output).first)
        #expect(commit.commitDate == commit.date)
    }

    @Test
    func messageFallsBackToSubjectWhenEmpty() throws {
        let output = record(hash: "aaaa", parents: "", subject: "Only subject", message: "")
        let commit = try #require(GitClient.logGraphParse(output).first)
        #expect(commit.message == "Only subject")
    }

    @Test
    func messageFallsBackToSubjectWhenOnlyWhitespace() throws {
        let output = record(hash: "aaaa", parents: "", subject: "Only subject", message: " \n\n ")
        let commit = try #require(GitClient.logGraphParse(output).first)
        #expect(commit.message == "Only subject")
    }

    @Test
    func messageBodyIsTrimmed() throws {
        let output = record(hash: "aaaa", parents: "", subject: "Title", message: "Title\n\nBody line\n\n")
        let commit = try #require(GitClient.logGraphParse(output).first)
        #expect(commit.message == "Title\n\nBody line")
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
            from: "grafted, HEAD -> refs/heads/main, refs/remotes/origin/main, refs/remotes/origin/HEAD, "
                + "tag: refs/tags/v1.0, refs/heads/feature/login"
        )
        #expect(refs.count == 4)
        #expect(refs.contains(GitLogRef(name: "main", kind: .head)))
        #expect(refs.contains(GitLogRef(name: "origin/main", kind: .remote)))
        #expect(refs.contains(GitLogRef(name: "v1.0", kind: .tag)))
        #expect(refs.contains(GitLogRef(name: "feature/login", kind: .branch)))
    }

    @Test
    func keepsSeparatorsInsideMessage() throws {
        let message = "Subject\n\nFix \u{1f} parsing, keep it"
        let output = record(hash: "aaaa", parents: "bbbb", subject: "Subject", message: message)
        let commits = GitClient.logGraphParse(output)
        #expect(commits.count == 1)
        let commit = try #require(commits.first)
        #expect(commit.subject == "Subject")
        #expect(commit.message == message)
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
            "aaaa\u{1f}bbbb\u{1f}name\u{1f}mail\u{1f}1700000000\u{1f}1700000000\u{1f}\u{1f}subject",
            record(hash: "cccc", parents: "", seconds: "not-a-number", subject: "Bad timestamp"),
            record(hash: "", parents: "", subject: "No hash")
        ].joined(separator: "\0")

        let commits = GitClient.logGraphParse(output)
        #expect(commits.count == 1)
        #expect(commits.first?.hash == "aaaa")
    }

    @Test
    func formatHasNineUnitSeparatedFields() {
        #expect(GitClient.logGraphFormat.components(separatedBy: "%x1f").count == 9)
    }
}
