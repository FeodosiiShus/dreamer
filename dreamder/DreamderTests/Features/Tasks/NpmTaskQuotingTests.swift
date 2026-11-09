import Foundation
import Testing
@testable import Dreamder

@Suite
struct NpmTaskQuotingTests {
    @Test
    func scriptNamesAreShellQuotedSoTheyCannotInjectCommands() async throws {
        let manifest = """
        {"scripts":{"build;curl x|sh":"a","it's":"b","dev":"c","$(id)":"d","a b":"e","build:prod":"f"}}
        """
        let groups = try await TaskDiscoveryFixture.discover(["package.json": manifest])
        #expect(groups.first?.tasks.map(\.command) == [
            "npm run '$(id)'",
            "npm run 'a b'",
            "npm run build:prod",
            "npm run 'build;curl x|sh'",
            "npm run dev",
            "npm run 'it'\\''s'"
        ])
    }

    @Test
    func scriptNamesThatLookLikeOptionsOrAreEmptyAreNotOffered() async throws {
        let manifest = #"{"scripts":{"--script-shell=/tmp/evil":"a","-x":"b","":"c","dev":"d"}}"#
        let groups = try await TaskDiscoveryFixture.discover(["package.json": manifest])
        #expect(groups.first?.tasks.map(\.command) == ["npm run dev"])
    }

    @Test(arguments: [
        ("plain", "plain"),
        ("with space", "'with space'"),
        ("quote'inside", "'quote'\\''inside'"),
        ("semi;colon", "'semi;colon'"),
        ("~home", "'~home'"),
        ("=expand", "'=expand'")
    ])
    func shellWordsAreQuotedOnlyWhenNeeded(value: String, expected: String) {
        #expect(NpmTaskDiscovery.shellWord(value) == expected)
    }
}
