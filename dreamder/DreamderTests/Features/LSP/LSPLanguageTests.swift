import CodeEditLanguages
import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@Suite("LSP language")
struct LSPLanguageTests {
    private static let staticRawValues: [(LSPLanguage, String)] = [
        (.swift, "swift"),
        (.objc, "objective-c"),
        (.objcpp, "objective-cpp"),
        (.c, "c"),
        (.cpp, "cpp"),
        (.typescript, "typescript"),
        (.javascript, "javascript"),
        (.typescriptreact, "typescriptreact"),
        (.javascriptreact, "javascriptreact"),
        (.python, "python"),
        (.go, "go"),
        (.rust, "rust"),
        (.json, "json"),
        (.css, "css"),
        (.scss, "scss"),
        (.less, "less"),
        (.html, "html"),
        (.java, "java"),
        (.yaml, "yaml"),
        (.shellscript, "shellscript"),
        (.kotlin, "kotlin"),
        (.toml, "toml")
    ]

    @Test(arguments: staticRawValues)
    func staticsCarryTheLanguageIdentifierRawValue(language: LSPLanguage, rawValue: String) {
        #expect(language.rawValue == rawValue)
        #expect(LSPLanguage(rawValue: rawValue) == language)
    }

    @Test func initFromIdentifierUsesItsRawValue() {
        for identifier in LanguageIdentifier.allCases {
            #expect(LSPLanguage(identifier).rawValue == identifier.rawValue)
        }
    }

    @Test func knownContainsEveryIdentifierPlusKotlinAndToml() {
        let known = LSPLanguage.known
        for identifier in LanguageIdentifier.allCases {
            #expect(known.contains(LSPLanguage(identifier)))
        }
        #expect(known.contains(.kotlin))
        #expect(known.contains(.toml))
        #expect(known.count == LanguageIdentifier.allCases.count + 2)
        #expect(Set(known).count == known.count)
    }

    @Test func knownRawValuesMirrorKnown() {
        #expect(LSPLanguage.knownRawValues == LSPLanguage.known.map(\.rawValue))
        #expect(LSPLanguage.knownRawValues.contains("kotlin"))
        #expect(LSPLanguage.knownRawValues.contains("toml"))
        #expect(LSPLanguage.knownRawValues.contains("objective-c"))
    }

    @Test func hashableTreatsEqualRawValuesAsOneElement() {
        let set: Set<LSPLanguage> = [.swift, LSPLanguage(rawValue: "swift"), LSPLanguage(.swift), .kotlin]
        #expect(set.count == 2)
        #expect(LSPLanguage(rawValue: "brainfuck") != .swift)
        #expect(LSPLanguage(rawValue: "brainfuck").rawValue == "brainfuck")
    }

    private static let families: [(LSPLanguage, LSPLanguage)] = [
        (.typescript, .typescript),
        (.javascript, .typescript),
        (.typescriptreact, .typescript),
        (.javascriptreact, .typescript),
        (.css, .css),
        (.scss, .css),
        (.less, .css),
        (.c, .c),
        (.cpp, .c),
        (.objcpp, .c),
        (.swift, .swift),
        (.objc, .swift),
        (.python, .python),
        (.go, .go),
        (.rust, .rust),
        (.json, .json),
        (.html, .html),
        (.java, .java),
        (.yaml, .yaml),
        (.shellscript, .shellscript),
        (.kotlin, .kotlin),
        (.toml, .toml)
    ]

    @Test(arguments: families)
    func serverFamilyTable(language: LSPLanguage, family: LSPLanguage) {
        #expect(language.serverFamily == family)
        #expect(family.serverFamily == family)
    }

    @Test func serverFamilyOfUnlistedLanguagesIsThemselves() {
        let grouped: Set<LSPLanguage> = [
            .typescript, .javascript, .typescriptreact, .javascriptreact,
            .css, .scss, .less, .c, .cpp, .objcpp, .swift, .objc
        ]
        for language in LSPLanguage.known where !grouped.contains(language) {
            #expect(language.serverFamily == language)
            #expect(language.familyMembers == [language])
        }
    }

    private static let familyMemberSets: [(LSPLanguage, Set<LSPLanguage>)] = [
        (.typescript, [.typescript, .javascript, .typescriptreact, .javascriptreact]),
        (.javascriptreact, [.typescript, .javascript, .typescriptreact, .javascriptreact]),
        (.scss, [.css, .scss, .less]),
        (.cpp, [.c, .cpp, .objcpp]),
        (.objc, [.swift, .objc])
    ]

    @Test(arguments: familyMemberSets)
    func familyMembersListEveryLanguageOfTheServer(language: LSPLanguage, members: Set<LSPLanguage>) {
        #expect(Set(language.familyMembers) == members)
        #expect(language.familyMembers.count == members.count)
    }
}

@MainActor
@Suite("CodeLanguage to LSP language", .uiGate)
struct CodeLanguageLSPLanguageTests {
    private nonisolated static let expectations: [(String, String?)] = [
        ("agda", nil),
        ("bash", "shellscript"),
        ("c", "c"),
        ("cpp", "cpp"),
        ("cSharp", "csharp"),
        ("css", "css"),
        ("dart", "dart"),
        ("dockerfile", "dockerfile"),
        ("elixir", "elixir"),
        ("go", "go"),
        ("goMod", "go"),
        ("haskell", nil),
        ("html", "html"),
        ("java", "java"),
        ("javascript", "javascript"),
        ("jsdoc", "javascript"),
        ("json", "json"),
        ("jsx", "javascriptreact"),
        ("julia", nil),
        ("kotlin", "kotlin"),
        ("lua", "lua"),
        ("markdown", "markdown"),
        ("markdownInline", "markdown"),
        ("objc", "objective-c"),
        ("ocaml", nil),
        ("ocamlInterface", nil),
        ("perl", "perl"),
        ("php", "php"),
        ("python", "python"),
        ("regex", nil),
        ("ruby", "ruby"),
        ("rust", "rust"),
        ("scala", "scala"),
        ("sql", "sql"),
        ("swift", "swift"),
        ("toml", "toml"),
        ("tsx", "typescriptreact"),
        ("typescript", "typescript"),
        ("verilog", nil),
        ("yaml", "yaml"),
        ("zig", nil),
        ("plainText", nil)
    ]

    private static func language(named name: String) -> CodeLanguage? {
        let all = CodeLanguage.allLanguages + [CodeLanguage.default]
        return all.first { $0.id.rawValue == name }
    }

    @Test(arguments: expectations)
    func mapsEveryCodeLanguage(name: String, expected: String?) throws {
        let language = try #require(Self.language(named: name))
        #expect(language.lspLanguage?.rawValue == expected)
        #expect(language.lspLanguageId == (expected ?? "plaintext"))
    }

    @Test func tableCoversEveryLanguageOfThePackage() {
        let covered = Set(Self.expectations.map(\.0))
        let packageIds = Set((CodeLanguage.allLanguages + [CodeLanguage.default]).map { $0.id.rawValue })
        #expect(covered == packageIds)
    }

    @Test func plainTextHasNoLanguageAndFallsBackToPlaintextId() {
        #expect(CodeLanguage.default.lspLanguage == nil)
        #expect(CodeLanguage.default.lspLanguageId == "plaintext")
    }

    @Test func specialisedReactAndShellIdsAreDistinctFromTheirParents() {
        #expect(CodeLanguage.tsx.lspLanguage == .typescriptreact)
        #expect(CodeLanguage.jsx.lspLanguage == .javascriptreact)
        #expect(CodeLanguage.bash.lspLanguage == .shellscript)
        #expect(CodeLanguage.kotlin.lspLanguage == .kotlin)
        #expect(CodeLanguage.toml.lspLanguage == .toml)
    }
}
