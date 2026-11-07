import Foundation
import Testing
@testable import Dreamder

@Suite
struct GitCommandLineTests {
    @Test(arguments: [
        ("status", ["status"]),
        ("  log   -n  5 \t", ["log", "-n", "5"]),
        ("", []),
        ("   ", []),
        ("commit --message=\"a b\"", ["commit", "--message=a b"]),
        ("commit --message=\"say \\\"hi\\\" \\$HOME \\`x\\` \\\\\"", ["commit", "--message=say \"hi\" $HOME `x` \\"]),
        ("'it'\\''s'", ["it's"]),
        ("a\\ b c", ["a b", "c"]),
        ("\"\"", [""]),
        ("''", [""]),
        ("a\"\" b", ["a", "b"]),
        ("x=\"\"", ["x="]),
        ("\"a\\nb\"", ["a\\nb"]),
        ("'a\\nb'", ["a\\nb"]),
        ("log \\\n-n 5", ["log", "-n", "5"]),
        ("log \\\r\n-n 5", ["log", "-n", "5"]),
        ("\"line one\nline two\"", ["line one\nline two"]),
        ("\"a\\\nb\"", ["ab"]),
        ("stash apply stash@{0}", ["stash", "apply", "stash@{0}"]),
        ("-c core.quotePath=false diff --name-status 'a' 'b'", ["-c", "core.quotePath=false", "diff", "--name-status", "a", "b"]),
        ("\"é ü\" 'ñ'", ["é ü", "ñ"]),
        ("trailing\\", ["trailing\\"])
    ])
    func tokenizes(command: String, expected: [String]) throws {
        #expect(try GitCommandLine.tokenize(command) == expected)
    }

    @Test(arguments: [
        "status; rm -rf x",
        "status && touch pwned",
        "log | cat",
        "log > out.txt",
        "log $(touch pwned)",
        "log `touch pwned`",
        "add *.swift",
        "checkout ~/other",
        "log #comment"
    ])
    func shellSyntaxIsNeverInterpreted(command: String) throws {
        let tokens = try GitCommandLine.tokenize(command)
        #expect(tokens.joined(separator: " ") == command)
    }

    @Test
    func quotedShellSyntaxStaysInsideOneArgument() throws {
        #expect(try GitCommandLine.tokenize("commit --message=\"a; rm -rf / $(touch x) `y`\"") == [
            "commit", "--message=a; rm -rf / $(touch x) `y`"
        ])
        #expect(try GitCommandLine.tokenize("'$(touch x)' \"$(touch y)\"") == ["$(touch x)", "$(touch y)"])
    }

    @Test(arguments: ["\"open", "'open", "a \"b 'c' d", "x 'y"])
    func unterminatedQuotesThrow(command: String) {
        #expect(throws: GitCommandLineError.self) {
            try GitCommandLine.tokenize(command)
        }
    }

    @Test
    func unterminatedQuoteReportsWhichQuote() {
        #expect(throws: GitCommandLineError.unterminatedQuote("single")) { try GitCommandLine.tokenize("'x") }
        #expect(throws: GitCommandLineError.unterminatedQuote("double")) { try GitCommandLine.tokenize("\"x") }
    }

    private static let awkwardValues = [
        "plain",
        "with space",
        "multiple   spaces",
        "it's",
        "say \"hi\"",
        "$HOME and ${PATH}",
        "`backticks`",
        "$(subshell)",
        "back\\slash",
        "trailing backslash\\",
        "line\nbreak",
        "tab\tsep",
        "ünïcödé 日本語 🙂",
        "semi;colon && pipe | redirect > glob *",
        "~tilde",
        "#hash",
        ""
    ]

    @Test(arguments: awkwardValues)
    func quoteRoundTrips(value: String) throws {
        let quoted = GitCommandLine.quote(value)
        #expect(try GitCommandLine.tokenize(quoted) == [value])
    }

    @Test
    func displayRoundTripsWholeArgumentLists() throws {
        let arguments = ["-c", "core.editor=true", "commit", "--message=" + Self.awkwardValues.joined(separator: "|"), ""]
        #expect(try GitCommandLine.tokenize(GitCommandLine.display(arguments)) == arguments)
    }

    @Test
    func quoteLeavesSafeWordsBare() {
        #expect(GitCommandLine.quote("refs/heads/feature-1_a.b") == "refs/heads/feature-1_a.b")
        #expect(GitCommandLine.quote("--format=%H") == "--format=%H")
        #expect(GitCommandLine.quote("a b") == "'a b'")
        #expect(GitCommandLine.quote("") == "''")
    }

    @Test(arguments: awkwardValues.filter { !$0.hasSuffix("\\") })
    func logGraphQuoteRoundTrips(value: String) throws {
        #expect(try GitCommandLine.tokenize(GitClient.logGraphQuote(value)) == [value])
    }

    @Test(arguments: [
        "/Users/test/plain",
        "/Users/test/with space/project",
        "/Users/test/it's here",
        "/Users/test/quote\"inside",
        "/Users/test/$HOME/dollar",
        "/Users/test/`tick`",
        "/Users/test/ünï"
    ])
    func escapedDirectoryRoundTrips(path: String) throws {
        #expect(try GitCommandLine.tokenize(path.escapedDirectory()) == [path])
    }

    @Test
    func escapedWhiteSpacesRoundTrips() throws {
        #expect(try GitCommandLine.tokenize("/Users/test/with space/a b".escapedWhiteSpaces()) == [
            "/Users/test/with space/a b"
        ])
    }

    @Test
    func branchOperationStyleQuotingRoundTrips() throws {
        for value in Self.awkwardValues where !value.isEmpty {
            let escaped = value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            #expect(try GitCommandLine.tokenize("checkout \"\(escaped)\"") == ["checkout", value])
        }
    }

    @Test
    func clientTurnsMalformedCommandsIntoOutputErrors() async throws {
        try await withTempDir { directory in
            let client = GitClient(directoryURL: directory, shellClient: .live())
            await #expect(throws: GitClient.GitClientError.outputError("Malformed git command: unterminated double quote")) {
                try await client.run("log \"unterminated")
            }
        }
    }
}
