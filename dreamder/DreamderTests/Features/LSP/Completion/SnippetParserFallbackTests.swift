import Foundation
import Testing
@testable import Dreamder

@Suite("Snippet parser fallbacks")
struct SnippetParserFallbackTests {
    static let malformed: [String] = [
        "$",
        "a$",
        "${",
        "${1",
        "${a",
        "${-}",
        "${1x}",
        "${1x",
        "${a-b}",
        "${1:x",
        "${a:x",
        "${1|a,b",
        "${1|a,b}",
        "$99999999999999999999",
        "${99999999999999999999}",
        "a\\",
        "\\",
        "\\q"
    ]

    @Test(arguments: SnippetParserFallbackTests.malformed)
    func malformedPlaceholdersStayLiteralText(_ source: String) {
        #expect(SnippetParser.parse(source) == [.text(source)])
    }

    @Test
    func aTrailingBackslashAfterAValidPlaceholderIsKept() {
        #expect(SnippetParser.parse("$1\\") == [.tabStop(index: 1, children: [], choices: []), .text("\\")])
    }

    @Test
    func anOverflowingIndexFallsBackWithoutHidingTheNextPlaceholder() {
        #expect(SnippetParser.parse("${99999999999999999999}$2") == [
            .text("${99999999999999999999}"),
            .tabStop(index: 2, children: [], choices: [])
        ])
    }
}
