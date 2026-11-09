import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct TextEditingSettingsModelCoverageTests {
    typealias Model = SettingsData.TextEditingSettings

    private static let toggleCommands: [(id: String, keyPath: WritableKeyPath<Model, Bool>)] = [
        ("prefs.text_editing.type_over_completion", \.enableTypeOverCompletion),
        ("prefs.text_editing.autocomplete_braces", \.autocompleteBraces),
        ("prefs.text_editing.wrap_lines_to_editor_width", \.wrapLinesToEditorWidth),
        ("prefs.text_editing.toggle_minimap", \.showMinimap),
        ("prefs.text_editing.toggle_gutter", \.showGutter),
        ("prefs.text_editing.toggle_folding_ribbon", \.showFoldingRibbon)
    ]

    @Test
    func searchKeysListEverySettingIncludingSystemCursor() {
        let keys = Model().searchKeys
        #expect(keys.count == 29)
        #expect(keys.contains("Font"))
        #expect(keys.contains("Invisibles"))
        #expect(keys.contains("Warning Characters"))
        #expect(keys.contains("System Cursor"))
        #expect(keys.contains("Remove trailing spaces on"))
        #expect(keys.contains("Keep trailing spaces on caret line"))
        #expect(keys.contains("Ensure every saved file ends with a line break"))
        #expect(keys.contains("Format on save"))
        #expect(keys.contains("Inlay hints"))
        #expect(keys.contains("Show inlay hints"))
        #expect(keys.contains("Parameter name hints"))
        #expect(keys.contains("Type hints"))
        #expect(keys.contains("Return type hints"))
    }

    @Test
    func defaultInitializerUsesDocumentedDefaults() {
        let model = Model()
        #expect(model.defaultTabWidth == 4)
        #expect(model.indentOption == Model.IndentOption(indentType: .spaces, spaceCount: 4))
        #expect(model.font == SettingsData.EditorFont())
        #expect(model.enableTypeOverCompletion)
        #expect(model.autocompleteBraces)
        #expect(!model.wrapLinesToEditorWidth)
        #expect(model.overscroll == .medium)
        #expect(model.lineHeightMultiple == 1.3)
        #expect(model.letterSpacing == 1.0)
        #expect(model.bracketEmphasis.highlightType == .flash)
        #expect(!model.bracketEmphasis.useCustomColor)
        #expect(model.useSystemCursor)
        #expect(model.showGutter)
        #expect(!model.showMinimap)
        #expect(model.showFoldingRibbon)
        #expect(model.reformatAtColumn == 120)
        #expect(model.showReformattingGuide)
        #expect(model.invisibleCharacters == .default)
        #expect(model.warningCharacters == .default)
        #expect(model.stripTrailingSpaces == .modifiedLines)
        #expect(model.keepTrailingSpacesOnCaretLine)
        #expect(!model.ensureFinalNewline)
    }

    @Test
    func decodingEmptyObjectFallsBackToDefaults() throws {
        let decoded = try JSONDecoder().decode(Model.self, from: Data("{}".utf8))
        #expect(decoded == Model())
    }

    @Test
    func decodingPartialObjectKeepsGivenValuesAndDefaultsTheRest() throws {
        let json = """
        {
          "defaultTabWidth": 2,
          "overscroll": "large",
          "useSystemCursor": false,
          "reformatAtColumn": 80,
          "font": { "size": 20, "name": "Menlo", "weight": 0.4 }
        }
        """
        let decoded = try JSONDecoder().decode(Model.self, from: Data(json.utf8))
        #expect(decoded.defaultTabWidth == 2)
        #expect(decoded.overscroll == .large)
        #expect(!decoded.useSystemCursor)
        #expect(decoded.reformatAtColumn == 80)
        #expect(decoded.font.size == 20)
        #expect(decoded.font.name == "Menlo")
        #expect(decoded.font.weight == .bold)
        #expect(decoded.showGutter)
        #expect(decoded.warningCharacters == .default)
    }

    @Test
    func everyFieldSurvivesAnEncodeDecodeRoundTrip() throws {
        var model = Model()
        model.defaultTabWidth = 8
        model.indentOption = Model.IndentOption(indentType: .tab, spaceCount: 2)
        model.font.size = 17
        model.font.name = "Menlo"
        model.font.weight = .semibold
        model.enableTypeOverCompletion = false
        model.autocompleteBraces = false
        model.wrapLinesToEditorWidth = true
        model.overscroll = .small
        model.lineHeightMultiple = 1.5
        model.letterSpacing = 1.2
        model.bracketEmphasis.highlightType = .underline
        model.bracketEmphasis.useCustomColor = true
        model.useSystemCursor = false
        model.showGutter = false
        model.showMinimap = true
        model.showFoldingRibbon = false
        model.reformatAtColumn = 100
        model.showReformattingGuide = false
        model.invisibleCharacters.enabled = true
        model.invisibleCharacters.spaceReplacement = "."
        model.warningCharacters.enabled = false
        model.warningCharacters.characters[0x41] = "A"
        model.stripTrailingSpaces = .allLines
        model.keepTrailingSpacesOnCaretLine = false
        model.ensureFinalNewline = true

        let data = try JSONEncoder().encode(model)
        let decoded = try JSONDecoder().decode(Model.self, from: data)
        #expect(decoded == model)
    }

    @Test
    func saveActionSettingsFollowTheThreeSaveOptions() {
        var model = Model()
        #expect(model.saveActionSettings == SaveActionSettings())

        model.stripTrailingSpaces = .none
        model.keepTrailingSpacesOnCaretLine = false
        model.ensureFinalNewline = true

        #expect(
            model.saveActionSettings == SaveActionSettings(
                trailingSpaces: .none,
                keepTrailingSpacesOnCaretLine: false,
                ensureFinalNewline: true
            )
        )
    }

    @Test
    func decodingTheSaveOptionsKeepsGivenValues() throws {
        let json = """
        { "stripTrailingSpaces": "allLines", "keepTrailingSpacesOnCaretLine": false, "ensureFinalNewline": true }
        """
        let decoded = try JSONDecoder().decode(Model.self, from: Data(json.utf8))

        #expect(decoded.stripTrailingSpaces == .allLines)
        #expect(!decoded.keepTrailingSpacesOnCaretLine)
        #expect(decoded.ensureFinalNewline)
        #expect(TrailingSpacesMode.allCases.map(\.rawValue) == ["none", "modifiedLines", "allLines"])
    }

    @Test
    func overscrollPercentagesAndRawValues() {
        #expect(Model.OverscrollOption.none.overscrollPercentage == 0)
        #expect(Model.OverscrollOption.small.overscrollPercentage == 0.25)
        #expect(Model.OverscrollOption.medium.overscrollPercentage == 0.5)
        #expect(Model.OverscrollOption.large.overscrollPercentage == 0.75)
        #expect(Model.OverscrollOption(rawValue: "large") == .large)
        #expect(Model.OverscrollOption(rawValue: "huge") == nil)
    }

    @Test
    func enumRawValuesRoundTrip() {
        #expect(Model.IndentOption.IndentType(rawValue: "tab") == .tab)
        #expect(Model.IndentOption.IndentType(rawValue: "spaces") == .spaces)
        for type in ["disabled", "bordered", "flash", "underline"] {
            #expect(Model.BracketPairEmphasis.HighlightType(rawValue: type)?.rawValue == type)
        }
    }

    @Test
    func invisibleCharactersDefaultsAndReplacements() {
        let config = Model.InvisibleCharactersConfig.default
        #expect(!config.enabled)
        #expect(config.showSpaces)
        #expect(config.showTabs)
        #expect(config.showLineEndings)
        #expect(config.spaceReplacement == "·")
        #expect(config.tabReplacement == "→")
        #expect(config.carriageReturnReplacement == "↵")
        #expect(config.lineFeedReplacement == "¬")
        #expect(config.paragraphSeparatorReplacement == "¶")
        #expect(config.lineSeparatorReplacement == "⏎")
    }

    @Test
    func warningCharactersDefaultsListKnownConfusables() {
        let warnings = Model.WarningCharacters.default
        #expect(warnings.enabled)
        #expect(warnings.characters.count == 13)
        #expect(warnings.characters[0x00A0] == "Non-breaking space")
        #expect(warnings.characters[0x037E] == "Greek Question Mark")
    }

    @Test
    func commandPaletteTogglesFlipTheMatchingSetting() throws {
        let directory = try makeTemporaryDirectory(label: "TextEditingSettingsModelCoverageTests")
        defer { removeTemporaryDirectory(directory) }
        let store = Settings(baseURL: directory)
        let manager = CommandManager()
        Model().populateCommands(manager: manager, settings: { store })
        for (id, keyPath) in Self.toggleCommands {
            let before = store.preferences.textEditing[keyPath: keyPath]
            manager.executeCommand(id)
            #expect(store.preferences.textEditing[keyPath: keyPath] == !before)
            manager.executeCommand(id)
            #expect(store.preferences.textEditing[keyPath: keyPath] == before)
        }
    }

    @Test
    func commandsAreRegisteredWithTitles() {
        _ = Model()
        let titles = Set(CommandManager.shared.commands.map(\.title))
        #expect(titles.isSuperset(of: [
            "Toggle Type-Over Completion",
            "Toggle Autocomplete Braces",
            "Toggle Word Wrap",
            "Toggle Minimap",
            "Toggle Gutter",
            "Toggle Folding Ribbon"
        ]))
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct TextEditingEditorFontCoverageTests {
    typealias Font = SettingsData.EditorFont

    @Test
    func defaultsAreJetBrainsMonoRegular() {
        let font = Font()
        #expect(font.size == 13)
        #expect(font.name == "JetBrains Mono")
        #expect(font.weight == .regular)
    }

    @Test
    func decodingEmptyObjectKeepsDefaults() throws {
        let decoded = try JSONDecoder().decode(Font.self, from: Data("{}".utf8))
        #expect(decoded == Font())
    }

    @Test
    func decodingGivenValuesOverridesDefaults() throws {
        let json = "{\"size\": 21, \"name\": \"Menlo\", \"weight\": \(NSFont.Weight.heavy.rawValue)}"
        let decoded = try JSONDecoder().decode(Font.self, from: Data(json.utf8))
        #expect(decoded.size == 21)
        #expect(decoded.name == "Menlo")
        #expect(decoded.weight == .heavy)
    }

    @Test
    func currentResolvesInstalledFontAtSize() {
        var font = Font()
        font.name = "Menlo"
        font.size = 15
        font.weight = .bold
        #expect(font.current.pointSize == 15)
    }

    @Test
    func currentFallsBackToMonospacedSystemFontForUnknownName() {
        var font = Font()
        font.name = "NoSuchFontFamilyForDreamderTests"
        font.size = 19
        let resolved = font.current
        #expect(resolved.pointSize == 19)
        #expect(resolved.isFixedPitch)
    }

    @Test
    func bundledFontsRegisterFromMainBundleAndSkipEmptyBundles() throws {
        _ = Font.bundledFontsRegistered
        Font.registerBundledFonts()
        Font.registerBundledFonts(from: .main)
        try withTempDir { dir in
            let empty = try #require(Bundle(url: dir))
            #expect(empty.url(forResource: "JetBrainsMono-Regular", withExtension: "ttf") == nil)
            Font.registerBundledFonts(from: empty)
        }
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct TextEditingFontWeightCoverageTests {
    private static let weights: [NSFont.Weight] = [
        .ultraLight, .light, .thin, .regular, .medium, .semibold, .bold, .heavy, .black
    ]

    @Test
    func withWeightKeepsPointSizeForEveryWeight() throws {
        let base = try #require(NSFont(name: "Menlo", size: 14))
        for weight in Self.weights {
            if let resolved = base.withWeight(weight: weight) {
                #expect(resolved.pointSize == 14)
            }
        }
    }

    @Test
    func withWeightHandlesFontsWithoutFamilyName() throws {
        let base = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        _ = base.withWeight(weight: .bold)
        _ = base.withWeight(weight: .regular)
    }

    @Test
    func weightEncodesAsItsRawValueAndDecodesBack() throws {
        let encoded = try JSONEncoder().encode(Self.weights)
        let decoded = try JSONDecoder().decode([NSFont.Weight].self, from: encoded)
        #expect(decoded == Self.weights)
        let single = try JSONDecoder().decode([NSFont.Weight].self, from: Data("[0.4]".utf8))
        #expect(single == [.bold])
    }

    @Test
    func weightsWrittenWithEitherPrecisionDecodeToTheSameNamedWeight() throws {
        let rounded = try JSONDecoder().decode([NSFont.Weight].self, from: Data("[0.4, 0.3, -0.4]".utf8))
        let exact = try JSONDecoder().decode(
            [NSFont.Weight].self,
            from: Data("[\(NSFont.Weight.bold.rawValue), \(NSFont.Weight.semibold.rawValue), \(NSFont.Weight.light.rawValue)]".utf8)
        )
        #expect(rounded == [.bold, .semibold, .light])
        #expect(exact == rounded)
    }
}
