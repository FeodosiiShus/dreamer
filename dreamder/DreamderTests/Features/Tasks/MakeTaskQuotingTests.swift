import Foundation
import Testing
@testable import Dreamder

@Suite
struct MakeTaskQuotingTests {
    @Test
    func targetsWithShellSyntaxAreQuotedIntoOneWord() async throws {
        let groups = try await TaskDiscoveryFixture.discover([
            "Makefile": ".PHONY: x;{curl,-sL,host}|sh ok\nok:\n\techo ok\n"
        ])

        #expect(groups.first?.tasks.map(\.command) == ["make 'x;{curl,-sL,host}|sh'", "make ok"])
    }

    @Test(arguments: [
        ("it's", "make 'it'\\''s'"),
        ("a`id`b", "make 'a`id`b'"),
        ("say\"hi\"", "make 'say\"hi\"'"),
        ("a;b", "make 'a;b'"),
        ("a&b", "make 'a&b'"),
        ("a|b", "make 'a|b'"),
        ("a>b", "make 'a>b'"),
        ("a\\b", "make 'a\\b'"),
        ("a*b", "make 'a*b'"),
        ("~home", "make '~home'"),
        ("ünï", "make 'ünï'"),
        ("build-all_1.2:x", "make build-all_1.2:x")
    ])
    func phonyTargetCommandsAreQuoted(target: String, expected: String) async throws {
        let groups = try await TaskDiscoveryFixture.discover(["Makefile": ".PHONY: \(target)\n"])

        #expect(groups.first?.tasks.map(\.command) == [expected])
        #expect(groups.first?.tasks.map(\.name) == [expected])
    }

    @Test
    func ruleTargetsAreQuotedToo() async throws {
        let groups = try await TaskDiscoveryFixture.discover(["Makefile": "a;b: dep\n\techo\n"])

        #expect(groups.first?.tasks.map(\.command) == ["make 'a;b'"])
    }

    @Test(arguments: [
        "x;{curl,-sL,host}|sh",
        "it's",
        "a`id`b",
        "say\"hi\"",
        "a&b",
        "a\\b",
        "a*b",
        "~home"
    ])
    func theShellReceivesTheTargetAsExactlyOneArgument(target: String) async throws {
        let groups = try await TaskDiscoveryFixture.discover(["Makefile": ".PHONY: \(target)\n"])
        let command = try #require(groups.first?.tasks.first?.command)
        let script = "make() { printf '%s:%s' \"$#\" \"$1\"; }; " + command

        try await withTempDir { directory in
            let output = try await ProcessRunner().run(ProcessTestSupport.shell(script, workingDirectory: directory))

            #expect(output.succeeded)
            #expect(output.standardOutputText == "1:" + target)
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).isEmpty)
        }
    }

    @Test
    func targetsThatLookLikeMakeOptionsAreNotOffered() async throws {
        let groups = try await TaskDiscoveryFixture.discover([
            "Makefile": ".PHONY: -k --eval-x -ffoo ok\n"
        ])

        #expect(groups.first?.tasks.map(\.command) == ["make ok"])
    }

    @Test
    func ruleTargetsThatLookLikeMakeOptionsAreNotOffered() async throws {
        let groups = try await TaskDiscoveryFixture.discover(["Makefile": "-k:\nall:\n"])

        #expect(groups.first?.tasks.map(\.command) == ["make all"])
    }
}
