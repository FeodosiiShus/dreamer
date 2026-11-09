import Testing
@testable import Dreamder

struct EditorConfigParserTests {
    private func section(_ name: String, _ pairs: [(String, String)]) -> EditorConfigFile.Section {
        EditorConfigFile.Section(name: name, pairs: pairs.map { EditorConfigFile.Pair(key: $0.0, value: $0.1) })
    }

    @Test func emptyTextIsNotRoot() {
        #expect(EditorConfigResolver.parse("") == EditorConfigFile(isRoot: false, sections: []))
    }

    @Test func commentsAndBlankLinesAreIgnored() {
        let text = "# hash\n; semi\n\n   \n  # indented\n[*]\n; inside\nindent_size = 2\n"
        #expect(EditorConfigResolver.parse(text) == EditorConfigFile(
            isRoot: false,
            sections: [section("*", [("indent_size", "2")])]
        ))
    }

    @Test(arguments: [
        ("root = true", true),
        ("root=TRUE", true),
        ("ROOT = True  ", true),
        ("root = false", false),
        ("root = yes", false),
        ("root =", false)
    ])
    func rootFlag(_ line: String, _ expected: Bool) {
        #expect(EditorConfigResolver.parse(line).isRoot == expected)
    }

    @Test func rootOutsidePreambleIsNotRootFlag() {
        let file = EditorConfigResolver.parse("[*]\nroot = true\n")
        #expect(file.isRoot == false)
        #expect(file.sections == [section("*", [("root", "true")])])
    }

    @Test func preambleOtherPairsAreDropped() {
        let file = EditorConfigResolver.parse("indent_size = 4\nroot = true\n[*.c]\ntab_width = 8\n")
        #expect(file == EditorConfigFile(isRoot: true, sections: [section("*.c", [("tab_width", "8")])]))
    }

    @Test func byteOrderMarkIsTolerated() {
        let file = EditorConfigResolver.parse("\u{FEFF}root = true\n[*]\nindent_style = tab\n")
        #expect(file.isRoot)
        #expect(file.sections == [section("*", [("indent_style", "tab")])])
    }

    @Test func crlfLineEndingsAreTolerated() {
        let file = EditorConfigResolver.parse("root = true\r\n\r\n[*.swift]\r\nindent_size = 4\r\ncharset = UTF-8\r\n")
        #expect(file.isRoot)
        #expect(file.sections == [section("*.swift", [("indent_size", "4"), ("charset", "utf-8")])])
    }

    @Test func keysAreLowercasedAndKnownValuesToo() {
        let file = EditorConfigResolver.parse("[*]\nINDENT_STYLE = Tab\nEnd_Of_Line = CRLF\nCustom_Key = MixedCase\n")
        #expect(file.sections == [section("*", [
            ("indent_style", "tab"),
            ("end_of_line", "crlf"),
            ("custom_key", "MixedCase")
        ])])
    }

    @Test func inlineCommentCharactersBelongToTheValue() {
        let file = EditorConfigResolver.parse("[*.txt]\nfoo = editorconfig ;)\nbar = a # b\n")
        #expect(file.sections == [section("*.txt", [("foo", "editorconfig ;)"), ("bar", "a # b")])])
    }

    @Test func valueSplitsAtFirstEqualsAndKeepsInnerWhitespace() {
        let file = EditorConfigResolver.parse("[*]\nkey =  a = b   c \nempty =\n")
        #expect(file.sections == [section("*", [("key", "a = b   c"), ("empty", "")])])
    }

    @Test func sectionNamesKeepEverythingBetweenOuterBrackets() {
        let file = EditorConfigResolver.parse("[[ab].a]\n[ a b ]\n[a]]\n  [*.c]  \n[]\n")
        #expect(file.sections.map(\.name) == ["[ab].a", " a b ", "a]", "*.c", ""])
    }

    @Test func invalidLinesAreIgnored() {
        let text = "just text\n[unterminated\n= value\n[*]\nno separator\n = nothing\nkey = ok\n"
        #expect(EditorConfigResolver.parse(text).sections == [section("*", [("key", "ok")])])
    }

    @Test func laterSectionsStaySeparateAndOrdered() {
        let file = EditorConfigResolver.parse("[*]\na = 1\n[*.c]\nb = 2\n[*]\nc = 3\n")
        #expect(file.sections == [
            section("*", [("a", "1")]),
            section("*.c", [("b", "2")]),
            section("*", [("c", "3")])
        ])
    }

    @Test func oversizedSectionNameDropsItsPairsOnly() {
        let longName = String(repeating: "a", count: 1025)
        let exactName = String(repeating: "b", count: 1024)
        let file = EditorConfigResolver.parse("[*]\nx = 1\n[\(longName)]\ny = 2\n[\(exactName)]\nz = 3\n")
        #expect(file.sections == [section("*", [("x", "1")]), section(exactName, [("z", "3")])])
    }

    @Test func oversizedKeyAndValueAreDropped() {
        let longKey = String(repeating: "k", count: 1025)
        let exactKey = String(repeating: "k", count: 1024)
        let longValue = String(repeating: "v", count: 4097)
        let exactValue = String(repeating: "v", count: 4096)
        let file = EditorConfigResolver.parse("[*]\n\(longKey) = 1\n\(exactKey) = 2\nbig = \(longValue)\nfit = \(exactValue)\n")
        #expect(file.sections == [section("*", [(exactKey, "2"), ("fit", exactValue)])])
    }

    @Test func oversizedFirstSectionYieldsNoSections() {
        let longName = String(repeating: "a", count: 1025)
        let file = EditorConfigResolver.parse("[\(longName)]\nx = 1\n")
        #expect(file.sections.isEmpty)
    }
}
