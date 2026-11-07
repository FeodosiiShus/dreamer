import AppKit
import Foundation
import Testing
@testable import Dreamder

@Suite
struct ThemeTests {
    typealias Attributes = Theme.Attributes
    typealias EditorColors = Theme.EditorColors
    typealias TerminalColors = Theme.TerminalColors

    private static let neutral = Attributes(color: "#000000")

    private static let editorKeyPaths: [(String, WritableKeyPath<EditorColors, Attributes>)] = [
        ("text", \.text),
        ("insertionPoint", \.insertionPoint),
        ("invisibles", \.invisibles),
        ("background", \.background),
        ("lineHighlight", \.lineHighlight),
        ("selection", \.selection),
        ("keywords", \.keywords),
        ("commands", \.commands),
        ("types", \.types),
        ("attributes", \.attributes),
        ("variables", \.variables),
        ("values", \.values),
        ("numbers", \.numbers),
        ("strings", \.strings),
        ("characters", \.characters),
        ("comments", \.comments)
    ]

    private static let terminalKeyPaths: [(String, WritableKeyPath<TerminalColors, Attributes>)] = [
        ("text", \.text),
        ("boldText", \.boldText),
        ("cursor", \.cursor),
        ("background", \.background),
        ("selection", \.selection),
        ("black", \.black),
        ("red", \.red),
        ("green", \.green),
        ("yellow", \.yellow),
        ("blue", \.blue),
        ("magenta", \.magenta),
        ("cyan", \.cyan),
        ("white", \.white),
        ("brightBlack", \.brightBlack),
        ("brightRed", \.brightRed),
        ("brightGreen", \.brightGreen),
        ("brightYellow", \.brightYellow),
        ("brightBlue", \.brightBlue),
        ("brightMagenta", \.brightMagenta),
        ("brightCyan", \.brightCyan),
        ("brightWhite", \.brightWhite)
    ]

    private static func attributes(_ number: Int) -> Attributes {
        Attributes(color: String(format: "#%06x", number))
    }

    private static func makeEditorColors(offset: Int = 0) -> EditorColors {
        EditorColors(
            text: attributes(offset + 1),
            insertionPoint: attributes(offset + 2),
            invisibles: attributes(offset + 3),
            background: attributes(offset + 4),
            lineHighlight: attributes(offset + 5),
            selection: attributes(offset + 6),
            keywords: attributes(offset + 7),
            commands: attributes(offset + 8),
            types: attributes(offset + 9),
            attributes: attributes(offset + 10),
            variables: attributes(offset + 11),
            values: attributes(offset + 12),
            numbers: attributes(offset + 13),
            strings: attributes(offset + 14),
            characters: attributes(offset + 15),
            comments: attributes(offset + 16)
        )
    }

    private static func makeTerminalColors() -> TerminalColors {
        TerminalColors(
            text: attributes(1),
            boldText: attributes(2),
            cursor: attributes(3),
            background: attributes(4),
            selection: attributes(5),
            black: attributes(6),
            red: attributes(7),
            green: attributes(8),
            yellow: attributes(9),
            blue: attributes(10),
            magenta: attributes(11),
            cyan: attributes(12),
            white: attributes(13),
            brightBlack: attributes(14),
            brightRed: attributes(15),
            brightGreen: attributes(16),
            brightYellow: attributes(17),
            brightBlue: attributes(18),
            brightMagenta: attributes(19),
            brightCyan: attributes(20),
            brightWhite: attributes(21)
        )
    }

    private static func makeTheme(name: String = "unit", appearance: Theme.ThemeType = .dark) -> Theme {
        Theme(
            editor: makeEditorColors(),
            terminal: makeTerminalColors(),
            author: "Author",
            license: "MIT",
            metadataDescription: "Description",
            distributionURL: "https://example.com/theme",
            isBundled: true,
            name: name,
            displayName: "Unit Theme",
            appearance: appearance,
            version: "1.2"
        )
    }

    private static func attributesJSON(_ number: Int) -> String {
        "{\"color\":\"\(String(format: "#%06x", number))\"}"
    }

    private static func sectionJSON(keys: [String]) -> String {
        let entries = keys.enumerated().map { "\"\($0.element)\":\(attributesJSON($0.offset + 1))" }
        return "{" + entries.joined(separator: ",") + "}"
    }

    private static func themeJSON(omitting omitted: Set<String> = [], type: String = "light") -> String {
        let fields: [(String, String)] = [
            ("author", "\"Ada\""),
            ("license", "\"MIT\""),
            ("description", "\"A theme\""),
            ("distributionURL", "\"https://example.com\""),
            ("name", "\"ada-light\""),
            ("displayName", "\"Ada Light\""),
            ("version", "\"3\""),
            ("type", "\"\(type)\""),
            ("editor", sectionJSON(keys: editorKeyPaths.map(\.0))),
            ("terminal", sectionJSON(keys: terminalKeyPaths.map(\.0)))
        ]
        let entries = fields.filter { !omitted.contains($0.0) }.map { "\"\($0.0)\":\($0.1)" }
        return "{" + entries.joined(separator: ",") + "}"
    }

    private static func decodeTheme(_ json: String) throws -> Theme {
        try JSONDecoder().decode(Theme.self, from: Data(json.utf8))
    }

    @Test
    func editorSubscriptGetterReturnsTheNamedProperty() {
        let colors = Self.makeEditorColors()

        for (key, keyPath) in Self.editorKeyPaths {
            #expect(colors[key] == colors[keyPath: keyPath], "key \(key)")
        }
        #expect(colors["text"].color == "#000001")
        #expect(colors["comments"].color == "#000010")
    }

    @Test
    func editorSubscriptSetterWritesOnlyTheNamedProperty() {
        let base = Self.makeEditorColors()
        let replacement = Attributes(color: "#ffffff", bold: true, italic: true)

        for (key, keyPath) in Self.editorKeyPaths {
            var colors = base
            colors[key] = replacement

            #expect(colors[keyPath: keyPath] == replacement, "key \(key)")
            for (other, otherKeyPath) in Self.editorKeyPaths where other != key {
                #expect(
                    colors[keyPath: otherKeyPath] == base[keyPath: otherKeyPath],
                    "key \(key) leaked into \(other)"
                )
            }
        }
    }

    @Test
    func editorSubscriptUnknownKeyReturnsNeutralBlack() {
        let colors = Self.makeEditorColors()

        for key in ["", "Text", "TEXT", "boldText", "brightRed", "unknown"] {
            #expect(colors[key] == Self.neutral, "key \(key)")
        }
        #expect(colors["unknown"].bold == false)
        #expect(colors["unknown"].italic == false)
    }

    @Test
    func editorSubscriptUnknownKeySetterChangesNothing() {
        let base = Self.makeEditorColors()
        var colors = base

        colors["unknown"] = Attributes(color: "#ffffff", bold: true)
        colors["boldText"] = Attributes(color: "#ffffff", bold: true)

        #expect(colors == base)
    }

    @Test
    func terminalSubscriptGetterReturnsTheNamedProperty() {
        let colors = Self.makeTerminalColors()

        for (key, keyPath) in Self.terminalKeyPaths {
            #expect(colors[key] == colors[keyPath: keyPath], "key \(key)")
        }
        #expect(colors["boldText"].color == "#000002")
        #expect(colors["brightWhite"].color == "#000015")
    }

    @Test
    func terminalSubscriptSetterWritesOnlyTheNamedProperty() {
        let base = Self.makeTerminalColors()
        let replacement = Attributes(color: "#fedcba", bold: true)

        for (key, keyPath) in Self.terminalKeyPaths {
            var colors = base
            colors[key] = replacement

            #expect(colors[keyPath: keyPath] == replacement, "key \(key)")
            for (other, otherKeyPath) in Self.terminalKeyPaths where other != key {
                #expect(
                    colors[keyPath: otherKeyPath] == base[keyPath: otherKeyPath],
                    "key \(key) leaked into \(other)"
                )
            }
        }
    }

    @Test
    func terminalSubscriptUnknownKeyReturnsNeutralBlackAndSetterIsNoOp() {
        let base = Self.makeTerminalColors()
        var colors = base

        for key in ["", "Text", "insertionPoint", "comments", "unknown"] {
            #expect(colors[key] == Self.neutral, "key \(key)")
        }

        colors["unknown"] = Attributes(color: "#ffffff", italic: true)
        colors["lineHighlight"] = Attributes(color: "#ffffff", italic: true)

        #expect(colors == base)
    }

    @Test
    func keyTablesCoverEveryStoredProperty() throws {
        let editorProperties = try Set(Self.makeEditorColors().allProperties().keys)
        let terminalProperties = try Set(Self.makeTerminalColors().allProperties().keys)

        #expect(editorProperties == Set(Self.editorKeyPaths.map(\.0)))
        #expect(terminalProperties == Set(Self.terminalKeyPaths.map(\.0)))
        #expect(editorProperties.count == 16)
        #expect(terminalProperties.count == 21)
    }

    @Test
    func ansiColorsListsTheSixteenPaletteColorsInOrder() {
        let colors = Self.makeTerminalColors()

        #expect(colors.ansiColors == (6...21).map { String(format: "#%06x", $0) })
        #expect(colors.ansiColors.count == 16)
    }

    @Test
    func attributesDefaultToPlainStyle() {
        let attributes = Attributes(color: "#123456")

        #expect(attributes.color == "#123456")
        #expect(attributes.bold == false)
        #expect(attributes.italic == false)
    }

    @Test(arguments: [(false, false), (true, false), (false, true), (true, true)])
    func attributesRoundTripThroughJSON(bold: Bool, italic: Bool) throws {
        let original = Attributes(color: "#a1b2c3", bold: bold, italic: italic)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Attributes.self, from: data)

        #expect(decoded == original)
    }

    @Test
    func attributesEncodingOmitsFalseFlags() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        let plain = try String(decoding: encoder.encode(Attributes(color: "#112233")), as: UTF8.self)
        let bold = try String(decoding: encoder.encode(Attributes(color: "#112233", bold: true)), as: UTF8.self)
        let italic = try String(decoding: encoder.encode(Attributes(color: "#112233", italic: true)), as: UTF8.self)
        let both = try String(
            decoding: encoder.encode(Attributes(color: "#112233", bold: true, italic: true)),
            as: UTF8.self
        )

        #expect(plain == ##"{"color":"#112233"}"##)
        #expect(bold == ##"{"bold":true,"color":"#112233"}"##)
        #expect(italic == ##"{"color":"#112233","italic":true}"##)
        #expect(both == ##"{"bold":true,"color":"#112233","italic":true}"##)
    }

    @Test
    func attributesDecodingTreatsMissingFlagsAsFalse() throws {
        let minimal = try JSONDecoder().decode(Attributes.self, from: Data(##"{"color":"#abcdef"}"##.utf8))
        let explicit = try JSONDecoder().decode(
            Attributes.self,
            from: Data(##"{"color":"#abcdef","bold":true,"italic":false}"##.utf8)
        )

        #expect(minimal == Attributes(color: "#abcdef"))
        #expect(explicit == Attributes(color: "#abcdef", bold: true, italic: false))
    }

    @Test
    func attributesDecodingRequiresColor() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Attributes.self, from: Data(#"{"bold":true}"#.utf8))
        }
    }

    @Test
    func attributesExposeTheirHexColorAsNSColorAndSwiftUIColor() {
        var attributes = Attributes(color: "#1d2e3f")

        #expect(attributes.nsColor.hexString == "#1d2e3f")
        #expect(attributes.swiftColor.hexString == "#1d2e3f")

        attributes.nsColor = NSColor(hex: "#ABCDEF")
        #expect(attributes.color == "#abcdef")

        attributes.swiftColor = .init(hex: "#010203")
        #expect(attributes.color == "#010203")
    }

    @Test
    func editorThemeGetterMapsEveryColorFromTheAttributes() {
        let colors = Self.makeEditorColors(offset: 0x102030)
        let editorTheme = colors.editorTheme

        #expect(editorTheme.text.color.hexString == colors.text.color)
        #expect(editorTheme.insertionPoint.hexString == colors.insertionPoint.color)
        #expect(editorTheme.background.hexString == colors.background.color)
        #expect(editorTheme.selection.hexString == colors.selection.color)
        #expect(editorTheme.keywords.color.hexString == colors.keywords.color)
        #expect(editorTheme.comments.color.hexString == colors.comments.color)
    }

    @Test
    func editorThemeSetterWritesColorsAndKeepsStyleFlags() {
        var colors = Self.makeEditorColors()
        colors.text = Attributes(color: "#000001", bold: true, italic: true)
        let other = Self.makeEditorColors(offset: 0x203040)

        colors.editorTheme = other.editorTheme

        #expect(colors.text == Attributes(color: other.text.color, bold: true, italic: true))
        #expect(colors.background.color == other.background.color)
        #expect(colors.insertionPoint.color == other.insertionPoint.color)
        #expect(colors.comments.color == other.comments.color)
    }

    @Test
    func themeDecodesMinimalDocumentAndAppliesDefaults() throws {
        let theme = try Self.decodeTheme(Self.themeJSON())

        #expect(theme.id == "ada-light")
        #expect(theme.name == "ada-light")
        #expect(theme.displayName == "Ada Light")
        #expect(theme.author == "Ada")
        #expect(theme.license == "MIT")
        #expect(theme.metadataDescription == "A theme")
        #expect(theme.distributionURL == "https://example.com")
        #expect(theme.version == "3")
        #expect(theme.appearance == .light)
        #expect(theme.isBundled == false)
        #expect(theme.fileURL == nil)
        #expect(theme.editor["text"] == Self.attributes(1))
        #expect(theme.editor["comments"] == Self.attributes(16))
        #expect(theme.terminal["text"] == Self.attributes(1))
        #expect(theme.terminal["brightWhite"] == Self.attributes(21))
    }

    @Test
    func themeDecodesDarkAppearance() throws {
        let theme = try Self.decodeTheme(Self.themeJSON(type: "dark"))

        #expect(theme.appearance == .dark)
    }

    @Test
    func themeDecodingRejectsUnknownAppearance() {
        #expect(throws: DecodingError.self) {
            try Self.decodeTheme(Self.themeJSON(type: "sepia"))
        }
    }

    @Test(arguments: [
        "author", "license", "description", "distributionURL", "name",
        "displayName", "version", "type", "editor", "terminal"
    ])
    func themeDecodingRejectsMissingRequiredKey(key: String) {
        #expect(throws: DecodingError.self) {
            try Self.decodeTheme(Self.themeJSON(omitting: [key]))
        }
    }

    @Test
    func themeDecodingRejectsIncompleteEditorSection() {
        let json = Self.themeJSON().replacingOccurrences(
            of: "\"comments\":{\"color\":\"#000010\"}",
            with: "\"unrelated\":{\"color\":\"#000010\"}"
        )

        #expect(throws: DecodingError.self) {
            try Self.decodeTheme(json)
        }
    }

    @Test
    func themeEncodingUsesFileKeysAndSkipsLocalState() throws {
        var theme = Self.makeTheme(appearance: .light)
        theme.fileURL = URL(filePath: "/tmp/theme.json")

        let data = try JSONEncoder().encode(theme)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["type"] as? String == "light")
        #expect(object["description"] as? String == "Description")
        #expect(object["name"] as? String == "unit")
        #expect(object["distributionURL"] as? String == "https://example.com/theme")
        #expect(object["isBundled"] == nil)
        #expect(object["fileURL"] == nil)
        #expect(object["appearance"] == nil)
        #expect(object["metadataDescription"] == nil)
    }

    @Test
    func themeRoundTripKeepsContentAndResetsLocalState() throws {
        var theme = Self.makeTheme()
        theme.fileURL = URL(filePath: "/tmp/theme.json")

        let decoded = try JSONDecoder().decode(Theme.self, from: JSONEncoder().encode(theme))

        #expect(decoded.editor == theme.editor)
        #expect(decoded.terminal == theme.terminal)
        #expect(decoded.author == theme.author)
        #expect(decoded.metadataDescription == theme.metadataDescription)
        #expect(decoded.appearance == theme.appearance)
        #expect(decoded.version == theme.version)
        #expect(decoded.isBundled == false)
        #expect(decoded.fileURL == nil)
    }

    @Test
    func themeEqualityIsDecidedByNameOnly() {
        let base = Self.makeTheme(name: "same")
        var changed = Self.makeTheme(name: "same", appearance: .light)
        changed.editor = Self.makeEditorColors(offset: 100)
        changed.author = "Someone Else"

        #expect(base == changed)
        #expect(base != Self.makeTheme(name: "other"))
        #expect(base.id == "same")
    }
}
