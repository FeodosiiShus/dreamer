import Foundation
import Testing
@testable import Dreamder

@Suite
struct StringShellQuotedTests {
    static let hostileValues = [
        "plain",
        "",
        " ",
        "with space",
        "multiple   spaces",
        "it's",
        "'",
        "''",
        "'quoted'",
        "say \"hi\"",
        "$HOME",
        "a$b",
        "$(touch pwned)",
        "`touch pwned`",
        "a;b",
        "x;{curl,-sL,host}|sh",
        "a && b || c",
        "a | b > c < d",
        "a & b",
        "*.swift ?",
        "[abc]",
        "{a,b}",
        "~tilde",
        "=assign",
        "#hash",
        "!bang",
        "a\\",
        "\\",
        "\\\\",
        "a\\'b",
        "back\\slash",
        "line\nbreak",
        "\nleading",
        "tab\tsep",
        "-leading-dash",
        "ünïcödé 日本語 🙂"
    ]

    @Test(arguments: [
        ("plain", "plain"),
        ("/Users/test/project-1_a.b", "/Users/test/project-1_a.b"),
        ("name:with@safe+chars,only", "name:with@safe+chars,only"),
        ("", "''"),
        ("with space", "'with space'"),
        ("it's", "'it'\\''s'"),
        ("'", "''\\'''"),
        ("say \"hi\"", "'say \"hi\"'"),
        ("a$b", "'a$b'"),
        ("`id`", "'`id`'"),
        ("a;b", "'a;b'"),
        ("a\\", "'a\\'"),
        ("line\nbreak", "'line\nbreak'"),
        ("~home", "'~home'"),
        ("=expand", "'=expand'"),
        ("ünï", "'ünï'")
    ])
    func wordsAreQuotedOnlyWhenNeeded(value: String, expected: String) {
        #expect(value.shellQuoted() == expected)
    }

    @Test(arguments: hostileValues)
    func theShellSeesExactlyOneWordWithTheOriginalValue(value: String) async throws {
        let script = "set -- \(value.shellQuoted()); printf '%s:%s' \"$#\" \"$1\""

        let output = try await ProcessRunner().run(ProcessTestSupport.shell(script))

        #expect(output.succeeded)
        #expect(output.standardOutputText == "1:" + value)
    }

    @Test(arguments: hostileValues)
    func quotedValuesNeverExecuteAnything(value: String) async throws {
        try await withTempDir { directory in
            let script = "printf %s \(value.shellQuoted()) > /dev/null"

            let output = try await ProcessRunner().run(ProcessTestSupport.shell(script, workingDirectory: directory))

            #expect(output.succeeded)
            #expect(output.standardErrorText.isEmpty)
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).isEmpty)
        }
    }

    @Test
    func severalQuotedWordsStayDistinctArguments() async throws {
        let values = ["a b", "it's", "$HOME", ""]
        let script = "printf '%s|' " + values.map { $0.shellQuoted() }.joined(separator: " ")

        let output = try await ProcessRunner().run(ProcessTestSupport.shell(script))

        #expect(output.standardOutputText == "a b|it's|$HOME||")
    }
}
