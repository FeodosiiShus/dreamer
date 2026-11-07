import Foundation
import Testing
@testable import Dreamder

@Suite
struct GitBlameParserTests {
    private let recentHash = "d3a3502fee4ab7d2bbd73cf7d7ed4a8bc02eb28c"
    private let olderHash = "9fceb02a1a1c2a1f5a8f1d3a0e3b4c5d6e7f8091"

    @Test
    func parsesSingleLine() {
        let output = """
        \(recentHash) 1 1 1
        author Ann
        author-mail <ann@example.com>
        author-time 1700000000
        author-tz +0000
        committer Ann
        committer-mail <ann@example.com>
        committer-time 1700000000
        committer-tz +0000
        summary Initial import
        boundary
        filename Sources/main.swift
        \tprint("hello")
        """

        let lines = GitBlameParser.parse(output)

        #expect(
            lines == [
                GitBlameLine(
                    line: 1,
                    commitHash: recentHash,
                    author: "Ann",
                    authorDate: Date(timeIntervalSince1970: 1700000000),
                    summary: "Initial import"
                )
            ]
        )
    }

    @Test
    func parsesMultiLineGroup() {
        let output = """
        \(recentHash) 10 1 3
        author Ann
        author-time 1700000000
        summary Extract helper
        \tfunc a() {}
        \tfunc b() {}
        \tfunc c() {}
        """

        let lines = GitBlameParser.parse(output)

        #expect(lines.map(\.line) == [1, 2, 3])
        #expect(Set(lines.map(\.commitHash)) == [recentHash])
        #expect(Set(lines.map(\.summary)) == ["Extract helper"])
    }

    @Test
    func reusesCommitMetadataForRepeatedCommits() throws {
        let output = """
        \(recentHash) 1 1 2
        author Ann Marie
        author-time 100
        summary First commit
        \talpha
        \tbeta
        \(olderHash) 3 3 1
        author Bob
        author-time 200
        summary Second commit
        \tgamma
        \(recentHash) 4 4 1
        \tdelta
        """

        let lines = GitBlameParser.parse(output)

        try #require(lines.count == 4)
        #expect(lines[2].commitHash == olderHash)
        #expect(lines[2].author == "Bob")
        #expect(lines[2].authorDate == Date(timeIntervalSince1970: 200))
        #expect(lines[3].commitHash == recentHash)
        #expect(lines[3].author == "Ann Marie")
        #expect(lines[3].authorDate == Date(timeIntervalSince1970: 100))
        #expect(lines[3].summary == "First commit")
    }

    @Test
    func marksUncommittedLines() throws {
        let output = """
        \(recentHash) 1 1 1
        author Ann
        author-time 100
        summary Committed line
        \tone
        0000000000000000000000000000000000000000 2 2 1
        author Not Committed Yet
        author-mail <not.committed.yet>
        author-time 1700000500
        author-tz +0000
        committer Not Committed Yet
        committer-time 1700000500
        summary Version of main.swift from main.swift
        previous \(recentHash) main.swift
        filename main.swift
        \ttwo
        """

        let lines = GitBlameParser.parse(output)

        try #require(lines.count == 2)
        #expect(lines[0].isUncommitted == false)
        #expect(lines[1].isUncommitted)
        #expect(lines[1].shortHash == "00000000")
        #expect(lines[1].author == "Not Committed Yet")
    }

    @Test
    func ignoresUnknownMetadataFields() throws {
        let output = """
        \(olderHash) 1 1 1
        author Bob
        author-mail <bob@example.com>
        author-time 42
        author-tz -0300
        committer Someone Else
        committer-mail <someone@example.com>
        committer-time 43
        committer-tz -0300
        encoding UTF-8
        summary Fix the thing
        previous 1111111111111111111111111111111111111111 old.swift
        filename new.swift
        \tsomething
        """

        let lines = GitBlameParser.parse(output)

        try #require(lines.count == 1)
        #expect(lines[0].author == "Bob")
        #expect(lines[0].summary == "Fix the thing")
        #expect(lines[0].authorDate == Date(timeIntervalSince1970: 42))
    }

    @Test
    func handlesEmptyOutput() {
        #expect(GitBlameParser.parse("").isEmpty)
        #expect(GitBlameParser.parse("\n\n").isEmpty)
    }

    @Test
    func sortsLinesByFinalLineNumber() {
        let output = """
        \(recentHash) 2 2 1
        author Ann
        author-time 100
        summary Second
        \tsecond
        \(olderHash) 1 1 1
        author Bob
        author-time 50
        summary First
        \tfirst
        """

        let lines = GitBlameParser.parse(output)

        #expect(lines.map(\.line) == [1, 2])
    }
}
