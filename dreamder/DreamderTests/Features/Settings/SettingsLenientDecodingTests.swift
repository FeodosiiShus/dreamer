import Foundation
import Testing
@testable import Dreamder

nonisolated struct LenientDecodingCase: Sendable, CustomTestStringConvertible {
    let section: String
    let corrupted: String
    let expected: String

    var testDescription: String { section }
}

@MainActor
@Suite(.serialized, .uiGate)
struct SettingsLenientDecodingTests {
    nonisolated static let sections = [
        "general", "navigation", "theme", "textEditing", "terminal",
        "sourceControl", "search", "languageServers", "developerSettings", "markdownPreview"
    ]

    nonisolated static let cases = [
        LenientDecodingCase(
            section: "general",
            corrupted: #"{"general":{"isAutoSaveOn":"yes","dimEditorsWithoutFocus":true,"appAppearance":"light"}}"#,
            expected: #"{"general":{"dimEditorsWithoutFocus":true,"appAppearance":"light"}}"#
        ),
        LenientDecodingCase(
            section: "general unknown enum case",
            corrupted: #"{"general":{"fileIconStyle":"sepia","reopenBehavior":"newDocument"}}"#,
            expected: #"{"general":{"reopenBehavior":"newDocument"}}"#
        ),
        LenientDecodingCase(
            section: "general null value",
            corrupted: #"{"general":{"isAutoSaveOn":null,"dimEditorsWithoutFocus":true}}"#,
            expected: #"{"general":{"dimEditorsWithoutFocus":true}}"#
        ),
        LenientDecodingCase(
            section: "navigation",
            corrupted: #"{"navigation":{"navigationStyle":"sideways"},"general":{"dimEditorsWithoutFocus":true}}"#,
            expected: #"{"general":{"dimEditorsWithoutFocus":true}}"#
        ),
        LenientDecodingCase(
            section: "theme",
            corrupted: #"{"theme":{"selectedTheme":5,"useThemeBackground":false,"matchAppearance":false}}"#,
            expected: #"{"theme":{"useThemeBackground":false,"matchAppearance":false}}"#
        ),
        LenientDecodingCase(
            section: "theme overrides",
            corrupted: #"{"theme":{"overrides":["x"],"selectedDarkTheme":"Custom Dark"}}"#,
            expected: #"{"theme":{"selectedDarkTheme":"Custom Dark"}}"#
        ),
        LenientDecodingCase(
            section: "textEditing",
            corrupted: #"{"textEditing":{"defaultTabWidth":"2","showGutter":false,"reformatAtColumn":80}}"#,
            expected: #"{"textEditing":{"showGutter":false,"reformatAtColumn":80}}"#
        ),
        LenientDecodingCase(
            section: "textEditing nested font",
            corrupted: #"{"textEditing":{"font":{"size":"large","name":"Menlo"},"lineHeightMultiple":1.5}}"#,
            expected: #"{"textEditing":{"font":{"name":"Menlo"},"lineHeightMultiple":1.5}}"#
        ),
        LenientDecodingCase(
            section: "textEditing inlay hints",
            corrupted: #"{"textEditing":{"inlayHints":{"enabled":"on","types":false},"formatOnSave":true}}"#,
            expected: #"{"textEditing":{"inlayHints":{"types":false},"formatOnSave":true}}"#
        ),
        LenientDecodingCase(
            section: "terminal",
            corrupted: #"{"terminal":{"shell":"fish","cursorBlink":true,"font":{"size":14,"name":7}}}"#,
            expected: #"{"terminal":{"cursorBlink":true,"font":{"size":14}}}"#
        ),
        LenientDecodingCase(
            section: "sourceControl key",
            corrupted: #"""
            {"sourceControl":{"general":{"refreshStatusLocally":"no","selectFilesToCommit":false},
            "git":{"showMergeCommitsPerFileLog":true}}}
            """#,
            expected: #"""
            {"sourceControl":{"general":{"selectFilesToCommit":false},
            "git":{"showMergeCommitsPerFileLog":true}}}
            """#
        ),
        LenientDecodingCase(
            section: "sourceControl subsection",
            corrupted: #"{"sourceControl":{"general":7,"git":{"showMergeCommitsPerFileLog":true}}}"#,
            expected: #"{"sourceControl":{"git":{"showMergeCommitsPerFileLog":true}}}"#
        ),
        LenientDecodingCase(
            section: "search",
            corrupted: #"{"search":{"ignoreGlobPatterns":"*.log"},"general":{"dimEditorsWithoutFocus":true}}"#,
            expected: #"{"general":{"dimEditorsWithoutFocus":true}}"#
        ),
        LenientDecodingCase(
            section: "languageServers",
            corrupted: #"""
            {"languageServers":{"installedLanguageServers":[]},"navigation":{"navigationStyle":"openInPlace"}}
            """#,
            expected: #"{"navigation":{"navigationStyle":"openInPlace"}}"#
        ),
        LenientDecodingCase(
            section: "developerSettings",
            corrupted: #"{"developerSettings":{"lspBinaries":{"swift":1},"showInternalDevelopmentInspector":true}}"#,
            expected: #"{"developerSettings":{"showInternalDevelopmentInspector":true}}"#
        ),
        LenientDecodingCase(
            section: "markdownPreview",
            corrupted: #"{"markdownPreview":{"fontSize":"big","isVerticalSplit":false,"lastLayout":"previewOnly"}}"#,
            expected: #"{"markdownPreview":{"isVerticalSplit":false,"lastLayout":"previewOnly"}}"#
        ),
        LenientDecodingCase(
            section: "markdownPreview layout",
            corrupted: #"{"markdownPreview":{"lastLayout":"floating","fontSize":18,"isAutoScrollEnabled":0}}"#,
            expected: #"{"markdownPreview":{"fontSize":18}}"#
        )
    ]

    private func decode(_ json: String) throws -> SettingsData {
        try JSONDecoder().decode(SettingsData.self, from: Data(json.utf8))
    }

    private func jsonObject(of settings: SettingsData) throws -> [String: Any] {
        let data = try JSONEncoder().encode(settings)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func paths(in object: [String: Any], prefix: [String] = []) -> [[String]] {
        object.keys.sorted().flatMap { key -> [[String]] in
            let path = prefix + [key]
            guard let nested = object[key] as? [String: Any] else { return [path] }
            return [path] + paths(in: nested, prefix: path)
        }
    }

    private func replacing(_ object: [String: Any], at path: [String], with value: Any) -> [String: Any] {
        guard let key = path.first else { return object }
        var copy = object
        if path.count == 1 {
            copy[key] = value
        } else if let nested = object[key] as? [String: Any] {
            copy[key] = replacing(nested, at: Array(path.dropFirst()), with: value)
        }
        return copy
    }

    @Test(arguments: SettingsLenientDecodingTests.cases)
    func oneMalformedValueCostsOnlyThatValue(_ scenario: LenientDecodingCase) throws {
        let corrupted = try decode(scenario.corrupted)
        let expected = try decode(scenario.expected)

        #expect(corrupted == expected)
        #expect(corrupted != SettingsData())
    }

    @Test(arguments: SettingsLenientDecodingTests.sections)
    func aWrongTypedSectionCostsOnlyThatSection(_ section: String) throws {
        let witness = section == "general"
            ? #""navigation":{"navigationStyle":"openInPlace"}"#
            : #""general":{"dimEditorsWithoutFocus":true}"#
        let corrupted = try decode(#"{"\#(section)":"oops",\#(witness)}"#)
        let expected = try decode("{\(witness)}")

        #expect(corrupted == expected)
        #expect(corrupted != SettingsData())
    }

    @Test
    func corruptingAnyKeyOfADefaultFileStillDecodesToTheDefaults() throws {
        let defaults = SettingsData()
        let object = try jsonObject(of: defaults)
        let allPaths = paths(in: object)

        #expect(allPaths.count > 60)
        for path in allPaths {
            let corrupted = replacing(object, at: path, with: ["corrupt": true])
            let data = try JSONSerialization.data(withJSONObject: corrupted)

            let decoded = try JSONDecoder().decode(SettingsData.self, from: data)

            #expect(decoded == defaults, "corrupting \(path.joined(separator: ".")) changed other settings")
        }
    }

    @Test
    func aRootThatIsNotAnObjectStillFailsSoTheFileIsPreserved() {
        #expect(throws: DecodingError.self) { try decode("[1, 2]") }
        #expect(throws: DecodingError.self) { try decode("5") }
    }

    @Test
    func absentKeysAndEmptySectionsDecodeToDefaults() throws {
        #expect(try decode("{}") == SettingsData())
        let sparseFile = #"{"general":{},"textEditing":{},"terminal":{"font":{}},"markdownPreview":{}}"#
        #expect(try decode(sparseFile) == SettingsData())
    }
}
